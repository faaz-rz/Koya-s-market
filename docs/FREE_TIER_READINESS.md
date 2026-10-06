# Catalogue performance and free-tier launch checks

Implemented locally, 19 September 2026. **Nothing has been deployed.** There is
no verified Supabase/SMTP usage yet. 1,000–1,500 total users is not a throughput
measurement or a guarantee of free hosting.

## Changes

- One `sync_store` RPC replaces repeated full-table REST downloads. The client
  retains a compact complete catalogue for local search, pack-size grouping,
  cart validation and admin inventory. This is not server-side search/pagination.
- Products and orders have 64 deterministic buckets. Only buckets with changed
  fingerprints are returned. Empty replacements remove archived/deleted rows.
  Fingerprints and content come from one SQL snapshot; late commits cannot be
  skipped by a timestamp watermark. Product revisions and order-item triggers
  invalidate changed content. Staff visibility is MFA-aware and user-scoped.
- Public catalogue rows can survive restart for up to 30 days, with a bounded
  disposable disk/browser cache. The server validates fingerprints before use.
  Orders, addresses, profiles and staff billing fields are never persisted there.
  Private-mode/storage failures become ordinary cold loads, not crashes or demo
  fallback. The client still needs network access to open the production store.
- Concurrent reads coalesce. A write during an in-flight read forces another
  snapshot before returning it as the post-write refresh. Unchanged responses
  reuse the previous bundle and do not rebuild the whole store state.
- Customer and staff sessions use one Realtime channel while foregrounded.
  Customer orders are filtered to the signed-in user and RLS remains enforced.
  Product/order events trigger a conditional snapshot after 2 seconds with a
  3-second minimum gap. Safety polling is 120 seconds while browsing, 30 seconds
  with an active order or a failed live connection, plus 0–7 seconds jitter.
  Staff also retain a 30-second fallback. Hidden/background sessions stop
  polling and unsubscribe; failures back off up to 10 minutes. Live updates
  consume Realtime connections/messages and event-triggered snapshot traffic;
  include foreground customers in usage planning. Checkout always rechecks
  authoritative prices, stock and offers transactionally.
- Home initially builds at most 24 featured product families; the full listing
  and local search retain the complete catalogue.
- New staff web picture uploads accept up to 5 MiB input, validate the file,
  resize to at most 960px and encode to at most 150 KiB. Native product-image
  disk caching is bounded to 350 objects with a 30-day stale period; decoded
  image width is capped at 512px. Browsers rely on HTTP caching. Immutable upload
  paths and one-year cache headers avoid re-downloading unchanged pictures.
  This does not recompress old uploads, change exact product photographs, or
  guarantee every image averages 40 KB. The server bucket still allows 5 MB;
  imports outside this UI need their own size audit before uploading.
- Email-code requests deduplicate in flight, enforce a 60-second local cooldown
  and cap attempts at 8 per running app/device-hour, across addresses. A lost
  response retains the cooldown. No automatic resend and no load-test emails.
  This is a UX guard, **not an account-wide security/quota enforcement service**:
  restarting or modifying a client bypasses it. Configure Auth rate limits,
  abuse protection and the SMTP provider's hard limits before public access.

Apply `202609190001_efficient_store_sync.sql` after all earlier migrations in
staging, and release the matching clients together. Old RPCs remain restricted.
Do not roll out the new clients against a database without `sync_store`.

## Local verification versus hosted capacity

Run the disposable PostgreSQL harness described in [CONCURRENCY.md](CONCURRENCY.md):

```sh
node tool/test_concurrent_transactions.mjs --performance
flutter test --no-pub
flutter test --no-pub tool/catalogue_preview_test.dart
flutter test --no-pub --platform chrome test/web/image_optimization_browser_test.dart
flutter analyze --no-pub
node --test tool/product_image_review_test.mjs tool/usage_budget_test.mjs
```

The SQL harness executes real migrations/functions/roles against local PostgreSQL,
with stubs for Supabase Auth and Storage. It verifies stock/checkout races,
unchanged/delta/deletion sync, role changes, order-line edits, late commits and
complete customer/admin history beyond 1,000 orders.

The peak regression uses 10/25/50/100 simulated shoppers and a 24-connection cap,
four synchronized bursts per stage. Ten percent place and cancel a test order
in the first burst; that order/cancellation pair shares a transaction. Queueing
is included in reported latency. It is a **short local regression, not a sustained
Supabase capacity test**, and it does not exercise real email, CDN, mobile
networks or hosted Realtime. Results are saved in
`outputs/performance/local-load-report.json` (machine-specific; not committed).

Initial measurements on this Mac were roughly 838 KB for a cold catalogue,
172 bytes unchanged, and 12 KB for one stock-change section. Sizes are JSON body
bytes, not provider billing measurements or compressed wire bytes. Bucket size,
number of changed products, order history and image URLs affect real usage.

Local verification completed: 167 Flutter tests, 2 Chromium image-encoding
tests, 4 rendered catalogue previews, 12 Node checks and 26 PostgreSQL
correctness/sync scenarios passed. Flutter analysis was clean, and customer
and admin release web builds compiled. The local 50/100-shopper bursts had
zero errors; p95 was approximately 183/353 ms on this Apple M5, respectively.
These results do not certify physical phones, hosted capacity or email delivery.

### Hosted staging test — required before launch

1. Create an isolated staging project with the actual catalogue, realistic order
   history and the matching migrations. Do not load-test production. Provision
   100 **synthetic** customers out of band without sending real login emails;
   obtain their existing access tokens securely. No service-role key belongs in
   the test config or client. Tokens must remain valid for another 20 minutes.
2. Create ignored `outputs/performance/staging-config.json` with this shape:

   ```json
   {
     "environment": "staging",
     "project_ref": "YOUR_20_CHARACTER_REF",
     "url": "https://YOUR_20_CHARACTER_REF.supabase.co",
     "production_project_ref": "not-created",
     "synthetic_users_only": true,
     "public_key": "YOUR_PUBLIC_PUBLISHABLE_OR_ANON_KEY",
     "access_tokens": ["EXACTLY_100_DISTINCT_SYNTHETIC_CUSTOMER_ACCESS_TOKENS"]
   }
   ```

   Set the real protected production ref if one exists. Never commit this file
   or share its token contents. The entire `outputs/` directory is gitignored.
3. Run only after explicitly confirming the staging target:

   ```sh
   node tool/test_staging_load.mjs \
     --config outputs/performance/staging-config.json \
     --confirm-staging YOUR_20_CHARACTER_REF
   ```

   This makes read-only HTTP requests: 50 shoppers for 10 minutes, then 100 for
   5 minutes, normal polling intervals/jitter and a cold-start burst. It refuses
   secret keys, production declarations, wrong-project/expired/duplicate tokens
   and redirects. It stops on errors rather than retrying aggressively. Target:
   zero errors and p95 below 2 seconds per stage. Output contains timings and
   counts, not tokens, emails or customer response data.
4. Separately repeat checkout/last-item/two-admin/refresh races through hosted
   PostgREST with staging fixtures, and observe real customer and staff Realtime. Verify
   small Android/iPhone devices, weak networks, background/resume, app restart,
   browser cache, image replacement, MFA expiry and email delivery. The HTTP
   runner is not a checkout or visual device test. Check CPU/DB metrics and
   billing dashboards during the run; it still consumes staging quotas.

## Budget and launch gate

```sh
node tool/check_usage_budget.mjs
node tool/check_usage_budget.mjs --config outputs/performance/usage-budget.json --check
```

Start a private config from `tool/usage_budget.example.json`, replace assumptions
with measured values, and fill the verification fields. `--check` intentionally
exits nonzero with the example config. It requires headroom (75% by default),
known SMTP allowances, fresh provider-dashboard measurements, physical-device /
hosted-transaction checks and a passing recent hosted 50/100-shopper report.
This is an explicit release checklist command, not an automatically installed
deployment block. Do not bypass it to label the application production-ready.

The example assumes 1,500 monthly/150 daily active customers, 1.2 sessions per
active day, five-minute visits, 24 pictures/session, 40 KB pictures, 65% device
cache reuse and 85% CDN hits. Cold catalogue loads are budgeted twice per monthly
customer; browsing, other API calls and eight daily staff hours are included.
There is a 15% traffic contingency. DB and storage estimates have a one-year
growth horizon, including order indexes, retry receipts and old image versions.
They are not measurements. Changed-poll bytes currently use the measured
single-stock-edit response: replace this with a representative *multi-edit*
response from staging if busy periods modify several buckets.

Under these assumptions the first estimate is about **4.2 GB uncached egress**,
above the 3.75 GB safety budget for a 5 GB allowance. Do not infer that the store
will certainly fit free tier. Measure cold-cache frequency, representative
multi-product updates, actual admin history responses and image compression;
then reduce unnecessary traffic or choose more capacity if headroom still fails.
Never silently hide orders, drop checkout transactions, or delete customer data
just to satisfy a hosting allowance.

Staff can use **Check hosting usage** to query DB size, image-bucket size and
order/retry-receipt counts on demand. It warns at 75%. DB size is an estimate;
the provider's accounting is authoritative, and other buckets/projects can
consume shared allowances. Bandwidth/Auth/SMTP must be checked in their provider
dashboards. During pilot operation check daily, extrapolate monthly traffic,
and investigate at 50%, act at 75%, and avoid launching campaigns near 90%.
No automatic monitoring job, deletion or provider billing change was created.

## Provider limits checked 19 September 2026

- [Supabase pricing](https://supabase.com/pricing): Free includes 50,000 MAU,
  500 MB database, 1 GB file storage, 5 GB egress and 5 GB cached egress, plus
  200 peak Realtime connections / 2 million monthly messages. These are separate
  budgets, not interchangeable. Recheck the account's scope and billing cycle.
  Free projects may pause after inactivity and lack automatic backups/SLA;
  capacity estimates alone do not guarantee uninterrupted operation.
- [Auth SMTP guidance](https://supabase.com/docs/guides/auth/auth-smtp) and
  [Auth rate limits](https://supabase.com/docs/guides/auth/rate-limits): built-in
  email is restricted to authorized team addresses and is not for public
  production delivery; its default send allowance is only two per hour.
  A custom SMTP provider is required, with verified daily/hourly/monthly limits
  and sender setup. Custom SMTP can have separate costs and deliverability rules.
- [Storage CDN](https://supabase.com/docs/guides/storage/cdn/fundamentals) and
  [cached_network_image](https://pub.dev/packages/cached_network_image): native
  disk caching and browser HTTP caching differ; do not assume all image bytes
  are served locally or that all CDN traffic is free.

Static admin hosting is another separate budget. Confirm a commercial-use plan
before selecting the host; none has been deployed or purchased in this task.
