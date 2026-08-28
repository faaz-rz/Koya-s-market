# Koya Stores

A professional Flutter ordering application for one small Indian supermarket,
with store pickup, manually arranged home delivery, payment at handover, push
notifications, and a responsive staff dashboard. Razorpay remains integrated
behind a disabled-by-default release flag for a later rollout.

The app is deliberately small and feature-first. It uses Riverpod, GoRouter,
Supabase, Razorpay, and Firebase Cloud Messaging without unnecessary domain
layers or duplicated models.

## Included experience

Customer screens:

- Splash and email OTP login
- Home, promotional banner, categories, search, offers, and product listing
- Product detail with availability and stock-safe quantity controls
- Cart with list price, product savings, admin-controlled minimum order, and
  totals; the default is no minimum
- Pickup or home-delivery selection
- Pickup goes directly to payment, followed by a ready-for-pickup notification
- Delivery address add/edit/delete/default, PIN serviceability, instructions,
  dates, and slots
- Cash or UPI at pickup and cash or UPI on delivery in the first production
  release; no payment is collected inside the app
- Order confirmation, simple order details, eligible cancellation, reorder,
  and order history
- Profile editing, notification preference, support, and secure logout
- Loading, empty, error, disabled, unavailable, and submitting states

Staff dashboard:

- Separate responsive website with staff-only email OTP, mandatory TOTP
  authenticator MFA, and admin-only routing
- Responsive navigation with separate Overview, Analytics, Pricing, Orders,
  and Inventory pages instead of one long dashboard
- Today, active, pickup, completed, daily-paid, monthly-paid, low-stock, and
  out-of-stock metrics
- Complete store order queue, filters, manual refresh, and a direct
  ready-for-pickup action
- Searchable inventory by product, brand, billing name, item code, or barcode;
  each pack size remains a separate SKU so its stock can be counted accurately
- Manual stock controls for setting the complete physical count or applying an
  atomic `+1`/`-1` correction, with all/in-stock/low-stock/out-of-stock filters
- Order-pricing controls for enabling, changing, or removing the minimum order,
  delivery fee, and free-delivery threshold
- Inventory add/edit controls for price, offer price, unit, category, featured
  products, and JPEG/PNG/WebP product-picture upload or replacement
- Live Supabase product and order updates across open staff and customer screens
- In-memory staff sessions, a 15-minute inactivity lock, periodic admin-access
  revalidation, secure sign-out, and no customer-shopping routes

Production backend:

- Normalized PostgreSQL schema, imported product-master catalogue, delivery
  slots, and PIN codes
- Supabase email OTP, session restoration, catalog/address/order hydration
- Row Level Security for all customer and admin data
- Idempotent `place_order` RPC that locks stock and recalculates every price
- Per-customer active/hourly order limits, bounded cart/input payloads, and a
  20-minute stock reservation for unfinished online payments
- Separate payment and order statuses
- Razorpay order creation, signature verification, and signed webhook handling
- FCM device-token registration, notification queue, and HTTP v1 dispatcher
- Keychain/Keystore-backed customer sessions, session-expiry data clearing,
  RPC-only device-token ownership, and automatic stale-token removal
- Product-image bucket limited to JPEG/PNG/WebP and 5 MB
- Audited, server-validated product and stock changes; administrator-owned
  image paths; automatic product availability synchronization; and validated
  order-status transitions
- Deny-by-default database function execution, MFA-aware staff authorization,
  minimal access to customer personal data, exact payment reconciliation, and
  atomic notification-queue claims

Debug builds run immediately in a deterministic local demo mode when no
external configuration is supplied. Demo mode does not charge money or call
external services. Customer releases refuse to build without production
signing and Supabase configuration; iOS and web releases show no demo data if
configuration is missing. Release admin builds also fail closed unless a
client-evaluation build explicitly opts into the separate admin preview.

For a temporary client-evaluation build only, admin demo access can be enabled
explicitly with `--dart-define=ENABLE_ADMIN_DEMO=true`. Never use that flag for
the production admin deployment.

## Run locally

```sh
flutter pub get
flutter run
```

Customer demo: use the prefilled email and select **Continue to Koya Stores**.

Run the separate staff website in Chrome:

```sh
flutter run -d chrome -t lib/admin_main.dart
```

Staff demo: enter an email address and select **Open staff dashboard demo**.
The customer app contains no admin route or admin-dashboard shortcut.

For a physical stock count, find the exact product and pack size and select
**Set**. Enter `0` to remove it from sale, or enter the counted shelf/store-room
quantity to make it orderable. Use `+` and `-` only for quick corrections. In a
configured Supabase build, these changes are saved immediately, audit logged,
and sent to open customer apps through Realtime.

To create a catalogue item, select **Add product** in the staff inventory,
choose an optional picture, complete the product details, and save. Pictures
are previewed before saving and validated as JPEG, PNG, or WebP up to 5 MB. The
same picture control can replace the photo on an existing product.

## Staff website production build

The staff site and customer app share models and the Supabase data layer, but
have separate entry points and route trees. Build the admin website with public
Supabase values only:

```sh
flutter build web --release -t lib/admin_main.dart \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_KEY \
  --dart-define=ADMIN_IDLE_TIMEOUT_MINUTES=15
```

Deploy the generated `build/web` directory to a static web host and configure
all unknown routes to serve `index.html`. The included `vercel.json` supplies
the SPA rewrite, HTTPS/browser security headers, no-index policy, and no-store
rules for the app shell. Do not deploy a build without the two Supabase defines:
the staff login is deliberately disabled in a release build without them.
Never put the Supabase service-role key or Razorpay secrets in the website.

## Supabase setup

1. Create a Supabase project.
2. Apply every file in `supabase/migrations/` in filename order, or link the
   Supabase CLI project and run `supabase db push`.
3. Create a real staff user through Supabase Auth, then approve that user's UUID
   in `public.admins` from the SQL editor:

   ```sql
   insert into public.admins (user_id, display_name)
   values ('AUTH_USER_UUID', 'Store manager');
   ```

   The admin login does not create accounts automatically. On the first login,
   the staff member must add the displayed setup key to Google Authenticator,
   Microsoft Authenticator, or another TOTP app and verify its six-digit code.
   Every admin RLS policy and RPC requires the resulting Supabase AAL2 session,
   so the second factor cannot be bypassed by calling the API directly. Do not
   expose a service-role key in Flutter or in the web host.
4. Deploy all functions in `supabase/functions/`.
5. Set these Edge Function secrets from `.env.example`:
   `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`,
   `KOYAS_WEBHOOK_SECRET`, and `FIREBASE_SERVICE_ACCOUNT_JSON`.
6. Point the Razorpay webhook to the deployed `razorpay-webhook` function and
   subscribe at least to `payment.captured` and `payment.failed`.
7. Trigger `send-order-notifications` from a protected scheduler or database
   webhook whenever `notification_queue` receives a row.
8. Enable Supabase Cron and run `select
   public.expire_abandoned_online_orders(100);` every minute. This releases
   stock from online orders whose 20-minute payment window has elapsed. The
   function is service-role-only and is already safe for concurrent workers.

For production Auth, configure a trusted custom SMTP provider, review Supabase
email OTP rate limits, keep the staff allowlist in `public.admins` small, and
deactivate a staff row immediately when access should be revoked. Admin browser
sessions are intentionally not persisted across refreshes or browser closure.

Run the configured application with public values only:

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_KEY
```

The customer app only loads production product images from the controlled
`product-images` bucket. Import or upload catalogue images there before launch;
third-party catalogue URLs are intentionally ignored to avoid leaking customer
network metadata.

## Product master catalogue

The reviewed billing export is integrated into both the local demo and the
Supabase production catalogue. It contains 3,380 accepted source rows across 12
customer categories. The customer app exposes the 3,193 products with a valid
selling price; the 187 zero-price rows stay inactive in Supabase until the store
sets a price. Only the 25 products with positive opening stock are initially
orderable, so missing stock is never invented.

Apply `supabase/migrations/202608130001_import_product_master.sql` after the base
schema. It preserves source row, item code, barcode, HSN/SAC, GST, billing
group, brand, and subcategory for later billing integration. The six review
rows and seven excluded non-sale rows remain in the reviewed workbook and are
not shown to customers.

Product cards show the complete print name, brand, inferred pack size, and
subcategory while retaining the original billing name, item code, and barcode
for reconciliation. Staff can add individual pictures from the dashboard.
Larger sets of exact images can also be bulk imported without putting a
service-role key in the app. Name image files using a barcode, item code,
`row-EXCEL_ROW`, or product UUID, then validate the folder first:

```sh
node tool/import_product_images.mjs --input /path/to/product-images
```

After reviewing `outputs/product_image_import/import_report.json`, upload the
validated files from a trusted development machine:

```sh
SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=YOUR_SERVICE_ROLE_KEY \
node tool/import_product_images.mjs --input /path/to/product-images --apply
```

Never place the service-role key in Flutter, Vercel, source control, or a
customer-facing build. Only JPEG, PNG, and WebP files up to 5 MB are accepted.

## Firebase / FCM setup

Add the platform files generated by FlutterFire (`google-services.json` and
`GoogleService-Info.plist`) for the final Firebase project. Then enable token
registration explicitly:

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_KEY \
  --dart-define=ENABLE_PUSH_NOTIFICATIONS=true
```

The app remains usable if notification permission is declined or token
registration temporarily fails.

## Optional Razorpay flow

Razorpay is disabled by default. A later release can expose online payments by
building with `--dart-define=ENABLE_RAZORPAY_PAYMENTS=true` after the live
merchant account, secrets, capture settings, webhooks, and payment tests are
ready.

The mobile app never receives the Razorpay secret and never supplies the
trusted order amount. The sequence is:

1. Flutter calls `place_order`; PostgreSQL validates product IDs, quantities,
   stock, store settings, address, PIN, slot capacity, payment eligibility, and
   totals.
2. `create-razorpay-order` reads that persisted total with service-role access
   and creates the provider order.
3. Android/iOS opens the official Razorpay checkout SDK.
4. `verify-razorpay-payment` validates the HMAC signature server-side.
5. The signed webhook independently reconciles captured or failed payments.

Duplicate app submissions and duplicate callbacks are constrained by
idempotency keys and unique payment-event indexes. Payment verification also
checks the provider order, amount, currency, and captured state; an out-of-order
failure webhook cannot downgrade an already captured payment.

## Release preparation

Android builds target SDK 36 and support Android 7.0 (API 24) and newer. The
release toolchain uses Java 17, NDK 28.2, and Flutter's supported AGP 8
compatibility path while native plugins complete their AGP 9 migrations.

Android release builds never fall back to the Flutter debug key. Signing can be
provided with an ignored `android/key.properties` file (start from
`android/key.properties.example`) or the `KOYAS_ANDROID_KEYSTORE_PATH`,
`KOYAS_ANDROID_KEYSTORE_PASSWORD`, `KOYAS_ANDROID_KEY_ALIAS`, and
`KOYAS_ANDROID_KEY_PASSWORD` environment variables. The public upload
certificate is in `android/koyas-upload-certificate.pem`; keep the corresponding
private keystore and password backed up securely before the first Play Console
upload because future updates must use the same upload identity.

Build and verify the signed bundle only after supplying the public Supabase
values:

```sh
flutter build appbundle --release \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_KEY
tool/verify_android_release.sh build/app/outputs/bundle/release/app-release.aab
```

Keep the private upload key outside the repository and store its passwords in a
developer-machine secret manager. Never document machine-specific credential
locations or account names in source control.

iOS uses Xcode automatic signing. Before creating an IPA, sign in to the
organization's Apple Developer account in Xcode and select its Team under
Runner > Signing & Capabilities. Xcode then creates or downloads the Apple
Distribution certificate and provisioning profile; those credentials cannot be
generated without an authorized Apple Developer team.

Before store submission, confirm the final Android application ID and iOS
bundle ID, add the production Firebase files, configure Razorpay live
keys/webhook, review the starter catalogue/PIN codes/charges, add App Store
privacy text, and test on at least one physical Android phone and one physical
iPhone. The current Firebase SDK requires iOS 15+.

## Verification

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --release -t lib/admin_main.dart
flutter build ios --release
```

Android release commands are shown in **Release preparation** because both
production signing credentials and the two Supabase `--dart-define` values are
mandatory. CI also verifies that an unconfigured Android release is rejected.

Primary implementation entry points:

- `lib/features/store/providers/store_provider.dart` — app/demo state and rules
- `lib/features/store/data/supabase_store_repository.dart` — live persistence
- `lib/app/router/app_router.dart` — customer-only guarded navigation
- `lib/admin_main.dart` — separate staff website entry point
- `lib/admin/router/admin_router.dart` — staff-only web navigation
- `supabase/migrations/202608050001_koyas_schema.sql` — schema, RLS, and RPCs
- `supabase/migrations/202608230001_admin_security_hardening.sql` — least-
  privilege admin writes, MFA-aware product saving, and product-image ownership
- `supabase/migrations/202608230002_notification_claims.sql` — atomic worker
  claims that prevent concurrent duplicate notification dispatch
- `supabase/migrations/202608270002_customer_security_hardening.sql` — customer
  rate limits, payment expiry, bounded inputs, and device-token RPCs
- `supabase/functions/` — Razorpay and FCM server functions
