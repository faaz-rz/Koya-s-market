# Android build 18 verification — 7 October 2026

For the latest APK changes and tests, see [build 23 verification](ANDROID_BUILD_23_QA.md).

For the latest staff sign-in and session behavior, see
[build 22 staff access](STAFF_ACCESS_22.md).

For the latest light/dark styling and visual checks, see
[build 21 visual refresh](VISUAL_REFRESH_21.md).

For the latest regression and UI audit, see
[Android build 20 verification](ANDROID_BUILD_20_QA.md). This build 18 report is
historical; later notification and Cloudflare checks are recorded in the newer
reports.

For the subsequent address setup, variant confirmation and lock-screen
notification changes, see [Android build 19 verification](ANDROID_BUILD_19_QA.md).

The tested application version is `1.1.5+18`. The APK uses the hosted Supabase
project `vorhfltcohtwtehngzay` and Firebase project `koya-stores`. Customer demo
login is unavailable in this configured build. These are internal testing APKs
signed with the same Android debug certificate as previous test APKs; store
distribution still requires the existing release-signing workflow.

## Verified coverage

| Area | Evidence |
| --- | --- |
| App regression | 271 Flutter tests: authentication states, protected routes, customer/staff ownership, cart recovery, product variants, pricing/offers, fulfilment, order status, request retries, offline/loading states, staff inventory, delivery pins and account deletion. |
| UI and accessibility | 24 rendered customer-screen previews at 390 px/normal text and 320 px/2× text. Additional widget coverage includes 3× text, keyboards, landscape, tablet sizes and reduced motion. Android touch targets and accessible labels pass on the shopping screens. |
| Android shopping journey | Emulator login using local demo fixtures, category/pack selection, add-to-cart, fulfilment and pickup review. No hosted customer order or email was created. |
| Android encrypted storage | Actual Android secure-storage plugin preserves cart data across fresh storage instances, isolates two QA account keys, and deletes only the selected account. Test keys were removed. |
| Firebase client | Configured native Android SDK initialized, obtained an emulator FCM token and revoked it after validation. The token was not registered to a real customer. |
| Firebase server | Deployed function v3 authenticated with the Supabase secret and returned HTTP 200 for a Google `validate_only` request using that token. Project ID matched `koya-stores`; zero queue events were claimed and no notification was sent by this check. |
| Request handlers | 33 Node tests cover unauthorized access, oversized/stalled/malformed bodies, deletion proof/replay, dispatch leases/retries/partial acknowledgements and private provider validation. |
| Staff browser alerts | Four browser scenarios: granted, denied, unavailable Notification API and mobile constructor failure. Real Web Audio API was exercised; the Notification API was mocked. |
| Database correctness | 51 cases against disposable local PostgreSQL cover overselling, slot capacity, duplicate submissions, concurrent cancellation, stale stock/address/profile edits, offers, user-scoped sync and owned notification queues. No hosted test account or test order was created. |
| Local load | 740 synchronized read requests across 10/25/50/100 simulated shoppers, plus checkout/cancellation work, with zero errors. At 100 shoppers, local p95 was about 753 ms. This is a local regression result, not a hosted free-tier capacity guarantee. |
| Hosted controls | Order/product Realtime publication enabled; all public tables have RLS. Notification dispatcher, queue trigger and retry job enabled. Unauthorized function calls return HTTP 401. |

The UI changes enlarge product/cart actions to 48 dp, preserve their hit areas
instead of scaling the entire stepper, use fewer columns where readable names
and controls need more room, correct singular item wording and explain optional
closed-app alerts before enabling them.

## Remaining live-device and deployment checks

- Install the updated APK on a physical Android phone, sign in, enable device
  alerts and allow Android notifications. With the app closed normally, mark a
  test pickup order ready in staff, confirm notification/sound, and tap it to
  open the correct order. Repeat for delivery, mute and logout. Android force
  stop, revoked permissions, network loss and battery restrictions can delay or
  prevent delivery. Provider validation does not establish visible delivery.
- Live OTP email was not resent during QA. The user's existing SMTP setup is
  retained; app tests cover success, rejection, expiry and send failures.
- GPS permission and address-pin failures were tested with controlled providers
  and database checks. Accuracy at a customer's real address needs a phone test.
- Live Cloudflare privacy/deletion URLs return HTTP 200, but the privacy page
  still serves the older policy that excludes push SDKs and delivery pins. The
  corrected page is already in `web/privacy.html`. Redeploy latest `main` before
  public launch. Cloudflare CLI and the available browser session are not signed
  in, so this QA run cannot update that deployment.
- Supabase security advisors retain the existing leaked-password-protection
  warning. The other notices concern intentionally RPC-only private tables and
  authenticated SECURITY DEFINER APIs whose ownership/MFA checks are exercised
  by database tests. No public table without RLS was found. See the
  [password protection setting](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
- iPhone background delivery remains dependent on Apple Developer/APNs
  provisioning and its separate Firebase app registration.

This report records the tested scenarios and their limits. It does not certify
every Android model, OS setting, provider outage or combination of user actions.
