# Google Play Data Safety worksheet

This worksheet is for the planned Android bundle with Firebase Cloud Messaging
enabled and cash or UPI at handover. Recheck it against the exact bundle,
production service settings and Play Console before submitting.

## Collection and sharing overview

- Does the app collect or share required user-data types? **Yes — collects.**
- Is all user data encrypted in transit? **Yes.** Production services and legal
  URLs must use HTTPS/TLS.
- Can users request deletion? **Yes.** Verify the public URL
  `https://koya-s-market.faazlance.workers.dev/delete-account` and the in-app path **Profile →
  Privacy and account → Delete account**.
- Is data sold or used for advertising? **No.**
- Determine sharing from the actual data flows. Review Supabase, the email
  sender and Firebase under Google's service-provider exception. For map tiles,
  reverse geocoding and external map links, check whether the data qualifies
  for the applicable service-provider or user-initiated exception. Disclose any
  transfer that falls outside an exception.
- Has the app completed an eligible independent security review? **No**, unless
  one is completed before submission.

## Data types to declare

| Play data type | Collected | Required or optional | Purpose | Handling |
| --- | --- | --- | --- | --- |
| Personal info → Email address | Yes | Required for account access | App functionality; account management; security/fraud prevention | Stored in Supabase Auth until account deletion |
| Personal info → User IDs | Yes | Required | App functionality; account management; security/fraud prevention | Internal Supabase user ID |
| Personal info → Name | Yes | Required for new customer address setup | App functionality; account management | Profile, recipient and order fulfilment |
| Personal info → Phone number | Yes | Required for new customer address setup | App functionality; account management | Profile, recipient and order fulfilment |
| Personal info → Address | Yes | Required for new customer address setup | App functionality; account management | Saved address and delivery snapshot |
| Financial info → Purchase history | Yes | Required when an order is placed | App functionality; fraud prevention/security; legal compliance | Order items, totals, discounts, status and fulfilment history |
| Location → Precise location | Yes | Optional for pickup, required for home delivery through GPS or manual map placement | App functionality | Coordinates and capture time stored with the address and order, with GPS accuracy when available |
| Location → Approximate location | Yes | Optional, when Android returns a coarse location | App functionality | The address editor shows estimated accuracy and allows manual pin placement |
| Device or other IDs | Yes when native push is enabled | Optional for messaging | App functionality | Firebase installation ID and notification registration token. Koya Stores removes the token association on logout or deletion. |
| App info and performance | Verify SDK data and provider settings | Depends on the final configuration | App functionality and diagnostics as applicable | Firebase documents SDK metadata collection. Check for any optional delivery metrics export, Analytics or Crashlytics in the submitted build. |

Cart product IDs/quantities are kept in encrypted on-device storage and are not
uploaded as a saved cart by this build. Logout retains that account's local cart;
account deletion removes it. This does not synchronize carts between devices.

The map requests tiles from OpenStreetMap using the displayed area. Native
geocoding sends the submitted street, area or PIN search or selected coordinates
to the device's geocoding service. Opening Maps shares coordinates with the chosen provider by explicit
user action. The app requests foreground location for the current-location
action. A saved delivery pin can be removed, and existing delivery orders
retain their original snapshots until account deletion. Confirm the final
manifest for permissions and absence of the advertising ID, and verify that
any provider data collection matches the Console declaration.

## Retention and deletion answer

Deleting an eligible customer account removes the Auth identity, profile, saved
addresses, notification tokens, notifications and personal offer-redemption
records. Active pickup or delivery orders must first be completed or cancelled.
Completed transaction records may be retained for accounting, fraud prevention
or legal obligations, but the deletion transaction disconnects them from the
user and removes customer/recipient names, phone numbers, address text and
delivery instructions and delivery pins.

The public deletion page must identify Koya Stores, explain the in-app steps,
list deleted and retained data, and remain reachable without signing in. Those
requirements are implemented by `web/delete-account.html`.

## Final verification before submitting

1. Confirm the bundle includes the intended Firebase Messaging and Installations
   SDKs. Check the final dependency list and verify that Google Play Billing and
   native online payment SDKs are absent for the cash or UPI handover flow.
2. Test deletion against the production Supabase project and confirm anonymized
   completed orders remain usable by staff.
3. Confirm the published privacy policy exactly matches the production flows.

[Google Play Data safety](https://support.google.com/googleplay/android-developer/answer/10787469) ·
[Firebase Android disclosure](https://firebase.google.com/docs/android/play-data-disclosure)
