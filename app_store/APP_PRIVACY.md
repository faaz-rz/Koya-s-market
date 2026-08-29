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

If Firebase push notifications are added in a later binary, also declare the
data reported by the chosen Firebase SDK version's privacy manifests:

| Apple data type | Linked to identity | Tracking | Purpose |
| --- | --- | --- | --- |
| Identifiers → Device ID | No | No | App Functionality |
| Diagnostics → Other Diagnostic Data | No | No | App Functionality |
| Other Data → Other Data Types | No | No | Analytics |

Do not declare payment information for the first release. Customers pay outside
the app at pickup or delivery, and the native online-payment SDK is excluded.
If native payment is introduced later, redo the binary privacy report, this
worksheet, the public privacy policy and the App Store answers before upload.

## Privacy manifest alignment

`ios/Runner/PrivacyInfo.xcprivacy` declares the six linked customer data types
used for account and order functionality, no tracking, no tracking domains and
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

1. Confirm Firebase and Razorpay frameworks are absent from the uploaded IPA.
2. Generate Xcode's privacy report from the final archive and compare every
   listed data type with this worksheet.
3. Test account deletion against production Supabase.
4. Confirm the deployed policy has the final support email and accurately
   describes every enabled provider.
