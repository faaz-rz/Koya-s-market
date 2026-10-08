# Android build 19 verification — 8 October 2026

Version: `1.1.5+19`. Customer APKs contain the existing public Supabase and
Android Firebase configuration. The private Firebase credential remains only in
Supabase. These are profile/internal-testing APKs using the existing debug
certificate, not Play Store release artifacts.

## Changes

- Customers without a saved address must complete address setup before shopping.
  The first address becomes the default. Manual entry works without location
  permission; the optional delivery pin uses the existing location flow.
- First sign-in automatically asks the phone for notification permission during
  address setup. Declining still permits shopping. The prompt is remembered per
  account/device, and Profile remains available for enabling alerts or changing
  sound later.
- Pack options use horizontal cards, a selection total and a fixed Confirm
  button. Quantities are drafts until confirmed. X, system back, outside
  dismissal and a swipe cancel drafts, preserving previously confirmed cart
  contents. Confirmation applies one atomic cart update and validates fresh
  stock and the current account.
- Android restores the existing notification opt-in and sound choice after
  reopening, without another permission prompt. Returning from phone settings
  rechecks permission and registration.
- Local alerts use expanded text, public order-status visibility on the lock
  screen and no notification timeout. FCM uses high delivery priority, high
  display priority and public visibility. Existing channels and user choices are
  preserved. Android controls the brief heads-up popup duration; the notification
  tray entry stays until opened or dismissed.

## Verification

- **281 Flutter tests passed**, including new address routing, required fields,
  default save, failed/offline retries, duplicate saves, late responses after
  logout, first-login permission requests, declining/repeat-prompt behavior,
  staged variants/cancellation, concurrent cart edits, stock changes,
  notification restore/mute and native Android notification parameters.
- **34 Node tests passed**, including queue leasing, owned-device dispatch,
  retry/deduplication, unauthorized calls and private delivery QA.
- **26 customer previews passed** at 390 px/normal text and 320 px/2× text,
  including address setup and the variant selector. Additional widget cases
  cover 3× text, keyboard, landscape, system insets and reduced motion.
- The notification Edge Function is active at version 4. A private credential
  probe returned HTTP 200 without claiming customer queue work.
- **Actual Firebase delivery to Android 15 emulator passed**: the screen was
  asleep, the customer app process was confirmed absent before dispatch, and
  deep idle was forced. A private QA message reached the Android notification
  service with importance 4, high priority and public visibility. The same
  notification remained posted for several minutes after the initial receipt.
- The cold emulator's first probes were delayed while Google Play Services'
  connection warmed up. Once connected, another high-priority probe arrived
  during deep idle. Firebase acceptance alone is not treated as device-display
  proof.
- QA used an emulator token only. No hosted customer account, order or email was
  created, no customer device token was extracted, and no real customer test
  notification was sent. The QA token was revoked, temporary app files were
  removed and the probe APK was uninstalled. Forced idle was reset.
- Cloudflare redeployment of build 18 was verified separately: the updated
  privacy page matches the source, and a signed-out dashboard request redirects
  to staff sign-in. This change does not require a database migration.

## Physical-phone check

Install build 19, sign in and choose Allow on the notification prompt. For an
existing account that has already finished address setup, Profile's Enable device
alerts remains available. Place a test order, lock the phone and change its status
to Ready for pickup or Out for delivery from the staff dashboard. Check the
notification tray, full text, sound/mute and opening the correct owned order.

OS-level notification/lock-screen blocking, force-stop, Do Not Disturb, vendor
battery restrictions and no internet can still prevent or delay display.
The app does not override those choices. iPhone background notifications still
require the separate iOS Firebase/APNs and Apple provisioning setup.
