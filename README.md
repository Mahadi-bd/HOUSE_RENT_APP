# Rent Solution (Phase 1 + 1.1 + 2 + 2.1)

Source of truth: Rent Solution Master Prompt v3 (a doc in claude.ai).
Read `docs/PHASE_2_2_REPORT.md` and `docs/PHASE_2_1_REPORT.md` first: it says what is done, what is not, and what needs your decision.

## 1. Create the project (Linux or macOS)
1. Make an empty folder `rent_solution`. Copy this whole zip into it, then run `bash tools/setup.sh`.
   It creates the Flutter project, forces the application id to `com.rentsolution.app`, adds packages, prepares `pubspec.yaml`
   (assets, localization generation, encrypted SQLite) and runs FlutterFire with the same id. It prints the real ids: check them.
   If `flutter create` complains the folder is not empty, create the project in a temporary folder first and copy this zip over it.
2. Bengali: put `NotoSansBengali-Regular.ttf` and `NotoSansBengali-Bold.ttf` (SIL OFL) in `assets/fonts/`, then run `python3 tools/patch_pubspec.py`.
   Until then the app text falls back to the system font and receipts print in English.
3. Append `.gitignore.additions` to `.gitignore`. Keep `pubspec.lock` committed.
4. Firebase console: see `firebase/README_FIREBASE.md`. **Do not publish `firestore.rules` until the emulator tests pass.**
5. App icon: needs a 1024x1024 PNG with real transparency (`flutter_launcher_icons` is not added until you approve it).

## 1b. Build the APK on GitHub
See `docs/GITHUB_APK_GUIDE.md`. The workflows in `.github/workflows/` build everything from the repository.

## 2. Run the gate
`bash tools/verify_phase1_1.sh` runs every command and writes `verification/REPORT.md` with PASS, FAIL, BLOCKED or NOT RUN.
Nothing in that report is typed by hand. Send me failures; they come before any new feature.

## 3. Decisions waiting for the Owner
- Offline authorization lease durations: `docs/OFFLINE_AUTHORIZATION_POLICY.md`
- Sign in with Apple option: `docs/APPLE_SIGNIN_AND_ACCOUNT_DELETION.md`
- Scoped Firestore design (before Phase 3) and Phase 2.2 to 2.4 plan: `docs/PHASE_2_1_REPORT.md`
- New packages: `app_links`, `url_launcher`, `image_picker`
- Tickets in Phase 6 (tenant Tickets tab is a placeholder until then)

## 4. Brand
`lib/core/brand/brand_config.dart` holds the brand of this build (LIFE EASY, owner name, logo). Business details are editable in Settings.
