#!/usr/bin/env bash
# Sets Android namespace/applicationId and the iOS bundle identifier, then prints what is
# actually in the project files. Safe to run again.
set -euo pipefail
APP_ID="${1:-com.rentsolution.app}"
OLD_PKG_DIR_GLOB="android/app/src/main/kotlin"

GRADLE="android/app/build.gradle.kts"
[ -f "$GRADLE" ] || GRADLE="android/app/build.gradle"
[ -f "$GRADLE" ] || { echo "No android/app/build.gradle(.kts) found. Run flutter create first."; exit 1; }

# Android: namespace and applicationId (Kotlin DSL "x = \"..\"" and Groovy "x \"..\"" forms).
sed -i.bak -E "s/(namespace[[:space:]]*=?[[:space:]]*)\"[^\"]+\"/\1\"$APP_ID\"/" "$GRADLE"
sed -i.bak -E "s/(applicationId[[:space:]]*=?[[:space:]]*)\"[^\"]+\"/\1\"$APP_ID\"/" "$GRADLE"

# Android: move MainActivity into the new package folder and fix its package line.
MAIN_FILE="$(find "$OLD_PKG_DIR_GLOB" "android/app/src/main/java" -name 'MainActivity.*' 2>/dev/null | head -n1 || true)"
if [ -n "$MAIN_FILE" ]; then
  EXT="${MAIN_FILE##*.}"
  ROOT="$(dirname "$MAIN_FILE" | sed -E 's#(kotlin|java)/.*#\1#')"
  NEW_DIR="$ROOT/$(echo "$APP_ID" | tr . /)"
  mkdir -p "$NEW_DIR"
  if [ "$MAIN_FILE" != "$NEW_DIR/MainActivity.$EXT" ]; then
    mv "$MAIN_FILE" "$NEW_DIR/MainActivity.$EXT"
    find "$ROOT" -type d -empty -delete 2>/dev/null || true
  fi
  sed -i.bak -E "s/^package .*/package $APP_ID/" "$NEW_DIR/MainActivity.$EXT"
  rm -f "$NEW_DIR/MainActivity.$EXT.bak"
fi

# iOS: every non-test target gets the id; the test target gets id.RunnerTests.
PBX="ios/Runner.xcodeproj/project.pbxproj"
[ -f "$PBX" ] || { echo "No $PBX found."; exit 1; }
sed -i.bak -E "s/(PRODUCT_BUNDLE_IDENTIFIER = )[^;]*\.RunnerTests;/\1$APP_ID.RunnerTests;/" "$PBX"
sed -i.bak -E "/RunnerTests/!s/(PRODUCT_BUNDLE_IDENTIFIER = )[^;]+;/\1$APP_ID;/" "$PBX"
rm -f "$PBX.bak" "$GRADLE.bak"

echo "== Actual values in the project =="
echo "Android gradle file: $GRADLE"
grep -nE 'namespace|applicationId' "$GRADLE" || true
echo "MainActivity package:"
grep -rn "^package " android/app/src/main --include='MainActivity.*' || true
echo "iOS PRODUCT_BUNDLE_IDENTIFIER values:"
grep -n "PRODUCT_BUNDLE_IDENTIFIER" "$PBX" | sort -u || true
echo "Firebase files (created by flutterfire configure):"
ls -1 android/app/google-services.json ios/Runner/GoogleService-Info.plist 2>/dev/null || echo "  not created yet"
