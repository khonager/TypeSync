/// TypeSync - A cross-platform note-taking application
/// 
/// Main entry point for the application. Initializes Firebase,
/// sets up providers, and configures the app theme.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';

import 'app/app.dart';
import 'core/services/sync_service.dart';
import 'core/services/auth_service.dart';
import 'core/services/storage_service.dart';
import 'core/services/theme_service.dart';
import 'core/providers/notes_provider.dart';
import 'core/providers/folders_provider.dart';
import 'core/providers/user_provider.dart';
import 'core/providers/sync_provider.dart';
import 'firebase_options.dart';

/// Main entry point for the TypeSync application
void main() async {
  // Ensure Flutter bindings are initialized before any async operations
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive for local storage (offline-first approach)
  await Hive.initFlutter();

  // Initialize Firebase for cloud sync and authentication
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Set preferred orientations for mobile devices
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Run the app with multi-provider setup for state management
  runApp(const TypeSyncApp());
}

/// Root widget that sets up all providers for the application
/// 
/// Uses MultiProvider to inject services and state management
/// throughout the widget tree.
class TypeSyncApp extends StatelessWidget {
  const TypeSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Theme service for managing app appearance (dark mode, colors, etc.)
        ChangeNotifierProvider(create: (_) => ThemeService()),
        
        // Authentication service for user login/registration
        ChangeNotifierProvider(create: (_) => AuthService()),
        
        // Storage service for managing cloud storage limits and subscriptions
        ChangeNotifierProvider(create: (_) => StorageService()),
        
        // Sync service for real-time file synchronization
        ChangeNotifierProvider(create: (_) => SyncService()),
        
        // User provider for managing user profile and preferences
        ChangeNotifierProvider(create: (_) => UserProvider()),
        
        // Notes provider for managing note documents
        ChangeNotifierProvider(create: (_) => NotesProvider()),
        
        // Folders provider for managing folder structure
        ChangeNotifierProvider(create: (_) => FoldersProvider()),
        
        // Sync provider for tracking sync status across devices
        ChangeNotifierProvider(create: (_) => SyncProvider()),
      ],
      child: const TypeSyncAppContent(),
    );
  }
}
