{
  description = "TypeSync - A cross-platform note-taking app with cloud sync";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    android-nixpkgs = {
      url = "github:tadfisher/android-nixpkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, android-nixpkgs }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };

        # Android SDK configuration
        androidSdk = android-nixpkgs.sdk.${system} (sdkPkgs: with sdkPkgs; [
          build-tools-34-0-0
          cmdline-tools-latest
          emulator
          platform-tools
          platforms-android-34
          sources-android-34
          ndk-26-1-10909125
        ]);

        # Build inputs for Flutter development
        buildInputs = with pkgs; [
          # Flutter and Dart
          flutter
          dart

          # Android development
          androidSdk
          jdk17

          # Linux desktop development dependencies
          gtk3
          glib
          pcre2
          libselinux
          libsepol
          util-linux
          libepoxy
          xorg.libX11
          xorg.libXcursor
          xorg.libXi
          xorg.libXrandr
          libGL
          pkg-config
          cmake
          ninja
          clang

          # Additional tools
          git
          curl
          unzip
          which
          
          # Firebase CLI (for deployment)
          firebase-tools
          nodePackages.npm
        ];

        # Native build inputs
        nativeBuildInputs = with pkgs; [
          pkg-config
        ];

        # Library path for runtime
        libPath = pkgs.lib.makeLibraryPath (with pkgs; [
          libGL
          xorg.libX11
          xorg.libXcursor
          xorg.libXi
          xorg.libXrandr
          gtk3
          glib
          libepoxy
        ]);

      in
      {
        devShells.default = pkgs.mkShell {
          inherit buildInputs nativeBuildInputs;

          # Environment variables for Flutter development
          shellHook = ''
            # Set up Android SDK
            export ANDROID_HOME="${androidSdk}/share/android-sdk"
            export ANDROID_SDK_ROOT="$ANDROID_HOME"
            export PATH="$ANDROID_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"

            # Set Java home
            export JAVA_HOME="${pkgs.jdk17}"

            # Set up library path for Linux desktop builds
            export LD_LIBRARY_PATH="${libPath}:$LD_LIBRARY_PATH"

            # Flutter configuration
            export CHROME_EXECUTABLE="${pkgs.chromium}/bin/chromium"

            # Gradle configuration
            export GRADLE_USER_HOME="$HOME/.gradle"

            # Print welcome message
            echo "╔═══════════════════════════════════════════════════════════╗"
            echo "║           TypeSync Development Environment                ║"
            echo "╠═══════════════════════════════════════════════════════════╣"
            echo "║  Flutter: $(flutter --version | head -1 | cut -d' ' -f2)                                       ║"
            echo "║  Dart: $(dart --version 2>&1 | cut -d' ' -f4)                                          ║"
            echo "║  Android SDK: $ANDROID_HOME                               ║"
            echo "╠═══════════════════════════════════════════════════════════╣"
            echo "║  Commands:                                                ║"
            echo "║    flutter pub get    - Install dependencies             ║"
            echo "║    flutter run -d linux    - Run on Linux                ║"
            echo "║    flutter run -d android  - Run on Android              ║"
            echo "║    flutter build apk       - Build Android APK           ║"
            echo "║    flutter build linux     - Build Linux app             ║"
            echo "╚═══════════════════════════════════════════════════════════╝"
            
            # Run flutter doctor to check setup
            echo ""
            echo "Running flutter doctor..."
            flutter doctor
          '';
        };

        # Package for building the app
        packages.default = pkgs.flutter.buildFlutterApplication {
          pname = "typesync";
          version = "0.1.0";
          src = ./.;
          
          # Add any additional build configuration here
          targetFlutterPlatform = "linux";
        };
      }
    );
}
