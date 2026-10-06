# App Store privacy worksheet

Complete App Store Connect from the exact production binary and production
privacy policy. The first release does not track people, sell data, show ads or
collect payment credentials inside the app.

## URLs

- Privacy Policy URL: `https://YOUR_PUBLIC_DOMAIN/privacy`
- Privacy Choices URL: `https://YOUR_PUBLIC_DOMAIN/delete-account`
- Support URL: `https://YOUR_PUBLIC_DOMAIN/support`

## App Privacy answers

Select **Yes, we collect data from this app** and declare:

| Apple data type | Linked to identity | Tracking | Purpose |
| --- | --- | --- | --- |
| Contact Info → Name | Yes | No | App Functionality |
| Contact Info → Email Address | Yes | No | App Functionality |
| Contact Info → Phone Number | Yes | No | App Functionality |
| Contact Info → Physical Address | Yes | No | App Functionality |
| Purchases → Purchase History | Yes | No | App Functionality |
| Identifiers → User ID | Yes | No | App Functionality |

Build 16 includes Firebase Core/Messaging. Declare the actual enabled flows and
the data reported by the SDK manifests in the final archive:

| Apple data type | Linked to identity | Tracking | Purpose |
| --- | --- | --- | --- |
| Identifiers → Device ID | Yes (registered tokens are associated with the account) | No | App Functionality |
| Location → Precise Location | Yes | No | App Functionality, optional delivery pin |
| Location → Coarse Location | Yes | No | App Functionality, optional approximate pin |
| Diagnostics → Other Diagnostic Data | No | No | App Functionality; messaging SDK analytics |
| Other Data → Other Data Types | No | No | Analytics |

Do not declare payment information for the first release. Customers pay outside
the app at pickup or delivery, and the native online-payment SDK is excluded.
If native payment is introduced later, redo the binary privacy report, this
worksheet, the public privacy policy and the App Store answers before upload.

## Privacy manifest alignment

`ios/Runner/PrivacyInfo.xcprivacy` declares customer/contact, location, device and
messaging SDK data types, no tracking, no tracking domains and
no app-owned required-reason API use. Third-party frameworks carry their own
privacy manifests. Validate the aggregated privacy report from the final Xcode
archive rather than assuming source declarations match the submitted binary.

## Retention and deletion

Eligible account deletion removes the Auth identity, profile, saved addresses,
notification tokens, notifications and personal offer-redemption records.
Active orders must first be completed or cancelled. Completed transaction rows
may be retained for accounting, fraud prevention and legal obligations, but the
deletion transaction removes the customer link and recipient personal data.

## Final reconciliation

Before submission:

1. Confirm Razorpay is absent; reconcile Firebase Core/Messaging SDK manifests,
   optional push configuration, APNs entitlement, and the final archive report.
2. Generate Xcode's privacy report from the final archive and compare every
   listed data type with this worksheet.
3. Test account deletion against production Supabase.
4. Confirm the deployed policy has the final support email and accurately
   describes every enabled provider.
