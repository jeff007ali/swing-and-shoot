# Release Builds and Signing

Debug APKs are signed with Godot's debug keystore automatically. Store builds need your own keys. Never commit
keystores or passwords; keep them out of the project folder or in a password manager.

## Shareable APK on GitHub (automatic)

`.github/workflows/android-release.yml` builds the APK on GitHub's servers whenever you push a version
tag, runs the tests, signs it with your key and attaches it to a GitHub Release. The newest APK is
then always at one fixed link:

```
https://github.com/<owner>/<repo>/releases/latest/download/swing-and-shoot.apk
```

### One-time setup

1. **Make a signing key** (once, and keep it backed up: every future build must use the same key, or
   phones refuse to update over the old install). Store it outside the project folder:
   ```
   keytool -genkeypair -v -keystore ~/keys/swingandshoot-release.jks -alias swingandshoot -keyalg RSA -keysize 2048 -validity 10000
   ```
   It asks for a password and a name; remember the password and the alias (`swingandshoot`).
2. **Copy the key as text** for GitHub:
   ```
   base64 -i ~/keys/swingandshoot-release.jks | pbcopy
   ```
3. **Add three secrets** in the repo: *Settings → Secrets and variables → Actions → New repository secret*:
   - `ANDROID_KEYSTORE_BASE64`: paste the clipboard from step 2
   - `ANDROID_KEYSTORE_ALIAS`: `swingandshoot`
   - `ANDROID_KEYSTORE_PASSWORD`: the password from step 1

   Secrets are never shown in logs or to people who fork the repo.
4. In *Settings → Actions → General*, make sure workflows are allowed to run (default on). The workflow
   asks for `contents: write` itself, which it needs to create releases.

### Making a release

```
git tag v0.2.0
git push origin v0.2.0
```

The *Actions* tab shows the build (about 5–10 minutes the first time). When it's green, the release
appears under *Releases* with `swing-and-shoot.apk` and notes listing the commits since the last tag.
The version shown in the game becomes `0.2.0`; Android's internal version code is the workflow run
number, so every release counts as newer than the last.

To get a test APK without making a release, run the workflow by hand (*Actions → Android APK release →
Run workflow*); the APK is then a downloadable artifact of that run.

### Installing from the link

On the phone, open the link, download, and allow *Install unknown apps* for the browser when Android
asks (once). Builds from the workflow are release builds: `adb shell run-as` (D24) doesn't work on
them, so use a local debug build when you need the playtest CSVs.

In a private repository only people with access can download; for a link anyone can open, the
repository must be public.

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
