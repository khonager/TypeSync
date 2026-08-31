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
import '../core/services/navigation_state_service.dart';
import '../core/widgets/desktop_window_frame.dart';
import '../core/widgets/startup_loading_screen.dart';
import '../core/providers/notes_provider.dart';
import '../features/home/screens/home_screen.dart';
import '../features/home/widgets/home_bottom_bar.dart';
import 'home_widget_sync_coordinator.dart';
import 'service_orchestrator.dart';

class TypeSyncAppContent extends StatelessWidget {
  const TypeSyncAppContent({super.key});

  @override
  Widget build(BuildContext context) {
    // Watch the theme service for changes
    final themeService = context.watch<ThemeService>();

    return ServiceOrchestrator(
      child: HomeWidgetSyncCoordinator(
        child: MaterialApp(
          title: 'TypeSync',
          debugShowCheckedModeBanner: false,

          // TypeSync is intentionally dark-only.
          theme: AppTheme.darkTheme(themeService.accentColor),
          darkTheme: AppTheme.darkTheme(themeService.accentColor),
          themeMode: ThemeMode.dark,

          // Set AuthWrapper as the home
          home: const AuthWrapper(),

          navigatorObservers: [NavigationStateObserver()],

          // Provide routes, but exclude the root, login and home to let AuthWrapper handle them
          routes: {
            AppRouter.login: AppRouter.routes[AppRouter.login]!,
            AppRouter.editor: AppRouter.routes[AppRouter.editor]!,
            AppRouter.register: AppRouter.routes[AppRouter.register]!,
            AppRouter.finishSignUp: AppRouter.routes[AppRouter.finishSignUp]!,
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
            Widget content = MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(
                  MediaQuery.of(context).textScaler.scale(1.0).clamp(0.8, 1.4),
                ),
              ),
              child: child ?? const SizedBox.shrink(),
            );

            content = _BackGestureFocusDismissScope(child: content);

            if (supportsCustomDesktopWindowFrame) {
              content = DesktopWindowFrameShell(child: content);
            }

            return content;
          },
        ),
      ),
    );
  }
}

class _BackGestureFocusDismissScope extends StatefulWidget {
  const _BackGestureFocusDismissScope({
    required this.child,
  });

  final Widget child;

  @override
  State<_BackGestureFocusDismissScope> createState() =>
      _BackGestureFocusDismissScopeState();
}

class _BackGestureFocusDismissScopeState
    extends State<_BackGestureFocusDismissScope> {
  bool _hasFocusedEditableText = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_handleFocusChange);
    _hasFocusedEditableText = _isEditableTextFocused();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_handleFocusChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasFocusedEditableText,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !_hasFocusedEditableText) return;
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: widget.child,
    );
  }

  void _handleFocusChange() {
    final hasFocusedEditableText = _isEditableTextFocused();
    if (hasFocusedEditableText == _hasFocusedEditableText) return;
    setState(() {
      _hasFocusedEditableText = hasFocusedEditableText;
    });
  }

  bool _isEditableTextFocused() {
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext == null) return false;
    final focusedWidget = focusedContext.widget;
    return focusedWidget is EditableText ||
        focusedContext.findAncestorWidgetOfExactType<EditableText>() != null;
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
      return const StartupLoadingScreen();
    }

    if (authService.isAuthenticated) {
      final workspaceId = authService.storageUserId;
      if (workspaceId == null) return const StartupLoadingScreen();
      return _AuthenticatedAppShell(
        key: ValueKey(workspaceId),
        workspaceId: workspaceId,
      );
    } else {
      return AppRouter.routes[AppRouter.login]!(context);
    }
  }
}

class _AuthenticatedAppShell extends StatefulWidget {
  const _AuthenticatedAppShell({
    required this.workspaceId,
    super.key,
  });

  final String workspaceId;

  @override
  State<_AuthenticatedAppShell> createState() => _AuthenticatedAppShellState();
}

class _AuthenticatedAppShellState extends State<_AuthenticatedAppShell> {
  late final Future<NavigationSnapshot> _snapshotFuture;
  NavigationSnapshot? _snapshot;
  bool _restorationFinished = false;
  bool _restorationStarted = false;

  @override
  void initState() {
    super.initState();
    _snapshotFuture =
        NavigationStateService.instance.activate(widget.workspaceId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<NavigationSnapshot>(
      future: _snapshotFuture,
      builder: (context, state) {
        if (!state.hasData) return const StartupLoadingScreen();
        _snapshot ??= state.data!;
        final snapshot = _snapshot!;
        final initialTab = snapshot.homeTab == 'profile'
            ? HomeBottomBarTab.profile
            : HomeBottomBarTab.files;

        return Stack(
          fit: StackFit.expand,
          children: [
            HomeScreen(
              initialFolderId: snapshot.homeFolderId,
              initialTab: initialTab,
              onWorkspaceInitialized: _restoreDestination,
            ),
            if (!_restorationFinished) const StartupLoadingScreen(),
          ],
        );
      },
    );
  }

  void _restoreDestination() {
    if (_restorationStarted || !mounted) return;
    _restorationStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final snapshot = _snapshot ?? const NavigationSnapshot();
      final notes = context.read<NotesProvider>();

      setState(() => _restorationFinished = true);

      if (snapshot.routeName == AppRouter.editor &&
          snapshot.noteId != null &&
          notes.getNoteById(snapshot.noteId!) != null) {
        AppRouter.openEditor(
          context,
          noteId: snapshot.noteId,
          folderId: snapshot.folderId,
        );
        return;
      }

      if (snapshot.routeName == AppRouter.splitEditor &&
          snapshot.primaryNoteId != null &&
          notes.getNoteById(snapshot.primaryNoteId!) != null) {
        AppRouter.openSplitEditor(
          context,
          primaryNoteId: snapshot.primaryNoteId!,
          secondaryNoteId: snapshot.secondaryNoteId,
          initialSecondaryFolderId: snapshot.secondaryFolderId,
        );
        return;
      }

      const restorableNamedRoutes = <String>{
        AppRouter.settings,
        AppRouter.calendar,
        AppRouter.timetable,
        AppRouter.homework,
        AppRouter.profile,
        AppRouter.subscription,
      };
      if (restorableNamedRoutes.contains(snapshot.routeName)) {
        AppRouter.navigateTo(context, snapshot.routeName);
        return;
      }

      // Missing/deleted note IDs and auth-only routes safely fall back home.
      NavigationStateService.instance.recordHomeState(
        folderId: snapshot.homeFolderId,
        tab: snapshot.homeTab,
      );
    });
  }
}
