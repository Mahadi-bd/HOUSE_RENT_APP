# Build the APK on GitHub (no Flutter on your own computer needed after step 2)

## 1. Put the project on GitHub
1. Create a PRIVATE repository on github.com.
2. Unzip the project and upload everything (GitHub web upload, or `git push`). The `.gitignore` already keeps secrets out.

## 2. Firebase: ONE file (no Flutter needed on your side)
1. Firebase console > Project settings > "Your apps" > **Add app > Android**. Package name exactly `com.rentsolution.app`. (Skip the SHA step for now.)
2. Download `google-services.json`, open it in any text editor, copy ALL the text.
3. GitHub repository > Settings > Secrets and variables > Actions > New repository secret.
   Name: `GOOGLE_SERVICES_JSON`. Value: paste the whole text. Save.
That is all: the build creates `lib/firebase_options.dart` from this file by itself. (`FIREBASE_OPTIONS_DART` is no longer needed.)
Until the secret exists, the "CI and debug APK" workflow still runs with PLACEHOLDER Firebase settings: it only proves the code compiles and the tests pass. That APK cannot sign in.

## 3. Make a signing key ONCE (so Google sign-in works and updates install over each other)
`keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
Then print its fingerprints and add BOTH the SHA-1 and SHA-256 to Firebase (Project settings > your Android app > Add fingerprint):
`keytool -list -v -keystore upload-keystore.jks -alias upload`
Base64 the keystore the same way. KEEP A SAFE COPY of the .jks and its passwords: if you lose it you cannot update the app under the same signature.

## 4. Add repository secrets (GitHub > Settings > Secrets and variables > Actions)
`GOOGLE_SERVICES_JSON` (step 2), `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS` (upload), `KEY_PASSWORD`.

## 5. Build
- Actions tab > **Release APK** > Run workflow. When it finishes, download the artifact `rent-solution-release-apk`.
- Or push a tag such as `v0.3.0`: the APK is attached to a GitHub Release automatically.
- **CI and debug APK** runs on every push, tests the Firestore rules on the emulator, analyzes, tests, and builds a debug APK.
  A debug APK built on GitHub gets a new random debug key every time, so Google sign-in will NOT work in it; use the Release APK.

## 6. First run
Expect failures on the first run (nobody has compiled this code yet). Send me the log of the failing step; I fix it.
When a run succeeds, download the `pubspec-lock` artifact and commit `pubspec.lock` so later builds use the same versions.

## Not covered
iPhone builds (need a Mac and an Apple Developer account). Deep links on iOS (Associated Domains) are not set up; iPhones use the paste-link step.
