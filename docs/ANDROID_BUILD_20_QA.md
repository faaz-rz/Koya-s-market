# Android build 20 final audit — 8 October 2026

Version: `1.1.5+20`. This audit follows the address, variant-confirmation and
notification work recorded in [build 19 verification](ANDROID_BUILD_19_QA.md).
The APKs use the configured Supabase and Android Firebase projects and the same
internal-testing certificate as builds 18 and 19.

## Fixes found during the audit

- A new customer starts with an empty name and phone. If a required address field
  is missing below the visible area, Save now focuses and scrolls to the first
  invalid field. Errors clear as the customer corrects them. Character limits
  remain enforced, with unnecessary counters removed from the form.
- The address header remains usable on a 320 px phone with 2× or 3× text and the
  keyboard open. Its compact sign-out action has an accessible label; Save stays
  reachable while the form scrolls.
- When the saved cart restores while the pack selector is open, its quantities
  and total update while preserving the shopper's draft changes. Confirm applies
  the draft once. Closing the selector still discards unconfirmed changes.

## Final verification

| Check | Result |
| --- | --- |
| Flutter analyzer | No issues found. |
| App regression | 286 tests passed, covering auth/routing, first address, cart persistence, variant confirmation/cancellation, checkout, offline/retry states, inventory, notifications and account deletion. |
| Server handlers | 34 Node tests passed for push dispatch, deletion, request handling, usage budgets and image review. |
| Screen previews | 26 customer previews passed at 390 px/normal text and 320 px/2× text; address, variant, cart and checkout renders were inspected. |
| Accessibility | New-customer address screen passes Android tap targets, labeled targets and text contrast checks. Additional address tests complete the form at 2× and 3× text with the keyboard open. |
| Saved-cart race | The displayed pack total and confirmed quantity stay consistent during a concurrent cart update. |
| Android artifacts | ARM64 and ARM32 APKs built successfully; package identity, version codes 2020/1020, target SDK 36 and v2 signatures verified. |
| Android upgrade/startup | ARM64 build 20 installed over build 19 successfully and rendered the configured customer sign-in screen. Startup logs contained no Flutter or activity crash. No test email or hosted customer order was created. |

The Firebase notification implementation and deployed Edge Function are unchanged
by this audit. Actual delivery with the Android emulator asleep, the app process
absent and deep idle enabled was verified for build 19; the posted notification
remained in the tray for several minutes. See its report for the evidence and the
cold-connection delay observed during that check.

The live Cloudflare staff deployment responds successfully and reports build 18.
This audit changes the customer app only and requires no database migration or
Edge Function redeployment.

## Device and release limits

These are profile APKs for internal testing, signed with the existing debug
certificate. Public Play Store distribution still requires release signing.
Install build 20 on the physical Android phone and verify Allow, lock-screen
display and opening the correct order. Android controls heads-up duration and
can delay or suppress notifications under force-stop, permission denial, battery
restrictions or network loss. iPhone background push still needs the separate
Firebase/APNs and Apple provisioning setup.

The automated and emulator checks cover the recorded scenarios, not every phone,
OS setting or possible combination of actions.
