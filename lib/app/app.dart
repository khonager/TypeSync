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

/// Main app content widget that responds to theme changes
///
/// Separates the MaterialApp from providers to allow theme
/// changes to rebuild only the necessary widgets.
class TypeSyncAppContent extends StatelessWidget {
  const TypeSyncAppContent({super.key});

  @override
  Widget build(BuildContext context) {
    // Watch the theme service for changes
    final themeService = context.watch<ThemeService>();
    final authService = context.watch<AuthService>();

    return ServiceOrchestrator(
      child: MaterialApp(
        title: 'TypeSync',
        debugShowCheckedModeBanner: false,

        // Theme configuration based on user preference or system setting
        theme: AppTheme.lightTheme(themeService.accentColor),
        darkTheme: AppTheme.darkTheme(themeService.accentColor),
        themeMode: themeService.themeMode,

        // Named routes for navigation
        routes: AppRouter.routes,

        // Initial route depends on authentication status
        initialRoute:
            authService.isAuthenticated ? AppRouter.home : AppRouter.login,

        // Handle unknown routes gracefully - redirect to home
        onUnknownRoute: (settings) => MaterialPageRoute(
          builder: (context) => AppRouter.routes[AppRouter.home]!(context),
        ),

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
