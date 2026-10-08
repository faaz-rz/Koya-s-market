import assert from 'node:assert/strict';
import {test} from 'node:test';
import {createDispatchHandler,notificationPayload} from '../supabase/functions/send-order-notifications/handler.ts';
const secret='only-test-authorization-'.repeat(3);
const event={id:'event',user_id:'alice',data:{order_id:'order',status:'ready_for_pickup'},body:'Your order is ready for pickup',claim_token:'lease',delivered_device_ids:[]};
function fixture(overrides={}) {
  const calls=[];
  const fn=(name,value)=>async(...args)=>{calls.push([name,...args]);return value;};
  const deps={authorize:fn('authorize',true),configured:()=>true,accessToken:fn('access','test-token'),claim:fn('claim',[structuredClone(event)]),
    devices:fn('devices',[{id:'first',user_id:'alice',token:'device-a'},{id:'second',user_id:'alice',token:'device-b'}]),
    current:fn('current',true),acknowledge:fn('ack',true),finish:fn('finish',true),removeDevice:fn('remove'),
    send:fn('send',{ok:true,unregistered:false}),now:()=>0,...overrides};
  return {calls,handler:createDispatchHandler(deps)};
}
const post=(handler,key=secret)=>handler(new Request('https://edge.test/push',{method:'POST',headers:{'x-koyas-webhook-secret':key}}));
test('unauthorized, missing credentials and provider auth failure never claim or lose a queued event',async()=>{
  for(const overrides of [{authorize:async()=>false},{configured:()=>false},{accessToken:async()=>{throw Error('credentials');}}]) {
    const {calls,handler}=fixture(overrides);const response=await post(handler);
    assert.ok([401,503].includes(response.status));assert.ok(!calls.some(c=>c[0]==='claim'));
  }
});
test('partial delivery retries only the failed device and retains a stable OS notification identity',async()=>{
  let first=true;
  const {calls,handler}=fixture({send:async(_,n,device)=>({ok:device.id==='first',unregistered:false})});
  await post(handler);
  assert.equal(calls.filter(c=>c[0]==='ack').length,1);
  assert.equal(calls.find(c=>c[0]==='finish')[2],false);
  const retry=fixture({claim:async()=>[{...event,delivered_device_ids:['first']}]});await post(retry.handler);
  assert.equal(retry.calls.filter(c=>c[0]==='send').length,1);
  assert.equal(retry.calls.find(c=>c[0]==='send')[3].id,'second');
  const payload=notificationPayload(event,{token:'device',sound_enabled:false});
  assert.equal(payload.message.android.notification.channel_id,'customer_order_updates_silent_v1');
  assert.equal(payload.message.apns.payload.aps.sound,undefined);
  assert.equal(payload.message.android.notification.tag,event.id);
  assert.equal(payload.message.data.user_id,'alice');
  assert.equal(payload.message.android.priority,'high');
  assert.equal(payload.message.android.notification.notification_priority,'PRIORITY_HIGH');
  assert.equal(payload.message.android.notification.visibility,'PUBLIC');
});
test('obsolete status and cross-account device rows cannot dispatch an order message',async()=>{
  const stale=fixture({current:async()=>false});await post(stale.handler);
  assert.equal(stale.calls.filter(c=>c[0]==='send').length,0);
  const foreign=fixture({devices:async()=>[{id:'foreign',token:'device',user_id:'bob'}]});await post(foreign.handler);
  assert.equal(foreign.calls.filter(c=>c[0]==='send').length,0);
});
test('revoked tokens are removed, failed transport releases the lease, and responses never expose tokens',async()=>{
  const invalid=fixture({send:async()=>({ok:false,unregistered:true})});await post(invalid.handler);
  assert.equal(invalid.calls.filter(c=>c[0]==='remove').length,2);
  const failed=fixture({send:async()=>{throw Error('secret-device-token');}});
  const response=await post(failed.handler);assert.equal(response.status,503);
  assert.ok(!(await response.text()).includes('secret-device-token'));
  assert.equal(failed.calls.find(c=>c[0]==='finish')[2],false);
});
test('private configuration validation never claims or sends, and rejects failed provider validation',async()=>{
  for(const [allowed,expected] of [[true,200],[false,503]]) {
    const {calls,handler}=fixture({projectId:()=> 'koya-stores',validate:async()=>allowed});
    const response=await handler(new Request('https://edge.test/push',{method:'POST',headers:{
      'x-koyas-webhook-secret':secret,'x-koyas-check-config':'true','x-koyas-validation-token':'private-qa-device-token'}}));
    assert.equal(response.status,expected);
    const body=await response.text();assert.ok(!body.includes('private-qa-device-token'));
    if(allowed) assert.deepEqual(JSON.parse(body),{ready:true,project_id:'koya-stores',provider_validated:true,claimed:0});
    assert.ok(!calls.some(c=>['claim','devices','send','ack','finish'].includes(c[0])));
  }
  const blocked=fixture({authorize:async()=>false});
  const denied=await blocked.handler(new Request('https://edge.test/push',{method:'POST',headers:{
    'x-koyas-webhook-secret':secret,'x-koyas-check-config':'true'}}));
  assert.equal(denied.status,401);assert.ok(!blocked.calls.some(c=>c[0]==='access'));
});
test('private delivery QA requires authorization and a token, sends only a fixed probe and never claims customer work',async()=>{
  for(const [allowed,token,expected] of [[false,'qa-token',401],[true,null,400],[true,'qa-token',200]]) {
    let sent=0;
    const {calls,handler}=fixture({authorize:async()=>allowed,testDelivery:async()=>{sent++;return true;}});
    const headers={'x-koyas-webhook-secret':secret,'x-koyas-test-delivery':'true'};
    if(token) headers['x-koyas-validation-token']=token;
    const response=await handler(new Request('https://edge.test/push',{method:'POST',headers}));
    assert.equal(response.status,expected);
    assert.equal(sent,expected===200?1:0);
    assert.ok(!calls.some(c=>['claim','devices','send','ack','finish'].includes(c[0])));
    assert.ok(!(await response.text()).includes('qa-token'));
  }
});
