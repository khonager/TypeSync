/// Theme Service
///
/// Manages app-wide theming including dark mode, accent colors,
/// and system theme synchronization.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sync_service.dart';
import '../utils/color_value_compat.dart';

enum HomeUpcomingVisibilityMode {
  always,
  onlyWithItems,
  never,
}

/// The fixed order used by the swipeable home-page widget carousel.
enum HomePageWidgetType {
  upcoming,
  recentlyOpened,
  frequentlyOpened,
  largestNotes,
}

/// Service for managing app theme and appearance
///
/// Supports light mode, dark mode, and system-sync mode.
/// Persists user preferences to SharedPreferences.
class ThemeService extends ChangeNotifier {
  // Theme state
  ThemeMode _themeMode = ThemeMode.dark;
  Color _accentColor = const Color(0xFF64D2FF);
  HomeUpcomingVisibilityMode _homeUpcomingVisibilityMode =
      HomeUpcomingVisibilityMode.onlyWithItems;
  List<HomePageWidgetType> _selectedHomePageWidgets =
      List<HomePageWidgetType>.from(HomePageWidgetType.values);
  HomePageWidgetType _lastViewedHomePageWidget = HomePageWidgetType.upcoming;

  // Sync service reference (set by parent)
  SyncService? _syncService;

  void setSyncService(SyncService? service) {
    _syncService = service;
  }

  // Keys for SharedPreferences
  static const String _themeModeKey = 'theme_mode';
  static const String _accentColorKey = 'accent_color';
  static const String _homeUpcomingVisibilityModeKey =
      'home_upcoming_visibility_mode';
  static const String _selectedHomePageWidgetsKey =
      'selected_home_page_widgets';
  static const String _lastViewedHomePageWidgetKey =
      'last_viewed_home_page_widget';

  // Predefined accent colors
  static const List<Color> accentColors = [
    Color(0xFF64D2FF), // Cyan (default)
    Color(0xFF007AFF), // Blue
    Color(0xFF5856D6), // Purple
    Color(0xFFFF2D55), // Pink
    Color(0xFFFF9500), // Orange
    Color(0xFFFFCC00), // Yellow
    Color(0xFF34C759), // Green
    Color(0xFFAF52DE), // Violet
  ];

  // ===========================================
  // GETTERS
  // ===========================================

  ThemeMode get themeMode => ThemeMode.dark;
  Color get accentColor => _accentColor;
  bool get isDarkMode => true;
  bool get syncWithSystem => false;
  HomeUpcomingVisibilityMode get homeUpcomingVisibilityMode =>
      _homeUpcomingVisibilityMode;
  List<HomePageWidgetType> get selectedHomePageWidgets =>
      List<HomePageWidgetType>.unmodifiable(_selectedHomePageWidgets);
  HomePageWidgetType get lastViewedHomePageWidget => _lastViewedHomePageWidget;

  /// Get the actual brightness based on current settings
  Brightness get currentBrightness => Brightness.dark;

  // ===========================================
  // CONSTRUCTOR
  // ===========================================

  ThemeService() {
    _loadPreferences();
  }

  // ===========================================
  // PUBLIC METHODS
  // ===========================================

  /// Toggle between light and dark mode
  void toggleTheme() {
    _enforceDarkMode();
  }

  /// Set theme mode directly
  void setThemeMode(ThemeMode mode) {
    _enforceDarkMode();
  }

  /// Enable system theme sync (hold to activate)
  void enableSystemSync() {
    _enforceDarkMode();
  }

  /// Disable system theme sync
  void disableSystemSync() {
    _enforceDarkMode();
  }

  /// Toggle system sync
  void toggleSystemSync() {
    _enforceDarkMode();
  }

  /// Set accent color
  void setAccentColor(Color color) {
    _accentColor = color;
    _savePreferences();
    notifyListeners();
  }

  void setHomeUpcomingVisibilityMode(HomeUpcomingVisibilityMode mode) {
    if (_homeUpcomingVisibilityMode == mode) return;
    _homeUpcomingVisibilityMode = mode;
    _savePreferences();
    notifyListeners();
  }

  void setHomePageWidgetSelected(HomePageWidgetType widget, bool selected) {
    final updated = _selectedHomePageWidgets.toSet();
    if (selected) {
      updated.add(widget);
    } else {
      updated.remove(widget);
    }
    // A carousel without pages is not useful, and keeping one selected makes
    // it possible to recover from a mistaken tap without another screen.
    if (updated.isEmpty) return;

    _selectedHomePageWidgets = HomePageWidgetType.values
        .where(updated.contains)
        .toList(growable: false);
    if (!_selectedHomePageWidgets.contains(_lastViewedHomePageWidget)) {
      _lastViewedHomePageWidget = _selectedHomePageWidgets.first;
    }
    _savePreferences(syncToCloud: false);
    notifyListeners();
  }

  void setLastViewedHomePageWidget(HomePageWidgetType widget) {
    if (_lastViewedHomePageWidget == widget) return;
    _lastViewedHomePageWidget = widget;
    _savePreferences(syncToCloud: false);
  }

  /// Get contrasting text color (black or white) based on background
  static Color getContrastingTextColor(Color backgroundColor) {
    // Calculate relative luminance
    final double luminance = backgroundColor.computeLuminance();

    // Use white text on dark backgrounds, black on light
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  /// Adjust text color for dark/light mode automatically
  Color getAdaptiveTextColor(Color baseColor) {
    if (currentBrightness == Brightness.dark) {
      // In dark mode, make dark colors lighter
      if (baseColor.computeLuminance() < 0.3) {
        return Colors.white;
      }
    } else {
      // In light mode, make light colors darker
      if (baseColor.computeLuminance() > 0.7) {
        return Colors.black;
      }
    }
    return baseColor;
  }

  // ===========================================
  // PRIVATE METHODS
  // ===========================================

  /// Handle settings update from cloud
  void handleCloudSettings(Map<String, dynamic> settings) {
    bool changed = false;

    if (settings.containsKey('accentColor')) {
      final colorValue = settings['accentColor'] as int;
      final newColor = Color(colorValue);
      if (_accentColor != newColor) {
        _accentColor = newColor;
        changed = true;
      }
    }

    if (changed) {
      _themeMode = ThemeMode.dark;
      _savePreferences(syncToCloud: false);
      notifyListeners();
    }
  }

  /// Load preferences from SharedPreferences
  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load theme mode
      final themeModeIndex = prefs.getInt(_themeModeKey);
      if (themeModeIndex != null && themeModeIndex < ThemeMode.values.length) {
        _themeMode = ThemeMode.dark;
      }

      // Load accent color
      final accentColorValue = prefs.getInt(_accentColorKey);
      if (accentColorValue != null) {
        _accentColor = Color(accentColorValue);
      }

      // Load home upcoming visibility mode.
      final visibilityIndex = prefs.getInt(_homeUpcomingVisibilityModeKey);
      if (visibilityIndex != null &&
          visibilityIndex >= 0 &&
          visibilityIndex < HomeUpcomingVisibilityMode.values.length) {
        _homeUpcomingVisibilityMode =
            HomeUpcomingVisibilityMode.values[visibilityIndex];
      }

      final selectedWidgetIndexes = prefs.getStringList(
        _selectedHomePageWidgetsKey,
      );
      if (selectedWidgetIndexes != null) {
        final selected = selectedWidgetIndexes
            .map(int.tryParse)
            .whereType<int>()
            .where(
              (index) => index >= 0 && index < HomePageWidgetType.values.length,
            )
            .map((index) => HomePageWidgetType.values[index])
            .toSet();
        if (selected.isNotEmpty) {
          _selectedHomePageWidgets = HomePageWidgetType.values
              .where(selected.contains)
              .toList(growable: false);
        }
      }
      final lastViewedIndex = prefs.getInt(_lastViewedHomePageWidgetKey);
      if (lastViewedIndex != null &&
          lastViewedIndex >= 0 &&
          lastViewedIndex < HomePageWidgetType.values.length) {
        _lastViewedHomePageWidget = HomePageWidgetType.values[lastViewedIndex];
      }
      if (!_selectedHomePageWidgets.contains(_lastViewedHomePageWidget)) {
        _lastViewedHomePageWidget = _selectedHomePageWidgets.first;
      }

      _themeMode = ThemeMode.dark;
      notifyListeners();
    } catch (e) {
      // Use defaults if loading fails
      debugPrint('Failed to load theme preferences: $e');
    }
  }

  /// Save preferences to SharedPreferences
  Future<void> _savePreferences({bool syncToCloud = true}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accentColorValue = colorToArgb32(_accentColor);

      _themeMode = ThemeMode.dark;

      await prefs.setInt(_themeModeKey, ThemeMode.dark.index);
      await prefs.setInt(_accentColorKey, accentColorValue);
      await prefs.setInt(
        _homeUpcomingVisibilityModeKey,
        _homeUpcomingVisibilityMode.index,
      );
      await prefs.setStringList(
        _selectedHomePageWidgetsKey,
        _selectedHomePageWidgets
            .map((widget) => widget.index.toString())
            .toList(),
      );
      await prefs.setInt(
        _lastViewedHomePageWidgetKey,
        _lastViewedHomePageWidget.index,
      );

      if (syncToCloud && _syncService != null) {
        _syncService!.syncSettings({
          'themeMode': ThemeMode.dark.index,
          'accentColor': accentColorValue,
          'syncWithSystem': false,
        });
      }
    } catch (e) {
      debugPrint('Failed to save theme preferences: $e');
    }
  }

  void _enforceDarkMode() {
    if (_themeMode == ThemeMode.dark) {
      return;
    }

    _themeMode = ThemeMode.dark;
    _savePreferences();
    notifyListeners();
  }
}
