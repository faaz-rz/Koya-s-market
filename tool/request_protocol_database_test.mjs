import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

export async function runRequestProtocolChecks({ owner, transaction, anotherUser, admin, check }) {
  await check('approving an existing verified customer grants staff once without bypassing MFA', async () => {
    const user = randomUUID(), email = `existing-${randomUUID()}@example.test`;
    await owner.query('insert into auth.users(id,email,email_confirmed_at) values ($1,$2,now())', [user, email]);
    assert.equal((await owner.query('select count(*)::int n from public.admins where user_id=$1', [user])).rows[0].n, 0);
    await owner.query('insert into koyas_private.staff_email_approvals(email,display_name) values ($1,$2)', [email, 'Existing verified staff']);
    assert.equal((await owner.query('select granted_user_id from koyas_private.staff_email_approvals where email=$1', [email])).rows[0].granted_user_id, user);
    assert.equal((await transaction(user, c => c.query('select public.is_admin() as allowed'), 'authenticated', 'aal1')).rows[0].allowed, false);
    assert.equal((await transaction(user, c => c.query('select public.is_admin() as allowed'))).rows[0].allowed, true);
    await owner.query('update public.admins set active=false where user_id=$1', [user]);
    await owner.query('insert into koyas_private.staff_email_approvals(email,display_name) values ($1,$2) on conflict do nothing', [email, 'Repeated approval']);
    assert.equal((await owner.query('select active from public.admins where user_id=$1', [user])).rows[0].active, false);
  });
  await check('staff email approval requires verified email, is private, consumes once, and still requires MFA', async () => {
    const user = randomUUID(), other = randomUUID(), email = `staff-${randomUUID()}@example.test`;
    await owner.query('insert into koyas_private.staff_email_approvals(email, display_name) values ($1,$2)', [email, 'Approved staff']);
    await owner.query('insert into auth.users(id,email) values ($1,$2)', [user, email.toUpperCase()]);
    assert.equal((await owner.query('select count(*)::int n from public.admins where user_id=$1', [user])).rows[0].n, 0);
    await owner.query('update auth.users set email_confirmed_at=now() where id=$1', [user]);
    assert.equal((await owner.query('select display_name from public.admins where user_id=$1', [user])).rows[0].display_name, 'Approved staff');
    assert.equal((await transaction(user, c => c.query('select public.is_admin() as allowed'), 'authenticated', 'aal1')).rows[0].allowed, false);
    assert.equal((await transaction(user, c => c.query('select public.is_admin() as allowed'))).rows[0].allowed, true);
    await assert.rejects(transaction(user, c => c.query('select * from koyas_private.staff_email_approvals')), { code: '42501' });
    await assert.rejects(transaction(user, c => c.query("insert into koyas_private.staff_email_approvals(email,display_name) values('attacker@example.test','Attacker')")), { code: '42501' });
    await owner.query('update public.admins set active=false where user_id=$1', [user]);
    await owner.query('update auth.users set email_confirmed_at=now() where id=$1', [user]);
    assert.equal((await owner.query('select active from public.admins where user_id=$1', [user])).rows[0].active, false);
    // Repeating a verified-email event or trying to reuse a consumed approval
    // must never reactivate revoked staff or grant a second identity access.
    await owner.query('insert into auth.users(id,email,email_confirmed_at) values ($1,$2,now())', [other, email]);
    assert.equal((await owner.query('select count(*)::int n from public.admins where user_id=$1', [other])).rows[0].n, 0);
  });
  await check('staff allowlist reads work before MFA and expose only the caller; direct writes and anonymous reads fail', async () => {
    const user = await anotherUser();
    const own = await transaction(admin, c => c.query('select user_id from public.admins'), 'authenticated', 'aal1');
    assert.deepEqual(own.rows, [{ user_id: admin }]);
    const customerRows = await transaction(user, c => c.query('select user_id from public.admins'), 'authenticated', 'aal1');
    assert.equal(customerRows.rows.length, 0);
    await assert.rejects(transaction(user, c => c.query('select user_id from public.admins'), 'anon'), { code: '42501' });
    await assert.rejects(transaction(user, c => c.query("insert into public.admins(user_id, display_name) values($1, 'Unauthorized')", [user])), { code: '42501' });
    await assert.rejects(transaction(admin, c => c.query('update public.admins set active=false where user_id=$1', [admin])), { code: '42501' });
    await assert.rejects(transaction(user, c => c.query('select * from public.products'), 'anon'), { code: '42501' });
    await assert.rejects(transaction(user, c => c.query('select public.is_admin()'), 'anon'), { code: '42501' });
  });
  const customer = (client, mutation, revision = null, id = randomUUID()) =>
    client.query('select public.mutate_customer($1,$2,$3::jsonb) as result', [id, revision, JSON.stringify(mutation)])
      .then(r => r.rows[0].result);
  const configuration = (client, mutation, revision, id = randomUUID()) =>
    client.query('select public.admin_mutate_configuration($1,$2,$3::jsonb) as result', [id, revision, JSON.stringify(mutation)])
      .then(r => r.rows[0].result);
  const address = (overrides = {}) => ({ action: 'save_address', address_id: null,
    label: 'Home', recipient_name: 'Test Customer', phone: '+91 9876543210', line1: '12 Test Street',
    city: 'Test City', pincode: '678001', instructions: '', is_default: false, ...overrides });
  const pricing = (overrides = {}) => ({ action: 'pricing', requested_minimum_order_paise: 0,
    requested_delivery_charge_paise: 2500, requested_free_delivery_threshold_paise: 50000, ...overrides });
  const offer = (overrides = {}) => ({ action: 'offer', target_offer_id: null,
    requested_code: 'PROTOCOL_' + randomUUID().slice(0, 8).toUpperCase(), requested_title: 'Test discount',
    requested_description: '', requested_minimum_subtotal_paise: 0, requested_discount_type: 'flat',
    requested_discount_value: 100, requested_free_quantity: 1, requested_per_customer_limit: 1,
    requested_active: true, ...overrides });

  await check('parallel address-creation retries create one address and one default', async () => {
    const user = await anotherUser(), id = randomUUID(), mutation = address({ is_default: true });
    const results = await Promise.all(Array.from({ length: 12 }, () => transaction(user, c => customer(c, mutation, null, id))));
    assert.equal(new Set(results.map(r => r.id)).size, 1);
    assert.equal((await owner.query('select count(*)::int n from public.addresses where user_id=$1', [user])).rows[0].n, 1);
    assert.equal((await owner.query('select count(*)::int n from public.configuration_requests where user_id=$1', [user])).rows[0].n, 1);
    await assert.rejects(transaction(user, c => customer(c, address({ label: 'Changed' }), null, id)), { code: 'PT409' });
  });
  await check('parallel default-address changes leave exactly one default', async () => {
    const user = await anotherUser(), addresses = [];
    for (let i = 0; i < 6; i++) addresses.push(await transaction(user, c => customer(c, address({ label: 'Address ' + i }))));
    await Promise.all(addresses.map(a => transaction(user, c => customer(c, { action: 'default_address', address_id: a.id }, a.revision))));
    assert.equal((await owner.query('select count(*)::int n from public.addresses where user_id=$1 and is_default', [user])).rows[0].n, 1);
  });
  await check('invalid default-address creation rolls back the previous default and its revision', async () => {
    const user = await anotherUser();
    const first = await transaction(user, c => customer(c, address({ is_default: true })));
    await assert.rejects(transaction(user, c => customer(c, address({ is_default: true, line1: 'x' }))));
    const current = (await owner.query('select * from public.addresses where id=$1', [first.id])).rows[0];
    assert.equal(current.is_default, true); assert.equal(Number(current.revision), 0);
  });
  await check('two address editors cannot overwrite the same revision; cross-user writes fail', async () => {
    const user = await anotherUser(), other = await anotherUser();
    const saved = await transaction(user, c => customer(c, address()));
    const results = await Promise.allSettled(['Updated one', 'Updated two'].map(label =>
      transaction(user, c => customer(c, address({ address_id: saved.id, label }), saved.revision))));
    assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
    assert.equal(results.find(r => r.status === 'rejected').reason.code, 'PT409');
    await assert.rejects(transaction(other, c => customer(c, { action: 'delete_address', address_id: saved.id }, 1)), /Address not found/);
    const key = randomUUID();
    await Promise.all(Array.from({ length: 5 }, () => transaction(user, c => customer(c, { action: 'delete_address', address_id: saved.id }, 1, key))));
    assert.equal((await owner.query('select count(*)::int n from public.addresses where id=$1', [saved.id])).rows[0].n, 0);
  });
  await check('profile edits reject stale versions and sync returns the current revision', async () => {
    const user = await anotherUser();
    const results = await Promise.allSettled(['Test Alice', 'Test Bob'].map(full_name =>
      transaction(user, c => customer(c, { action: 'save_profile', full_name, phone: '' }, 0))));
    assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
    assert.equal(results.find(r => r.status === 'rejected').reason.code, 'PT409');
    const snapshot = await transaction(user, c => c.query('select public.sync_store() as data'));
    assert.equal(snapshot.rows[0].data.metadata.profile.revision, 1);
  });
  await check('address books are bounded at 20 records without changing the default on failure', async () => {
    const user = await anotherUser();
    for (let i = 0; i < 20; i++) await transaction(user, c => customer(c, address({ is_default: i === 0 })));
    await assert.rejects(transaction(user, c => customer(c, address({ is_default: true }))), /up to 20 addresses/);
    assert.equal((await owner.query('select count(*)::int n from public.addresses where user_id=$1 and is_default', [user])).rows[0].n, 1);
  });
  await check('two staff pricing edits cannot overwrite the same revision; retries audit once', async () => {
    const other = await anotherUser();
    await owner.query("insert into public.admins(user_id,display_name) values($1,'Second tester')", [other]);
    const revision = (await owner.query('select revision from public.store_settings where id=1')).rows[0].revision;
    const attempts = [[admin, pricing(), randomUUID()], [other, pricing({ requested_delivery_charge_paise: 3000 }), randomUUID()]];
    const results = await Promise.allSettled(attempts.map(([user, mutation, key]) => transaction(user, c => configuration(c, mutation, revision, key))));
    assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
    assert.equal(results.find(r => r.status === 'rejected').reason.code, 'PT409');
    const [user, mutation, key] = attempts[results.findIndex(r => r.status === 'fulfilled')];
    const before = (await owner.query("select count(*)::int n from public.admin_audit_logs where action='update_order_pricing'")).rows[0].n;
    await Promise.all(Array.from({ length: 5 }, () => transaction(user, c => configuration(c, mutation, revision, key))));
    assert.equal((await owner.query("select count(*)::int n from public.admin_audit_logs where action='update_order_pricing'")).rows[0].n, before);
    await assert.rejects(transaction(user, c => configuration(c, pricing({ requested_minimum_order_paise: 100 }), revision, key)), { code: 'PT409' });
  });
  await check('offer creation retries save once and parallel offer editors cannot lose an edit', async () => {
    const mutation = offer(), key = randomUUID();
    const results = await Promise.all(Array.from({ length: 6 }, () => transaction(admin, c => configuration(c, mutation, 0, key))));
    assert.equal(new Set(results.map(r => r.id)).size, 1);
    const id = results[0].id;
    assert.equal((await owner.query("select count(*)::int n from public.admin_audit_logs where action='create_offer' and entity_id=$1", [id])).rows[0].n, 1);
    const edits = await Promise.allSettled(['First title', 'Second title'].map(requested_title =>
      transaction(admin, c => configuration(c, { ...mutation, target_offer_id: id, requested_title }, 0))));
    assert.equal(edits.filter(r => r.status === 'fulfilled').length, 1);
    assert.equal(edits.find(r => r.status === 'rejected').reason.code, 'PT409');
  });
  await check('configuration receipts and unversioned writes are inaccessible to clients', async () => {
    const user = await anotherUser();
    await assert.rejects(transaction(user, c => configuration(c, pricing(), 0)), /Admin access required/);
    await assert.rejects(transaction(admin, c => configuration(c, pricing(), 0), 'authenticated', 'aal1'), /Admin access required/);
    await assert.rejects(transaction(admin, c => c.query('select public.admin_update_order_pricing(0,0,0)')), { code: '42501' });
    await assert.rejects(transaction(user, c => c.query('select * from public.configuration_requests')), { code: '42501' });
    await assert.rejects(transaction(user, c => c.query("update public.profiles set full_name='Bypass' where id=$1", [user])), { code: '42501' });
    await assert.rejects(transaction(user, c => c.query('update public.addresses set is_default=true where user_id=$1', [user])), { code: '42501' });
  });
  await check('account deletion removes customer request receipts and their personal data', async () => {
    const user = await anotherUser();
    await transaction(user, c => customer(c, address()));
    assert.equal((await owner.query('select count(*)::int n from public.configuration_requests where user_id=$1', [user])).rows[0].n, 1);
    await owner.query('delete from auth.users where id=$1', [user]);
    assert.equal((await owner.query('select count(*)::int n from public.configuration_requests where user_id=$1', [user])).rows[0].n, 0);
  });
  await check('a held customer request lock times out without a partial write', async () => {
    const user = await anotherUser();
    let release, ready;
    const held = new Promise(r => release = r), reached = new Promise(r => ready = r);
    const holding = transaction(user, async c => {
      await c.query('select pg_advisory_xact_lock(hashtextextended($1,0))', [user]);
      ready(); await held;
    });
    await reached;
    try { await assert.rejects(transaction(user, c => customer(c, address())), { code: '55P03' }); }
    finally { release(); await holding; }
    assert.equal((await owner.query('select count(*)::int n from public.addresses where user_id=$1', [user])).rows[0].n, 0);
  });
}
