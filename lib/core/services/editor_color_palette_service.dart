library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/color_utils.dart';

class EditorColorPaletteService extends ChangeNotifier {
  static const String _textColorsKey = 'editor_text_colors';
  static const String _markerColorsKey = 'editor_marker_colors';

  List<ColorOption> _textColors = AppColorPalette.cloneColors(
    AppColorPalette.textColors,
  );
  List<ColorOption> _markerColors = AppColorPalette.cloneColors(
    AppColorPalette.markerColors,
  );
  bool _isLoaded = false;

  EditorColorPaletteService() {
    _load();
  }

  List<ColorOption> get textColors => List.unmodifiable(_textColors);
  List<ColorOption> get markerColors => List.unmodifiable(_markerColors);
  bool get isLoaded => _isLoaded;

  Future<void> setTextColors(List<ColorOption> colors) async {
    _textColors = colors.map((color) => color.copyWith()).toList(growable: false);
    notifyListeners();
    await _saveList(_textColorsKey, _textColors);
  }

  Future<void> setMarkerColors(List<ColorOption> colors) async {
    _markerColors =
        colors.map((color) => color.copyWith()).toList(growable: false);
    notifyListeners();
    await _saveList(_markerColorsKey, _markerColors);
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _textColors = _readList(
        prefs.getString(_textColorsKey),
        fallback: AppColorPalette.textColors,
      );
      _markerColors = _readList(
        prefs.getString(_markerColorsKey),
        fallback: AppColorPalette.markerColors,
      );
    } catch (error) {
      debugPrint('Failed to load editor color palettes: $error');
      _textColors = AppColorPalette.cloneColors(AppColorPalette.textColors);
      _markerColors = AppColorPalette.cloneColors(AppColorPalette.markerColors);
    }

    _isLoaded = true;
    notifyListeners();
  }

  List<ColorOption> _readList(
    String? encoded, {
    required List<ColorOption> fallback,
  }) {
    if (encoded == null || encoded.trim().isEmpty) {
      return AppColorPalette.cloneColors(fallback);
    }

    try {
      final decoded = jsonDecode(encoded) as List<dynamic>;
      return decoded
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .map(ColorOption.fromMap)
          .toList(growable: false);
    } catch (_) {
      return AppColorPalette.cloneColors(fallback);
    }
  }

  Future<void> _saveList(String key, List<ColorOption> colors) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded =
          jsonEncode(colors.map((color) => color.toMap()).toList(growable: false));
      await prefs.setString(key, encoded);
    } catch (error) {
      debugPrint('Failed to save editor color palettes: $error');
    }
  }
}
