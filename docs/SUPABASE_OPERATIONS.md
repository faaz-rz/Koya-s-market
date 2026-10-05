# Koya Stores: operating the deployed backend

Project: `vorhfltcohtwtehngzay`, hosted in Sydney (`ap-southeast-2`).
[Open the Supabase project](https://supabase.com/dashboard/project/vorhfltcohtwtehngzay).
The 26 repository migrations and the `delete-account` Edge Function were deployed
on 5 October 2026. Migration history matches the repository versions so later
CLI deployments do not replay the schema. The 3,380-row billing catalogue was
uploaded in eight bounded, idempotent batches because of the tool request limit.
No customer accounts or orders were created during deployment.

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
customers, staff and account-deletion verification. Set the Auth Site URL and
allowed redirect origin to your final dashboard HTTPS address. See
[email templates](https://supabase.com/docs/guides/auth/auth-email-templates).

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
| Build command | `bash tool/build_admin_web.sh` |
| Deploy command | `npx --yes wrangler@4.147.0 deploy` |
| Non-production deploy command, if requested | `npx --yes wrangler@4.147.0 versions upload` |
| Production branch | `main` |

Remove any existing `--assets ./web` argument from the deploy command: `web` is
the uncompiled source and contains only the shell and legal files. Add
`SUPABASE_URL=https://vorhfltcohtwtehngzay.supabase.co` and the public publishable
key as `SUPABASE_ANON_KEY` under **Build variables and secrets**. They must be
available while Flutter compiles, rather than being Worker runtime variables.
Keep secret/service-role/SMTP credentials out of this configuration.

Save and retry the latest `main` build. After it succeeds, check the deployed
HTTPS site, `/login`, `/dashboard`, `/privacy`, `/delete-account`, and
`/flutter_bootstrap.js`. The dashboard route must show sign-in to a signed-out
visitor. Set the Supabase Auth Site URL to the actual deployed HTTPS address.
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
