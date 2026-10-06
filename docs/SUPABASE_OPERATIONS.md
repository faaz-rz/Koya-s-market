# Koya Stores: operating the deployed backend

Project: `vorhfltcohtwtehngzay`, hosted in Sydney (`ap-southeast-2`).
[Open the Supabase project](https://supabase.com/dashboard/project/vorhfltcohtwtehngzay).
The 26 repository migrations and the `delete-account` Edge Function were deployed
on 5 October 2026. Migration history matches the repository versions so later
CLI deployments do not replay the schema. The 3,380-row billing catalogue was
uploaded in eight bounded, idempotent batches because of the tool request limit.
No customer accounts or orders were created during deployment.

Production website: [koya-s-market.faazlance.workers.dev](https://koya-s-market.faazlance.workers.dev).
The native app's privacy and deletion URLs are recorded in
`config/production.json`. That file contains only public frontend configuration;
pass it to customer release builds with
`--dart-define-from-file=config/production.json`. Confirm both legal pages are
publicly accessible before shipping a native release. Cloudflare's dashboard
build still receives its two Supabase values through **Build variables and
secrets**.

## Finish email delivery before launch

In **Authentication**, keep Email sign-up and email confirmation enabled.
Phone/SMS and anonymous sign-in must stay disabled. Set email OTP length to **6**,
expiry to **600 seconds**, and the resend interval to **60 seconds**.
These are recorded in `supabase/config.toml`; deploying SQL does not apply hosted
Auth settings. The live public settings confirm Email is enabled, confirmation
is required, and Phone/anonymous sign-in are disabled.

In **Authentication → Email / SMTP**, connect your transactional SMTP sender.
Supabase's built-in sender is for testing and restricts recipients to project
team addresses. Email avoids SMS fees; public delivery still depends on the
SMTP provider's allowance. See [Supabase SMTP setup](https://supabase.com/docs/guides/auth/auth-smtp).
Enter SMTP credentials directly in the dashboard, never in a Flutter build.

Set **both Confirm signup and Magic Link** email templates to the contents of
`supabase/templates/email-code.html`, with subject **Your Koya Stores verification
code**. The `{{ .Token }}` field provides a typed code for new customers, returning
customers, staff and account-deletion verification. See
[email templates](https://supabase.com/docs/guides/auth/auth-email-templates).

Open [Authentication → URL Configuration](https://supabase.com/dashboard/project/vorhfltcohtwtehngzay/auth/url-configuration)
and save these hosted settings:

| Setting | Value |
| --- | --- |
| Site URL | `https://koya-s-market.faazlance.workers.dev` |
| Additional Redirect URL | `https://koya-s-market.faazlance.workers.dev/` |
| Additional Redirect URL | `https://koya-s-market.faazlance.workers.dev/login` |

These exact production paths are also recorded in `supabase/config.toml`.
Editing that file or deploying SQL does not change the hosted Auth URL settings.
Typed email codes remain the app's sign-in method; no browser callback route is
required for code verification. See [Supabase redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls).

Test a first signup, returning login, resend and expired code using an address
outside your Supabase team. Complete one disposable customer's deletion with no
active orders. Delivery, hosted MFA and the authenticated deletion flow still
require this real-device verification; the automated tests use mocked Auth HTTP
and isolated PostgreSQL.

## Staff access

The first staff email supplied for this deployment is preapproved in the private
staff-email approvals table. Enter it on **Staff sign in**, verify its email code, then set up a six-digit
authenticator app when prompted. Verification consumes the approval and creates
the staff role. Every privileged database action also requires the authenticator
session (AAL2). The private approval table cannot be read or changed by customers.

For the second staff member, replace the two example values below and run this
once in **SQL Editor**. Approve only a person you intend to give store access:

```sql
insert into koyas_private.staff_email_approvals(email, display_name)
values (lower(trim('SECOND_STAFF_EMAIL')), 'Second staff member');
```

That person then signs in and verifies email and their authenticator. Pending
approvals are one-use: repeating a verification cannot reactivate revoked staff.
To cancel an unused approval, delete its row where `granted_at is null`.
To revoke an existing staff role immediately:

```sql
update public.admins set active = false
where user_id in (
  select id from auth.users where lower(email) = lower('STAFF_EMAIL')
);
```

Do not delete staff Auth accounts as a way to revoke access. Retain the audit
history and disable the role. To restore an existing role after reviewing access,
update its `active` field in the SQL Editor; reissuing OTP does not restore it.

## Cloudflare Workers (the project already created)

The `koya-s-market` project in the supplied Cloudflare build log is a Worker.
Keep that project: it can serve the static Flutter dashboard with no Worker
script. The repository's `wrangler.jsonc` points to the compiled `build/web`
bundle and uses Cloudflare's native single-page application fallback. The old
`/* /index.html 200` wildcard rewrite was removed because Workers rejects its
redirect loop.

In **Workers & Pages → koya-s-market → Settings → Build**, set:

| Setting | Value |
| --- | --- |
| Root directory | Repository root (not `web`) |
| Build command | Leave blank; the deploy script builds first |
| Deploy command | `bash tool/deploy_cloudflare.sh` |
| Non-production deploy command, if requested | `bash tool/build_admin_web.sh && npx --yes wrangler@4.147.0 versions upload` |
| Production branch | `main` |

The deploy script always runs the Flutter release build before Wrangler, so a
fresh checkout does not need an existing `build/web` directory. If an earlier
build command is still set to `bash tool/build_admin_web.sh`, deployment remains
correct but compiles twice; clear that field to avoid the extra build. Do not
rely on `build.command` inside Wrangler configuration for Workers Builds; that
service does not honor Wrangler custom builds.

Remove any existing `--assets ./web` argument from the deploy command: `web` is
the uncompiled source and contains only the shell and legal files. Add
`SUPABASE_URL=https://vorhfltcohtwtehngzay.supabase.co` and the public publishable
key as `SUPABASE_ANON_KEY` under **Build variables and secrets**. They must be
available while Flutter compiles, rather than being Worker runtime variables.
Keep secret/service-role/SMTP credentials out of this configuration.

Save and retry the latest `main` build. After it succeeds, check the deployed
HTTPS site, `/login`, `/dashboard`, `/privacy`, `/delete-account`, and
`/flutter_bootstrap.js`. The dashboard route must show sign-in to a signed-out
visitor. The expected production address is
`https://koya-s-market.faazlance.workers.dev`; set the hosted Supabase Auth URL
settings above after Cloudflare succeeds.

An error saying `/opt/buildhome/repo/build/web` does not exist means compilation
was skipped. Confirm the deploy command is `bash tool/deploy_cloudflare.sh` and
retry a deployment of the latest `main` commit. If the script instead reports
`SUPABASE_URL is required` or `SUPABASE_ANON_KEY is required`, add the two build
variables above before retrying.

See [Workers build configuration](https://developers.cloudflare.com/workers/ci-cd/builds/configuration/)
and [native SPA routing](https://developers.cloudflare.com/workers/static-assets/routing/single-page-application/).

## Cloudflare Pages (alternative)

Cloudflare Pages suits this static Flutter dashboard. Its free plan includes
unlimited static requests and bandwidth; [build/file limits](https://developers.cloudflare.com/pages/platform/limits/)
still apply. Use a free `pages.dev` address initially; a custom domain is optional.
The backend remains in Supabase.

In **Cloudflare → Workers & Pages → Create → Pages**, connect the GitHub repository
`faaz-rz/Koya-s-market` and choose branch `main`. Set:

| Setting | Value |
| --- | --- |
| Framework preset | None |
| Build command | `bash tool/build_admin_web.sh` |
| Build output | `build/web` |
| Root directory | Repository root |
| `SUPABASE_URL` | `https://vorhfltcohtwtehngzay.supabase.co` |
| `SUPABASE_ANON_KEY` | Project's public publishable key from API Keys |
| `ADMIN_IDLE_TIMEOUT_MINUTES` | `15` |

Do not enable `ENABLE_ADMIN_DEMO`. Legal pages and security headers are included
in the web bundle. The HTTPS web app uses `/privacy` and `/delete-account` at its
deployed origin when explicit legal URL variables are omitted. Native customer
builds still require the published HTTPS `PRIVACY_POLICY_URL` and
`ACCOUNT_DELETION_URL`. These links must be checked after the Pages deployment.
The Flutter route fallback is handled by
[Pages' SPA behavior](https://developers.cloudflare.com/pages/configuration/serving-pages/).

Alternatively, upload the verified `build/admin-web` bundle through Pages Direct
Upload. Choose Git integration if you want pushes to deploy automatically.
Cloudflare has not been deployed or authenticated from this chat.

## Daily store work

Use the **staff dashboard** for orders, payment collection, inventory, prices,
offers and delivery settings. Supabase handles accounts and data; it is not the
day-to-day order screen. Before launch, check stock and prices: the imported
catalogue initially has only **25 sellable products** with positive stock.
Review the store's address, contact number, delivery pincodes, pickup/delivery
availability, capacity, minimum order and charges.

Use **Authentication → Users** to inspect customer accounts, **Edge Functions →
delete-account → Logs** for deletion failures, and **Database → Advisors** for
new findings. Never disable RLS to fix a screen. Direct client writes are blocked;
the checked RPCs handle ownership, revisions, retries and concurrent stock.

The remaining advisor notices are expected: authenticated SECURITY DEFINER RPCs
are the explicitly checked application API, and private receipt/challenge tables
deliberately have no client policies. Review any new functions against
[the advisor guidance](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
Unused-index notices are normal before traffic; keep indexes protecting FK lookups.
The anonymous-function warning, repeated Auth policy evaluation and missing FK
indexes were resolved during deployment.

Check **Usage** regularly: database size, storage, egress, Auth email limits and
SMTP allowance. A 1,000-customer population can plausibly fit Free, but usage and
hosted latency decide capacity. Local concurrency tests are not a guarantee for
100 hosted shoppers. Run the documented staging load test before public launch.
Free projects do not include automatic backups; follow
[Supabase's backup guidance](https://supabase.com/docs/guides/platform/backups)
and keep periodic database exports securely outside the project.

## Future backend changes

Authenticate the CLI, link this project, and review the dry run:

```sh
npx --yes supabase@2.119.0 login
npx --yes supabase@2.119.0 link --project-ref vorhfltcohtwtehngzay
npx --yes supabase@2.119.0 migration list
npx --yes supabase@2.119.0 db push --dry-run
```

Only apply newly reviewed migrations. Deploy function updates with `functions
deploy delete-account`. Keep all secret/service-role keys in Supabase, never in
GitHub, Cloudflare client configuration or the customer app. Use a separate
staging project for load tests and changes that create synthetic users/orders.

## Inventory updates (6 October 2026)

Staff can type **Total stock** or make several +/− changes, then press **Save**
once. A typed count is a total, not a delivery increment: if 20 units remain and
500 arrive, enter 520. Button-only drafts save as an atomic delta; typed totals
are protected by a revision check. If a customer order changes stock while a
count is being typed, use Reset to review the latest stock before editing again.

The `complete_store_realtime_publication` migration was deployed on 6 October.
Products, orders, offers and store settings are published, with authenticated
RLS still enabled. Updated customer builds subscribe while foregrounded and
refresh after live events; the old installed builds continue polling until
updated. A connected live update normally triggers refresh within a few seconds,
but the elapsed time also depends on network and server response. Verify one
staff save on a separate customer device before treating latency as measured.

## Staff order alerts (build 14)

Deploy the latest `main` commit to Cloudflare, then reload the staff dashboard.
Each staff device must select **Enable order alerts** and grant browser
notification permission. Audio requires this click, even if notifications were
allowed previously. Use **Test sound** to check volume; mute is available.

New orders trigger a prioritized refresh, a persistent banner, a browser-title
count and, when enabled, a chime and desktop notification. Historical orders do
not ring on login. Notifications contain no customer contact/address details.
View orders acknowledges the alert but does not accept, charge or advance an
order. Confirmed/cancelled orders remove their pending alert automatically.

Live sync shows its actual connection/failure state. A disconnected staff tab
checks every 5 seconds (with jitter/backoff), rather than every 30 seconds.
Failed live subscriptions also rebuild automatically with bounded backoff;
rejected join attempts do not postpone the backup read.
Healthy live sync retains a 60-second safety check. The signed-in staff tab can
receive live events while hidden, but a closed/suspended browser, computer sleep,
network loss or session expiry cannot deliver these open-dashboard notifications.
MFA, the configured idle lock, authorization checks and atomic checkout are
unchanged. No SMS, paid audio service or notification vendor is added.

Verify on two devices: keep the enabled staff dashboard open, place a customer
order, check its arrival/banner/chime, navigate to Inventory, place another,
then test blocked notification permission and disconnect/reconnect. The browser
probe tests Web Audio and graceful permission fallback in an isolated headless
browser; it does not certify the store computer's speakers or OS alert settings.

## Customer status alerts and delivery pins (build 15)

Customer order history and profile include **Enable device alerts**. Customers
must explicitly grant notification permission; sound is optional and is only
used after that action. The app also shows an in-app live banner without this
permission. Initial order history is silent, status changes are deduplicated,
and logout clears pending customer alerts. Pickup readiness, out-for-delivery,
delivered, collected, cancelled and rejected states each have their own message.
The current release supports foreground and open-browser alerts. It does not
deliver a notification when the customer app or browser is fully closed.
Closed-app push requires a later APNs/FCM credentialed release, an Edge Function
dispatcher, platform entitlements and a physical-device test; do not describe
the current build as background push enabled.

Build 16 adds the native push client and deploys the dispatch function, private
Vault authorization, queue leases, per-device acknowledgements, status-change
wakeup and retry schedule. The dispatcher stays disabled because Firebase/APNs
credentials are missing. Follow [PUSH_NOTIFICATIONS.md](PUSH_NOTIFICATIONS.md)
for activation and physical-device verification.

## Saved customer carts (build 16)

Customer carts are saved as product IDs and quantities in encrypted device
storage, separately by authenticated user ID. Normal logout clears the visible
cart and retains the saved copy for that account's next sign-in on the same
device. App reopening restores it after the account/catalogue loads. Confirmed
checkout removes only the submitted quantities; edits made during the request
remain. No prices, stock, profile, address, or payment data is trusted from this
cache. Account deletion removes its saved cart. Storage failures show a recovery
message and never block ordinary ordering or disclose a different user's cart.

This is device persistence, not cross-device synchronization. Clearing app data
or browser storage can remove it. The client/server still validate prices,
offers, stock, basket bounds and account ownership when ordering.

When adding or editing a delivery address, a customer may tap **Use current
location**. Location is requested only for that foreground action and the user
can continue with a typed address. The saved record contains latitude,
longitude, estimated accuracy and capture time. The checkout order copies this
pin into an immutable snapshot, so later address edits cannot move an existing
delivery. Staff with MFA see a **Directions to delivery pin** link in order
details. Confirm the written address and landmark when the accuracy is
approximate; GPS is never an exact guarantee. Account deletion removes saved
and order pins.
