# Release Builds and Signing

Debug APKs are signed with Godot's debug keystore automatically. Store builds need your own keys. Never commit
keystores or passwords; keep them out of the project folder or in a password manager.

## Android (Google Play)

1. **Create an upload key** once (keep it safe: losing it means contacting Google to reset it):
   ```
   keytool -genkeypair -v -keystore ~/keys/swingandshoot-upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
   ```
2. **Point the export at it** without writing secrets into `export_presets.cfg`: set environment variables
   before exporting (Godot reads them for the release keystore):
   ```
   export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=~/keys/swingandshoot-upload.jks
   export GODOT_ANDROID_KEYSTORE_RELEASE_USER=upload
   export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=...
   ```
3. **Play needs an `.aab`**: enable *Use Gradle Build* in the Android preset (needs JDK 17 and the Android build
   template: *Project → Install Android Build Template*), set *Export Format* to AAB, bump `version/code` (an integer,
   +1 every upload) and `version/name`, then:
   ```
   godot --headless --path . --export-release "Android" export/android/swing-and-shoot.aab
   ```
4. In Play Console, opt into **Play App Signing** (Google keeps the app key; you upload with the upload key).
5. Fill the Data safety form ("no data collected"), content rating questionnaire, and target audience. Upload the
   listing from `docs/store/listing.md` and the screenshots.

## iOS (App Store)

1. Needs a Mac with Xcode, an Apple Developer account ($99/year) and its **Team ID** (set
   `application/app_store_team_id` in the iOS preset).
2. Bundle ID `com.jefflabs.swingandshoot`; register it in the developer portal. For LAN auto-discovery request the
   **multicast networking entitlement** (`com.apple.developer.networking.multicast`) from Apple; until it is granted,
   iPhones join with the join code (§6.2).
3. Export the Xcode project from Godot (*iOS* preset), open it, choose *Automatically manage signing* with your team,
   *Product → Archive*, then *Distribute App → App Store Connect*.
4. In App Store Connect: privacy label "Data Not Collected", the privacy policy URL, age rating, screenshots
   (6.9" iPhone and 13" iPad sizes), and the listing text.

## Every release

- `version/code` (Android) and `application/version` (iOS) go up by one; the shown version is
  `application/config/version` in `project.godot` and both presets.
- If the LAN protocol changed, `NetProtocol.VERSION` goes up so old and new builds refuse to play together.
- Run the full test suite: `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`.
- Play a LAN session on real phones (§6.2 "done when").
