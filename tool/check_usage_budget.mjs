import fs from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

const nonnegative = (n, name) => {
  if (!Number.isFinite(n) || n < 0) throw new Error(`Missing/invalid value: ${name}`);
  return n;
};
export function estimateBudget(config, measured) {
  const t = config.traffic, l = config.limits;
  for (const [key, value] of Object.entries(t)) nonnegative(value, key);
  for (const [key, value] of Object.entries(t).filter(([key]) => key.endsWith('_fraction'))) {
    if (value > 1) throw new Error(`Fraction exceeds 1: ${key}`);
  }
  for (const key of ['cold_response_bytes', 'unchanged_response_bytes', 'single_stock_change_bytes']) nonnegative(measured[key], key);
  const sessions = t.daily_active_users * t.sessions_per_active_day * 30;
  const polls = sessions * t.session_minutes * ((1-t.active_order_session_fraction)/2 + t.active_order_session_fraction*2);
  const imageBytes = sessions * t.images_per_session * (1-t.device_image_cache_hit_fraction) * t.average_image_bytes;
  const apiBytes = t.monthly_active_users * t.cold_catalogues_per_user_month * measured.cold_response_bytes
    + polls * ((1-t.changed_poll_fraction) * measured.unchanged_response_bytes + t.changed_poll_fraction * measured.single_stock_change_bytes)
    + sessions*t.other_api_bytes_per_session + t.admin_hours_per_day*120*30*t.admin_average_sync_bytes;
  const usage = {
    monthly_active_users: t.monthly_active_users,
    // One-year planning horizon, not a claim that historical data stays flat.
    database_bytes: t.database_baseline_bytes + 365*(t.orders_per_day*t.database_bytes_per_order_including_indexes + t.inventory_changes_per_day*t.database_bytes_per_inventory_change),
    storage_bytes: t.storage_current_and_old_image_versions_bytes + 12*t.storage_monthly_growth_bytes,
    // 15% contingency for payload variation, metadata and protocol overhead.
    uncached_egress_bytes: 1.15*(apiBytes+imageBytes*(1-t.cdn_image_cache_hit_fraction)),
    cached_egress_bytes: 1.15*imageBytes*t.cdn_image_cache_hit_fraction,
    realtime_peak_connections: t.peak_staff_sessions,
    realtime_monthly_messages: 30*t.realtime_events_per_day*t.peak_staff_sessions,
    smtp_daily_emails: t.login_emails_per_day,
    smtp_hourly_emails: t.peak_login_emails_per_hour,
    smtp_monthly_emails: 30*t.login_emails_per_day,
  };
  const threshold = config.headroom_fraction;
  if (!(threshold > 0 && threshold <= .8)) throw new Error('Reserve at least 20% headroom');
  const checks = Object.entries(usage).map(([metric, estimate]) => {
    const limit = l[metric];
    if (limit != null) nonnegative(limit, metric);
    return {metric, estimate: Math.ceil(estimate), allowance: limit, fraction: limit > 0 ? +(estimate/limit).toFixed(4) : null,
      status: !(limit > 0) ? 'UNVERIFIED' : estimate <= limit*threshold ? 'PASS_ESTIMATE' : 'REVIEW'};
  });
  return {sessions_per_month: sessions, poll_requests_per_month: Math.ceil(polls), checks};
}

export function launchBlockers(config, estimate, hosted, now = Date.now()) {
  const v = config.verification, reasons = [];
  if (config.assumptions_not_measured) reasons.push('Traffic/image assumptions have not been validated.');
  for (const c of estimate.checks) if (c.status !== 'PASS_ESTIMATE') reasons.push(`${c.metric}: ${c.status}`);
  for (const key of ['custom_smtp_configured','server_auth_rate_limits_configured','physical_devices_checked','hosted_checkout_and_realtime_checked']) {
    if (v[key] !== true) reasons.push(`Not verified: ${key}`);
  }
  const recent = date => Number.isFinite(Date.parse(date)) && now-Date.parse(date) >= 0 && now-Date.parse(date) <= 7*86400000;
  if (!recent(v.provider_dashboards_checked_at)) reasons.push('Provider dashboard evidence must be from the last 7 days.');
  const actuals = {database_actual_bytes:'database_bytes', storage_actual_bytes:'storage_bytes',
    uncached_egress_actual_bytes:'uncached_egress_bytes', cached_egress_actual_bytes:'cached_egress_bytes',
    smtp_daily_actual_emails:'smtp_daily_emails', smtp_hourly_actual_emails:'smtp_hourly_emails',
    smtp_monthly_actual_emails:'smtp_monthly_emails'};
  for (const [field, metric] of Object.entries(actuals)) {
    if (!Number.isFinite(v[field]) || v[field] < 0 || !(config.limits[metric] > 0)) reasons.push(`No valid provider measurement: ${field}`);
    else if (v[field] > config.limits[metric]*config.headroom_fraction) reasons.push(`Current usage above headroom: ${field}`);
  }
  if (!hosted || hosted.environment !== 'Supabase staging HTTP' || hosted.project_ref !== v.staging_project_ref ||
      !recent(hosted.tested_at) || hosted.live_supabase_verified !== true ||
      ![50,100].every(users => hosted.stages?.some(s => s.simultaneous_shoppers === users && s.elapsed_seconds >= 300 && s.errors === 0 && s.requests >= users*2 && s.p95_ms < 2000))) {
    reasons.push('Missing recent passing hosted 50/100-shopper test (at least 5 minutes per stage).');
  }
  return reasons;
}

async function main() {
  const args = process.argv.slice(2), option = (name, fallback) => { const i=args.indexOf(name); return i<0 ? fallback : args[i+1]; };
  const config = JSON.parse(await fs.readFile(option('--config','tool/usage_budget.example.json'),'utf8'));
  const measured = JSON.parse(await fs.readFile('outputs/performance/local-load-report.json','utf8'));
  let hosted = null;
  try { hosted=JSON.parse(await fs.readFile('outputs/performance/staging-load-report.json','utf8')); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  const estimate = estimateBudget(config, measured), blockers = launchBlockers(config, estimate, hosted);
  const report = {generated_at: new Date().toISOString(), planning_only: true, ...estimate, launch_ready: blockers.length===0, blockers};
  await fs.mkdir('outputs/performance',{recursive:true});
  await fs.writeFile('outputs/performance/usage-budget-report.json', JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report,null,2));
  if (args.includes('--check') && blockers.length) process.exitCode=1;
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main().catch(error => { console.error(error.message); process.exitCode=1; });
