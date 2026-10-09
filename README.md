# Koya Stores

A professional Flutter ordering application for one small Indian supermarket,
with store pickup, manually arranged home delivery, payment at handover and a
responsive staff dashboard. Native online payment remains excluded. Native push
is implemented and awaits Firebase/APNs configuration and physical-device
verification; encrypted customer carts survive reopening and logout/login.

The app is deliberately small and feature-first. It uses Riverpod, GoRouter,
Supabase without unnecessary domain
layers or duplicated models.

## Included experience

Customer screens:

- Splash and email OTP login
- Home, promotional banner, categories, search, offers, and product listing
- Product detail with availability and stock-safe quantity controls
- Cart saved separately for each customer on the device, with list price, product savings, admin-controlled minimum order, and
  totals; the default is no minimum
- Pickup or home-delivery selection
- Pickup goes directly to payment, followed by a ready-for-pickup notification
- Delivery address add/edit/delete/default, PIN serviceability, instructions,
  dates, and slots; optional foreground GPS delivery pin with reported accuracy
- In-app pickup, out-for-delivery, delivered and cancelled status alerts;
  optional sound/device notification while the app is open
- Cash or UPI at pickup and cash or UPI on delivery in the first production
  release; no payment is collected inside the app
- Order confirmation, simple order details, eligible cancellation, reorder,
  and order history
- Profile editing, privacy policy, in-app account deletion, support, and secure
  logout
- Loading, empty, error, disabled, unavailable, and submitting states

Staff dashboard:

- Separate responsive website with staff-only email OTP and admin-only routing
- Responsive navigation with separate Overview, Analytics, Pricing, Orders,
  and Inventory pages instead of one long dashboard
- Today, active, pickup, completed, daily-paid, monthly-paid, low-stock, and
  out-of-stock metrics
- Complete store order queue, filters, manual refresh, and a direct
  ready-for-pickup action
- Printable traditional supermarket bills from each order's details, with
  saved item rates, quantities, offers, delivery charges, and payment status
- Searchable inventory by product, brand, billing name, item code, or barcode;
  each pack size remains a separate SKU so its stock can be counted accurately
- Manual stock controls for setting the complete physical count or applying an
  atomic `+1`/`-1` correction, with all/in-stock/low-stock/out-of-stock filters
- Order-pricing controls for enabling, changing, or removing the minimum order,
  delivery fee, and free-delivery threshold
- Inventory add/edit controls for price, offer price, unit, category, featured
  products, and JPEG/PNG/WebP product-picture upload or replacement
- Debounced staff live updates and cached, conditional customer refreshes
- In-memory staff sessions without an inactivity lock, periodic admin-access
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
- Durable order-status notification queue for future server push; the current
  release shows customer alerts while open and does not claim closed-app push
- Keychain/Keystore-backed customer sessions, session-expiry data clearing,
  RPC-only device-token ownership, and automatic stale-token removal
- Product-image bucket limited to JPEG/PNG/WebP and 5 MB
- Audited, server-validated product and stock changes; administrator-owned
  image paths; automatic product availability synchronization; and validated
  order-status transitions
- Deny-by-default database function execution, active-staff authorization,
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

To print an order, open **Orders → View details → Print bill**. The browser
opens a black-and-white receipt and its print dialog, where staff can choose
a printer or **Save as PDF**. The bill fits an 80 mm receipt roll and can also
be printed on A4. Choose the matching paper size and turn off browser headers
and footers. If pop-ups are blocked, allow them for the staff website and try
again. Printing does not change the order or record a payment.

For a physical stock count, find the exact product and pack size, type its
**Total stock**, then select **Save**. Enter `0` to remove it from sale, or enter
the counted shelf/store-room quantity to make it orderable. Multiple `+`/`−`
taps edit a local draft and Save submits one atomic adjustment; typing a total
uses a revision check to protect concurrent orders/edits. **Set total…** also
opens the physical-count dialog. Live changes cannot silently replace a typed
draft; Reset accepts the latest count before editing again.

While open, customer and staff apps keep one debounced Realtime channel for
catalogue changes and authorized orders. Changes trigger a conditional snapshot
after 2 seconds for catalogue edits. Order events take priority, with a 100 ms
debounce and 500 ms minimum refresh gap. The staff connection survives section
navigation and stays connected while its signed-in tab is hidden. Customer
apps pause/unsubscribe when backgrounded. Staff use a 5-second backup (0–1 second
jitter, bounded backoff) if live sync is unavailable and a 60-second safety check
when healthy. Customer safety checks remain 120 seconds browsing or 30 seconds
with an active order/disconnected channel. Checkout rechecks stock on the server.
Failed live subscriptions rebuild with bounded backoff; failed join attempts
cannot postpone the backup snapshot timer.

Select **Enable order alerts** once per staff browser session to unlock the
chime and request desktop notification permission. New orders show a persistent
banner and unread count in the browser title; **View orders** opens the queue.
**Test sound** and mute controls are included. Initial historical orders and
repeated snapshots do not sound again. Reconnect catches newly missed orders.
If notifications or audio are blocked, in-app alerts and ordering still work.
Keep the staff tab open and signed in; these are open-dashboard alerts, not
closed-browser push. OS/browser sleep can suspend delivery until reconnect.
Active staff authorization and sign-out guards remain enforced; no authenticator or inactivity lock is required.

To create a catalogue item, select **Add product** in the staff inventory,
choose an optional picture, complete the product details, and save. Pictures
are previewed before saving and validated as JPEG, PNG, or WebP up to 5 MB input.
The staff website resizes and compresses new uploads to at most 150 KiB. The
same picture control can replace the photo on an existing product.

### Performance and hosting allowances

Catalogue/order refreshes use a single conditional snapshot RPC and a bounded
public catalogue cache. Images are cached, hidden sessions stop polling, and
email-code requests have cooldown/deduplication guards. See
[the pre-deployment checklist](docs/FREE_TIER_READINESS.md) for local load tests,
hosted 50/100-shopper testing, usage estimates and the explicit launch gate.
Local tests do not certify Supabase free-tier capacity. The current example
bandwidth estimate needs more headroom, and SMTP/hosted-device checks remain
unverified. No backend or hosting deployment was performed.

The request and session rules are documented in
[request protocols](docs/REQUEST_PROTOCOLS.md). Authentication uses email OTP;
phone/SMS sign-in is disabled. The app shows a persistent no-internet banner
when the network is unavailable and uses a shared rotating four-dot loader for
requests. Email delivery itself still depends on the free allowance or pricing
of the SMTP provider selected for the hosted project.

### Client catalogue review

The bundled catalogue now uses the client's specific departments, including
Dal, Atta, Millets, Masala Box, Basmati and Detergents. See the
[catalogue review](catalogue/CATALOGUE_REVIEW.md) for image decisions, replacement
sources, verification commands and deployment boundaries. The
[photo queue](catalogue/IMAGE_PHOTO_QUEUE.md) lists products still needing exact
store photos. The September 7 category and image-metadata migrations are narrow
updates; they do not reset prices or stock. These local changes do not mean
the live database or store-uploaded photos have been updated.

All 37 client departments have bundled representative pictures, shared by the
customer home/categories/search screens and the staff inventory/category picker.
They work locally without Supabase Storage or remote image requests. Category
pictures are not substitutes for exact SKU photos: the outstanding product-photo
queue stays separate. Run `python3 tool/category_image_sheet.py` (requires Pillow)
to review the picture contact sheet, or
`flutter test --no-pub tool/catalogue_preview_test.dart` for rendered customer and
admin previews in `outputs/`.

The 5 October customer layout/motion refresh follows the supplied visual
reference while preserving existing wording and catalogue behaviour. See
[customer UI refresh](docs/CUSTOMER_UI_REFRESH.md) for the Figma draft, local
verification, testing APKs and the remaining physical-device checks.

## Staff website production build

The staff site and customer app share models and the Supabase data layer, but
have separate entry points and route trees. Build the admin website with public
Supabase values only:

```sh
flutter build web --release -t lib/admin_main.dart \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_KEY
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

   Staff sign-in verifies the approved email with a six-digit code. Every
   privileged policy and RPC checks the active staff membership in the database.
   No authenticator is required and inactivity does not lock the dashboard.
   Do not expose a service-role key in Flutter or the web host.
4. For the first store release, deploy only the authenticated `delete-account`
   function. Razorpay and notification functions remain reserved for a later
   audited release and must not be deployed/scheduled yet.
5. Follow [DEPLOYMENT_RUNBOOK.md](DEPLOYMENT_RUNBOOK.md) for production SMTP,
   OTP templates, staff access, reviewer access, Vercel, legal URLs, and final
   platform builds.

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

## Native push notifications

The native Firebase client, owned token registration, leased dispatcher,
status-change trigger and conditional retry schedule are implemented. Delivery
is active for Android after verifying the Firebase server credential and public
app values. iPhone additionally requires APNs capability and Apple Developer
Program signing. Follow [PUSH_NOTIFICATIONS.md](docs/PUSH_NOTIFICATIONS.md).
Android build 18 includes the local Firebase configuration for `koya-stores`.
Native SDK token generation and server-side FCM validation passed; displaying a
real notification on a closed physical phone still needs verification. Build 16
on iPhone still has foreground alerts; iPhone closed-app
delivery also requires its own Firebase registration and APNs provisioning.
See [FINAL_ANDROID_QA.md](docs/FINAL_ANDROID_QA.md) for coverage and deployment limits.

## Reserved online-payment backend

The first Android and iOS store releases exclude the native Razorpay SDK and
accept cash or UPI only at pickup or delivery. The hardened server-side order,
verification and webhook work remains for a later payment release. Do not pass
`ENABLE_RAZORPAY_PAYMENTS=true`; the iOS release verifier rejects it.

A later online-payment release must reintroduce a current audited SDK and pass a
new privacy-manifest, merchant-account, secret, capture, webhook, failure and
physical-device review before the payment method is exposed.

The mobile app never receives the Razorpay secret and never supplies the
trusted order amount. The sequence is:

1. Flutter calls `place_order`; PostgreSQL validates product IDs, quantities,
   stock, store settings, address, PIN, slot capacity, payment eligibility, and
   totals.
2. `create-razorpay-order` reads that persisted total with service-role access
   and creates the provider order.
3. A future Android/iOS client opens an audited checkout SDK.
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
values and the deployed legal-page URLs. The review-login flag exposes a normal
email/password sign-in form for the dedicated non-staff account whose credentials
are supplied privately in Play Console; no credential is embedded in the app.

```sh
flutter build appbundle --release \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_KEY \
  --dart-define=PRIVACY_POLICY_URL=https://YOUR_PUBLIC_DOMAIN/privacy \
  --dart-define=ACCOUNT_DELETION_URL=https://YOUR_PUBLIC_DOMAIN/delete-account \
  --dart-define=ENABLE_PLAY_REVIEW_LOGIN=true
tool/verify_android_release.sh build/app/outputs/bundle/release/app-release.aab
```

For `.aab` manifest inspection, install Google's official Bundletool command or
set `BUNDLETOOL_JAR` to the local `bundletool-all.jar`. The verifier checks the
signature, non-debuggable state, application ID, version, Internet permission
and target SDK 36 from the built artifact itself.

Before that build, apply all Supabase migrations and deploy the deletion
function:

```sh
supabase db push
supabase functions deploy delete-account
```

The customer profile links to the public privacy policy and supports permanent
self-service deletion protected by a fresh email OTP verified by the Edge
function. Apply `202609230001_account_deletion_otp.sql` before deploying the
updated `delete-account` function. The email template must include `{{ .Token }}`
(as for email OTP login). Deletion challenges expire after 10 minutes, allow five
verification attempts, and enforce a 60-second resend wait and eight sends per
account per hour. See `docs/ACCOUNT_DELETION_AND_TRANSITIONS.md` for testing and
launch checks. The database blocks deletion while an order is active,
then removes authentication, profile, addresses, tokens and offer-redemption
data while anonymizing retained completed transaction records. The public
`/delete-account` page provides the required assisted route for customers who
cannot sign in.

Google Play copy, screenshots, graphics, Data Safety answers, reviewer-access
instructions and the final console checklist live in `play_store/`. Reviewer
credentials and the private upload key must never be committed.

Keep the private upload key outside the repository and store its passwords in a
developer-machine secret manager. Never document machine-specific credential
locations or account names in source control.

iOS uses Xcode automatic signing. Before creating an IPA, sign in to the
organization's Apple Developer account in Xcode and select its Team under
Runner > Signing & Capabilities. Xcode then creates or downloads the Apple
Distribution certificate and provisioning profile; those credentials cannot be
generated without an authorized Apple Developer team.

The first iOS release targets iPhone in portrait orientation on iOS 15 or later.
It includes an app privacy manifest, production-only Info.plist, branded launch
screen, Swift Package Manager native dependencies and a build-time production
configuration gate. Build only after Supabase and the public Vercel URLs are
live:

```sh
flutter build ipa --release \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_KEY \
  --dart-define=PRIVACY_POLICY_URL=https://YOUR_PUBLIC_DOMAIN/privacy \
  --dart-define=ACCOUNT_DELETION_URL=https://YOUR_PUBLIC_DOMAIN/delete-account \
  --dart-define=ENABLE_PLAY_REVIEW_LOGIN=true
```

Use `flutter run --profile` for a physical-device demo before the production
backend exists. App Store listing copy, privacy answers, reviewer access and the
submission checklist live in `app_store/`.

Before store submission, confirm the final Android application ID and iOS
bundle ID, review the starter catalogue/PIN codes/charges, and test on at least
one physical Android phone and one physical iPhone. Firebase push and native
online payment require separate audited releases before either integration is
restored.

## Verification

Checkout/stock race protection and its isolated real-PostgreSQL test harness are
documented in [Concurrency and safe retries](docs/CONCURRENCY.md). The September
17 migration must be applied with the matching admin client during backend
integration; these local tests do not mean Supabase or Vercel is deployed.

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --release -t lib/admin_main.dart
flutter build ios --debug --simulator
# Profile mode requires a physical iPhone:
flutter run --profile -d <physical-device-id>
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
  privilege admin writes, staff-authorized product saving, and product-image ownership
- `supabase/migrations/202608230002_notification_claims.sql` — atomic worker
  claims that prevent concurrent duplicate notification dispatch
- `supabase/migrations/202608270002_customer_security_hardening.sql` — customer
  rate limits, payment expiry, bounded inputs, and device-token RPCs
- `supabase/functions/` — Razorpay and FCM server functions
