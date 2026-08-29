# Google Play reviewer access

Google reviewers must receive a stable, reusable account; the normal one-time
email code is unsuitable because reviewers cannot depend on access to a store
operator's inbox.

## Production setup

1. In the production Supabase project, create one ordinary customer Auth user
   with email/password credentials. Do not add this user to `public.admins`.
2. Give the account a normal customer profile and keep it free of active orders
   before submission.
3. Store its random password in the team's password manager. Never add it to
   source control, Dart defines, screenshots or release notes.
4. Build with `--dart-define=ENABLE_PLAY_REVIEW_LOGIN=true`. Android release
   builds intentionally fail if this flag is missing.
5. In Play Console → App content → App access, select that access is restricted
   and add the instructions below with the real credentials.

## Text to paste into Play Console

**Access name:** Koya Stores customer review account

**Username/email:** `[enter the dedicated reviewer email in Play Console only]`

**Password:** `[enter the dedicated reviewer password in Play Console only]`

**Instructions:**

1. Open Koya Stores.
2. On the sign-in screen, tap **App review access** below the OTP button.
3. Enter the reusable email and password supplied above.
4. Tap **Sign in for review**.
5. The account opens the customer Home screen. No OTP, phone verification or
   special location is required.

If Google requests access to staff-only features, create a separate least-
privilege review process rather than promoting this customer account. Never
publish production administrator credentials.
