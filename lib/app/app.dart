/// TypeSync App Configuration
///
/// Contains the main MaterialApp configuration including routing,
/// theming, and global app settings.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/services/theme_service.dart';
import '../core/theme/app_theme.dart';
import '../core/routes/app_router.dart';
import '../core/services/auth_service.dart';
import 'service_orchestrator.dart';

class TypeSyncAppContent extends StatelessWidget {
  const TypeSyncAppContent({super.key});

  @override
  Widget build(BuildContext context) {
    // Watch the theme service for changes
    final themeService = context.watch<ThemeService>();

    return ServiceOrchestrator(
      child: MaterialApp(
        title: 'TypeSync',
        debugShowCheckedModeBanner: false,

        // Theme configuration based on user preference or system setting
        theme: AppTheme.lightTheme(themeService.accentColor),
        darkTheme: AppTheme.darkTheme(themeService.accentColor),
        themeMode: themeService.themeMode,

        // Set AuthWrapper as the home
        home: const AuthWrapper(),

        // Provide routes, but exclude the root, login and home to let AuthWrapper handle them
        routes: {
          AppRouter.login: AppRouter.routes[AppRouter.login]!,
          AppRouter.editor: AppRouter.routes[AppRouter.editor]!,
          AppRouter.register: AppRouter.routes[AppRouter.register]!,
          AppRouter.settings: AppRouter.routes[AppRouter.settings]!,
          AppRouter.calendar: AppRouter.routes[AppRouter.calendar]!,
          AppRouter.timetable: AppRouter.routes[AppRouter.timetable]!,
          AppRouter.homework: AppRouter.routes[AppRouter.homework]!,
          AppRouter.profile: AppRouter.routes[AppRouter.profile]!,
          AppRouter.subscription: AppRouter.routes[AppRouter.subscription]!,
        },

        // Global error handling for navigation
        builder: (context, child) {
          // Apply global text scaling limits for accessibility
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(
                MediaQuery.of(context).textScaler.scale(1.0).clamp(0.8, 1.4),
              ),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}

/// A wrapper widget that handles authentication state transitions gracefully.
/// It displays a loading indicator while AuthService initializes, and then
/// switches between HomeScreen and LoginScreen based on authentication status.
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();

    if (!authService.isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (authService.isAuthenticated) {
      // Defer to the same widget builder defined in AppRouter for consistency
      return AppRouter.routes[AppRouter.home]!(context);
    } else {
      return AppRouter.routes[AppRouter.login]!(context);
    }
  }
}
