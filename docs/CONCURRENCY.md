# Checkout and inventory concurrency

Implemented locally on 17 September 2026. No live Supabase database has been
modified and no Vercel deployment has been performed.

## Database protections

Apply `supabase/migrations/202609170001_concurrent_transactions.sql` after the
existing migrations, first in staging. It does not reset prices, stock or pictures.

- Checkout locks the customer, offer, fulfilment slot, and basket/free-gift
  products in UUID order. Stock, order lines, discounts, gift reservations and
  offer redemption commit together or roll back together.
- A checkout key is bound to its canonical basket, address, date, slot, payment
  method, instructions and offer. An identical retry returns the original ID;
  a changed request returns a conflict. Legacy orders without the fingerprint
  return a conflict rather than guessing.
- Product revisions increment on every update, including checkout/restoration.
  Full saves and counted-stock replacements require the admin's viewed revision.
  A stale edit returns `PT409`; it cannot silently restore sold stock.
- Stock +/- controls are atomic deltas. Each staff mutation has a request UUID
  and transactionally stored receipt. Repeated requests cannot apply the delta
  twice or create a second product. Receipts are private; active-staff checks
  remain required.
- Cancellation/rejection lock the order and products; identical transition
  retries cannot double-restore stock. Expiry workers claim whole batches with
  `SKIP LOCKED` and lock all affected products in UUID order.
- Existing cash/UPI payment confirmation is row-locked and idempotent; concurrent
  confirmations are tested to produce one audit event.

Old unversioned product-save/stock RPCs are revoked from browser/mobile roles.
**Deploy the matching admin client alongside this migration.** Older admin
clients fail safely rather than bypass revision checks. Keep receipts while
clients might retry; deleting them removes replay protection for those IDs.

New entry points bound lock acquisition to five seconds. The app uses at most
three attempts with short backoff for database deadlocks, serialization failures,
lock timeouts and temporary gateway/timeout failures. Only idempotent operations
are retried, with unchanged keys/payloads. Validation errors are not auto-retried.

## App and admin behaviour

- Double submissions share one in-flight checkout. An uncertain response retains
  the basket/date/key across payment-screen recreation in the same session.
  Confirmation removes only submitted cart quantities, not newer additions.
- A committed checkout followed by a failed refresh still shows "Order received".
  It does not ask the customer to place another order.
- Staff saves refresh server data without merging stale product fields over it.
  Conflict messages request a refresh. A committed save with a failed refresh
  is distinguished from an unconfirmed save.
- Retried image uploads use the same per-request path. Client-side deletion is
  deferred because an uncertain save or concurrent editor may reference an
  image. Old/unreferenced objects consume storage until a separate, reference-aware
  server cleanup process is implemented.
- Out-of-order loads cannot replace newer completed loads. Product revisions
  prevent stock display regression; valid delivery/address/slot choices survive
  same-user realtime refreshes.
- Demo stock writes also check/increment revisions. Demo mode is local to each
  process, not a shared multi-user database.

## Local verification

The SQL harness starts disposable PostgreSQL 17 on a random loopback port and
applies **every repository migration**. Auth/storage schema stubs allow the real
functions, triggers, constraints, RLS and roles to run. Concurrent transactions
use separate database connections. It accepts no remote DB URL, stops its server
on exit, and prints the retained temporary database/log path for inspection.

Install the test-only runtime outside the repository:

```sh
export KOYAS_PG_RUNTIME="$(mktemp -d /tmp/koyas-concurrency.XXXXXX)"
npm install --prefix "$KOYAS_PG_RUNTIME" --no-audit --no-fund \
  embedded-postgres@17.10.0-beta.17 pg@8.23.0
node tool/test_concurrent_transactions.mjs
```

On Apple Silicon, the runtime used here runs the packaged macOS PostgreSQL
binary under Rosetta. If npm blocks its platform package's postinstall script,
inspect and explicitly allow `scripts/hydrate-symlinks.js` before retrying.
This runtime is developer tooling, not an app dependency.

```sh
flutter test --no-pub test/concurrent_transactions_test.dart
flutter test --no-pub
flutter analyze --no-pub
node --test tool/product_image_review_test.mjs
flutter build web --release --no-pub -t lib/main.dart
flutter build web --release --no-pub -t lib/admin_main.dart
```

The 19 PostgreSQL scenarios cover last-unit sales, checkout retries, changed
payloads, slot capacity, rollback, stale edits, stock deltas, an explicitly held
uncommitted checkout, cancellation races, opposite basket/gift lock order, offer
limits, same-SKU gifts, concurrent expiry, creation retries, payment confirmation
and role/RPC bypass attempts. This is a correctness suite, not a capacity benchmark.

## Before production

1. Apply migrations to staging and deploy the matching clients. Never expose a
   service-role key in either client.
2. Repeat two-device/two-admin scenarios using actual Supabase email Auth,
   PostgREST, Storage and Realtime, including deliberately dropped responses.
3. Test physical Android/iPhone devices and target browsers. Widget tests and
   web compilation do not replace device/integration testing.
4. Establish expiry scheduling, monitoring, backups, receipt retention and safe
   storage cleanup. Load-test expected volume: same-slot and hot-SKU writes
   necessarily serialize to enforce capacity and stock.

Pending client request identities are **in memory**, not crash-persistent. After
a reload/restart with an uncertain result, inspect Orders/inventory before
starting another operation. Different devices using different keys intentionally
create separate orders. The new `sync_store` refresh is one database snapshot;
foreground Realtime events trigger debounced conditional refreshes, with polling
as a fallback. Stock button drafts save as one atomic delta; typed physical
counts retain their revision check.
Checkout RPCs revalidate authoritative prices/stock. See
[FREE_TIER_READINESS.md](FREE_TIER_READINESS.md) for sync/load tests and limits.
Offer/pricing form edits still use their existing last-writer behaviour; product
revision protection does not version every configuration screen.

Online gateway payments/refunds remain disabled in this release. Provider
callbacks, late captures, reconciliation and refunds require a separate
end-to-end audit before activation. Expiry tests do not certify those integrations.

Design references: PostgreSQL's [explicit locking guidance](https://www.postgresql.org/docs/17/explicit-locking.html)
and [transaction isolation documentation](https://www.postgresql.org/docs/17/transaction-iso.html).
