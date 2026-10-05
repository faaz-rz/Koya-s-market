import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

export async function runDeletionChecks({ owner, transaction, anotherUser, fixture, place, admin, check }) {
  const email = 'customer@example.test';
  const service = fn => transaction(null, fn, 'service_role');
  const begin = user => service(c => c.query('select public.begin_account_deletion_otp($1,$2) result', [user,email])).then(r => r.rows[0].result);
  const claim = (user, id, address = email) => service(c => c.query('select public.claim_account_deletion_attempt($1,$2,$3) result',[user,id,address])).then(r => r.rows[0].result);
  const consume = (user,id,address = email) => service(c => c.query('select public.consume_account_deletion_otp($1,$2,$3) result',[user,id,address])).then(r => r.rows[0].result);
  const pending = user => owner.query("update public.account_deletion_challenges set status='pending' where user_id=$1",[user]);
  const age = user => owner.query("update public.account_deletion_challenges set last_sent_at=now()-interval '61 seconds' where user_id=$1",[user]);

  await check('deletion challenges and service RPCs are inaccessible to app clients', async () => {
    const user = await anotherUser();
    for (const role of ['anon','authenticated']) {
      for (const sql of ['select * from public.account_deletion_challenges',
        `select public.begin_account_deletion_otp('${user}','${email}')`,
        `select public.claim_account_deletion_attempt('${user}','${randomUUID()}','${email}')`,
        `select public.consume_account_deletion_otp('${user}','${randomUUID()}','${email}')`]) {
        await assert.rejects(transaction(user,c => c.query(sql),role), { code: '42501' });
      }
    }
  });
  await check('12 concurrent deletion code requests reserve one send; hourly quota survives failures', async () => {
    const user = await anotherUser();
    const results = await Promise.all(Array.from({ length: 12 }, () => begin(user)));
    assert.equal(results.filter(r => r.ok).length, 1);
    assert.ok(results.filter(r => !r.ok).every(r => r.code === 'rate_limited' && r.retry_after > 0));
    for (let i=1; i<8; i++) { await age(user); assert.equal((await begin(user)).ok,true); }
    await age(user); assert.equal((await begin(user)).code,'rate_limited');
    await owner.query("update public.account_deletion_challenges set window_started_at=now()-interval '61 minutes' where user_id=$1",[user]);
    assert.equal((await begin(user)).ok,true);
  });
  await check('five attempts maximum under parallel guessing and one proof consumption', async () => {
    const user = await anotherUser(), { challenge_id: id } = await begin(user);
    assert.equal((await claim(user,id)).code,'otp_expired'); // send must finish first
    await pending(user);
    const results = await Promise.all(Array.from({ length: 12 }, () => claim(user,id)));
    assert.equal(results.filter(r => r.ok).length,5);
    assert.ok(results.filter(r => !r.ok).every(r => r.code === 'attempts_exhausted'));
    const consumed = await Promise.all(Array.from({ length: 12 }, () => consume(user,id)));
    assert.equal(consumed.filter(Boolean).length,1);
    assert.equal((await claim(user,id)).code,'otp_expired');
    await age(user); assert.equal((await begin(user)).code,'deletion_in_progress');
  });
  await check('expired, replaced, cross-user and changed-email challenges cannot authorize deletion', async () => {
    const user = await anotherUser(), other = await anotherUser();
    const { challenge_id: id } = await begin(user); await pending(user);
    for (const [target, address] of [[other,email],[user,'different@example.test']]) {
      assert.equal((await claim(target,id,address)).code,'otp_expired');
      assert.equal(await consume(target,id,address),false);
    }
    assert.equal(await consume(user,id),false); // must claim an attempt first
    await age(user); const replacement = await begin(user); await pending(user);
    assert.notEqual(replacement.challenge_id,id);
    assert.equal((await claim(user,id)).code,'otp_expired');
    await owner.query("update public.account_deletion_challenges set expires_at=now()-interval '1 second' where user_id=$1",[user]);
    assert.equal((await claim(user,replacement.challenge_id)).code,'otp_expired');
    assert.equal(await consume(user,replacement.challenge_id),false);
  });
  await check('staff and active orders block deletion; completed records are fully anonymized', async () => {
    assert.equal((await begin(admin)).code,'staff_account');
    const f = await fixture(); const id = await transaction(f.user,c => place(c,f,{ instructions: 'Private door code 1234' }));
    assert.equal((await begin(f.user)).code,'active_orders');
    await assert.rejects(owner.query('delete from auth.users where id=$1',[f.user]), /active orders/);
    await owner.query("update public.orders set order_status='cancelled' where id=$1",[id]);
    assert.equal((await begin(f.user)).ok,true);
    await owner.query('delete from auth.users where id=$1',[f.user]);
    const record = (await owner.query('select * from public.orders where id=$1',[id])).rows[0];
    assert.equal(record.user_id,null); assert.equal(record.checkout_request,null);
    assert.equal(record.delivery_instructions,''); assert.equal(record.customer_name_snapshot,'Deleted customer');
    assert.equal(record.customer_phone_snapshot,''); assert.equal(record.delivery_recipient_phone_snapshot,null);
    assert.equal((await owner.query('select * from public.account_deletion_challenges where user_id=$1',[f.user])).rowCount,0);
    assert.equal((await owner.query('select * from public.profiles where id=$1',[f.user])).rowCount,0);
  });
  await check('concurrent checkout and account deletion cannot orphan an active order', async () => {
    for (let i=0; i<8; i++) {
      const f = await fixture();
      await Promise.allSettled([
        transaction(f.user,c => place(c,f)),
        transaction(null,c => c.query('delete from auth.users where id=$1',[f.user]),'postgres'),
      ]);
      const orders = (await owner.query('select o.user_id,u.id from public.orders o left join auth.users u on u.id=o.user_id where o.id in (select order_id from public.order_items where product_id=$1)',[f.product])).rows;
      for (const order of orders) { assert.equal(order.user_id,f.user); assert.equal(order.id,f.user); }
    }
  });
}
