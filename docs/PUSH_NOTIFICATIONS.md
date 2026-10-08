# Background order notifications

Build 19 asks for notification permission during first-customer address setup,
remembers the choice, restores enabled alerts after reopening, and uses public
Android lock-screen visibility with no notification expiry. Profile remains the
place to change alerts and sound later. Android controls heads-up popup duration;
the notification tray keeps the full message until opened or dismissed. An
actual Firebase delivery was verified with an Android emulator asleep, the app
process stopped and deep idle enabled. See [build 19 QA](ANDROID_BUILD_19_QA.md).

The client integration, authenticated device registration, leased dispatcher,
database trigger and retry schedule are implemented. On 7 October 2026, the
hosted dispatcher was activated for Android project `koya-stores`. The server
credential authenticated successfully, and FCM accepted a `validate_only` request
for an Android emulator token. No notification was sent by that check; the QA
token was revoked afterward. A physical-phone delivery check remains necessary.
iPhone separately needs its Firebase app configuration and Apple push provisioning.
Device registration reports the dispatcher setting, so permission alone does not
make an unconfigured server appear ready.

## Activate Android

Build 18 has local Android Firebase configuration for project `koya-stores`,
imported from the matching `com.koyas.koyas_supermarket` app registration. The
configuration remains in ignored `config/push-production.json`. The private
service-account credential is saved separately in Supabase secrets. Firebase
configuration and provider permission were verified, but a successfully built
APK alone does not establish that a physical phone displays background alerts.

1. Create or select the store's Firebase project. Analytics is unnecessary.
2. Register Android app `com.koyas.koyas_supermarket`. Copy its public SDK
   project ID, sender ID, API key and app ID into an ignored copy of
   `config/push.example.json` named `config/push-production.json`.
3. Enable the Firebase Cloud Messaging HTTP v1 API. Create a dedicated service
   account with the Firebase Cloud Messaging API Admin role. Put its private
   credential JSON in Supabase **Edge Functions → Secrets** as
   `FIREBASE_SERVICE_ACCOUNT_JSON`. Never put this credential in a Dart define,
   app bundle, public config, GitHub, chat, or Cloudflare frontend variables.
4. Build with both configuration files:

   ```sh
   flutter build apk --profile --dart-define-from-file=config/production.json --dart-define-from-file=config/push-production.json
   ```

   Public app configuration also generates the Android native Firebase resource
   values needed when Android starts the notification service after app closure.
   Missing required values fail the Android build. Auto registration is disabled
   until the customer explicitly enables alerts.

## Activate iPhone

1. Use an Apple Developer Program account with Push Notifications capability;
   the current free Personal Team signing is insufficient for APNs.
2. Register Firebase iOS app `com.koyas.koyasSupermarket`; add its public API key
   and app ID to the same private build-configuration file.
3. Create an APNs authentication key in Apple Developer and upload it to Firebase
   Cloud Messaging with the correct Apple team ID/key ID. Keep the `.p8` private.
4. In Xcode, enable Push Notifications for Runner and select the matching
   provisioning profile. Use `Runner/Push-Development.entitlements` for signed
   device development and `Runner/Push-Release.entitlements` for production.
   Set Runner's `CODE_SIGN_ENTITLEMENTS` for the relevant build configuration.
   Remote notifications are already declared in both app plists.
5. Build using both Dart configuration files. The release validator checks
   Firebase values and a production APNs entitlement before accepting push.

## Enable the hosted dispatcher

The deployed `send-order-notifications` function verifies a private database
authorization secret. The secret was generated in Supabase Vault and is never
sent to a client. The database trigger wakes dispatch after a committed status
change. A minute schedule checks for retryable work; an empty or disabled queue
does not call an Edge Function.

After the Firebase service-account secret is saved and the client is installed,
enable dispatch in Supabase SQL Editor:

```sql
update koyas_private.push_dispatch_config set enabled=true where id;
```

This administrative setting is unavailable to app users and staff sessions.
If Firebase server credentials are not ready, keep it false. Android-only
activation is supported while the iPhone build has no Firebase push configuration
and therefore registers no iPhone push token. To stop new dispatch, set it false
again. Do not disclose or edit the generated Vault secret.

The function also accepts private operational checks with
`x-koyas-check-config: true` after the same Vault authorization. An optional QA
token in `x-koyas-validation-token` is passed to Google's `validate_only` API.
This route never claims queue events or sends notifications, and exposes no
private credentials or device tokens in its response. It reports the public
Firebase project ID so an operator can detect a mismatched server credential.

## Verify before launch

Sign in and select **Enable device alerts**. Confirm background alerts show as
enabled. Close the app normally, mark that customer's pickup order ready in the
staff dashboard, and check its notification/sound. Repeat for out-for-delivery,
mute, denied permission, token refresh, logout/account switching and a tap from
the closed state. Taps reload owned server orders before navigation. Live database
updates own foreground presentation, avoiding a second FCM chime.

OS force-stop, network loss, notification denial, power restrictions and device
settings can prevent or delay delivery. FCM requires compatible Google Play
services on Android. A free iPhone development build is not an APNs test.

Leases prevent parallel workers from processing the same queued event. Device
acknowledgements survive partial retries; stale leases cannot finish a newer
claim. Obsolete statuses and events older than 24 hours are dropped. Transport
failures are retried with bounded backoff. A crash between provider acceptance
and database acknowledgement can still repeat a send; stable event identifiers
group/replace OS notifications. Delivery is not guaranteed exactly once.

Official setup: [Firebase Flutter FCM](https://firebase.google.com/docs/cloud-messaging/flutter/get-started)
and [message handling](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages).
