#!/usr/bin/env bash

set -euo pipefail

readonly APP_ID="de.khonager.typesync"
readonly ACTIVITY="$APP_ID/.MainActivity"
readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly FIREBASE_LOG="$(mktemp)"
FIREBASE_PID=""

cleanup() {
  if [[ -n "$FIREBASE_PID" ]]; then
    kill "$FIREBASE_PID" 2>/dev/null || true
    wait "$FIREBASE_PID" 2>/dev/null || true
  fi
  rm -f "$FIREBASE_LOG"
}
trap cleanup EXIT

for command_name in adb curl firebase flutter; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
done

adb wait-for-device
if [[ "$(adb shell getprop ro.kernel.qemu | tr -d '\r')" != "1" ]]; then
  echo "Refusing to clear TypeSync data: connect an Android emulator, not a physical device." >&2
  exit 1
fi

cd "$REPO_ROOT"

echo "Building the dedicated Auth persistence probe..."
flutter build apk \
  --debug \
  --target=integration_test/auth_persistence_probe.dart
bash scripts/verify_android_firebase_auth_version.sh debug

echo "Starting the local Firebase Auth emulator..."
firebase emulators:start \
  --only auth \
  --project typesynced \
  --config firebase.json \
  >"$FIREBASE_LOG" 2>&1 &
FIREBASE_PID=$!

auth_emulator_ready=false
for _ in $(seq 1 60); do
  if curl --silent --fail "http://127.0.0.1:9099/" >/dev/null 2>&1; then
    auth_emulator_ready=true
    break
  fi
  sleep 1
done

if [[ "$auth_emulator_ready" != "true" ]]; then
  echo "Firebase Auth emulator did not start." >&2
  tail -80 "$FIREBASE_LOG" >&2
  exit 1
fi

echo "Installing the probe and starting from clean emulator app data..."
adb install -r build/app/outputs/flutter-apk/app-debug.apk >/dev/null
adb shell pm clear "$APP_ID" >/dev/null

wait_for_probe_log() {
  local expected="$1"
  for _ in $(seq 1 60); do
    local logs
    logs="$(adb logcat -d -s flutter:I '*:S')"
    if grep -Fq "AUTH_PERSISTENCE_PROBE:FAIL" <<<"$logs"; then
      echo "$logs" >&2
      return 1
    fi
    if grep -Fq "AUTH_PERSISTENCE_PROBE:$expected" <<<"$logs"; then
      return 0
    fi
    sleep 1
  done

  adb logcat -d -s flutter:I '*:S' >&2
  return 1
}

adb logcat -c
adb shell am start -W -n "$ACTIVITY" >/dev/null
if ! wait_for_probe_log "READY"; then
  echo "The first probe launch did not sign in." >&2
  exit 1
fi

echo "Force-stopping the Android process..."
adb shell am force-stop "$APP_ID"

adb logcat -c
adb shell am start -W -n "$ACTIVITY" >/dev/null
if ! wait_for_probe_log "PASS"; then
  echo "Firebase Auth did not restore the same user after the cold restart." >&2
  exit 1
fi

echo "PASS: Firebase Auth restored the same user after a force-stop and cold relaunch."
