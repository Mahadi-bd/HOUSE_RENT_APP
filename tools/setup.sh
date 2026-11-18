#!/usr/bin/env bash
# THE ONE setup script. Works on Linux and macOS. Run once from an EMPTY folder named rent_solution,
# then copy the project files over it (the zip's lib/, test/, assets/, tools/ ...).
# Needs: Flutter (recent stable with build-hook support), python3, Node (only for the rules tests).
set -euo pipefail

APP_ID="com.rentsolution.app"
FIREBASE_PROJECT="rent-solution-2dd62"

flutter create --org com.rentsolution --project-name rent_solution --platforms android,ios .

# `flutter create` builds the id as org + project name (com.rentsolution.rent_solution),
# which is NOT the intended id. Fix it everywhere and print the real values.
bash tools/set_app_id.sh "$APP_ID"

flutter pub add flutter_riverpod go_router drift sqlite3 path_provider path \
  flutter_secure_storage cryptography crypto firebase_core firebase_auth cloud_firestore \
  google_sign_in local_auth intl logger pdf printing url_launcher image_picker app_links flutter_tesseract_ocr
flutter pub add flutter_localizations --sdk=flutter
flutter pub add --dev drift_dev build_runner very_good_analysis
flutter pub add --dev integration_test --sdk=flutter

mkdir -p assets/brand assets/fonts assets/tessdata
bash tools/fetch_tessdata.sh || echo 'WARNING: language data not downloaded; OCR will not work until you run tools/fetch_tessdata.sh'
python3 tools/patch_pubspec.py
python3 tools/patch_android.py

dart pub global activate flutterfire_cli
flutterfire configure --project="$FIREBASE_PROJECT" --platforms=android,ios \
  --android-package-name="$APP_ID" --ios-bundle-id="$APP_ID"

echo
echo "Next: add the Noto Sans Bengali font files (see README), then run: bash tools/verify_phase1_1.sh"
