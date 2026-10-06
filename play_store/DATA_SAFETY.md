# Google Play Data Safety worksheet

Use this worksheet for the exact production bundle. Recheck it whenever a data
flow or third-party SDK changes. Google Play Console remains the source of truth.

## Collection and sharing overview

- Does the app collect or share required user-data types? **Yes — collects.**
- Is all user data encrypted in transit? **Yes.** Production services and legal
  URLs must use HTTPS/TLS.
- Can users request deletion? **Yes.** Use the deployed public URL
  `https://YOUR_PUBLIC_DOMAIN/delete-account` and the in-app path **Profile →
  Privacy and account → Delete account**.
- Is data sold or used for advertising? **No.**
- Is data shared with third parties? **No**, provided Supabase is used only as
  a contracted service provider acting on Koya Stores' instructions and none of
  Google's sharing exceptions cease to apply. Confirm the executed provider
  agreement before submitting this answer.
- Has the app completed an eligible independent security review? **No**, unless
  one is completed before submission.

## Data types to declare

| Play data type | Collected | Required or optional | Purpose | Handling |
| --- | --- | --- | --- | --- |
| Personal info → Email address | Yes | Required for account access | App functionality; account management; security/fraud prevention | Stored in Supabase Auth until account deletion |
| Personal info → User IDs | Yes | Required | App functionality; account management; security/fraud prevention | Internal Supabase user ID |
| Personal info → Name | Yes | Required for fulfilment once provided | App functionality; account management | Profile and order fulfilment |
| Personal info → Phone number | Yes | Required for delivery/pickup contact once provided | App functionality; account management | Profile and order fulfilment |
| Personal info → Address | Yes | Required only when delivery is selected | App functionality; account management | Saved addresses and delivery snapshot |
| Financial info → Purchase history | Yes | Required when an order is placed | App functionality; fraud prevention/security; legal compliance | Order items, totals, discounts, status and fulfilment history |

| Location → Precise location | Yes | Optional; only after tapping Use current location and granting permission | App functionality (accurate delivery) | Coordinates, accuracy and capture time saved with the address and immutable order snapshot; removed on account deletion |
| Location → Approximate location | Yes | Optional; when the device provides an approximate fix | App functionality (delivery) | Labelled with its estimated accuracy; manual address remains available |
| Device or other IDs | Yes when native push is configured/enabled | Optional for messaging | App functionality | FCM installation/device registration, linked to account for delivery; unregisters at logout |
| Diagnostics → Other diagnostics | Messaging SDK declaration; reconcile actual final bundle/flow | Optional messaging service | App functionality; service analytics | Firebase SDK privacy manifests declare limited messaging diagnostics |

Cart product IDs/quantities are kept in encrypted on-device storage and are not
uploaded as a saved cart by this build. Logout retains that account's local cart;
account deletion removes it. This does not synchronize carts between devices.

Location is read once in the foreground; no background tracking is requested.
Customers can remove the pin from saved addresses. Existing orders keep the
original delivery snapshot until account deletion. Opening Maps is an explicit
external navigation action and shares the selected coordinates with the map
provider; review Google's user-initiated sharing exception in the final Data
Safety submission. Do not declare contacts, photos, audio recordings, files,
health, advertising IDs or other uncollected categories.

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

1. Confirm the first-release binary contains neither Firebase nor native online
   payment SDKs.
2. Test deletion against the production Supabase project and confirm anonymized
   completed orders remain usable by staff.
3. Confirm the published privacy policy exactly matches the production flows.
