# Launching on the App Store

The iPhone app shares everything with Android (code, backend, prices). This
list is only what's different. Do the Play launch first (docs/LAUNCH_PLAYSTORE.md):
the backend, RevenueCat project and AdMob account are reused.

You don't need a Mac. The iPhone build runs on a cloud Mac (step 6).

## 1. Apple Developer account

- Join the Apple Developer Program: **$99 a year**. As an individual it's
  ready in a day or two. As a company you first need a free D-U-N-S number
  (1–2 weeks).
- App Store Connect → Agreements, Tax and Banking: accept the **Paid Apps**
  agreement and add bank and tax details. Subscriptions don't load until this
  is done.

## 2. App ID and keys (developer.apple.com → Certificates, IDs & Profiles)

1. Identifiers → **App ID** `com.clearskinai.app`, with **Sign in with Apple**
   and **App Attest** turned on.
2. Keys → new key with **Sign in with Apple** → download the `.p8` (only
   downloadable once). Note its **Key ID** and your **Team ID** (top right).

## 3. Backend (Supabase)

1. Deploy the iPhone pieces (same commands as Android, step 2 there):
   migration `20261028000000_ios.sql`, functions `app-attest` and `apple-token`.
2. Secrets in `supabase/functions/.env`, then `supabase secrets set`:

   | Setting | Value |
   |---|---|
   | `APPLE_APP_ID` | `<Team ID>.com.clearskinai.app` (turns on the iPhone anti-tamper check) |
   | `APPLE_TEAM_ID`, `APPLE_SIGN_IN_KEY_ID`, `APPLE_SIGN_IN_KEY` | from step 2.2 (paste the whole `.p8` file) |
   | `APP_ATTEST_ALLOW_DEVELOPMENT` | `false` |

3. Supabase → Authentication → Providers → **Apple**: enable, and put
   `com.clearskinai.app` in **Client IDs**. (No secret is needed for the native
   iPhone sign-in.)
4. Google sign-in on iPhone (optional; it's hidden until set): Google Cloud →
   Credentials → **iOS OAuth client** for `com.clearskinai.app`. Put its client
   ID in `GOOGLE_IOS_CLIENT_ID` (env/prod.json) and in Supabase → Google
   provider → **Client IDs** (comma-separated, after the web one), and its
   "iOS URL scheme" in `GOOGLE_IOS_URL_SCHEME` in `ios/Flutter/AppIds.xcconfig`.

`INTEGRITY_MODE=enforce` covers both platforms. Set `APPLE_APP_ID` **before**
switching to enforce, or iPhone users can't scan.

## 4. Subscriptions (App Store Connect → your app → Subscriptions)

- One subscription group "ClearSkin Premium" with **Premium Monthly $4.99**
  and **Premium Yearly $29.99**, same product IDs as on Play where possible.
  Add the free trial as an **introductory offer**.
- RevenueCat → add the **App Store app**, upload an **In-App Purchase key**
  (App Store Connect → Users and Access → Integrations), attach the products to
  the same `premium` entitlement and `default` offering. Copy the public
  **Apple API key** (`appl_…`) into `RC_IOS_KEY` in env/prod.json.

## 5. AdMob

- AdMob → Apps → add the **iOS** app → three units (banner, interstitial,
  rewarded). The rewarded unit uses the **same** server-side verification URL as
  Android.
- App ID → `ADMOB_IOS_APP_ID` in `ios/Flutter/AppIds.xcconfig`. Units →
  `ADMOB_IOS_BANNER_ID`, `ADMOB_IOS_INTERSTITIAL_ID`, `ADMOB_IOS_REWARDED_ID` in
  env/prod.json.
- Paste Google's full **SKAdNetwork** list
  (developers.google.com/admob/ios/3p-skadnetworks) plus AppLovin's, Meta's and
  Unity's into `SKAdNetworkItems` in `ios/Runner/Info.plist`. Only Google's own
  entry is there now. Ads work without the rest, but they earn less.

## 6. Build and upload (Codemagic, cloud Mac, free tier ~500 min/month)

1. codemagic.io → sign in with GitHub → add `bornBrian/clearskin-ai` → Flutter app.
2. Teams → Integrations → **App Store Connect** API key (App Store Connect →
   Users and Access → Integrations → App Store Connect API, role App Manager).
3. Environment variables: `PROD_JSON` = the contents of env/prod.json (secure).
4. Workflow: iOS, release, automatic code signing (App Store), build command

   ```bash
   echo "$PROD_JSON" > env/prod.json
   flutter build ipa --release --obfuscate --split-debug-info=build/symbols \
     --dart-define-from-file=env/prod.json
   ```

   Publish to **App Store Connect / TestFlight**. Keep `build/symbols` from each
   release (crash reports need it).

The GitHub workflow `.github/workflows/ios.yml` builds the iPhone app on
every iOS change, without signing, to catch build breaks early.

## 7. App Store Connect listing

- **App Privacy**: answer exactly as `ios/Runner/PrivacyInfo.xcprivacy` says
  (user ID, e-mail, name, photos, other user content, coarse location, device ID,
  purchases: App Functionality, linked; product interaction: Analytics;
  crash data; **no tracking**). Ads: AdMob's own manifest adds its data types.
- Age rating: medical/treatment information "infrequent/mild". Not "Made for Kids".
- Category: Health & Fitness (or Lifestyle). Price: free with in-app purchases.
- Screenshots: 6.9" iPhone (1320×2868) required. iPhone only, so no iPad set.
- Review notes: "No sign-in needed to use the app. Account deletion: Settings →
  Delete account & all data. Scans give cosmetic skincare guidance, not a
  diagnosis; the medical disclaimer is shown before the first scan."

## 8. TestFlight

Internal testers (up to 100, no review) right away; external testers after a
short beta review. There's no 14-day rule like Google's.
