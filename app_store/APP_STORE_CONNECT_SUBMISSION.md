# App Store Connect submission checklist

## Permanent release identity

- App name: **Koya Stores**
- Bundle ID: **`com.koyas.koyasSupermarket`**
- Version: **`1.1.5`**
- Build: **`9`**
- Platform: **iPhone only** for the first release
- Minimum iOS version: **iOS 15**
- Primary category: **Shopping**
- Secondary category: **Food & Drink** (optional)
- Suggested SKU: **`KOYAS-IOS-001`**
- Ads: **No**
- In-App Purchases: **No**
- Tracking: **No**
- First-release payment: **Cash or UPI at pickup/delivery**
- Native online payment: **Not included**
- Push notifications: **Not included in the first release**

Treat the bundle ID as permanent after creating the App Store Connect record.
Future uploads for version `1.1.5` must use a build number greater than `9`.

## Repository-controlled items completed

- Customer account deletion is available in the app.
- Public privacy, account-deletion and customer-support pages are ready for
  Vercel.
- An app-owned `PrivacyInfo.xcprivacy` declares customer data used for account
  and order functionality and declares no tracking.
- Debug-only Bonjour/local-network descriptions are excluded from Release.
- The Release Info.plist declares that the app does not use non-exempt
  encryption.
- Release builds require production Supabase values, public legal URLs and a
  reusable reviewer-login path.
- The first Release is iPhone-only and portrait-only, matching its tested UI and
  screenshot set.
- The launch screen uses Koya Stores branding instead of a blank image.
- Razorpay remains excluded. Firebase Core/Messaging are included in build 16;
  background delivery requires credentials, APNs signing and device verification.
- iOS native dependencies use Swift Package Manager without CocoaPods.
- App Store metadata, privacy answers and reviewer instructions are prepared in
  `app_store/`.

## Account, credentials and console actions still required

1. Enrol the legal owner in the Apple Developer Program and complete all tax,
   banking and agreement prompts shown in App Store Connect.
2. Create an explicit App ID for `com.koyas.koyasSupermarket`, then create the
   App Store Connect app using that exact bundle ID.
3. Confirm that Apple allows the display name **Koya Stores** and use a unique
   internal SKU.
4. Select the organization's Apple Developer Team for Runner in Xcode. Use
   automatic signing and let Xcode manage the App Store provisioning profile.
5. Choose a monitored support email and add it to App Review contact details,
   TestFlight feedback, the public support page and the privacy policy.
6. Deploy Supabase and Vercel. Replace every `YOUR_*` URL/key in build commands
   with production values.
7. Create the dedicated ordinary customer reviewer account described in
   `APP_REVIEW_ACCESS.md`. Never make this account an administrator.
8. Complete App Privacy using `APP_PRIVACY.md`; use `/privacy` as the Privacy
   Policy URL and `/delete-account` as the Privacy Choices URL.
9. Complete the age-rating questionnaire honestly. For the current grocery-only
   catalogue, all objectionable-content answers are **None** and the calculated
   rating should normally be **4+**. Re-answer if age-restricted goods are added.
10. Confirm content rights for every product image and catalogue entry before
    selecting that the app has the necessary rights to third-party content.
11. Build the archive with the production command in `README.md`, then run
    `tool/verify_ios_release.sh` against the exported `.app` or `.ipa`.
12. Upload with Xcode Organizer, allow App Store Connect to process the build,
    and resolve every validation warning before TestFlight distribution.
13. Install the processed build through TestFlight on a physical iPhone. Test
    reusable review login, OTP login, catalogue, offers, cart, pickup, delivery,
    order lifecycle, pay-at-handover reconciliation, privacy links and account
    deletion.
14. Upload one to ten production screenshots from `app_store/assets/iphone-6.9/`,
    paste the metadata from `listing/en-US/`, provide App Review contact details,
    and select the processed build.
15. Submit to TestFlight external review first. After the production backend has
    remained stable, submit the same verified build to App Review using manual
    release.

## Suggested App Review notes

Koya Stores is a local supermarket ordering app for store pickup and manually
arranged delivery in Hyderabad. The first release does not collect payment in
the app. Customers pay by cash or UPI when collecting the order or when delivery
arrives. The reviewer account uses the **App review access** button on the login
screen and does not require access to an OTP inbox. Account deletion is under
Profile → Privacy and account → Delete account. The public privacy, support and
deletion URLs are provided in App Store Connect.

## Final physical-device flow

- Fresh install and relaunch
- Reusable reviewer login and ordinary email OTP login
- Profile name and phone editing
- Browse/search/filter products and open product variants
- Apply a percentage/fixed offer and a minimum-buy free-product offer
- Pickup checkout and delivery checkout with recipient/address/instructions
- Admin receives the order and sees complete fulfilment details
- Admin advances, rejects and cancels eligible orders
- Admin marks cash/UPI payment received and analytics update
- Customer receives realtime status updates
- Privacy/support/deletion pages open over HTTPS
- Deletion is blocked for active orders and succeeds after closure
- Deleted customer can no longer sign in with the deleted credentials
