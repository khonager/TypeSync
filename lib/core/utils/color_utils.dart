/// Color Utilities
///
/// Provides a unified color palette system that works well
/// in both dark and light modes, with proper contrast ratios.
library;

import 'dart:convert';

import 'package:flutter/material.dart';

/// Unified color palette for the app
///
/// All colors are designed to work well together and provide
/// good contrast in both dark and light modes.
class AppColorPalette {
  AppColorPalette._();

  // ===========================================
  // NOTE BACKGROUND COLORS
  // ===========================================
  // These are subtle, muted colors that work as backgrounds
  // and provide good contrast with text in both themes

  static const List<ColorOption> noteBackgroundColors = [
    ColorOption(
      id: 'coral',
      name: 'Coral',
      color: Color(0xFFFF6B6B),
      hex: '#FF6B6B',
      isLight: false,
    ),
    ColorOption(
      id: 'peach',
      name: 'Peach',
      color: Color(0xFFFFB88C),
      hex: '#FFB88C',
      isLight: true,
    ),
    ColorOption(
      id: 'amber',
      name: 'Amber',
      color: Color(0xFFFFD93D),
      hex: '#FFD93D',
      isLight: true,
    ),
    ColorOption(
      id: 'lime',
      name: 'Lime',
      color: Color(0xFF6BCB77),
      hex: '#6BCB77',
      isLight: false,
    ),
    ColorOption(
      id: 'mint',
      name: 'Mint',
      color: Color(0xFF4ECDC4),
      hex: '#4ECDC4',
      isLight: false,
    ),
    ColorOption(
      id: 'sky',
      name: 'Sky',
      color: Color(0xFF74C0FC),
      hex: '#74C0FC',
      isLight: false,
    ),
    ColorOption(
      id: 'lavender',
      name: 'Lavender',
      color: Color(0xFFA29BFE),
      hex: '#A29BFE',
      isLight: false,
    ),
    ColorOption(
      id: 'rose',
      name: 'Rose',
      color: Color(0xFFFF8CC8),
      hex: '#FF8CC8',
      isLight: false,
    ),
    ColorOption(
      id: 'slate',
      name: 'Slate',
      color: Color(0xFF95A5A6),
      hex: '#95A5A6',
      isLight: false,
    ),
    ColorOption(
      id: 'warm-gray',
      name: 'Warm Gray',
      color: Color(0xFFBDC3C7),
      hex: '#BDC3C7',
      isLight: true,
    ),
  ];

  // ===========================================
  // TEXT COLORS
  // ===========================================
  // Bright, vibrant colors for text that stand out
  // against both dark and light backgrounds

  static const List<ColorOption> textColors = [
    ColorOption(
      id: 'grey',
      name: 'Grey',
      color: Color(0xFF9E9E9E),
      hex: '#9E9E9E',
      isLight: false,
      meaning: 'Something that is not important',
    ),
    ColorOption(
      id: 'yellow',
      name: 'Yellow',
      color: Color(0xFFFFCC00),
      hex: '#FFCC00',
      isLight: true,
      meaning:
          "Something that I wrote that is technically correct, but the teacher doesn't see as important",
    ),
    ColorOption(
      id: 'amber',
      name: 'Amber',
      color: Color(0xFFFF9500),
      hex: '#FF9500',
      isLight: false,
      meaning:
          'Something that the teacher said, but it is wrong in my opinion based on research, logic, or experience',
    ),
    ColorOption(
      id: 'red',
      name: 'Red',
      color: Color(0xFFFF3B30),
      hex: '#FF3B30',
      isLight: false,
      meaning: 'Something I did wrong',
    ),
    ColorOption(
      id: 'pink',
      name: 'Pink',
      color: Color(0xFFFF69B4),
      hex: '#FF69B4',
      isLight: false,
      meaning: 'Something a student said and the teacher said is correct',
    ),
    ColorOption(
      id: 'purple',
      name: 'Purple',
      color: Color(0xFF9370DB),
      hex: '#9370DB',
      isLight: false,
      meaning: 'Unique, or figure it out from context, or add context',
    ),
    ColorOption(
      id: 'blue',
      name: 'Blue',
      color: Color(0xFF4A90E2),
      hex: '#4A90E2',
      isLight: false,
      meaning: 'Something a student said',
    ),
    ColorOption(
      id: 'sky',
      name: 'Sky',
      color: Color(0xFF64D2FF),
      hex: '#64D2FF',
      isLight: false,
      meaning: 'Something the teacher said',
    ),
    ColorOption(
      id: 'teal',
      name: 'Teal',
      color: Color(0xFF4ECDC4),
      hex: '#4ECDC4',
      isLight: false,
      meaning: 'Something AI said',
    ),
    ColorOption(
      id: 'green',
      name: 'Green',
      color: Color(0xFF6BCB77),
      hex: '#6BCB77',
      isLight: false,
      meaning: 'Something I did correctly',
    ),
  ];

  // ===========================================
  // MARKER/HIGHLIGHT COLORS
  // ===========================================
  // Semi-transparent, vibrant colors for highlighting text
  // These work well with both dark and light text

  static const List<ColorOption> markerColors = [
    ColorOption(
      id: 'grey',
      name: 'Grey',
      color: Color(0xFF9E9E9E),
      hex: '#9E9E9E',
      isLight: true,
      opacity: 0.25,
      meaning: 'Something that is not important',
    ),
    ColorOption(
      id: 'yellow',
      name: 'Yellow',
      color: Color(0xFFFFFF00),
      hex: '#FFFF00',
      isLight: true,
      opacity: 0.4,
      meaning:
          "Something that I wrote that is technically correct, but the teacher doesn't see as important",
    ),
    ColorOption(
      id: 'amber',
      name: 'Amber',
      color: Color(0xFFFFA500),
      hex: '#FFA500',
      isLight: true,
      opacity: 0.4,
      meaning:
          'Something that the teacher said, but it is wrong in my opinion based on research, logic, or experience',
    ),
    ColorOption(
      id: 'red',
      name: 'Red',
      color: Color(0xFFFF8A80),
      hex: '#FF8A80',
      isLight: true,
      opacity: 0.45,
      meaning: 'Something I did wrong',
    ),
    ColorOption(
      id: 'pink',
      name: 'Pink',
      color: Color(0xFFFFC0CB),
      hex: '#FFC0CB',
      isLight: true,
      opacity: 0.5,
      meaning: 'Something a student said and the teacher said is correct',
    ),
    ColorOption(
      id: 'purple',
      name: 'Purple',
      color: Color(0xFFE6E6FA),
      hex: '#E6E6FA',
      isLight: true,
      opacity: 0.5,
      meaning: 'Unique, or figure it out from context, or add context',
    ),
    ColorOption(
      id: 'blue',
      name: 'Blue',
      color: Color(0xFFB3E5FC),
      hex: '#B3E5FC',
      isLight: true,
      opacity: 0.5,
      meaning: 'Something a student said',
    ),
    ColorOption(
      id: 'sky',
      name: 'Sky',
      color: Color(0xFF00FFFF),
      hex: '#00FFFF',
      isLight: true,
      opacity: 0.4,
      meaning: 'Something the teacher said',
    ),
    ColorOption(
      id: 'teal',
      name: 'Teal',
      color: Color(0xFFB2DFDB),
      hex: '#B2DFDB',
      isLight: true,
      opacity: 0.5,
      meaning: 'Something AI said',
    ),
    ColorOption(
      id: 'green',
      name: 'Green',
      color: Color(0xFF90EE90),
      hex: '#90EE90',
      isLight: true,
      opacity: 0.4,
      meaning: 'Something I did correctly',
    ),
  ];

  static List<ColorOption> cloneColors(List<ColorOption> colors) =>
      colors.map((color) => color.copyWith()).toList(growable: false);

  static String normalizeHex(String hex) {
    final normalized = hex.trim().replaceFirst('#', '').toUpperCase();
    if (normalized.length != 6 && normalized.length != 8) {
      throw FormatException('Invalid hex color: $hex');
    }
    return '#$normalized';
  }

  static Color parseHexColor(String hex) {
    final normalized = normalizeHex(hex).substring(1);
    if (normalized.length == 6) {
      return Color(int.parse('FF$normalized', radix: 16));
    }
    return Color(int.parse(normalized, radix: 16));
  }

  static bool isLightColorHex(String hex) {
    return parseHexColor(hex).computeLuminance() > 0.6;
  }

  /// Get contrasting text color for a background
  ///
  /// Returns white for dark backgrounds, black for light backgrounds
  static Color getContrastingTextColor(Color backgroundColor) {
    // Calculate relative luminance
    final double luminance = backgroundColor.computeLuminance();

    // Use white text on dark backgrounds (luminance < 0.5), black on light
    return luminance > 0.5 ? Colors.black87 : Colors.white;
  }

  /// Get adaptive text color based on theme brightness
  ///
  /// Adjusts text color to ensure visibility in both dark and light modes
  static Color getAdaptiveTextColor(Color baseColor, Brightness brightness) {
    final double luminance = baseColor.computeLuminance();

    if (brightness == Brightness.dark) {
      // In dark mode, ensure text is visible
      if (luminance < 0.3) {
        return baseColor.lighten(0.3);
      }
    } else {
      // In light mode, ensure text is visible
      if (luminance > 0.7) {
        return baseColor.darken(0.3);
      }
    }
    return baseColor;
  }

  /// Get icon color for a background
  ///
  /// Returns appropriate icon color based on background brightness
  static Color getIconColor(Color backgroundColor) {
    final double luminance = backgroundColor.computeLuminance();
    if (luminance > 0.5) {
      // Light background - use dark icon
      return Colors.black54;
    } else {
      // Dark background - use light icon
      return Colors.white70;
    }
  }
}

/// Color option with metadata
class ColorOption {
  final String id;
  final String name;
  final Color color;
  final String hex;
  final bool isLight;
  final double? opacity;
  final String? meaning;

  const ColorOption({
    required this.id,
    required this.name,
    required this.color,
    required this.hex,
    required this.isLight,
    this.opacity,
    this.meaning,
  });

  /// Get the color with opacity applied (for markers)
  Color get colorWithOpacity {
    if (opacity != null) {
      return color.withValues(alpha: opacity!);
    }
    return color;
  }

  ColorOption copyWith({
    String? id,
    String? name,
    Color? color,
    String? hex,
    bool? isLight,
    double? opacity,
    String? meaning,
  }) {
    return ColorOption(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      hex: hex ?? this.hex,
      isLight: isLight ?? this.isLight,
      opacity: opacity ?? this.opacity,
      meaning: meaning ?? this.meaning,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'hex': hex,
      'isLight': isLight,
      'opacity': opacity,
      'meaning': meaning,
    };
  }

  String toJson() => jsonEncode(toMap());

  factory ColorOption.fromMap(Map<String, dynamic> map) {
    final hex =
        AppColorPalette.normalizeHex((map['hex'] as String?) ?? '#000000');
    return ColorOption(
      id: (map['id'] as String?) ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: (map['name'] as String?) ?? 'Unnamed',
      color: AppColorPalette.parseHexColor(hex),
      hex: hex,
      isLight: map['isLight'] as bool? ?? AppColorPalette.isLightColorHex(hex),
      opacity: (map['opacity'] as num?)?.toDouble(),
      meaning: map['meaning'] as String?,
    );
  }

  factory ColorOption.fromJson(String source) {
    return ColorOption.fromMap(jsonDecode(source) as Map<String, dynamic>);
  }
}

/// Extension methods for Color
extension ColorExtensions on Color {
  /// Lighten a color by a factor (0.0 to 1.0)
  Color lighten(double factor) {
    assert(factor >= 0.0 && factor <= 1.0);
    return withValues(
      red: (r + (1.0 - r) * factor).clamp(0.0, 1.0),
      green: (g + (1.0 - g) * factor).clamp(0.0, 1.0),
      blue: (b + (1.0 - b) * factor).clamp(0.0, 1.0),
    );
  }

  /// Darken a color by a factor (0.0 to 1.0)
  Color darken(double factor) {
    assert(factor >= 0.0 && factor <= 1.0);
    return withValues(
      red: (r * (1.0 - factor)).clamp(0.0, 1.0),
      green: (g * (1.0 - factor)).clamp(0.0, 1.0),
      blue: (b * (1.0 - factor)).clamp(0.0, 1.0),
    );
  }
}
