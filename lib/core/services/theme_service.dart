/// Theme Service
/// 
/// Manages app-wide theming including dark mode, accent colors,
/// and system theme synchronization.

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing app theme and appearance
/// 
/// Supports light mode, dark mode, and system-sync mode.
/// Persists user preferences to SharedPreferences.
class ThemeService extends ChangeNotifier {
  // Theme state
  ThemeMode _themeMode = ThemeMode.dark;
  Color _accentColor = const Color(0xFF64D2FF);
  bool _syncWithSystem = false;
  
  // Keys for SharedPreferences
  static const String _themeModeKey = 'theme_mode';
  static const String _accentColorKey = 'accent_color';
  static const String _syncWithSystemKey = 'sync_with_system';
  
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
  
  ThemeMode get themeMode => _syncWithSystem ? ThemeMode.system : _themeMode;
  Color get accentColor => _accentColor;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  bool get syncWithSystem => _syncWithSystem;
  
  /// Get the actual brightness based on current settings
  Brightness get currentBrightness {
    if (_syncWithSystem) {
      final brightness = SchedulerBinding.instance.platformDispatcher.platformBrightness;
      return brightness;
    }
    return _themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light;
  }

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
    _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    _syncWithSystem = false;
    _savePreferences();
    notifyListeners();
  }

  /// Set theme mode directly
  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _syncWithSystem = false;
    _savePreferences();
    notifyListeners();
  }

  /// Enable system theme sync (hold to activate)
  void enableSystemSync() {
    _syncWithSystem = true;
    _savePreferences();
    notifyListeners();
  }

  /// Disable system theme sync
  void disableSystemSync() {
    _syncWithSystem = false;
    _savePreferences();
    notifyListeners();
  }

  /// Toggle system sync
  void toggleSystemSync() {
    _syncWithSystem = !_syncWithSystem;
    _savePreferences();
    notifyListeners();
  }

  /// Set accent color
  void setAccentColor(Color color) {
    _accentColor = color;
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
  
  /// Load preferences from SharedPreferences
  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load theme mode
      final themeModeIndex = prefs.getInt(_themeModeKey);
      if (themeModeIndex != null && themeModeIndex < ThemeMode.values.length) {
        _themeMode = ThemeMode.values[themeModeIndex];
      }
      
      // Load accent color
      final accentColorValue = prefs.getInt(_accentColorKey);
      if (accentColorValue != null) {
        _accentColor = Color(accentColorValue);
      }
      
      // Load system sync preference
      _syncWithSystem = prefs.getBool(_syncWithSystemKey) ?? false;
      
      notifyListeners();
    } catch (e) {
      // Use defaults if loading fails
      debugPrint('Failed to load theme preferences: $e');
    }
  }

  /// Save preferences to SharedPreferences
  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.setInt(_themeModeKey, _themeMode.index);
      await prefs.setInt(_accentColorKey, _accentColor.value);
      await prefs.setBool(_syncWithSystemKey, _syncWithSystem);
    } catch (e) {
      debugPrint('Failed to save theme preferences: $e');
    }
  }
}

