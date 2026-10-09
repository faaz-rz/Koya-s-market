# Staff email access — build 22

9 October 2026. Version `1.1.5+22`.

Staff sign-in now uses only the approved email and its verification code. The
authenticator enrollment/challenge screens and AAL2 checks are removed from the
client. The inactivity timer, keyboard/pointer tracking and idle-timeout build
setting are removed. Existing in-memory web sessions still require email sign-in
after closing or reloading the tab.

The session guard retains sign-out/session-loss handling and active staff-role
revalidation every five minutes and on resume. A temporary network failure does
not sign staff out. Revoked access clears local order/store data and returns to
sign-in. The database remains authoritative on every privileged request.

## Database deployment

Migration `20261009132149_staff_email_access_without_mfa.sql` is applied to the
configured Supabase project. `public.is_admin()` requires the authenticated
user's active, server-owned staff record, without an authenticator assurance
claim. Anonymous callers cannot execute this function. Customer ownership,
staff-only RPC validation and RLS stay enabled.

Hosted checks passed for active staff at AAL1, nonstaff denial, anonymous
execution denial, staff snapshot loading and the staff diagnostic RPC. No hosted
customer/order/device record was created or modified by QA. Existing
authenticator factors are not deleted; the app no longer requires them.

## Verification

- 292 Flutter tests pass, including email-only staff access, invalid membership,
  a stale client approval rejected by server data, code-consumption-safe retries,
  restored sessions and small-screen email entry.
- Idle tests cover 24 hours without a backend and 30 minutes with a verified
  staff session. The latter also tests a network failure followed by revocation.
- 51 isolated real-PostgreSQL cases pass using AAL1 as the default authenticated
  session, including staff writes, revocation at both AAL1/AAL2, customer data
  isolation, anonymous denial, concurrent requests, checkout and push queues.
- The analyzer is clean; configured staff web and both Android APKs compile.
  APK identities, versions 2022/1022, target SDK 36 and signatures are verified.

The security advisor categories and counts match the previous baseline. Its
[RPC notice](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)
concerns intentional authenticated APIs whose owner/staff checks are exercised
above. Its [private-table notice](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)
concerns tables intentionally accessed through controlled RPCs, and the existing
[password protection notice](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)
is unchanged.

## Staff website rollout

Redeploy the latest GitHub `main` in Cloudflare. The deployed older frontend will
continue to display its authenticator/idle flow until this build is deployed.
Cloudflare CLI is not authenticated in this workspace, so the compiled web build
has not been published from here. Supabase's permission change is already live.

The Android artifacts use the existing profile/internal-testing certificate.
