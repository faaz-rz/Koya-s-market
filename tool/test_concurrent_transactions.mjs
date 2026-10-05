// Isolated real-PostgreSQL tests. Never accepts or connects to a remote DB URL.
// Install pg + embedded-postgres into a disposable directory, then set
// KOYAS_PG_RUNTIME to that directory. See docs/CONCURRENCY.md.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { mkdtemp, readFile, readdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import net from 'node:net';

if (!process.env.KOYAS_PG_RUNTIME) throw new Error('Set KOYAS_PG_RUNTIME to the disposable npm runtime.');
const require = createRequire(path.join(process.env.KOYAS_PG_RUNTIME, 'package.json'));
const { default: EmbeddedPostgres } = await import(pathToFileURL(require.resolve('embedded-postgres')));
const { Client } = require('pg');
const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const directory = await mkdtemp(path.join(tmpdir(), 'koyas-pg-test-'));
const port = await new Promise(resolve => {
  const server = net.createServer();
  server.listen(0, '127.0.0.1', () => {
    const chosen = server.address().port;
    server.close(() => resolve(chosen));
  });
});
const connection = { host: '127.0.0.1', port, user: 'postgres', password: randomUUID(), database: 'postgres' };
const database = new EmbeddedPostgres({
  databaseDir: path.join(directory, 'data'), port,
  user: connection.user, password: connection.password, persistent: true,
  postgresFlags: ['-h', '127.0.0.1', '-k', directory, '-c', 'deadlock_timeout=200ms'],
  onLog: () => {}, onError: () => {},
});
const clients = new Set();
async function connect() {
  const client = new Client(connection);
  await client.connect(); clients.add(client);
  await client.query("set statement_timeout='15s'");
  return client;
}
async function transaction(user, fn, role = 'authenticated', aal = 'aal2') {
  const client = await connect();
  try {
    await client.query('begin');
    await client.query(`set local role ${role}`);
    await client.query("select set_config('request.jwt.claims', $1, true)", [JSON.stringify({ sub: user, aal })]);
    const result = await fn(client);
    await client.query('commit');
    return result;
  } catch (error) {
    await client.query('rollback'); throw error;
  } finally { await client.end(); clients.delete(client); }
}
let admin, category, owner, slotSequence = 0;
async function fixture(stock = 10, capacity = 100) {
  const user = randomUUID(), product = randomUUID(), slot = randomUUID();
  await owner.query('insert into auth.users(id) values ($1)', [user]);
  await owner.query(`insert into public.products(id,category_id,name,description,unit,price_paise,stock_quantity)
    values($1,$2,'Concurrency product','Test inventory','1 pack',1000,$3)`, [product, category, stock]);
  await owner.query(`insert into public.fulfilment_slots(id,fulfilment_type,label,start_time,end_time,max_orders)
    values($1,'pickup','Concurrency slot',time '00:00' + make_interval(secs => $3),'23:59',$2)`, [slot, capacity, ++slotSequence]);
  return { user, product, slot };
}
async function anotherUser() {
  const id = randomUUID(); await owner.query('insert into auth.users(id) values ($1)', [id]); return id;
}
function place(client, fixture, { key = randomUUID(), items, offer = null, instructions = '' } = {}) {
  return client.query(`select public.place_order_v2($1::jsonb,'pickup',null,current_date,$2,'pay_at_store',$3,$4,$5) as id`,
    [JSON.stringify(items ?? [{ product_id: fixture.product, quantity: 1 }]), fixture.slot, instructions, key, offer])
    .then(result => result.rows[0].id);
}
function mutate(client, mutation, revision = null, key = randomUUID()) {
  return client.query('select public.admin_mutate_product($1,$2,$3::jsonb) as result', [key, revision, JSON.stringify(mutation)])
    .then(result => result.rows[0].result);
}
async function stock(id) {
  return (await owner.query('select stock_quantity from public.products where id=$1', [id])).rows[0].stock_quantity;
}
async function check(name, fn) { await fn(); console.log(`PASS ${name}`); }
function businessRejections(results, message) {
  for (const result of results.filter(r => r.status === 'rejected')) {
    assert.equal(result.reason.code, 'P0001');
    assert.match(result.reason.message, message);
  }
}

try {
  await database.initialise(); await database.start(); owner = await connect();
  console.log((await owner.query('select version()')).rows[0].version);
  await owner.query(`
    create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
    create schema auth; create schema storage;
    create table auth.users(id uuid primary key, raw_user_meta_data jsonb default '{}', phone text, email text, email_confirmed_at timestamptz);
    create function auth.jwt() returns jsonb language sql stable as
      $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
    create function auth.uid() returns uuid language sql stable as $$ select (auth.jwt()->>'sub')::uuid $$;
    grant usage on schema auth,storage,public to anon,authenticated,service_role;
    create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text,owner_id text,metadata jsonb);
    alter table storage.objects enable row level security;
    create function storage.foldername(text) returns text[] language sql as $$ select string_to_array($1,'/') $$;
    alter default privileges in schema public grant all on tables to anon,authenticated,service_role;
    alter default privileges in schema public grant all on sequences to anon,authenticated,service_role;
  `);
  for (const file of (await readdir(path.join(root, 'supabase/migrations'))).filter(file => file.endsWith('.sql')).sort()) {
    try { await owner.query(await readFile(path.join(root, 'supabase/migrations', file), 'utf8')); }
    catch (error) { throw new Error(`Migration ${file}: ${error.message}`, { cause: error }); }
  }
  admin = await anotherUser(); category = (await owner.query('select id from public.categories where active limit 1')).rows[0].id;
  await owner.query("insert into public.admins(user_id,display_name) values($1,'Concurrency tester')", [admin]);
  await owner.query('update public.store_settings set minimum_order_paise=0');
  await check('12 customers compete for the final unit: exactly one order and no oversell', async () => {
    const f = await fixture(1);
    // Separate slots ensure this verifies product locks, not just slot locking.
    const shoppers = [];
    for (let index = 0; index < 12; index++) shoppers.push(await fixture());
    const results = await Promise.allSettled(shoppers.map(shopper => transaction(shopper.user, c => place(c, { ...f, slot: shopper.slot }))));
    assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
    businessRejections(results, /Insufficient stock|A product is unavailable/);
    assert.equal(await stock(f.product), 0);
    assert.equal((await owner.query('select count(*)::int n from public.order_items where product_id=$1', [f.product])).rows[0].n, 1);
  });
  await check('parallel retries return one order and decrement stock once', async () => {
    const f = await fixture(), key = randomUUID();
    const ids = await Promise.all(Array.from({ length: 8 }, () => transaction(f.user, c => place(c, f, { key }))));
    assert.equal(new Set(ids).size, 1); assert.equal(await stock(f.product), 9);
    await assert.rejects(transaction(f.user, c => place(c, f, { key, instructions: 'changed details' })), { code: 'PT409' });
  });
  await check('cart order does not change retry identity; changed quantities do', async () => {
    const f = await fixture(), other = await fixture(), key = randomUUID();
    const items = [{ product_id: f.product, quantity: 1 }, { product_id: other.product, quantity: 2 }];
    const first = await transaction(f.user, c => place(c, f, { key, items }));
    assert.equal(await transaction(f.user, c => place(c, f, { key, items: [...items].reverse() })), first);
    await assert.rejects(transaction(f.user, c => place(c, f, { key, items: [{ product_id: f.product, quantity: 2 }] })), { code: 'PT409' });
  });
  await check('slot capacity cannot be overbooked by concurrent customers', async () => {
    const f = await fixture(20, 1), other = await anotherUser();
    const results = await Promise.allSettled([f.user, other].map(user => transaction(user, c => place(c, f))));
    assert.equal(results.filter(r => r.status === 'fulfilled').length, 1); assert.equal(await stock(f.product), 19);
    businessRejections(results, /slot is full/);
  });
  await check('invalid mixed quantities and partial baskets roll back completely', async () => {
    const f = await fixture(), empty = await fixture(0);
    await assert.rejects(transaction(f.user, c => place(c, f, { items: [{ product_id: f.product, quantity: -1 }, { product_id: f.product, quantity: 2 }] })));
    await assert.rejects(transaction(f.user, c => place(c, f, { items: [{ product_id: f.product, quantity: 1 }, { product_id: empty.product, quantity: 1 }] })));
    assert.equal(await stock(f.product), 10);
    assert.equal((await owner.query('select count(*)::int n from public.orders where user_id=$1', [f.user])).rows[0].n, 0);
  });
  await check('two admins cannot both overwrite the same product revision', async () => {
    const f = await fixture();
    const otherAdmin = await anotherUser();
    await owner.query("insert into public.admins(user_id,display_name) values($1,'Other admin')", [otherAdmin]);
    const mutation = { action: 'set_stock', target_product_id: f.product, requested_stock: 20 };
    const results = await Promise.allSettled([[admin, 20], [otherAdmin, 30]].map(([user, quantity]) => transaction(user, c => mutate(c, { ...mutation, requested_stock: quantity }, 0))));
    assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
    assert.equal(results.find(r => r.status === 'rejected').reason.code, 'PT409');
  });
  await check('an old admin form cannot restore stock consumed by an order', async () => {
    const f = await fixture(); await transaction(f.user, c => place(c, f));
    await assert.rejects(transaction(admin, c => mutate(c, {
      action: 'save', target_product_id: f.product, product_category_id: category,
      product_name: 'Stale price edit', product_description: 'Test product', product_unit: '1 pack',
      product_price_paise: 1200, product_stock_quantity: 10,
    }, 0)), { code: 'PT409' });
    assert.equal(await stock(f.product), 9);
  });
  await check('parallel stock deltas are additive; retrying a receipt does not apply twice', async () => {
    const f = await fixture(), key = randomUUID();
    const mutation = { action: 'adjust_stock', target_product_id: f.product, stock_delta: 1 };
    await Promise.all(Array.from({ length: 5 }, () => transaction(admin, c => mutate(c, mutation, null, key))));
    assert.equal(await stock(f.product), 11);
    await Promise.all(Array.from({ length: 5 }, () => transaction(admin, c => mutate(c, mutation))));
    assert.equal(await stock(f.product), 16);
    await assert.rejects(transaction(admin, c => mutate(c, { ...mutation, stock_delta: 2 }, null, key)), { code: 'PT409' });
  });
  await check('stock updates serialize against a genuinely uncommitted checkout', async () => {
    const f = await fixture(); let release, locked;
    const held = new Promise(resolve => release = resolve), reached = new Promise(resolve => locked = resolve);
    const checkout = transaction(f.user, async c => { const id = await place(c, f); locked(); await held; return id; });
    await reached;
    let finished = false;
    const write = transaction(admin, c => mutate(c, { action: 'adjust_stock', target_product_id: f.product, stock_delta: 2 })).then(r => { finished = true; return r; });
    try { await new Promise(resolve => setTimeout(resolve, 150)); assert.equal(finished, false); }
    finally { release(); }
    await Promise.all([checkout, write]); assert.equal(await stock(f.product), 11);
  });
  await check('duplicate customer cancellations restore stock only once', async () => {
    const f = await fixture(), id = await transaction(f.user, c => place(c, f));
    await Promise.all(Array.from({ length: 5 }, () => transaction(f.user, c => c.query('select public.cancel_own_order($1,null)', [id]))));
    assert.equal(await stock(f.product), 10);
  });
  await check('customer cancellation versus admin rejection restores stock only once', async () => {
    const f = await fixture(), id = await transaction(f.user, c => place(c, f));
    const results = await Promise.allSettled([
      transaction(f.user, c => c.query('select public.cancel_own_order($1,null)', [id])),
      transaction(admin, c => c.query("select public.update_order_status($1,'rejected')", [id])),
    ]);
    assert.equal(results.filter(r => r.status === 'fulfilled').length, 1); assert.equal(await stock(f.product), 10);
    businessRejections(results, /cancel|transition/i);
  });
  await check('opposite baskets and free gifts have a consistent global product lock order', async () => {
    const a = await fixture(), b = await fixture();
    const codes = ['TEST_' + randomUUID().slice(0, 8).toUpperCase(), 'TEST_' + randomUUID().slice(0, 8).toUpperCase()];
    for (const [index, gift] of [b.product, a.product].entries()) {
      await owner.query(`insert into public.offers(code,title,description,minimum_subtotal_paise,free_product_id,free_quantity)
        values($1,'Test gift','Test gift offer',0,$2,1)`, [codes[index], gift]);
    }
    await Promise.all([
      transaction(a.user, c => place(c, a, { offer: codes[0] })),
      transaction(b.user, c => place(c, b, { offer: codes[1] })),
    ]);
    assert.equal(await stock(a.product), 8); assert.equal(await stock(b.product), 8);
  });
  await check('offer redemption limit and gift stock remain atomic', async () => {
    const f = await fixture(), gift = await fixture(), other = await anotherUser();
    const code = 'LIMIT_' + randomUUID().slice(0, 8).toUpperCase();
    await owner.query(`insert into public.offers(code,title,description,minimum_subtotal_paise,free_product_id,free_quantity,total_redemption_limit)
      values($1,'Limited gift','Limited gift offer',0,$2,1,1)`, [code, gift.product]);
    const results = await Promise.allSettled([f.user, other].map(user => transaction(user, c => place(c, f, { offer: code }))));
    assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
    businessRejections(results, /redemption limit/);
    assert.equal(await stock(f.product), 9); assert.equal(await stock(gift.product), 9);
  });
  await check('buying and receiving the same last item as a gift rolls back the entire order', async () => {
    const f = await fixture(1), code = 'SAME_' + randomUUID().slice(0, 8).toUpperCase();
    await owner.query(`insert into public.offers(code,title,description,minimum_subtotal_paise,free_product_id,free_quantity)
      values($1,'Same gift','Same product gift',0,$2,1)`, [code, f.product]);
    await assert.rejects(transaction(f.user, c => place(c, f, { offer: code })), { code: 'P0001', message: 'The free product is currently unavailable' });
    assert.equal(await stock(f.product), 1);
    assert.equal((await owner.query('select count(*)::int n from public.orders where user_id=$1', [f.user])).rows[0].n, 0);
  });
  await check('multiple expiry workers and cancellation restore each reservation once', async () => {
    const f = await fixture(10), ids = [];
    for (let index = 0; index < 6; index++) {
      const user = index === 0 ? f.user : await anotherUser();
      ids.push(await transaction(user, c => place(c, f)));
    }
    // Online checkout remains disabled in the app; owner fixtures exercise the
    // existing expiry worker without enabling or contacting a payment gateway.
    await owner.query(`update public.orders set payment_method='online',
      payment_expires_at=now()-interval '1 minute' where id=any($1::uuid[])`, [ids]);
    const results = await Promise.allSettled([
      ...Array.from({ length: 4 }, () => transaction(null, c => c.query('select public.expire_abandoned_online_orders(2)'), 'service_role')),
      transaction(f.user, c => c.query('select public.cancel_own_order($1,null)', [ids[0]])),
    ]);
    assert.ok(results.every(r => r.status === 'fulfilled'), results.find(r => r.status === 'rejected')?.reason);
    assert.equal(await stock(f.product), 10);
    assert.equal((await owner.query("select count(*)::int n from public.orders where id=any($1::uuid[]) and order_status='cancelled'", [ids])).rows[0].n, 6);
    await transaction(null, c => c.query('select public.expire_abandoned_online_orders(20)'), 'service_role');
    assert.equal(await stock(f.product), 10);
  });
  await check('cancellation and a new checkout serialize on the same inventory', async () => {
    const f = await fixture(2), other = await anotherUser();
    const id = await transaction(f.user, c => place(c, f));
    await Promise.all([
      transaction(f.user, c => c.query('select public.cancel_own_order($1,null)', [id])),
      transaction(other, c => place(c, f)),
    ]);
    assert.equal(await stock(f.product), 1);
  });
  await check('repeated product creation returns the same product and one audit event', async () => {
    const key = randomUUID(), mutation = {
      action: 'save', target_product_id: null, product_category_id: category,
      product_name: 'Created once', product_description: 'Creation retry test', product_unit: '1 pack',
      product_price_paise: 1200, product_stock_quantity: 10, product_featured: false,
      product_active: true, product_available: true, remove_product_image: false,
    };
    const results = await Promise.all(Array.from({ length: 5 }, () => transaction(admin, c => mutate(c, mutation, 0, key))));
    const id = results[0].product_id;
    assert.ok(results.every(result => result.product_id === id));
    assert.equal(await stock(id), 10);
    assert.equal((await owner.query("select count(*)::int n from public.admin_audit_logs where entity_id=$1 and action='create_product'", [id])).rows[0].n, 1);
  });
  await check('concurrent manual payment confirmations are audited once', async () => {
    const f = await fixture(), id = await transaction(f.user, c => place(c, f));
    await transaction(admin, c => c.query("select public.update_order_status($1,'ready_for_pickup')", [id]));
    const results = await Promise.all(Array.from({ length: 5 }, () => transaction(admin, c => c.query('select public.admin_mark_order_paid($1) as paid_at', [id]))));
    assert.equal(new Set(results.map(result => result.rows[0].paid_at.toISOString())).size, 1);
    assert.equal((await owner.query("select count(*)::int n from public.admin_audit_logs where entity_id=$1 and action='mark_order_paid'", [id])).rows[0].n, 1);
  });
  await check('authorization prevents stale-write API bypasses and unauthorized receipts', async () => {
    const f = await fixture();
    await assert.rejects(transaction(f.user, c => mutate(c, { action: 'adjust_stock', target_product_id: f.product, stock_delta: 1 })));
    await assert.rejects(transaction(admin, c => mutate(c, { action: 'adjust_stock', target_product_id: f.product, stock_delta: 1 }), 'authenticated', 'aal1'), { code: 'P0001', message: 'Admin access required' });
    await assert.rejects(transaction(admin, c => c.query('select public.admin_set_product_stock($1,50)', [f.product])), { code: '42501' });
    await assert.rejects(transaction(admin, c => c.query('select * from public.admin_inventory_requests')), { code: '42501' });
    await assert.rejects(transaction(admin, c => c.query('update public.products set stock_quantity=500 where id=$1', [f.product])), { code: '42501' });
    assert.equal(await stock(f.product), 10);
  });
  const { runSyncChecks } = await import('./store_sync_load_test.mjs');
  await runSyncChecks({ owner, transaction, fixture, anotherUser, admin, category, place, mutate, check,
    performance: process.argv.includes('--performance'), });
  const { runDeletionChecks } = await import('./account_deletion_database_test.mjs');
  await runDeletionChecks({ owner, transaction, fixture, anotherUser, admin, place, check });
  const { runRequestProtocolChecks } = await import('./request_protocol_database_test.mjs');
  await runRequestProtocolChecks({ owner, transaction, anotherUser, admin, check });
  console.log('All concurrency and sync checks passed. No remote database was contacted.');
} finally {
  await Promise.all([...clients].map(c => c.end().catch(() => {})));
  await database.stop();
  console.log(`Stopped disposable PostgreSQL. Local test data/logs: ${directory}`);
}
