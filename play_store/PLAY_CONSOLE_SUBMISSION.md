# Google Play submission checklist

## Permanent release identity

- App name/brand: **Koya Stores**
- Android application ID: **`com.koyas.koyas_supermarket`**
- Current version name: **`1.1.5`**
- Current version code: **`9`**
- Category: **Shopping**
- Ads: **No**
- Recommended target audience: **18 and over**. The service is for adults
  arranging household purchases and is not designed for children.
- Target SDK: **36** (the final AAB verifier must confirm this)

Treat the application ID as permanent before the first Play upload. Future
uploads must use a higher version code.

## Repository-controlled items completed

- Explicit Android Internet permission.
- API 36 compile and target configuration.
- Release builds reject debug signing, missing production Supabase values,
  missing HTTPS legal URLs and missing reusable reviewer access.
- In-app privacy policy link and self-service permanent account deletion.
- Public `/privacy` and `/delete-account` pages prepared for Vercel.
- Play listing copy, release notes, 512 px icon, 1024×500 feature graphic and
  six phone screenshots in `play_store/assets/`.
- Data Safety and reviewer-access worksheets.

## Credentials and console actions still required

1. **Choose a monitored support email address.** Play Console requires one and
   no support email is currently authorized in the repository. Add it to the
   Store settings and privacy contact before publishing.
2. **Deploy Supabase.** Apply migrations and deploy `delete-account`; configure
   production Auth, catalogue, PIN codes and store settings. Firebase and
   Razorpay secrets are not required for the first-release binary.
3. **Deploy Vercel.** Record the final public HTTPS domain and use its `/privacy`
   and `/delete-account` URLs in both Play Console and the release Dart defines.
4. **Recover or create the private upload keystore.** If the app/package has
   ever been registered, use the private key matching
   `android/koyas-upload-certificate.pem`; creating a different key may prevent
   updates. For a genuinely new package, create an upload key securely, export
   its public certificate, then keep both the keystore and passwords outside Git.
5. Copy `android/key.properties.example` to the ignored
   `android/key.properties` and replace every placeholder, or set all four
   `KOYAS_ANDROID_*` environment variables.
6. Create the dedicated reviewer customer described in `APP_ACCESS.md` and put
   its credentials only in Play Console.
7. Build the release AAB using the command in the project README, then run:
   `tool/verify_android_release.sh build/app/outputs/bundle/release/app-release.aab`.
   Install the official Bundletool command or set `BUNDLETOOL_JAR` to a local
   `bundletool-all.jar` so the verifier can inspect the AAB manifest itself.
8. Install/test the signed release on at least one physical supported Android
   phone. Verify OTP and review login, catalogue, offer calculation, cart,
   pickup, delivery, realtime order status, privacy link, deletion with/without
   an active order, and relaunch after deletion.
9. Create the Play app, complete the listing from `listing/en-US/`, upload the
   graphics/screenshots, provide the support contact, and complete App access,
   Ads, Content rating, Target audience, News apps and Data Safety forms.
10. Enrol in **Play App Signing** during the first upload and use the private key
    only as the upload key. Download and archive the Play signing certificate.
11. Upload to Internal testing first, resolve every pre-launch report issue,
    then promote the exact tested artifact to production.

## Suggested content-rating answers

Answer based on the final product catalogue. For the current grocery-only app:
no violence, sexual content, gambling/simulated gambling, profanity, controlled
substances, user-generated content, social features or unrestricted web access.
If alcohol, tobacco or another age-restricted product is ever listed, redo both
content rating and target-audience declarations before that release.

## Asset notes

- Store icon: `assets/app-icon-512.png`
- Feature graphic: `assets/feature-graphic-1024x500.png`
- Final phone screenshots: `assets/phone/`
- `assets/account-deletion-flow-540x960.png` is QA evidence and need not be part
  of the public listing.
