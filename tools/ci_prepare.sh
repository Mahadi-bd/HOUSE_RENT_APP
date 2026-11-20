#!/usr/bin/env bash
# Prepares a fresh checkout so it can build an APK (used by GitHub Actions; also fine locally).
# Linux and macOS. Needs flutter and python3 on PATH.
# Secrets come from the environment (GitHub "secrets"), never from files in git:
#   GOOGLE_SERVICES_JSON        base64 of android/app/google-services.json
#   FIREBASE_OPTIONS_DART       base64 of lib/firebase_options.dart
#   KEYSTORE_BASE64, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD   (release signing, optional)
set -euo pipefail
APP_ID="com.rentsolution.app"

if [ ! -d android ]; then
  flutter create --org com.rentsolution --project-name rent_solution --platforms android,ios .
fi
# flutter create adds a sample test that does not belong to this app.
if [ -f test/widget_test.dart ] && grep -q "MyApp" test/widget_test.dart; then rm -f test/widget_test.dart; fi

# Two files that came from an earlier attempt and are not part of this project (they break the build).
for stray in lib/features/household/presentation/add_household_screen.dart test/vault_and_ids_test.dart; do
  if [ -f "$stray" ]; then rm -f "$stray"; echo "removed stray file $stray"; fi
done

bash tools/set_app_id.sh "$APP_ID"
python3 tools/patch_pubspec.py
python3 tools/patch_android.py

bash tools/fetch_tessdata.sh || echo "WARNING: language data not downloaded (OCR will not work in this build)"

put_secret() { # put_secret <env var> <target path>: accepts raw text or base64
  local value="${!1:-}"
  if [ -n "$value" ]; then
    mkdir -p "$(dirname "$2")"
    case "$value" in
      \{*|\/\/*|import*) printf '%s' "$value" > "$2" ;;
      *) printf '%s' "$value" | base64 --decode > "$2" ;;
    esac
    echo "wrote $2 from secret $1"
  fi
}
put_secret GOOGLE_SERVICES_JSON android/app/google-services.json
put_secret FIREBASE_OPTIONS_DART lib/firebase_options.dart

PLACEHOLDER=0
if [ ! -f android/app/google-services.json ]; then
  if [ "${REQUIRE_FIREBASE:-0}" = "1" ]; then
    echo "MISSING secret GOOGLE_SERVICES_JSON (download google-services.json from the Firebase console and paste its whole text as a repository secret)"; exit 1
  fi
  PLACEHOLDER=1
fi
if [ ! -f lib/firebase_options.dart ]; then
  if [ "$PLACEHOLDER" = "1" ]; then
    python3 tools/make_firebase_options.py --placeholder
    echo "::warning::No Firebase secret found: building with PLACEHOLDER Firebase settings. This only checks that the code compiles. The APK cannot sign in or sync."
  else
    python3 tools/make_firebase_options.py
  fi
fi

if [ -n "${KEYSTORE_BASE64:-}" ]; then
  printf '%s' "$KEYSTORE_BASE64" | base64 --decode > android/app/upload-keystore.jks
  cat > android/key.properties <<PROPS
storePassword=${KEYSTORE_PASSWORD}
keyPassword=${KEY_PASSWORD}
keyAlias=${KEY_ALIAS}
storeFile=upload-keystore.jks
PROPS
  echo "release signing configured"
else
  echo "no keystore secret: the release APK will be signed with the debug key (installable, not for the Play Store)"
fi
