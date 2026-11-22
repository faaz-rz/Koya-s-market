# Google Play submission for Koya Stores

| Setting | Value |
| --- | --- |
| App name | Koya Stores |
| Android application ID | `com.koyas.koyas_supermarket` |
| Source version | The `version` field in `pubspec.yaml` |
| Android support | API 24 and higher, targets API 36 and compiles with API 37 |
| Category | Shopping |
| Ads | No |
| Target audience | 18 and over, for adults arranging household purchases |
| Payments | Cash or UPI at pickup or delivery for physical groceries |

## Release check on 22 November 2026

| Check | Result |
| --- | --- |
| Local app and backend QA | Flutter analysis and 315 Flutter tests passed. All 34 backend handler tests passed. All 33 migrations applied in a disposable database, where delivery radius, checkout, retries, inventory, cancellation, order isolation and manual payment passed. |
| Android QA bundle | Version `1.1.5 (24)`, API 36, 16 KB native library alignment, non-debuggable, HTTPS-only, and no background location, advertising ID or broad photo/video access. It is signed with a local QA key. |
| Upload bundle | Pending a configured private upload key that matches the intended Play Console app. Confirm the version code in Play Console before building. |
| Hosted email | Staging delivered a six-digit email code. Verify that the Play-delivered app can use a code to sign in against the backend configured in the bundle. |
| Hosted checkout | Staging lacks `place_order_v2` and `sync_store`. The production backend has those RPCs and still needs migration `20261121171338_delivery_radius.sql` for server-side 5 km enforcement. Verify checkout on the release schema before launch. |
| Public pages | Privacy, deletion and support return HTTP 200 without signing in. The live privacy and deletion pages still serve older text. Deploy the current `web/privacy.html` and `web/delete-account.html`, then confirm the map disclosures and test one external deletion request with staff. |
| Play review and device testing | Confirm the reusable reviewer login, install the signed build from Play on a physical Android device, and check the Console's testing requirements and pre-launch report. Full database concurrency testing is pending. |

Keep the application ID for all Google Play releases. Check Play Console for
the highest version code ever uploaded before building. Use the source version
code if it is unused and higher than any existing upload. Split profile APKs
created for local testing have different version codes from the AAB.
For each new release, update `pubspec.yaml` and add the matching
`release_notes_<version>.txt` under `listing/en-US/`. Use `.flutter-version` to
update the Flutter SDK used by CI and the web build bootstrap together.

## Build and verify the upload bundle

Confirm the intended upload certificate in Play Console. The verifier uses the
public certificate at `android/koyas-upload-certificate.pem`. For an enrolled
app, match it to the Play Console **Upload key certificate** and configure its
corresponding private key. If the registered private key is unavailable, use
Play Console's upload-key reset process. For a first upload, confirm which key
will be registered and use its public certificate with the verifier. Keep the
keystore and passwords outside Git. Configure them through the ignored
`android/key.properties` file or the four `KOYAS_ANDROID_*` environment
variables in its example.

For the Android release with optional push notifications, build with the public
production configuration and the separate public Firebase configuration.

```sh
flutter build appbundle --release \
  --dart-define-from-file=config/production.json \
  --dart-define-from-file=config/push-production.json \
  --dart-define=ENABLE_PLAY_REVIEW_LOGIN=true
tool/verify_android_release.sh build/app/outputs/bundle/release/app-release.aab
```

Install the official Bundletool executable or point `BUNDLETOOL_JAR` to its
standalone JAR. The verifier checks the upload certificate, package, version,
API target, manifest, native 64-bit libraries and 16 KB alignment. Use Play
App Signing and verify the uploaded bundle in **App bundle explorer**.

## Set up App content and the listing

| Play Console item | What to enter or verify |
| --- | --- |
| Main store listing | Copy `listing/en-US/`, upload `assets/app-icon-512.png`, `assets/feature-graphic-1024x500.png` and the six images in `assets/phone/`. Check that the screenshots match the submitted app. |
| Store settings | Add an authorized, monitored public support email. Confirm the store contact and intended countries or regions. |
| Privacy policy | `https://koya-s-market.faazlance.workers.dev/privacy` |
| Account deletion | `https://koya-s-market.faazlance.workers.dev/delete-account` |
| App access | Select restricted access and provide the reusable customer credentials from `APP_ACCESS.md`. |
| Data safety | Complete from `DATA_SAFETY.md` using the exact bundle and production services. |
| Ads and advertising ID | Declare based on the final manifest and SDKs. This release is designed for no ads and no advertising ID. |
| Content rating and audience | Complete the IARC questionnaire against the live catalogue. Declare Shopping and the intended adult audience. |
| Other declarations | Review all Console prompts, including applicable financial features, health, permissions and developer verification. |

To refresh the phone screenshots from the current UI, run the preview test and
export the Home, Categories, Detail, Cart, Fulfilment and Profile captures in
`build/qa/customer-ui/` as 1080 × 1920 JPEGs. The captures use a sample account
and sample catalogue data.

```sh
flutter test --dart-define=CAPTURE_PLAY_LISTING=true tool/customer_ui_preview_test.dart
```

Before submission, open both legal URLs while signed out and verify the current
policy mentions delivery location and messaging. Test the in-app deletion flow
and the public support route with disposable accounts. Confirm that staff can
receive and complete a verified request from a customer who has uninstalled the
app. Check the updated delivery rule on the same backend the bundle will use.

## Testing tracks

1. Upload the verified AAB to **Internal testing** and install the Play-delivered
   app on a physical Android phone. Exercise OTP sign-in, reusable reviewer
   access, catalogue, cart, offers, pickup, delivery inside and outside the
   radius, map and notification permissions, status alerts, legal links and
   account deletion.
2. Check the Play pre-launch report when it runs for the test release. Verify an
   install on an Android 16 device and a device or emulator using 16 KB memory
   pages. Review accessibility, stability and device compatibility findings.
3. If Play Console gates production on a closed test for this personal developer
   account, keep at least 12 testers opted in continuously for 14 days and apply
   for production access. Check the Console dashboard for eligibility.
4. Promote the tested bundle after the backend, reviewer access, listing and
   Console checks pass. If you rebuild the bundle, test that new artifact.

[Target API](https://support.google.com/googleplay/android-developer/answer/11926878) ·
[16 KB compatibility](https://developer.android.com/guide/practices/page-sizes) ·
[Preview assets](https://support.google.com/googleplay/android-developer/answer/9866151) ·
[App review](https://support.google.com/googleplay/android-developer/answer/9859455) ·
[Closed testing](https://support.google.com/googleplay/android-developer/answer/14151465)
