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

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      android-nixpkgs,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            android_sdk.accept_license = true;
            allowUnfree = true;
          };
        };

        isLinux = pkgs.stdenv.isLinux;
        isDarwin = pkgs.stdenv.isDarwin;

        # Android SDK configuration - include cmake and all needed components
        androidSdk = android-nixpkgs.sdk.${system} (
          sdkPkgs:
          with sdkPkgs;
          [
            cmdline-tools-latest
            build-tools-36-0-0
            build-tools-35-0-0
            build-tools-34-0-0
            platform-tools

            # Platforms
            platforms-android-36
            platforms-android-35
            platforms-android-34
            platforms-android-33
            platforms-android-31

            # Sources
            sources-android-34

            # Native tools - include cmake!
            ndk-28-2-13676358
            cmake-3-22-1
          ]
          ++ pkgs.lib.optionals isLinux [
            emulator
          ]
        );

        # Linux-specific: Use FHS environment for binary compatibility
        linuxDevShell = pkgs.buildFHSEnv {
          name = "typesync-dev-env";
          targetPkgs =
            pkgs:
            (with pkgs; [
              androidSdk
              flutter
              dart
              jdk17

              # Common libraries needed by unpatched binaries (like aapt2)
              glibc
              zlib
              ncurses5
              stdenv.cc.cc.lib
              openssl
              expat

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

              # Utilities
              git
              curl
              unzip
              which
              google-chrome
              mesa-demos
              nodejs_22
              github-cli
              nspr
              nss

              # Python for Firebase Functions
              python313
              python313Packages.pip
            ]);

          runScript = "bash";

          profile = ''
            export ANDROID_HOME="${androidSdk}/share/android-sdk"
            export ANDROID_SDK_ROOT="${androidSdk}/share/android-sdk"
            export JAVA_HOME="${pkgs.jdk17}"
            export LD_LIBRARY_PATH="${
              pkgs.lib.makeLibraryPath [
                pkgs.vulkan-loader
                pkgs.libGL
                pkgs.xorg.libX11
                pkgs.xorg.libXcursor
                pkgs.xorg.libXi
                pkgs.xorg.libXrandr
                pkgs.gtk3
                pkgs.glib
                pkgs.libepoxy
              ]
            }"
            export CHROME_EXECUTABLE="${pkgs.google-chrome}/bin/google-chrome-stable"
            export GRADLE_USER_HOME="$HOME/.gradle"

            # Update android/local.properties to use the Nix SDK
            if [ -d "android" ]; then
              echo "sdk.dir=${androidSdk}/share/android-sdk" > android/local.properties
              echo "flutter.sdk=${pkgs.flutter}" >> android/local.properties
            fi

            echo "╔═══════════════════════════════════════════════════════════╗"
            echo "║           TypeSync Development Environment                ║"
            echo "╠═══════════════════════════════════════════════════════════╣"
            echo "║  Flutter: $(flutter --version 2>/dev/null | head -1 | cut -d' ' -f2 || echo 'loading...')                                       ║"
            echo "║  Android SDK: $ANDROID_HOME                               ║"
            echo "╠═══════════════════════════════════════════════════════════╣"
            echo "║  Commands:                                                ║"
            echo "║    flutter pub get         - Install dependencies        ║"
            echo "║    flutter run -d linux    - Run on Linux                ║"
            echo "║    flutter run -d android  - Run on Android              ║"
            echo "║    flutter build apk       - Build Android APK           ║"
            echo "║    flutter build linux     - Build Linux app             ║"
            echo "║    firebase deploy         - Deploy Firebase services    ║"
            echo "╚═══════════════════════════════════════════════════════════╝"

            # Set up Python venv for Firebase Functions if functions directory exists
            if [ -d "functions" ] && [ ! -d "functions/venv" ]; then
              echo "Setting up Python virtual environment for Firebase Functions..."
              cd functions
              python3.13 -m venv venv
              source venv/bin/activate
              pip install -r requirements.txt
              deactivate
              cd ..
              echo "✓ Python venv ready for Firebase Functions"
            fi
          '';
        };

        # macOS-specific: Standard devShell (no FHS needed, binaries are native)
        darwinDevShell = pkgs.mkShell {
          buildInputs = with pkgs; [
            androidSdk
            flutter
            dart
            jdk17
            cocoapods # Required for iOS development on macOS

            # Additional tools
            git
            curl
            unzip
            which
            nodejs_22

            # Python for Firebase Functions
            python313
            python313Packages.pip
          ];

          shellHook = ''
            export ANDROID_HOME="${androidSdk}/share/android-sdk"
            export ANDROID_SDK_ROOT="${androidSdk}/share/android-sdk"
            export JAVA_HOME="${pkgs.jdk17}"

            # macOS-specific: Use system Chrome or installed browser
            if [ -e "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]; then
              export CHROME_EXECUTABLE="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
            elif [ -e "/Applications/Chromium.app/Contents/MacOS/Chromium" ]; then
              export CHROME_EXECUTABLE="/Applications/Chromium.app/Contents/MacOS/Chromium"
            fi

            # Update android/local.properties
            if [ -d "android" ]; then
              echo "sdk.dir=${androidSdk}/share/android-sdk" > android/local.properties
              echo "flutter.sdk=${pkgs.flutter}" >> android/local.properties
            fi

            echo "TypeSync development environment ready!"
            echo "  ANDROID_HOME: $ANDROID_HOME"
            echo "  JAVA_HOME: $JAVA_HOME"
          '';
        };

      in
      {
        devShells.default = if isLinux then linuxDevShell.env else darwinDevShell;

        # Package for building the app
        packages.default = pkgs.flutter.buildFlutterApplication {
          pname = "typesync";
          version = "0.1.0";
          src = ./.;

          # Add any additional build configuration here
          targetFlutterPlatform = "linux";

          meta = {
            mainProgram = "typesync";
          };
        };
      }
    );
}
