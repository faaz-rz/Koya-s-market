import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { estimateBudget, launchBlockers } from './check_usage_budget.mjs';
import { validateStagingConfig } from './test_staging_load.mjs';

const example=JSON.parse(await fs.readFile(new URL('./usage_budget.example.json',import.meta.url),'utf8'));
const measured={cold_response_bytes:838236,unchanged_response_bytes:172,single_stock_change_bytes:11979};
test('usage planning flags unknown SMTP and never treats local load as launch evidence', () => {
  const estimate=estimateBudget(example,measured);
  assert.equal(estimate.checks.find(c=>c.metric==='smtp_daily_emails').status,'UNVERIFIED');
  assert.ok(launchBlockers(example,estimate,{environment:'isolated local PostgreSQL',live_supabase_verified:false}).length>0);
});
test('bandwidth includes cold catalogues, images, admin traffic and contingency', () => {
  const estimate=estimateBudget(example,measured);
  const bytes=estimate.checks.find(c=>c.metric==='uncached_egress_bytes');
  assert.ok(bytes.estimate>1500*2*838236);
  const busier=structuredClone(example); busier.traffic.daily_active_users*=3;
  assert.ok(estimateBudget(busier,measured).checks.find(c=>c.metric==='uncached_egress_bytes').estimate>bytes.estimate);
  assert.equal(bytes.status,'REVIEW');
});
test('invalid fractions and missing measurements cannot pass a budget', () => {
  assert.throws(()=>estimateBudget(example,{}));
  const invalid=structuredClone(example); invalid.traffic.device_image_cache_hit_fraction=2;
  assert.throws(()=>estimateBudget(invalid,measured));
});
test('foreground customer live subscriptions count toward connections, messages and bandwidth', () => {
  const estimate=estimateBudget(example,measured);
  assert.equal(estimate.checks.find(c=>c.metric==='realtime_peak_connections').estimate, 102);
  const busier=structuredClone(example);
  busier.traffic.average_foreground_customer_sessions=100;
  const busy=estimateBudget(busier,measured);
  assert.ok(busy.checks.find(c=>c.metric==='realtime_monthly_messages').estimate>estimate.checks.find(c=>c.metric==='realtime_monthly_messages').estimate);
  assert.ok(busy.checks.find(c=>c.metric==='uncached_egress_bytes').estimate>estimate.checks.find(c=>c.metric==='uncached_egress_bytes').estimate);
});
const ref='abcdefghijklmnopqrst', now=Date.now();
const token=data=>`test.${Buffer.from(JSON.stringify(data)).toString('base64url')}.test`;
const config=()=>({environment:'staging',project_ref:ref,url:`https://${ref}.supabase.co`,
  public_key:'sb_publishable_test',production_project_ref:'not-created',synthetic_users_only:true,
  access_tokens:Array.from({length:100},(_,i)=>token({role:'authenticated',aud:'authenticated',sub:`user${i}`,iss:`https://${ref}.supabase.co/auth/v1`,exp:Math.floor(now/1000)+3600}))});
test('staging preflight permits only explicit staging with existing distinct sessions', () => {
  assert.equal(validateStagingConfig(config(),ref,now),`https://${ref}.supabase.co`);
  assert.throws(()=>validateStagingConfig(config(),'wrong',now));
  for (const changes of [{environment:'production'},{production_project_ref:ref},{public_key:'sb_secret_never'},
    {public_key:token({role:'service_role'})},{url:'https://unrelated.example'},{synthetic_users_only:false},
    {access_tokens:Array(100).fill(config().access_tokens[0])}]) {
    assert.throws(()=>validateStagingConfig({...config(),...changes},ref,now));
  }
});
test('expired/wrong-project tokens are refused before making a network request', () => {
  const c=config(); c.access_tokens[0]=token({role:'authenticated',aud:'authenticated',sub:'expired',exp:0,iss:`${c.url}/auth/v1`});
  assert.throws(()=>validateStagingConfig(c,ref,now));
  const wrong=config(); wrong.access_tokens[0]=token({role:'authenticated',aud:'authenticated',sub:'wrong',exp:9999999999,iss:'https://other.supabase.co/auth/v1'});
  assert.throws(()=>validateStagingConfig(wrong,ref,now));
});
