// Read-only HTTP load test. No account creation, OTP sends, checkout writes,
// service-role keys or production defaults. Use synthetic staging users only.
import fs from 'node:fs/promises';
import { performance } from 'node:perf_hooks';
import { pathToFileURL } from 'node:url';

export function validateStagingConfig(config, acknowledgedRef, now = Date.now()) {
  const url = new URL(config.url);
  if (config.environment !== 'staging' || !/^[a-z0-9]{20}$/.test(config.project_ref ?? '') ||
      acknowledgedRef !== config.project_ref || url.origin !== `https://${config.project_ref}.supabase.co` ||
      url.pathname !== '/' || url.search || url.hash || url.username || url.password) {
    throw new Error('Use an explicitly acknowledged staging Supabase project; custom/redirect URLs are refused.');
  }
  if (config.synthetic_users_only !== true || config.production_project_ref === config.project_ref ||
      typeof config.production_project_ref !== 'string' || !config.production_project_ref) {
    throw new Error('Declare synthetic_users_only and the protected production ref (or "not-created").');
  }
  const jwt = token => { try { return JSON.parse(Buffer.from(token.split('.')[1],'base64url')); } catch { throw new Error('Invalid test JWT'); } };
  if (typeof config.public_key !== 'string' || (!config.public_key.startsWith('sb_publishable_') && jwt(config.public_key).role !== 'anon')) {
    throw new Error('Use a public anon/publishable key, never a service-role/secret key.');
  }
  if (!Array.isArray(config.access_tokens) || config.access_tokens.length !== 100) throw new Error('Supply 100 existing synthetic customer access tokens; this script never sends emails.');
  const users = new Set();
  for (const token of config.access_tokens) {
    const claims = jwt(token);
    if (claims.role !== 'authenticated' || claims.aud !== 'authenticated' || !claims.sub ||
        claims.iss !== `${url.origin}/auth/v1` || claims.exp*1000 < now+20*60000 || users.has(claims.sub)) {
      throw new Error('Tokens must be unique customer sessions for this project, valid for another 20 minutes.');
    }
    users.add(claims.sub);
  }
  return url.origin;
}

const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
async function main() {
  const args = process.argv.slice(2), option = name => { const i=args.indexOf(name); return i<0 ? null : args[i+1]; };
  const file=option('--config');
  if (!file) throw new Error('Usage: node tool/test_staging_load.mjs --config outputs/performance/staging-config.json --confirm-staging PROJECT_REF');
  const config=JSON.parse(await fs.readFile(file,'utf8'));
  const origin=validateStagingConfig(config,option('--confirm-staging'));
  await fs.mkdir('outputs/performance',{recursive:true});
  // Invalidate an earlier pass before beginning; a stopped run is not evidence.
  await fs.writeFile('outputs/performance/staging-load-report.json',JSON.stringify({
    tested_at:new Date().toISOString(),environment:'Supabase staging HTTP',
    project_ref:config.project_ref,live_supabase_verified:false,stages:[],launch_ready:false,
  },null,2)+'\n');
  const clients = config.access_tokens.map(token => ({token, known_catalogue:{}, known_orders:{}, known_metadata:null}));
  const stages=[];
  let stop=false;
  for (const [count, seconds] of [[50,600],[100,300]]) {
    const start=performance.now(), timings=[], statusCounts={}, sizes=[];
    let errors=0;
    const query=async client => {
      const before=performance.now();
      try {
        const response=await fetch(`${origin}/rest/v1/rpc/sync_store`, {
          method:'POST', redirect:'error', signal:AbortSignal.timeout(15000),
          headers:{apikey:config.public_key, Authorization:`Bearer ${client.token}`, 'Content-Type':'application/json'},
          body:JSON.stringify({known_catalogue:client.known_catalogue,known_orders:client.known_orders,known_metadata:client.known_metadata}),
        });
        statusCounts[response.status]=(statusCounts[response.status]??0)+1;
        if (!response.ok) throw new Error('HTTP failure');
        const body=await response.text(), data=JSON.parse(body);
        if (data.schema!==1 || data.is_admin!==false || !Array.isArray(data.catalogue) || !Array.isArray(data.orders)) throw new Error('Invalid customer snapshot');
        for (const bucket of data.catalogue) client.known_catalogue[bucket.id]=bucket.hash;
        for (const bucket of data.orders) client.known_orders[bucket.id]=bucket.hash;
        client.known_metadata=data.metadata_hash;
        sizes.push(Buffer.byteLength(body));
      } catch {
        errors++; stop=true; // Stop on errors/rate limits instead of retry-storming.
      } finally { timings.push(performance.now()-before); }
    };
    console.log(`Starting ${count} staging shoppers for ${seconds/60} minutes; no emails or writes.`);
    await Promise.all(clients.slice(0,count).map(async (client,index) => {
      // One synchronized initial burst; then normal foreground intervals + jitter.
      while (!stop && performance.now()-start < seconds*1000) {
        await query(client);
        if (stop) break;
        const remaining=seconds*1000-(performance.now()-start);
        if (remaining<=0) break;
        await wait(Math.min(remaining, (index%10===0 ? 30 : 120)*1000+Math.random()*7000));
      }
    }));
    timings.sort((a,b)=>a-b);
    const percentile=p => +(timings[Math.max(0,Math.ceil(timings.length*p)-1)]??0).toFixed(1);
    const stage={simultaneous_shoppers:count,requests:timings.length,errors,p50_ms:percentile(.5),p95_ms:percentile(.95),
      max_ms:percentile(1),elapsed_seconds:Math.round((performance.now()-start)/1000),status_counts:statusCounts,
      response_bytes:sizes.reduce((a,b)=>a+b,0)};
    stages.push(stage); console.log(JSON.stringify(stage));
    if (stop) break;
  }
  const report={tested_at:new Date().toISOString(),environment:'Supabase staging HTTP',project_ref:config.project_ref,
    live_supabase_verified:!stop && stages.length===2 && stages.every(s=>s.p95_ms<2000),
    stages,emails_sent:0,checkout_writes:0,launch_ready:false};
  await fs.mkdir('outputs/performance',{recursive:true});
  await fs.writeFile('outputs/performance/staging-load-report.json',JSON.stringify(report,null,2)+'\n');
  console.log('Saved outputs/performance/staging-load-report.json. Checkout/realtime/device checks remain separate.');
  if (!report.live_supabase_verified) process.exitCode=1;
}
if (process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) main().catch(() => {
  console.error('Staging test refused or failed. Check configuration, synthetic session expiry and explicit staging acknowledgement. No token contents are logged.');
  process.exitCode=1;
});
