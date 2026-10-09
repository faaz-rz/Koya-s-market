# Android build 23 verification

9 October 2026. Version `1.1.5+23`; configured production Supabase/Firebase,
with the existing internal-testing certificate.

## Changes

- Production products resolve their reviewed bundled photo. The live catalogue
  has 3,193 active products and no Storage image paths. All 1,990 reviewed photos
  match the live product IDs, names and units. Products without reviewed photos
  retain illustrations. Staff uploads take priority; renamed products do not
  reuse unrelated packaging.
- Current location opens an in-app map and native Android/iOS address lookup.
  Confirmation fills available street, city and PIN data. Flat/house number can
  be added without clearing the pin. Cancellation preserves typed fields;
  unavailable postal data is never invented or retained from an old address.
- Profile → Preferences → Appearance offers Light, Dark and System, remembered
  across restarts/logout. Sign-in and staff dashboard also have an appearance
  button. Theme changes preserve authentication and cart data.
- Double-tapping search or tapping outside dismisses the keyboard without
  clearing the query; another tap reopens it.
- Each customer has Order #1, #2, etc. Customer screens and alerts use that
  number. Staff retain the global reference, and see the customer's number too.
  Cancelled orders keep their number; rollback and retries do not consume one.

Map tiles use OpenStreetMap with attribution, an identifying User-Agent and
HTTP-aware native caching bounded to 50 MiB. The public service is best-effort;
manual entry remains available. No paid Maps API key was added. Native address
autofill works on Android/iOS; web retains the map/manual fallback. The privacy
page discloses the map and native-geocoder providers.

## Checks

- 305 Flutter tests and the final numbered-alert regression checks pass.
- 54 disposable real-PostgreSQL checks pass, including concurrent numbering,
  independent customers, rollback, retries, cancellation, immutable numbers,
  counter isolation and owned sync responses.
- Android 15 emulator tests decode native product photos, select both themes
  through the real preferences plugin, resolve a Hyderabad city/PIN with the
  native geocoder and open the map widget.
- 60 customer previews cover both themes, 390 px normal text and 320 px large
  text. Map confirmation separately fits 320 px/2× text in both appearances.
  Semantic color/contrast and cart-preservation tests pass.
- Analysis is clean. Configured staff web and both profile APKs compile.
  The final arm64 APK starts on Android; its explicit dark choice survives a
  process restart. Package versions and signatures are inspected for delivery.

## Notification persistence

The deployed dispatcher sent a fixed operational message to an unregistered QA
emulator token: Firebase accepted it with `claimed: 0`. No customer order,
account, email or device registration was created. The emulator initially
needed a network reconnection; acceptance alone was not treated as display proof.

Android displayed it on the locked screen with public visibility, high importance
and `timeout=PT0S`. It persisted after the app process closed for 373 seconds,
then disappeared after a manual swipe. OS records/screenshots are saved under
`outputs/final-android23`. The token was revoked, temporary files/probe app
removed, and the test screen-lock credential cleared.

Android controls the brief heads-up banner. The notification card remains in the
tray/lock screen until opened or dismissed, subject to the user's notification,
lock-screen, DND and device settings. iPhone background push still requires its
separate APNs/provisioning setup.

## Deployment

Migration `20261009151549_customer_order_numbers.sql` is deployed. Eight existing
orders have zero customer-sequence mismatches or duplicate global references.
Counter maxima match history; the private counter table has RLS and no client
read grants. No live test order was placed.

Advisor categories are unchanged: intentional restricted/private tables,
authenticated guarded RPCs and the existing password-protection setting.
References: [private tables](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy),
[guarded RPCs](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable),
[password settings](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

Install build 23 over the previous test APK. Redeploy latest GitHub `main` in
Cloudflare for staff appearance controls and customer-number labels. Backend
numbering is already live. Keep the private counters/global identity sequence
intact when operating the store.
