/// TypeSync App Router
///
/// Defines all named routes and navigation helpers for the app.
/// Centralizes route management for easier maintenance.
library;

import 'package:flutter/material.dart';

import '../../features/home/screens/home_screen.dart';
import '../../features/editor/screens/editor_screen.dart';
import '../../features/editor/screens/split_editor_screen.dart';
import '../../features/auth/screens/email_link_sign_in_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/calendar/screens/calendar_screen.dart';
import '../../features/timetable/screens/timetable_screen.dart';
import '../../features/homework/screens/homework_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/subscription/screens/subscription_screen.dart';

/// App-wide route management
///
/// Contains all route definitions and navigation helper methods.
class AppRouter {
  // Private constructor to prevent instantiation
  AppRouter._();

  // ===========================================
  // ROUTE NAMES
  // ===========================================

  /// Home screen showing folders and files
  static const String home = '/';

  /// Note editor screen
  static const String editor = '/editor';

  /// Login screen
  static const String login = '/login';

  /// Split editor screen
  static const String splitEditor = '/split-editor';

  /// Registration screen
  static const String register = '/register';

  /// Email link completion screen
  static const String finishSignUp = '/finishSignUp';

  /// Settings screen
  static const String settings = '/settings';

  /// Calendar with test reminders
  static const String calendar = '/calendar';

  /// Timetable screen
  static const String timetable = '/timetable';

  /// Homework todo list
  static const String homework = '/homework';

  /// User profile screen
  static const String profile = '/profile';

  /// Subscription management screen
  static const String subscription = '/subscription';

  // ===========================================
  // ROUTE MAP
  // ===========================================

  /// Map of all named routes to their widget builders
  static Map<String, WidgetBuilder> get routes => {
        home: (_) => const HomeScreen(),
        editor: (_) => const EditorScreen(),
        login: (_) => const LoginScreen(),
        register: (_) => const RegisterScreen(),
        finishSignUp: (_) => const EmailLinkSignInScreen(),
        settings: (_) => const SettingsScreen(),
        calendar: (_) => const CalendarScreen(),
        timetable: (_) => const TimetableScreen(),
        homework: (_) => const HomeworkScreen(),
        profile: (_) => const ProfileScreen(),
        subscription: (_) => const SubscriptionScreen(),
      };

  // ===========================================
  // NAVIGATION HELPERS
  // ===========================================

  /// Navigate to a named route
  static Future<T?> navigateTo<T>(
    BuildContext context,
    String routeName, {
    Object? arguments,
  }) {
    return Navigator.pushNamed<T>(context, routeName, arguments: arguments);
  }

  /// Navigate to a route and remove all previous routes
  static Future<T?> navigateAndClearStack<T>(
    BuildContext context,
    String routeName,
  ) {
    return Navigator.pushNamedAndRemoveUntil<T>(
      context,
      routeName,
      (route) => false,
    );
  }

  /// Navigate to the editor with a specific note
  static Future<void> openEditor(
    BuildContext context, {
    String? noteId,
    String? folderId,
    String? searchQuery,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        settings: RouteSettings(
          name: editor,
          arguments: <String, dynamic>{
            'noteId': noteId,
            'folderId': folderId,
            'searchQuery': searchQuery,
          },
        ),
        builder: (_) => EditorScreen(
          noteId: noteId,
          folderId: folderId,
          searchQuery: searchQuery,
        ),
      ),
    );
  }

  /// Open two notes side by side in a single window.
  static Future<void> openSplitEditor(
    BuildContext context, {
    required String primaryNoteId,
    String? secondaryNoteId,
    String? initialSecondaryFolderId,
    bool replaceCurrent = false,
  }) {
    final route = MaterialPageRoute(
      settings: RouteSettings(
        name: splitEditor,
        arguments: <String, dynamic>{
          'primaryNoteId': primaryNoteId,
          'secondaryNoteId': secondaryNoteId,
          'secondaryFolderId': initialSecondaryFolderId,
        },
      ),
      builder: (_) => SplitEditorScreen(
        primaryNoteId: primaryNoteId,
        secondaryNoteId: secondaryNoteId,
        initialSecondaryFolderId: initialSecondaryFolderId,
      ),
    );
    if (replaceCurrent) {
      return Navigator.pushReplacement(
        context,
        route,
      );
    }
    return Navigator.push(
      context,
      route,
    );
  }

  /// Go back to the previous screen
  static void goBack<T>(BuildContext context, [T? result]) {
    Navigator.pop<T>(context, result);
  }

  /// Check if we can go back
  static bool canGoBack(BuildContext context) {
    return Navigator.canPop(context);
  }
}
