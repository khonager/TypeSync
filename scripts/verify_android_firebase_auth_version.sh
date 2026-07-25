#!/usr/bin/env bash

set -euo pipefail

readonly EXPECTED_VERSION="24.2.0"
readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BUILD_VARIANT="${1:-release}"
readonly REPORT_PATH="$REPO_ROOT/build/app/outputs/firebase-auth-version/${BUILD_VARIANT}.txt"

if [[ ! -f "$REPORT_PATH" ]]; then
  echo "Missing Android $BUILD_VARIANT Firebase Auth version report: $REPORT_PATH" >&2
  echo "Build the $BUILD_VARIANT APK before running this verification." >&2
  exit 1
fi

resolved_version="$(tr -d '[:space:]' < "$REPORT_PATH")"
if [[ "$resolved_version" != "$EXPECTED_VERSION" ]]; then
  echo "Expected firebase-auth $EXPECTED_VERSION, but Gradle resolved ${resolved_version:-nothing}." >&2
  exit 1
fi

echo "Verified Android $BUILD_VARIANT APK uses firebase-auth $EXPECTED_VERSION."
