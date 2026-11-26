# Store release checklist

This checklist reflects the current TypeSync source tree. Update the privacy
answers whenever an SDK or a data flow changes.

## iOS / TestFlight

GitHub Actions builds TypeSync on relevant pushes to `unstable`. For a manual
build, open **Actions → TypeSync TestFlight → Run workflow** and select the branch.
The workflow reads the marketing version from pubspec.yaml and checks Apple’s
existing build numbers before signing. It uploads to TestFlight only.

Configure the repository secrets `ASC_ISSUER_ID`, `ASC_KEY_ID`, `ASC_PRIVATE_KEY`,
`IOS_CERTIFICATE_PASSWORD`, `IOS_DISTRIBUTION_P12_BASE64`, and `IOS_PROFILE_BASE64`.
Use the App Store profile for `de.khonager.typesync` with Associated Domains.
Set `REVENUECAT_APPLE_API_KEY` to TypeSync’s Apple public SDK key. The Firebase
plist and other Flutter assets are versioned in Git.

Flutter 3.27.3 supports the existing Quill editor. Its iOS runner uses the
application-delegate lifecycle. Use Xcode 26.6 until the runner and Flutter
plugins support UIScene. Apple requires SDK 27 for uploads starting April 2027.

Verify processing and internal testing availability for the uploaded version and
build in [TypeSync TestFlight](https://appstoreconnect.apple.com/apps/6762024261/testflight).
External beta review and public release are separate decisions.

Before uploading, configure the same products and entitlement IDs in App Store
Connect, RevenueCat, and the app: `monthly`, `typesync_plus_monthly`, and
`typesync_pro_monthly`; entitlements `TypeSync Lite`, `plus`, and `pro`.
Test purchases through Sandbox/TestFlight before submission.

## Google Play: Data safety

Select **Yes, this app collects user data**. “Collected” includes data sent by
an SDK, not only data sent to your own server. TypeSync uses Firebase
Authentication, Firestore, Cloud Storage, and RevenueCat.

Use these answers for the current app, provided you do not add analytics,
crash reporting, ads, Google Calendar integration, or Health Connect:

| Play data type | Collected? | Shared? | Purpose | Required? | Encrypted in transit? | Deletable? |
| --- | --- | --- | --- | --- | --- | --- |
| Name | Yes, if a user supplies a display name | No | App functionality; account management | Optional | Yes | Yes |
| Email address | Yes | No | App functionality; account management | Required to create an account | Yes | Yes |
| User IDs | Yes (Firebase UID; RevenueCat app user ID) | No, if Firebase/RevenueCat only process it as your service providers | App functionality; account management | Required for signed-in sync/purchases | Yes | Yes |
| Purchase history | Yes (subscription/product/entitlement state) | No, if RevenueCat has no non-service-provider integrations | App functionality | Optional; only when subscribing | Yes | Yes |
| Photos | Yes, only when the user chooses one as an attachment | No, if Cloud Storage is only your service provider | App functionality | Optional | Yes | Yes |
| Files and docs | Yes (note attachments and their metadata) | No, if Cloud Storage is only your service provider | App functionality | Optional | Yes | Yes |
| Calendar events | Yes (events created inside TypeSync, synced as app data) | No, if Firestore is only your service provider | App functionality | Optional | Yes | Yes |
| Other user-generated content | Yes (notes, folders, homework, timetable content) | No, if Firestore is only your service provider | App functionality | Optional | Yes | Yes |
| App info and performance / diagnostics | Do not declare unless a shipped SDK actually sends it | — | — | — | — | — |
| Device or other IDs | Verify Firebase and RevenueCat’s current Android SDK disclosure before submitting; declare if their shipped SDKs transmit installation/device identifiers | Usually shared with the respective SDK provider | App functionality, and security/fraud prevention if applicable | Optional | Yes | Yes |

“Shared” needs particular care: a transfer to a service provider processing
data solely on your behalf is not “shared” for this form. The table assumes
Firebase and RevenueCat are used only in that role, with no advertising,
analytics, or other third-party integrations. If that assumption changes, mark
the affected row as shared. Do not claim data is anonymous: the cloud sync data
is associated with the signed-in account.

The app has an in-app **Profile → Delete Account** flow that deletes the
Firebase account, cloud records, and stored attachments. It does **not**
currently erase the associated RevenueCat customer record. Before submission,
either add a backend process to delete/anonymize that customer through
RevenueCat or publish a support/contact deletion route and describe any
retained purchase records in the privacy policy. Confirm the outcome in a test
account before submitting.

## Google Play: financial features and health

For **Financial features**, select **No**. TypeSync sells optional digital
subscriptions; it does not provide banking, lending, investing, insurance,
payments, or other financial products. Subscription purchase history belongs
in Data safety, but it does not make the app a financial-services app.

For the mandatory **Health apps declaration**, select **No health features**.
TypeSync is a note, calendar, homework, and timetable app. It has no health or
fitness feature, no Health Connect integration, and no health-related Android
permission. User-written notes may contain arbitrary text, but that is not a
health feature offered by the app. Revisit this answer if you add health
tracking, medical claims, Health Connect, or a relevant permission.

## Both stores: remaining submission essentials

- Publish a public privacy policy that accurately covers Firebase, RevenueCat,
  cloud sync, attachments, subscriptions, retention, and in-app account
  deletion; enter its URL in both consoles.
- Complete the App Store privacy label from the same data inventory, including
  the practices of Firebase and RevenueCat. Apple requires a privacy policy
  URL and data-practice answers for third-party partners too.
- Prepare store listing copy, category, support URL/email, 1024×1024 iOS icon,
  Android app icon, screenshots for every supported device class, and a
  reviewer demo account/instructions if sign-in blocks review.
- Complete Google Play App content: privacy policy, ads declaration (No, if
  unchanged), target audience/content rating, app access instructions, and
  account-deletion declaration. Complete Apple age rating, export compliance
  (the app currently declares no non-exempt encryption), pricing/availability,
  and App Review notes.
- Use the stores’ own purchase systems for the iOS/Android digital
  subscriptions, with RevenueCat connected as the entitlement service. Do not
  enable an external web checkout from the native app unless it is permitted
  for the relevant storefront and policy.
