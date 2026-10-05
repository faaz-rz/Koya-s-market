# Koya Stores production deployment runbook

This runbook is for the first public release: Supabase is the production
backend, Cloudflare Pages or Vercel hosts the private staff dashboard and public legal pages, and
customers pay by cash or UPI at pickup/delivery. Native Razorpay checkout and
push notifications stay disabled until a later audited release.

The live project is now deployed. See [Supabase operations](docs/SUPABASE_OPERATIONS.md)
for its project details, verified-email staff provisioning, Cloudflare Pages setup,
and the remaining hosted Auth/email and launch checks. The Vercel instructions
below remain an alternative hosting path.

Never put a Supabase secret/service-role key, database password, SMTP password,
reviewer password, Android keystore, or Apple signing certificate in Git,
Flutter `--dart-define` values, Vercel client output, screenshots, or store
listing text.

## 1. Create the production Supabase project

1. Create a new Supabase organization/project. Choose the production region
   carefully because changing it later requires a migration.
2. Generate a strong database password and save it in the business password
   manager.
3. In **Project Settings → API**, record only:
   - the Project URL, such as `https://PROJECT_REF.supabase.co`;
   - the public publishable key (`sb_publishable_...`) or legacy anon key.
4. Keep the secret/service-role key out of every Flutter and Vercel setting.
5. For a live store, use a Supabase plan and backup/PITR policy that matches the
   business recovery requirement. Free projects may be paused.

### Apply the database migrations

Install the Supabase CLI on the deployment Mac, then run from the repository
root:

```sh
brew install supabase/tap/supabase
supabase login
supabase projects list
supabase link --project-ref YOUR_PROJECT_REF
supabase db push --dry-run
supabase db push
supabase migration list
supabase db lint --linked
```

Review the dry run before the real push. Do not paste migrations manually out
of order. `db push` records them and will skip already-applied migrations on
later deployments.

After the push, open **Database → Security Advisor** and resolve unexpected
findings. The migrations already enable RLS, restricted RPC permissions,
Realtime tables, the product-image bucket, order contact snapshots, manual
payment collection, offer limits, audit logs, and account anonymization.

The request-protocol migration is
`supabase/migrations/202610050001_request_protocols.sql`. It adds replay
receipts, stale-editor conflicts, atomic address/default changes, and the
revised settings, offer, profile, and address fields. Deploy the matching
client build after the migration has been applied.
Apply the later production grants, verified staff provisioning and policy/index
migrations as well; use the complete migration directory in version order.

### Configure customer and staff email OTP

1. In **Authentication → Providers**, keep Email enabled and allow customer
   account creation. The customer OTP flow intentionally creates a new account
   on first successful sign-in.
2. Disable phone/SMS sign-up and confirmation. This release uses email OTP only;
   phone numbers are optional delivery contacts and are never authentication
   factors. The repository's `supabase/config.toml` records this policy for
   local projects.
3. Set email OTP length to 6 digits, expiry to 600 seconds, and resend
   frequency to at least one minute. These values match the client cooldowns.
4. Configure a trusted custom SMTP provider in **Authentication → SMTP**. The
   built-in Supabase mail service is limited and is not suitable for public
   production OTP. Email-only avoids SMS charges, but the SMTP provider's free
   allowance or pricing still applies.
5. In **Authentication → Email Templates → Confirm signup and Magic Link/OTP**, use
   `{{ .Token }}` in the subject/body so the app receives a six-digit code,
   not a magic-link-only email. Example body:

   ```html
   <h2>Your Koya Stores sign-in code</h2>
   <p>Enter this code in Koya Stores:</p>
   <p><strong>{{ .Token }}</strong></p>
   <p>If you did not request it, ignore this email.</p>
   ```

6. Set the Auth Site URL to the final HTTPS Vercel/custom domain. Add the same
   production origin to the redirect allow list even though this release uses
   typed OTP codes.
7. Review OTP expiry and rate limits, then test delivery to addresses outside
   the Supabase organization.

### Create the first administrator

The deployed project uses private, one-time verified-email approvals; follow
[the staff access steps](docs/SUPABASE_OPERATIONS.md#staff-access). The UUID method
below is an alternative for an existing confirmed Auth user.

1. In **Authentication → Users**, create or invite the real staff email and
   make sure it is confirmed.
2. Copy that user's UUID and run this in the Supabase SQL editor:

   ```sql
   insert into public.admins (user_id, display_name, active)
   values ('AUTH_USER_UUID', 'Store manager', true);
   ```

3. Open the deployed staff site and sign in with the staff email OTP.
4. On first sign-in, add the displayed setup key to a time-based, six-digit
   authenticator app and enter its current code. Keep the TOTP seed private.
5. To remove staff access immediately:

   ```sql
   update public.admins
   set active = false
   where user_id = 'AUTH_USER_UUID';
   ```

Do not make the Play/App Store reviewer account an administrator.

### Create the reusable store-review customer

In **Authentication → Users**, create a dedicated ordinary customer with a
random email/password combination, confirm it, and do not insert its UUID into
`public.admins`. Save the password in the business password manager and provide
it only in Google Play Console and App Store Connect. The database trigger
creates its customer profile automatically; complete the profile in the app
and leave it with no active orders before review.

### Deploy the account-deletion function

Only the account-deletion Edge Function is needed in the first release:

```sh
supabase functions deploy delete-account
supabase functions list
```

Supabase supplies `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and
`SUPABASE_SERVICE_ROLE_KEY` to its hosted functions. Do not copy the
service-role key elsewhere. Test deletion end to end with a disposable customer
that has no active orders, then confirm that Auth, profile, addresses, and
personal order snapshots were deleted/anonymized as documented.

Do **not** deploy or schedule `create-razorpay-order`,
`verify-razorpay-payment`, `razorpay-webhook`, or
`send-order-notifications` for this first release. They are reserved backend
work for later native payment/push releases.

## 2. Deploy the staff site and legal pages on Vercel

The root `vercel.json` runs `tool/build_admin_web.sh`, installs the pinned
Flutter 3.47.1 SDK when needed, builds `lib/admin_main.dart`, serves
`build/web`, applies SPA rewrites, and adds browser security/no-store headers.

1. In Vercel, choose **Add New → Project**, import the GitHub repository, and
   keep the repository root as the Root Directory.
2. Set Framework Preset to **Other**. Do not override the Build Command or
   Output Directory; they are version-controlled in `vercel.json`.
3. Choose the Vercel project name before entering legal URLs. Its initial
   production URL will normally be
   `https://YOUR_VERCEL_PROJECT.vercel.app`.
4. Add these **Production** environment variables:

   ```text
   SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
   SUPABASE_ANON_KEY=YOUR_PUBLIC_PUBLISHABLE_KEY
   PRIVACY_POLICY_URL=https://YOUR_VERCEL_PROJECT.vercel.app/privacy
   ACCOUNT_DELETION_URL=https://YOUR_VERCEL_PROJECT.vercel.app/delete-account
   ADMIN_IDLE_TIMEOUT_MINUTES=15
   ```

5. Do not add `ENABLE_ADMIN_DEMO`; production admin builds must fail closed.
   Do not add Razorpay, Firebase, database, service-role, or SMTP secrets.
6. Deploy the `main` branch. The first build is slower because it downloads the
   pinned Flutter SDK; subsequent Git pushes create new deployments.
7. If previews are required, connect them to a separate staging Supabase
   project. Do not give arbitrary preview branches production database access.
8. Add the permanent custom domain. Update the two legal URL environment
   variables to that domain and redeploy production.
9. Update the Supabase Auth Site URL/redirect allow list to the permanent
   domain.

Verify all four public routes in a private browser window:

```text
https://YOUR_DOMAIN/
https://YOUR_DOMAIN/privacy
https://YOUR_DOMAIN/delete-account
https://YOUR_DOMAIN/support
```

The first route must show only the staff sign-in, never demo controls. The
three legal routes must load without authentication. Test the phone link on the
deletion/support pages and verify the privacy/deletion links inside a configured
mobile build.

For a manual CLI redeploy after the Vercel project is linked:

```sh
npx vercel@latest pull --environment=production
npx vercel@latest build --prod
npx vercel@latest deploy --prebuilt --prod
```

## 3. Build the store binaries with the live URLs

Do this only after Supabase and the permanent legal URLs are working.

### Android

Create the private upload keystore once, store two secure backups, and never
regenerate it for later updates. Configure its absolute path/passwords in the
ignored `android/key.properties` or the four `KOYAS_ANDROID_*` environment
variables. Then build:

```sh
flutter build appbundle --release \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLIC_PUBLISHABLE_KEY \
  --dart-define=PRIVACY_POLICY_URL=https://YOUR_DOMAIN/privacy \
  --dart-define=ACCOUNT_DELETION_URL=https://YOUR_DOMAIN/delete-account \
  --dart-define=ENABLE_PLAY_REVIEW_LOGIN=true
```

Install official bundletool, then verify the final artifact:

```sh
tool/verify_android_release.sh build/app/outputs/bundle/release/app-release.aab
```

The verifier requires package `com.koyas.koyas_supermarket`, version
`1.1.5 (9)`, target API 36, Internet permission, a non-debug signature, and a
non-debuggable bundle. Upload it to Play Console internal testing first and
physically test the Play-delivered build before production submission.

### iOS

Select the permanent Apple Developer team/signing profile in Xcode, then build
the archive/IPA with the same production public values:

```sh
flutter build ipa --release \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLIC_PUBLISHABLE_KEY \
  --dart-define=PRIVACY_POLICY_URL=https://YOUR_DOMAIN/privacy \
  --dart-define=ACCOUNT_DELETION_URL=https://YOUR_DOMAIN/delete-account \
  --dart-define=ENABLE_PLAY_REVIEW_LOGIN=true
```

Upload through Xcode/Transporter to TestFlight and physically test the
TestFlight-delivered build before App Store submission. Use the prepared files
under `app_store/` and `play_store/` for the store forms and listing assets.

## 4. Operating Koya Stores

### Customer journey

1. A customer enters an email address and the six-digit OTP. The first verified
   login creates the customer account/profile.
2. The customer browses in-stock products, applies an eligible offer, and
   chooses pickup or delivery.
3. Delivery requires a serviceable PIN, recipient name/phone, address, date,
   slot, and optional instructions. Orders use snapshots so later profile edits
   do not alter fulfilment details.
4. The customer chooses cash or UPI at handover. This release never collects
   money inside the app.
5. Customers can track/cancel eligible orders, manage addresses, open the
   privacy policy, or delete their account when no active order remains.

### Staff sign-in and security

1. Open the Vercel/custom-domain root, enter the approved staff email, then the
   email OTP and authenticator code.
2. The browser session is intentionally in-memory and locks after 15 minutes of
   inactivity. Never share the TOTP setup seed or approve personal accounts as
   administrators.
3. Use **Sign out** at the end of each shift and deactivate a lost/compromised
   staff account in `public.admins` immediately.

### Daily admin workflow

- **Orders:** open each order to see recipient, phone, full delivery address,
  instructions, items, prices, slot, and payment. Reject/cancel with a reason
  when necessary, or advance the fulfilment status in order.
- **Payment collection:** for pay-at-store, use **Mark payment received** only
  at collection; for cash-on-delivery, use it only during delivery. The backend
  prevents collected/delivered completion until payment is recorded, and paid
  totals then appear in Overview/Analytics.
- **Pricing:** control minimum basket, delivery charge, free-delivery threshold,
  individual SKU offer prices, and cart offers. Cart offers support a minimum
  purchase, flat/percentage discount, percentage cap, free product/quantity,
  pickup/delivery restriction, date window, total limit, and per-customer limit.
- **Inventory:** search the exact SKU/pack, use **Set** for a physical stock
  count, use `+`/`-` only for corrections, archive unavailable products, and
  add/edit products and validated product photos.
- **Overview/Analytics:** monitor active orders, paid revenue, low/out-of-stock
  products, period sales, and top products. Revenue counts only orders whose
  payment has actually been marked paid.

Before each store release, repeat `flutter analyze`, `flutter test`, the
platform release verifier, and a real customer-to-admin order cycle using the
store-delivered TestFlight/Play artifact—not a locally installed debug build.
