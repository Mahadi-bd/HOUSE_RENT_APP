#!/usr/bin/env bash
# Runs the Phase 1.1 gate for real and writes verification/REPORT.md.
# Every step is PASS (exit code 0), FAIL (non-zero), or BLOCKED (tool missing).
# Nothing is simulated: the logs in verification/ are the evidence.
set -uo pipefail
mkdir -p verification
REPORT=verification/REPORT.md
: > "$REPORT"
echo "# Phase 1.1 verification report" >> "$REPORT"
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ) on $(uname -srm)" >> "$REPORT"
echo >> "$REPORT"
echo "| # | Step | Result | Log |" >> "$REPORT"
echo "|---|------|--------|-----|" >> "$REPORT"
N=0

step() { # step "name" "tool-needed" command...
  local name="$1" tool="$2"; shift 2
  N=$((N+1)); local log; log=$(printf "verification/%02d_%s.log" "$N" "$(echo "$name" | tr -c 'A-Za-z0-9' '_')")
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "BLOCKED: '$tool' is not installed" > "$log"
    echo "| $N | $name | BLOCKED | $log |" >> "$REPORT"; return
  fi
  "$@" > "$log" 2>&1
  local code=$?
  if [ $code -eq 0 ]; then r=PASS; else r="FAIL (exit $code)"; fi
  echo "| $N | $name | $r | $log |" >> "$REPORT"
}
not_run() { N=$((N+1)); echo "| $N | $1 | NOT RUN | $2 |" >> "$REPORT"; }

step "flutter --version" flutter flutter --version
step "dart --version" dart dart --version
step "flutter doctor -v" flutter flutter doctor -v
step "flutter pub get" flutter flutter pub get
step "build_runner" dart dart run build_runner build --delete-conflicting-outputs
step "flutter gen-l10n" flutter flutter gen-l10n
step "dart format check" dart dart format --line-length=100 --set-exit-if-changed .
step "flutter analyze" flutter flutter analyze
step "flutter test (all unit and widget tests)" flutter flutter test --reporter expanded
step "flutter build apk --debug" flutter flutter build apk --debug
step "flutter build apk --release" flutter flutter build apk --release
step "Dependency audit (needs internet)" dart dart run tools/dependency_audit.dart

# Firestore rules on the emulator
if command -v node >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
  step "Firestore rules: npm install" npm bash -c "cd firebase && npm install"
  step "Firestore rules: emulator security tests" npm bash -c "cd firebase && npm test"
else
  not_run "Firestore rules: emulator security tests" "needs node, java and the Firebase emulator"
fi

# Real-device tests
if command -v flutter >/dev/null 2>&1 && flutter devices 2>/dev/null | grep -qi "android"; then
  step "Android device: keystore and encrypted database" flutter flutter test integration_test/keystore_database_test.dart
else
  not_run "Android device: keystore and encrypted database" "no Android device or emulator connected"
fi
if [ "$(uname -s)" = "Darwin" ] && command -v flutter >/dev/null 2>&1 && flutter devices 2>/dev/null | grep -qi "ios"; then
  step "iOS device: keychain and encrypted database" flutter flutter test integration_test/keystore_database_test.dart -d ios
else
  not_run "iOS device: keychain and encrypted database" "needs macOS with an iOS simulator or device"
fi
if [ -f pubspec.lock ]; then
  echo "| - | pubspec.lock present | PASS | pubspec.lock |" >> "$REPORT"
else
  echo "| - | pubspec.lock present | FAIL | missing |" >> "$REPORT"
fi
echo >> "$REPORT"
echo "APK outputs (if built): build/app/outputs/flutter-apk/" >> "$REPORT"
cat "$REPORT"
