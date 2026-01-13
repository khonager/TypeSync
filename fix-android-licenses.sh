#!/usr/bin/env bash
# Quick fix to accept Android SDK licenses and install CMake

set -e

ANDROID_SDK_WRITABLE="$HOME/.android/sdk"
export ANDROID_HOME="$ANDROID_SDK_WRITABLE"
export ANDROID_SDK_ROOT="$ANDROID_SDK_WRITABLE"

SDKMANAGER="$ANDROID_SDK_WRITABLE/cmdline-tools/latest/bin/sdkmanager"

if [ ! -f "$SDKMANAGER" ]; then
  echo "Error: sdkmanager not found at $SDKMANAGER"
  echo "Please run ./setup-android-sdk.sh first to set up the SDK."
  exit 1
fi

echo "Accepting Android SDK licenses..."
yes | "$SDKMANAGER" --licenses

echo ""
echo "Installing CMake 3.22.1..."
"$SDKMANAGER" "cmake;3.22.1"

echo ""
echo "✓ Licenses accepted and CMake installed!"
echo "You can now run: flutter build apk"

