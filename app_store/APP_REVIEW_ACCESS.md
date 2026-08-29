# Apple App Review access

Apple reviewers need a stable account that does not depend on a one-time code
sent to the store operator's inbox.

## Production setup

1. Create one ordinary Supabase Auth customer using email/password credentials.
2. Do not add the account to `public.admins`.
3. Complete a normal customer profile, but leave the account with no active
   orders before submission.
4. Store the random password in the organization's password manager. Never add
   it to Git, screenshots, Dart defines or public documentation.
5. Build with `--dart-define=ENABLE_PLAY_REVIEW_LOGIN=true`. This shared review
   flag exposes the reusable sign-in form to both Google Play and Apple App
   Review.
6. Put the real credentials only in App Store Connect → App Review Information.

## App Store Connect text

**Sign-in required:** Yes

**Username:** `[enter the dedicated reviewer email in App Store Connect only]`

**Password:** `[enter the dedicated reviewer password in App Store Connect only]`

**Review notes:**

1. Open Koya Stores.
2. Tap **App review access** below the one-time-code button.
3. Enter the supplied reusable email and password.
4. Tap **Sign in for review**.
5. The account opens the customer storefront without an OTP.
6. No purchase is charged in the app. Select pickup or delivery and use the
   cash/UPI-at-handover option.
7. Account deletion is under Profile → Privacy and account → Delete account.

The staff dashboard is a separate private website and is not part of the iOS
binary. Never provide a production administrator password or TOTP secret in App
Store Connect.
