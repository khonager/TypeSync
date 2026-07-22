/// TypeSync - A cross-platform note-taking application
///
/// Main entry point for the application. Initializes Firebase,
/// sets up providers, and configures the app theme.
// ignore_for_file: deprecated_member_use, experimental_member_use

library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show SpellCheckerServiceProvider;
import 'package:flutter_quill/flutter_quill_internal.dart'
    show ClipboardServiceProvider;
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firedart/firedart.dart' as firedart;

import 'app/app.dart';
import 'core/services/sync_service.dart';
import 'core/services/auth_service.dart';
import 'core/services/billing_service.dart';
import 'core/services/storage_service.dart';
import 'core/services/editor_color_palette_service.dart';
import 'core/services/theme_service.dart';
import 'core/services/attachment_preferences_service.dart';
import 'core/services/local_folder_sync_service.dart';
import 'core/services/diagnostics_service.dart';
import 'core/services/plain_text_quill_clipboard_service.dart';
import 'core/services/typesync_spellchecker_service.dart';
import 'core/utils/web_spellcheck_suppressor_stub.dart'
    if (dart.library.html) 'core/utils/web_spellcheck_suppressor_web.dart';
import 'core/providers/notes_provider.dart';
import 'core/providers/folders_provider.dart';
import 'core/providers/tags_provider.dart';
import 'core/providers/timetable_provider.dart';
import 'core/providers/user_provider.dart';
import 'core/providers/sync_provider.dart';
import 'core/providers/homework_provider.dart';
import 'core/providers/calendar_provider.dart';
import 'core/services/admin_entitlement_service.dart';
import 'core/services/hive_token_store.dart';
import 'core/widgets/desktop_window_frame.dart';
import 'firebase_options.dart';

/// Main entry point for the TypeSync application
void main() async {
  // Ensure Flutter bindings are initialized before any async operations
  WidgetsFlutterBinding.ensureInitialized();

  suppressBrowserSpellcheckForFlutterInputs();
  await TypeSyncSpellcheckerService.instance.initialize();
  SpellCheckerServiceProvider.setNewCheckerService(
    TypeSyncSpellcheckerService.instance,
  );

  await configureDesktopWindowFrame();

  // Initialize Hive for local storage (offline-first approach)
  await Hive.initFlutter();

  // Initialize Firebase for cloud sync and authentication
  try {
    await _initializeFirebase();
  } catch (e) {
    // Silently handle Firebase initialization errors
    // On Linux and some platforms, Firebase might not be fully supported
    // The app can run in offline mode without Firebase
    if (kDebugMode) {
      debugPrint(
        'Firebase initialization skipped/failed: ${e.toString().split(':').first}',
      );
    }
  }

  // Initialize Firedart for Linux support
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
    // Quill's default Linux clipboard bridge probes rich formats by spawning
    // xclip processes before falling back to plain text, which makes even tiny
    // paste operations feel sluggish in the editor.
    ClipboardServiceProvider.setInstance(PlainTextQuillClipboardService());

    try {
      // Initialize Auth with persistent TokenStore (or memory fallback if Hive fails)
      final tokenStore = await HiveTokenStore.create();

      // Ensure we don't initialize multiple times
      if (!firedart.FirebaseAuth.initialized) {
        firedart.FirebaseAuth.initialize(
          DefaultFirebaseOptions.linux.apiKey,
          tokenStore,
        );
      }

      // Initialize Firestore if Firebase core failed (common on Linux)
      firedart.Firestore.initialize(DefaultFirebaseOptions.linux.projectId);

      if (kDebugMode) {
        debugPrint('Firedart initialized for Linux (Auth)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Firedart initialization failed: $e');
      }
    }
  }

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

Future<void> _initializeFirebase() async {
  if (kIsWeb) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    return;
  }

  if (defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    try {
      // Prefer the native default app on Apple platforms when a bundled
      // GoogleService-Info.plist exists.
      await Firebase.initializeApp();
      return;
    } on FirebaseException catch (e) {
      final code = e.code.toLowerCase();
      final message = e.message?.toLowerCase() ?? '';
      final missingNativeApp = code == 'no-app' ||
          code == 'core/no-app' ||
          message.contains('no firebase app') ||
          message.contains('no app');

      if (!missingNativeApp) {
        rethrow;
      }

      // Fall back to Dart-provided options when the native plist is absent.
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      return;
    }
  }

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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

        // Per-note attachment display choices, shared across signed-in devices.
        ChangeNotifierProvider(create: (_) => AttachmentPreferencesService()),

        // Authentication service for user login/registration
        ChangeNotifierProvider(create: (_) => AuthService()),

        // Storage service for managing cloud storage limits and subscriptions
        ChangeNotifierProvider(create: (_) => StorageService()),

        // Editor color palettes for text and highlighter semantics
        ChangeNotifierProvider(create: (_) => EditorColorPaletteService()),

        // Billing service for RevenueCat entitlement checks and purchases
        ChangeNotifierProvider(create: (_) => BillingService()),

        // Server-authorized complimentary plan administration.
        ChangeNotifierProvider(create: (_) => AdminEntitlementService()),

        // Sync service for real-time file synchronization
        ChangeNotifierProvider(create: (_) => SyncService()),

        // Diagnostics log for user-visible errors and warnings
        ChangeNotifierProvider<DiagnosticsService>.value(
          value: DiagnosticsService.instance,
        ),

        // Local folder sync service for syncing with local folders
        ChangeNotifierProvider(create: (_) => LocalFolderSyncService()),

        // User provider for managing user profile and preferences
        ChangeNotifierProvider(create: (_) => UserProvider()),

        // Notes provider for managing note documents
        ChangeNotifierProvider(create: (_) => NotesProvider()),

        // Folders provider for managing folder structure
        ChangeNotifierProvider(create: (_) => FoldersProvider()),

        // Tags provider for managing note tags
        ChangeNotifierProvider(create: (_) => TagsProvider()),

        // Timetable provider for managing class schedule
        ChangeNotifierProvider(create: (_) => TimetableProvider()),

        // Homework provider for managing homework tasks
        ChangeNotifierProvider(create: (_) => HomeworkProvider()),

        // Calendar provider for managing calendar events
        ChangeNotifierProvider(create: (_) => CalendarProvider()),

        // Sync provider for tracking sync status across devices
        ChangeNotifierProvider(create: (_) => SyncProvider()),
      ],
      child: const TypeSyncAppContent(),
    );
  }
}
