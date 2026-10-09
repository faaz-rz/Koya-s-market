# Startup notification permission and required address contacts — build 24

9 October 2026. Version `1.1.5+24`.

The customer app requests native notification permission at first startup,
before sign-in. Permission is remembered per installation, separately from
account alert settings. Allowed devices activate alerts only after customer
authentication. Firebase token registration never occurs for a signed-out user.
Returning customers with an existing address follow the same startup flow.

Permission is checked without another request when already allowed or declined.
An existing operating-system denial cannot be forcibly replaced with a new iOS
dialog. Customers can still use phone notification settings and the explicit
Enable device alerts action. Web keeps its existing user-initiated permission
flow, since browsers require a user gesture.

Account notification presentation initializes after the startup permission
check, keeping the order-open callback active. Saved sound/mute choices remain
intact. Late permission responses after logout do not attach a device to the
old account. A device-preference failure still restores an existing opt-in and
does not treat the failure as a permission denial. Declining notifications does
not block shopping.

New-address setup no longer prefills name/contact from the profile. Customers
must enter the recipient name and contact number. The shared form rejects blank
or one-character names, empty phone numbers and invalid phone formats; contact
numbers require 10–15 digits and at most 32 formatted characters. Both labels
explicitly say required. Editing an existing address preserves its entered
details. Location autofill fills location fields only.

## Verification

- 312 Flutter tests pass; analysis reports no issues.
- Tests cover signed-out startup permission, account activation without another
  OS prompt, existing addresses, decline across launches, returning-customer
  notification callback sequencing, mute retention and late logout responses.
- Required-field tests start with a populated profile but blank address contact
  fields, reject missing/invalid entries, then save entered valid details.
  Existing 320 px/2×/3× text, keyboard, focus and offline-save checks pass.
- A configured Android 15 emulator shows the real system notification dialog
  before login. Allow and decline both return to sign-in; restarting after
  either choice does not show another prompt. No hosted customer/email/order or
  notification-device registration was created by this QA.
- Both Android profile APKs compile. The configured, signed iOS profile app
  also compiles with the existing development team. This is a build check,
  not a new installation or remote-push test on the user's physical iPhone.

These remain internal-testing builds using the existing signing setup. iPhone
background push still needs separate Apple/APNs configuration. Existing backend
name/contact constraints stay in place; this change needs no database migration.

Re-run the documented configured `flutter run --profile` command to update the
connected iPhone. Android APKs and QA records are under `outputs/apk` and
`outputs/final-android24`.
