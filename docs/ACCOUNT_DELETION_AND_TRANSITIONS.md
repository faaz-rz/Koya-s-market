# Account deletion and customer transitions

Updated 30 September 2026, customer version 1.1.5+10. These changes are local;
no Supabase deployment, email delivery or store submission has been performed.

## Deletion flow

Profile → Delete account → type DELETE → Send email code → enter the latest
code → Delete permanently. Cancelling before confirmation keeps the account.
The app never deletes merely because the text or a locally checked code matches.
Both API actions use the distinct `DELETE_WITH_OTP` protocol marker, not the old
`DELETE` marker. A new app pointed at the old one-step endpoint therefore fails
closed, including when merely requesting a code. The user still types DELETE in
the dialog to express consent.

The authenticated `delete-account` Edge function obtains the identity and verified
email from Supabase Auth. It does not accept an account ID/email from the client.
It sends an Auth email OTP with `shouldCreateUser: false`, verifies that OTP on
the server, matches the returned user, atomically consumes the private deletion
challenge, then calls Auth's administrative delete API. No OTP, session or
service-role secret is returned to the app or written to logs.

Challenge controls:

- Ten-minute deletion window, at most five verification attempts per challenge.
- Sixty-second resend cooldown, at most eight sends per account per hour.
- Limits are enforced in PostgreSQL across devices and concurrent requests.
  Failed sends also reserve quota. Supabase Auth/SMTP can impose stricter limits.
- Resending replaces the old challenge. Expired, cross-user, changed-email and
  consumed challenges fail closed. Wrong codes do not remove the account.
- Staff accounts and accounts with active orders cannot self-delete. The final
  database trigger rechecks this rule using the customer lock shared with checkout.
  Checkout and deletion cannot both commit an orphaned active order.
- Auth deletion cascades private account data and the challenge. Retained
  transaction records are anonymized, including checkout retry fingerprints
  which can contain delivery instructions.

OTP state exists only inside the dialog. Sending/confirming disables repeated
taps and back dismissal. Resend/expiry/error states remain visible; network
timeouts never automatically retry a destructive request. After confirmed
deletion, personal read caches and local credentials are cleared. A subsequent
logout network failure is not presented as a failed account deletion.

In unconfigured debug/profile builds only, the dialog explicitly labels the code
`123456` as a demo with no email sent. Active-order safety still applies. Demo
data includes active orders; those must be completed/cancelled in test fixtures
before exercising the success path. Release builds cannot use this fallback.

## Transitions

- Native Flutter page navigation/back transitions are retained.
- A short incoming-tab fade keeps the existing branch navigators and scroll state.
- Loading buttons keep their label's layout size, retain screen-reader tap actions,
  and disable duplicate submissions.
- Checkout opens confirmation immediately after success, retaining the order ID
  while details refresh in the background. Slow reads cannot trap a completed
  checkout, and stale responses cannot hydrate a later login/checkout. Submission
  has a network timeout and retains its idempotency key for safe retries. Back and
  payment-selection controls are locked while pending.
- Splash starts loading after the first frame without an artificial 700 ms wait;
  duplicate retries and stale-session hydration are guarded.
- Custom tab, cart, button, selection and pack animations respect reduced-motion
  and accessible-navigation preferences.

## Local verification

The 30 September run passed 191 Flutter unit/widget tests, 23 Node checks,
32 real PostgreSQL concurrency/sync/deletion scenarios, two Chromium image
tests, two deletion-screen visual renders, static analysis and Edge TypeScript
checking. Customer and admin profile web builds also compiled successfully.
Physical-device and real Supabase/SMTP verification remain pending.

```sh
flutter analyze --no-pub
flutter test --no-pub
node --test tool/account_deletion_handler_test.mjs tool/usage_budget_test.mjs
deno check --no-lock supabase/functions/delete-account/index.ts
# Install the isolated runtime described in CONCURRENCY.md first:
KOYAS_PG_RUNTIME=/path/to/disposable/runtime node tool/test_concurrent_transactions.mjs
```

The test suite exercises wrong/expired codes, resend cooldowns, concurrent send
and attempt limits, one-time consumption, active orders, anonymization, replay,
duplicate taps, back navigation, 320–430 logical-pixel phone layouts with large
text and a keyboard, tab scroll preservation, and checkout confirmation frames.
The real local PostgreSQL harness uses all migrations and no remote database.
Edge HTTP tests inject Auth/email services; they do not prove SMTP delivery.

Android profile/debug builds include Flutter's development-only integration-test
plugin. Its three dynamic AndroidX test dependency ranges are pinned to compatible
stable versions in `android/build.gradle.kts` to avoid failing on Maven version-list
queries. Explicit dependency versions are not overridden. Release builds retain
Flutter's normal exclusion of development plugins and the existing release gates.

## Required before launch

1. Apply all migrations, including `202609230001_account_deletion_otp.sql`, then
   deploy the updated `delete-account` function. Keep JWT verification enabled.
   An old one-step client will be rejected by the new function, so release the
   matching customer app. Never deploy only the UI and assume OTP is enforced.
2. Configure SMTP and the Auth email OTP template with `{{ .Token }}`. Use wording
   suitable for both sign-in and account verification. Test delivery to real
   customer email providers, Auth rate/captcha settings and provider quotas.
3. On staging with disposable accounts, exercise success, wrong code, expiry,
   resend, lost network, active-order blocking and a real concurrent checkout.
   Check that the Auth user/private rows disappear and retained orders contain
   no personal fields. Never run destructive verification with real customers.
4. Publish working HTTPS privacy/deletion pages and pass their URLs into the
   release build. The outside-app assisted deletion route remains available for
   people who cannot sign in. Verify its support contact and ownership checks.
5. Test low-end and current Android phones, gesture/system back, slow/offline
   networks, large text and TalkBack. No Android device was connected for these
   local checks; widget tests are not proof of frame-time performance on hardware.
6. Measure staging load and actual usage with `FREE_TIER_READINESS.md`. Configure
   the production backend, private upload key and Play reviewer access, build the
   signed AAB, and run `tool/verify_android_release.sh`. Profile APKs are for
   customer testing only, not Play submission. Recheck current Play requirements
   when submitting; passing local tests is not store approval.

References: [Supabase email OTP](https://supabase.com/docs/guides/auth/auth-email-passwordless),
[server OTP verification](https://supabase.com/docs/reference/javascript/auth-verifyotp),
[Google Play deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en).
