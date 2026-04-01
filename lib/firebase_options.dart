/// Firebase Configuration Options
///
/// This file should be generated using the FlutterFire CLI.
/// Run: flutterfire configure
///
/// IMPORTANT: Replace these placeholder values with your actual
/// Firebase project configuration before running the app.
library;

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// To regenerate this file, run:
/// ```bash
/// flutterfire configure
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        return linux;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // ============================================
  // PLACEHOLDER VALUES - REPLACE WITH YOUR OWN
  // ============================================
  //
  // To get these values:
  // 1. Go to https://console.firebase.google.com
  // 2. Create a new project or select existing one
  // 3. Add Android and Web apps
  // 4. Download the configuration files or copy values
  // 5. Run: flutterfire configure (recommended)

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAXZ7gn9i6QGzpDJrbU7SG071F4bSNRnCs',
    appId: '1:461465199276:web:default',
    messagingSenderId: '461465199276',
    projectId: 'typesynced',
    authDomain: 'typesynced.firebaseapp.com',
    storageBucket: 'typesynced.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAXZ7gn9i6QGzpDJrbU7SG071F4bSNRnCs',
    appId: '1:461465199276:android:5c90b9333e07c88ebd3509',
    messagingSenderId: '461465199276',
    projectId: 'typesynced',
    storageBucket: 'typesynced.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAXZ7gn9i6QGzpDJrbU7SG071F4bSNRnCs',
    appId: '1:461465199276:ios:default',
    messagingSenderId: '461465199276',
    projectId: 'typesynced',
    storageBucket: 'typesynced.firebasestorage.app',
    iosBundleId: 'de.khonager.typesync',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAXZ7gn9i6QGzpDJrbU7SG071F4bSNRnCs',
    appId: '1:461465199276:macos:default',
    messagingSenderId: '461465199276',
    projectId: 'typesynced',
    storageBucket: 'typesynced.firebasestorage.app',
    iosBundleId: 'de.khonager.typesync',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAXZ7gn9i6QGzpDJrbU7SG071F4bSNRnCs',
    appId: '1:461465199276:windows:default',
    messagingSenderId: '461465199276',
    projectId: 'typesynced',
    storageBucket: 'typesynced.firebasestorage.app',
  );

  // Linux uses web configuration since Linux app isn't registered in Firebase
  // Desktop platforms can typically use web app configuration
  static const FirebaseOptions linux = FirebaseOptions(
    apiKey: 'AIzaSyAXZ7gn9i6QGzpDJrbU7SG071F4bSNRnCs',
    appId: '1:461465199276:web:default',
    messagingSenderId: '461465199276',
    projectId: 'typesynced',
    authDomain: 'typesynced.firebaseapp.com',
    storageBucket: 'typesynced.firebasestorage.app',
  );
}
