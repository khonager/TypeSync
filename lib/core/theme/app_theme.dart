/// TypeSync App Theme Configuration
///
/// Defines the visual appearance of the app including colors,
/// typography, and component styling for both light and dark modes.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// App-wide theme configuration
///
/// Based on the design mockup with dark mode as primary theme.
/// Features a sleek, modern UI with subtle gradients and accent colors.
class AppTheme {
  // Private constructor to prevent instantiation
  AppTheme._();

  // ===========================================
  // COLOR PALETTE
  // ===========================================

  /// Primary dark background color (from design)
  static const Color darkBackground = Color(0xFF1C1C1E);

  /// Secondary dark surface color (cards, dialogs)
  static const Color darkSurface = Color(0xFF2C2C2E);

  /// Tertiary dark color (elevated surfaces)
  static const Color darkTertiary = Color(0xFF3A3A3C);

  /// Light mode background
  static const Color lightBackground = Color(0xFFF2F2F7);

  /// Light mode surface
  static const Color lightSurface = Color(0xFFFFFFFF);

  /// Default accent color (teal from design)
  static const Color defaultAccent = Color(0xFF64D2FF);

  /// Text colors
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFF8E8E93);
  static const Color lightTextPrimary = Color(0xFF000000);
  static const Color lightTextSecondary = Color(0xFF6C6C70);

  /// Folder colors from the design
  static const Color folderDefault = Color(0xFF48484A);
  static const Color folderHighlight = Color(0xFF636366);

  // ===========================================
  // THEME BUILDERS
  // ===========================================

  /// Creates the dark theme with optional accent color override
  static ThemeData darkTheme([Color? accentColor]) {
    final Color accent = accentColor ?? defaultAccent;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      // Color scheme for dark mode
      colorScheme: ColorScheme.dark(
        primary: accent,
        secondary: accent.withOpacity(0.7),
        surface: darkSurface,
        error: const Color(0xFFFF6B6B),
        onPrimary: darkBackground,
        onSecondary: darkTextPrimary,
        onSurface: darkTextPrimary,
        onError: darkTextPrimary,
      ),

      // Scaffold background
      scaffoldBackgroundColor: darkBackground,

      // AppBar theme
      appBarTheme: AppBarTheme(
        backgroundColor: darkBackground,
        foregroundColor: darkTextPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: darkTextPrimary,
        ),
      ),

      // Card theme (for folder/file cards)
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),

      // Elevated button theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: darkBackground,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),

      // Text button theme
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
        ),
      ),

      // Icon button theme
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: darkTextSecondary,
        ),
      ),

      // Input decoration theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkTertiary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: GoogleFonts.inter(
          color: darkTextSecondary,
        ),
      ),

      // Bottom navigation bar theme
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: darkSurface,
        selectedItemColor: accent,
        unselectedItemColor: darkTextSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      // Floating action button theme
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: darkTertiary,
        foregroundColor: darkTextPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // Divider theme
      dividerTheme: const DividerThemeData(
        color: darkTertiary,
        thickness: 1,
      ),

      // Text theme using Google Fonts
      textTheme: _buildTextTheme(isDark: true),

      // Dialog theme
      dialogTheme: DialogThemeData(
        backgroundColor: darkSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),

      // Snackbar theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: darkTertiary,
        contentTextStyle: GoogleFonts.inter(color: darkTextPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Creates the light theme with optional accent color override
  static ThemeData lightTheme([Color? accentColor]) {
    final Color accent = accentColor ?? const Color(0xFF007AFF);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      // Color scheme for light mode
      colorScheme: ColorScheme.light(
        primary: accent,
        secondary: accent.withOpacity(0.7),
        surface: lightSurface,
        error: const Color(0xFFFF3B30),
        onPrimary: Colors.white,
        onSecondary: lightTextPrimary,
        onSurface: lightTextPrimary,
        onError: Colors.white,
      ),

      scaffoldBackgroundColor: lightBackground,

      appBarTheme: AppBarTheme(
        backgroundColor: lightBackground,
        foregroundColor: lightTextPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: lightTextPrimary,
        ),
      ),

      cardTheme: CardThemeData(
        color: lightSurface,
        elevation: 1,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFE5E5EA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: lightSurface,
        selectedItemColor: accent,
        unselectedItemColor: lightTextSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: Color(0xFFD1D1D6),
        thickness: 1,
      ),

      textTheme: _buildTextTheme(isDark: false),

      dialogTheme: DialogThemeData(
        backgroundColor: lightSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: lightTextPrimary,
        contentTextStyle: GoogleFonts.inter(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Builds the text theme using Google Fonts Inter
  static TextTheme _buildTextTheme({required bool isDark}) {
    final Color textColor = isDark ? darkTextPrimary : lightTextPrimary;
    final Color secondaryColor =
        isDark ? darkTextSecondary : lightTextSecondary;

    return TextTheme(
      // Large display text
      displayLarge: GoogleFonts.inter(
        fontSize: 57,
        fontWeight: FontWeight.w400,
        color: textColor,
      ),
      displayMedium: GoogleFonts.inter(
        fontSize: 45,
        fontWeight: FontWeight.w400,
        color: textColor,
      ),
      displaySmall: GoogleFonts.inter(
        fontSize: 36,
        fontWeight: FontWeight.w400,
        color: textColor,
      ),

      // Headlines
      headlineLarge: GoogleFonts.inter(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
      headlineMedium: GoogleFonts.inter(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
      headlineSmall: GoogleFonts.inter(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),

      // Titles
      titleLarge: GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w500,
        color: textColor,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: textColor,
      ),
      titleSmall: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: textColor,
      ),

      // Body text
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: textColor,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: textColor,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: secondaryColor,
      ),

      // Labels
      labelLarge: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: textColor,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: textColor,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: secondaryColor,
      ),
    );
  }
}
