import assert from 'node:assert/strict';
import { performance as clock } from 'node:perf_hooks';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import os from 'node:os';

const fingerprints = response => ({
  catalogue: Object.fromEntries(response.catalogue.map(b => [b.id, b.hash])),
  orders: Object.fromEntries(response.orders.map(b => [b.id, b.hash])),
  metadata: response.metadata_hash,
});
const bytes = value => Buffer.byteLength(JSON.stringify(value));
const sync = (client, known = {}) => client.query('select public.sync_store($1,$2,$3) as result', [known.catalogue ?? {}, known.orders ?? {}, known.metadata ?? null]).then(r => r.rows[0].result);
const merge = (known, response) => ({
  catalogue: { ...known.catalogue, ...fingerprints(response).catalogue },
  orders: { ...known.orders, ...fingerprints(response).orders },
  metadata: response.metadata_hash,
});

export async function runSyncChecks({ owner, transaction, fixture, anotherUser, admin, category, place, mutate, check, performance }) {
  const f = await fixture(10000, 10000);
  let cold, warm, changed, known;
  await check('cold catalogue is complete; unchanged sync omits catalogue, metadata and orders', async () => {
    cold = await transaction(f.user, c => sync(c)); known = fingerprints(cold);
    assert.equal(cold.catalogue.length, 64); assert.equal(cold.orders.length, 64);
    assert.equal(cold.catalogue.flatMap(b => b.rows).length, (await owner.query('select count(*)::int n from public.products p join public.categories c on c.id=p.category_id where p.active and c.active')).rows[0].n);
    warm = await transaction(f.user, c => sync(c, known));
    assert.deepEqual(warm.catalogue, []); assert.deepEqual(warm.orders, []); assert.equal(warm.metadata, null);
    assert.ok(bytes(warm) < 512); assert.ok(bytes(warm) < bytes(cold) / 100);
  });
  await check('one stock edit changes only one catalogue section', async () => {
    await transaction(admin, c => mutate(c, { action: 'adjust_stock', target_product_id: f.product, stock_delta: 1 }));
    changed = await transaction(f.user, c => sync(c, known));
    assert.equal(changed.catalogue.length, 1); assert.deepEqual(changed.orders, []);
    assert.equal(changed.metadata, null); assert.ok(bytes(changed) < bytes(cold) / 8);
    known = merge(known, changed);
  });
  await check('archiving and deleting rows invalidate cached sections', async () => {
    const test = await fixture();
    let response = await transaction(f.user, c => sync(c, known)); known = merge(known, response);
    await owner.query('update public.products set active=false where id=$1', [test.product]);
    response = await transaction(f.user, c => sync(c, known)); known = merge(known, response);
    assert.equal(response.catalogue.length, 1); assert.ok(!response.catalogue.flatMap(b => b.rows).some(row => row[0] === test.product));
    await owner.query('update public.products set active=true where id=$1', [test.product]);
    response = await transaction(f.user, c => sync(c, known)); known = merge(known, response);
    await owner.query('delete from public.products where id=$1', [test.product]);
    response = await transaction(f.user, c => sync(c, known)); known = merge(known, response);
    assert.equal(response.catalogue.length, 1); assert.ok(!response.catalogue.flatMap(b => b.rows).some(row => row[0] === test.product));
  });
  await check('order sync is user-scoped and responds to order and line changes', async () => {
    const id = await transaction(f.user, c => place(c, f));
    let response = await transaction(f.user, c => sync(c, known)); known = merge(known, response);
    assert.equal(response.orders.length, 1); assert.equal(response.orders.flatMap(b => b.rows)[0].id, id);
    assert.equal(response.orders.flatMap(b => b.rows)[0].checkout_request, undefined);
    await owner.query("update public.order_items set product_name='Corrected snapshot' where order_id=$1", [id]);
    response = await transaction(f.user, c => sync(c, known)); known = merge(known, response);
    assert.equal(response.orders.length, 1);
    assert.equal(response.orders.flatMap(b => b.rows)[0].order_items[0].product_name, 'Corrected snapshot');
    const stranger = await anotherUser();
    const other = await transaction(stranger, c => sync(c, known));
    assert.equal(other.orders.length, 64); assert.equal(other.orders.flatMap(b => b.rows).length, 0);
    assert.equal(other.user_id, stranger);
  });
  await check('customer snapshots cannot retain staff-only inventory or other customers orders', async () => {
    const staff = await transaction(admin, c => sync(c));
    assert.equal(staff.is_admin, true);
    const customer = await transaction(f.user, c => sync(c, fingerprints(staff)));
    assert.equal(customer.catalogue.length, 64); assert.equal(customer.orders.length, 64);
    assert.ok(customer.catalogue.flatMap(b => b.rows).every(row => row[14] === true && row.slice(16).every(v => v === null)));
    assert.ok(customer.orders.flatMap(b => b.rows).every(row => row.user_id === f.user));
    const noMfa = await transaction(admin, c => sync(c, fingerprints(staff)), 'authenticated', 'aal1');
    assert.equal(noMfa.is_admin, false); assert.equal(noMfa.orders.flatMap(b => b.rows).length, 0);
    await assert.rejects(transaction(null, c => sync(c)), { code: 'P0001' });
    await assert.rejects(transaction(f.user, c => c.query('select public.admin_resource_usage()')), { code: 'P0001' });
    await assert.rejects(transaction(f.user, c => sync(c, { catalogue: { 70: 'wrong' } })), { code: 'P0001' });
    assert.ok((await transaction(admin, c => c.query('select public.admin_resource_usage() as result'))).rows[0].result.database_bytes > 0);
  });

  await check('a late committed stock change is not lost behind a newer sync', async () => {
    let release, reached;
    const held=new Promise(resolve=>release=resolve), locked=new Promise(resolve=>reached=resolve);
    const edit=transaction(admin,async c=>{
      await mutate(c,{action:'adjust_stock',target_product_id:f.product,stock_delta:1});
      reached(); await held;
    });
    await locked;
    try {
      const during=await transaction(f.user,c=>sync(c));
      release(); await edit;
      const after=await transaction(f.user,c=>sync(c,fingerprints(during)));
      assert.equal(after.catalogue.length,1);
      const beforeRow=during.catalogue.flatMap(b=>b.rows).find(row=>row[0]===f.product);
      const afterRow=after.catalogue.flatMap(b=>b.rows).find(row=>row[0]===f.product);
      assert.equal(afterRow[7],beforeRow[7]+1);
    } finally { release(); await edit; }
  });

  await check('customer and admin order history is complete beyond 1000 rows', async () => {
    const historyUser=await anotherUser();
    await owner.query(`insert into public.orders(user_id,fulfilment_type,fulfilment_date,slot_id,slot_label,
      subtotal_paise,total_paise,payment_method,payment_status,order_status,idempotency_key)
      select $1,'pickup',current_date,$2,'History fixture',1000,1000,'pay_at_store','paid','collected',
        'history-fixture-' || n from generate_series(1,1005) n`,[historyUser,f.slot]);
    const customer=await transaction(historyUser,c=>sync(c));
    assert.equal(customer.orders.flatMap(b=>b.rows).length,1005);
    const staff=await transaction(admin,c=>sync(c));
    assert.equal(staff.orders.flatMap(b=>b.rows).length,(await owner.query('select count(*)::int n from public.orders')).rows[0].n);
    const warmHistory=await transaction(admin,c=>sync(c,fingerprints(staff)));
    assert.deepEqual(warmHistory.orders,[]);
  });

  if (!performance) return;
  // At most 24 DB connections, like an API connection pool. Virtual shoppers
  // queue their requests; latency includes that queue, connection + transaction.
  const shoppers = [];
  for (let index=0;index<100;index++) shoppers.push(await anotherUser());
  const latest = await transaction(f.user, c => sync(c));
  const catalogue = fingerprints(latest).catalogue;
  const userKnown = new Map();
  for (const user of shoppers) {
    userKnown.set(user, merge({ catalogue }, await transaction(user, c => sync(c, { catalogue }))));
  }
  const stages = [];
  for (const users of [10, 25, 50, 100]) {
    const timings = [], failures = [], payloads = [];
    const started = clock.now();
    // Four synchronized bursts emulate browsing + resume; 10% of users place
    // an order in the first burst (normal cart writes, not OTP email sends).
    for (let burst=0;burst<4;burst++) {
      const queued = clock.now();
      let next = 0;
      await Promise.all(Array.from({ length: Math.min(24, users) }, async () => {
        for (;;) {
          const index = next++; if (index >= users) return;
          const user = shoppers[index];
          try {
            if (burst === 0 && index % 10 === 0) {
              await transaction(user, async c => {
                const id = await place(c, f);
                // Leave room for later stages without tripping active-order limits.
                await c.query('select public.cancel_own_order($1,null)', [id]);
              });
            }
            const response = await transaction(user, c => sync(c, userKnown.get(user)));
            userKnown.set(user, merge(userKnown.get(user), response));
            payloads.push(bytes(response));
            timings.push(clock.now() - queued);
          } catch (error) { failures.push({ code: error.code, message: error.message }); }
        }
      }));
    }
    timings.sort((a,b) => a-b);
    const p95 = timings[Math.max(0, Math.ceil(timings.length * 0.95)-1)];
    assert.deepEqual(failures, []);
    assert.ok(p95 < 2000, 'Local p95 exceeded the 2-second regression budget');
    stages.push({ simultaneous_shoppers: users, requests: timings.length, errors: failures.length,
      p50_ms: +timings[Math.floor(timings.length*0.5)].toFixed(1), p95_ms: +p95.toFixed(1),
      max_ms: +timings.at(-1).toFixed(1), total_response_bytes: payloads.reduce((a,b)=>a+b,0),
      elapsed_ms: +(clock.now()-started).toFixed(1), });
  }
  const report = {
    tested_at: new Date().toISOString(), environment: 'isolated local PostgreSQL; NOT hosted Supabase',
    platform: os.platform(), architecture: os.arch(), cpu: os.cpus()[0]?.model,
    total_ram_bytes: os.totalmem(), database_pool_cap: 24,
    catalogue_products: cold.catalogue.flatMap(b=>b.rows).length,
    cold_response_bytes: bytes(cold), unchanged_response_bytes: bytes(warm), single_stock_change_bytes: bytes(changed),
    stages, emails_sent: 0, live_supabase_verified: false, launch_ready: false,
  };
  const destination = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../outputs/performance/local-load-report.json');
  await mkdir(path.dirname(destination), { recursive: true });
  await writeFile(destination, JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify(report, null, 2));
  console.log('Local load report:', destination);
}
