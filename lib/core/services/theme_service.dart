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
