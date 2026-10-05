# Request protocols

The client and database now use the same rules for every mutating request:

- Checkout, inventory changes, pricing, offers, profiles, and addresses use a
  stable request UUID. A retry with the same UUID returns the original receipt;
  reusing it with different details returns a conflict.
- Product, offer, settings, profile, and address revisions reject stale editors
  with `PT409`. Address default changes and profile updates run in one database
  transaction, so a lost response cannot leave half a change.
- Stock and checkout locks use a consistent order and a five-second lock
  timeout. The client retries only transient lock/deadlock/timeout failures,
  with the same payload and request ID, up to three attempts.
- Logout, account deletion, session refresh, and user switching invalidate the
  in-memory request scope. A late response cannot hydrate or mutate the next
  session.
- Reads coalesce and verify the session again after the response. A write during
  a read triggers a post-write snapshot before the UI accepts the refresh.

The app uses email OTP for customer and staff sign-in. Phone/SMS authentication
is disabled in `supabase/config.toml`; profile phone numbers are contact fields,
not authentication factors. Email delivery remains subject to the selected
SMTP provider's allowance. The hosted Supabase project must mirror the email
settings and use a verified sender before launch.

When the network fails, the shared HTTP client marks the session offline and the
app shows “No internet connection” in a persistent accessible banner. API errors
from a reachable server remain server errors. A timed-out mutation keeps its
request identity so the user can retry safely; checkout keeps the original cart
and tells the user to check Orders before starting another attempt.

Loading controls use the shared four-dot animation: four dots orbit, grow, and
shrink in each turn. Reduced-motion settings show a still indicator. Buttons
retain their layout while loading and reject duplicate taps.

Apply `supabase/migrations/202610050001_request_protocols.sql` after all earlier
migrations. Deploy its matching client at the same time. The local database
runner in `tool/test_concurrent_transactions.mjs` covers address/default races,
stale profile/pricing/offer edits, replay receipts, lock timeouts, deletion
cascades, and the existing checkout/inventory scenarios.
