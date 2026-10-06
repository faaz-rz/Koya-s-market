import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

export async function runCustomerDeliveryChecks({owner,transaction,fixture,anotherUser,admin,place,check}) {
  const pin = {latitude:17.386,longitude:78.419,accuracy_meters:12,captured_at_ms:Date.now()};
  const save = (user, mutation, revision = null, key = randomUUID()) => transaction(user, c =>
    c.query('select public.mutate_customer($1,$2,$3::jsonb) as saved',[key,revision,JSON.stringify(mutation)]).then(r => r.rows[0].saved));
  const address = (overrides = {}) => ({action:'save_address',label:'Home',recipient_name:'Delivery test',phone:'9876543210',
    line1:'12 Test Street',city:'Hyderabad',pincode:'500008',is_default:false,delivery_pin:pin,...overrides});
  await check('delivery pins validate, remain owned, and address retries save once', async () => {
    const user = await anotherUser(), other = await anotherUser(), key = randomUUID();
    const a = await save(user,address(),null,key);
    assert.deepEqual(a.delivery_pin,pin);
    assert.equal((await save(user,address(),null,key)).id,a.id);
    assert.equal((await transaction(other,c=>c.query('select delivery_pin from public.addresses where id=$1',[a.id]))).rows.length,0);
    await assert.rejects(save(other,address({address_id:a.id}),a.revision),/Address not found/);
    for (const bad of [{...pin,latitude:91},{...pin,longitude:-181},{...pin,accuracy_meters:-1},{...pin,latitude:null},{...pin,captured_at_ms:'bad'},'bad',{}]) {
      await assert.rejects(save(user,address({delivery_pin:bad})), {code:'23514'});
    }
    const moved = await save(user,address({address_id:a.id,delivery_pin:{...pin,latitude:17.387}}),a.revision);
    await assert.rejects(save(user,address({address_id:a.id}),a.revision),{code:'PT409'});
    // A legacy client that omits the field must preserve a pin; explicit null removes it.
    const legacy = address({address_id:a.id}); delete legacy.delivery_pin;
    const retained = await save(user,legacy,moved.revision);
    assert.equal(retained.delivery_pin.latitude,17.387);
    const removed = await save(user,address({address_id:a.id,delivery_pin:null}),retained.revision);
    assert.equal(removed.delivery_pin,null);
  });
  await check('order pins are immutable address snapshots, visible only to owner/MFA staff, and erased on account deletion', async () => {
    const f = await fixture(5);
    await owner.query("insert into public.serviceable_pincodes(pincode) values('500008') on conflict do nothing");
    const slot = randomUUID();
    await owner.query("insert into public.fulfilment_slots(id,fulfilment_type,label,start_time,end_time,max_orders) values($1,'delivery',$2,'00:00','23:59',100)",[slot,randomUUID()]);
    const a = await save(f.user,address());
    const key = randomUUID();
    const order = await transaction(f.user,c=>c.query("select public.place_order_v2($1::jsonb,'delivery',$2,current_date,$3,'cash_on_delivery','Test landmark',$4,null) as id",[
      JSON.stringify([{product_id:f.product,quantity:1}]),a.id,slot,key]).then(r=>r.rows[0].id));
    assert.deepEqual((await owner.query('select delivery_pin from public.orders where id=$1',[order])).rows[0].delivery_pin,pin);
    await save(f.user,address({address_id:a.id,delivery_pin:null,line1:'Changed address'}),a.revision);
    const read = async(user,aal='aal1') => (await transaction(user,c=>c.query('select delivery_pin from public.orders where id=$1',[order]),'authenticated',aal)).rows;
    assert.deepEqual((await read(f.user))[0].delivery_pin,pin);
    assert.equal((await read(await anotherUser())).length,0);
    assert.equal((await read(admin)).length,0);
    assert.deepEqual((await read(admin,'aal2'))[0].delivery_pin,pin);
    for (const status of ['confirmed','preparing','ready_for_dispatch','out_for_delivery']) {
      await transaction(admin,c=>c.query('select public.update_order_status($1,$2)',[order,status]));
    }
    await transaction(admin,c=>c.query("select public.update_order_status($1,'out_for_delivery')",[order]));
    assert.equal((await owner.query("select count(*)::int n from public.notification_queue where order_id=$1 and data->>'status'='out_for_delivery'",[order])).rows[0].n,1);
    await transaction(admin,c=>c.query('select public.admin_mark_order_paid($1)',[order]));
    await transaction(admin,c=>c.query("select public.update_order_status($1,'delivered')",[order]));
    await owner.query('delete from auth.users where id=$1',[f.user]);
    const deleted = (await owner.query('select delivery_pin,user_id,delivery_address_text from public.orders where id=$1',[order])).rows[0];
    assert.equal(deleted.delivery_pin,null); assert.equal(deleted.user_id,null);
    assert.equal(deleted.delivery_address_text,'Removed after account deletion');
  });
  await check('pickup readiness is queued once without coordinates or duplicate retry notification', async () => {
    const f = await fixture(); const id = await transaction(f.user,c=>place(c,f));
    await transaction(admin,c=>c.query("select public.update_order_status($1,'ready_for_pickup')",[id]));
    await transaction(admin,c=>c.query("select public.update_order_status($1,'ready_for_pickup')",[id]));
    const queued = (await owner.query('select data from public.notification_queue where order_id=$1',[id])).rows;
    assert.equal(queued.length,1); assert.equal(queued[0].data.status,'ready_for_pickup');
    assert.equal((await owner.query('select delivery_pin from public.orders where id=$1',[id])).rows[0].delivery_pin,null);
  });
}
