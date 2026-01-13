#!/usr/bin/env bash
# Setup script for writable Android SDK on NixOS

set -e

ANDROID_SDK_WRITABLE="$HOME/.android/sdk"
NIX_SDK="${ANDROID_HOME:-/nix/store/*-android-sdk-env/share/android-sdk}"

# Find Nix SDK if ANDROID_HOME is not set
if [ ! -d "$NIX_SDK" ] || [[ "$NIX_SDK" == *"*"* ]]; then
  # Try to find it in common Nix store locations
  NIX_SDK=$(find /nix/store -name "android-sdk" -type d 2>/dev/null | grep "android-sdk-env" | head -1)
  if [ -z "$NIX_SDK" ] || [ ! -d "$NIX_SDK" ]; then
    echo "Error: Could not find Android SDK in Nix store."
    echo "Please run this script from within the nix develop shell, or set ANDROID_HOME."
    exit 1
  fi
fi

echo "Setting up writable Android SDK at $ANDROID_SDK_WRITABLE"
echo "Copying from Nix SDK: $NIX_SDK"
echo ""

mkdir -p "$ANDROID_SDK_WRITABLE"

# Copy essential SDK components
echo "Copying platform-tools..."
[ -d "$NIX_SDK/platform-tools" ] && cp -r "$NIX_SDK/platform-tools" "$ANDROID_SDK_WRITABLE/" 2>/dev/null || true

echo "Copying build-tools..."
[ -d "$NIX_SDK/build-tools" ] && cp -r "$NIX_SDK/build-tools" "$ANDROID_SDK_WRITABLE/" 2>/dev/null || true

echo "Copying platforms..."
[ -d "$NIX_SDK/platforms" ] && cp -r "$NIX_SDK/platforms" "$ANDROID_SDK_WRITABLE/" 2>/dev/null || true

echo "Copying cmdline-tools..."
[ -d "$NIX_SDK/cmdline-tools" ] && cp -r "$NIX_SDK/cmdline-tools" "$ANDROID_SDK_WRITABLE/" 2>/dev/null || true

echo "Copying NDK..."
[ -d "$NIX_SDK/ndk" ] && cp -r "$NIX_SDK/ndk" "$ANDROID_SDK_WRITABLE/" 2>/dev/null || true

# Update local.properties
echo ""
echo "Updating android/local.properties..."
mkdir -p android
if [ -f android/local.properties ]; then
  # Backup original
  cp android/local.properties android/local.properties.bak
  # Update SDK path
  if grep -q "sdk.dir=" android/local.properties; then
    sed -i "s|sdk.dir=.*|sdk.dir=$ANDROID_SDK_WRITABLE|" android/local.properties
  else
    echo "sdk.dir=$ANDROID_SDK_WRITABLE" >> android/local.properties
  fi
else
  echo "sdk.dir=$ANDROID_SDK_WRITABLE" > android/local.properties
  if [ -n "$FLUTTER_SDK" ]; then
    echo "flutter.sdk=$FLUTTER_SDK" >> android/local.properties
  fi
fi

# Accept SDK licenses and install CMake
echo ""
echo "Accepting Android SDK licenses..."
export ANDROID_HOME="$ANDROID_SDK_WRITABLE"
export ANDROID_SDK_ROOT="$ANDROID_SDK_WRITABLE"
SDKMANAGER="$ANDROID_SDK_WRITABLE/cmdline-tools/latest/bin/sdkmanager"

if [ -f "$SDKMANAGER" ]; then
  # Accept all licenses
  yes | "$SDKMANAGER" --licenses > /dev/null 2>&1 || {
    echo "Warning: Could not accept licenses automatically. You may need to run:"
    echo "  $SDKMANAGER --licenses"
  }
  
  # Install CMake 3.22.1
  echo "Installing CMake 3.22.1..."
  "$SDKMANAGER" "cmake;3.22.1" || {
    echo "Warning: Could not install CMake 3.22.1. You may need to run:"
    echo "  $SDKMANAGER \"cmake;3.22.1\""
  }
else
  echo "Warning: sdkmanager not found at $SDKMANAGER"
  echo "You may need to install CMake manually using Android Studio SDK Manager"
fi

echo ""
echo "✓ Android SDK setup complete!"
echo "  SDK location: $ANDROID_SDK_WRITABLE"
echo "  You can now run: flutter build apk"

