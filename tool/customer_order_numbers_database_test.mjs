import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

export async function runCustomerOrderNumberChecks({ owner, transaction, fixture, anotherUser, admin, place, check }) {
  await check('customer sequences start at one independently, while staff references stay globally unique and retries keep the number', async () => {
    const f = await fixture(100);
    const other = await anotherUser(), key = randomUUID();
    const first = await transaction(f.user, c => place(c, f, {key}));
    const second = await transaction(f.user, c => place(c, f));
    const otherFirst = await transaction(other, c => place(c, f));
    assert.equal(await transaction(f.user, c => place(c, f, {key})), first);
    const rows = (await owner.query('select id,customer_order_number::int n,order_number from public.orders where id=any($1::uuid[])',[ [first,second,otherFirst] ])).rows;
    assert.equal(rows.find(r => r.id===first).n,1);
    assert.equal(rows.find(r => r.id===second).n,2);
    assert.equal(rows.find(r => r.id===otherFirst).n,1);
    assert.equal(new Set(rows.map(r=>r.order_number)).size,3);
    assert.equal((await owner.query('select last_number::int n from koyas_private.customer_order_counters where user_id=$1',[f.user])).rows[0].n,2);
    const sync = await transaction(f.user, c => c.query('select public.sync_store() as data'));
    const visible = sync.rows[0].data.orders.flatMap(b=>b.rows);
    assert.deepEqual(visible.map(o=>Number(o.customer_order_number)).sort((a,b)=>a-b),[1,2]);
  });
  await check('simultaneous orders get consecutive customer numbers; cancelled orders keep their number and notification uses it', async () => {
    const f = await fixture(100);
    const ids = await Promise.all(Array.from({length:3},()=>transaction(f.user,c=>place(c,f))));
    const rows = (await owner.query('select customer_order_number::int n from public.orders where user_id=$1 order by customer_order_number',[f.user])).rows;
    assert.deepEqual(rows.map(r=>r.n),Array.from({length:3},(_,i)=>i+1));
    await assert.rejects(transaction(f.user,c=>place(c,f)), {message:'Too many active orders'});
    await transaction(f.user,c=>c.query('select public.cancel_own_order($1)',[ids[0]]));
    const next = await transaction(f.user,c=>place(c,f));
    assert.equal((await owner.query('select customer_order_number::int n from public.orders where id=$1',[next])).rows[0].n,4);
    const cancelled=(await owner.query('select customer_order_number::int n from public.orders where id=$1',[ids[0]])).rows[0].n;
    const notification=(await owner.query('select title,body from public.notification_queue where order_id=$1',[ids[0]])).rows[0];
    assert.equal(notification.title,`Order #${cancelled}`);
    assert.match(notification.body,new RegExp(`^Order #${cancelled}:`));
  });
  await check('rolled-back checkout does not consume a customer number; clients cannot edit numbers or private counters', async () => {
    const f = await fixture(100);
    await assert.rejects(transaction(f.user,async c=>{await place(c,f);throw new Error('rollback QA');}));
    const first=await transaction(f.user,c=>place(c,f));
    assert.equal((await owner.query('select customer_order_number::int n from public.orders where id=$1',[first])).rows[0].n,1);
    await assert.rejects(transaction(f.user,c=>c.query('update public.orders set customer_order_number=900 where id=$1',[first])),{code:'42501'});
    await assert.rejects(transaction(admin,c=>c.query('select * from koyas_private.customer_order_counters')),{code:'42501'});
    await assert.rejects(owner.query('update public.orders set customer_order_number=900 where id=$1',[first]),{message:'An order number cannot be changed'});
  });
}
