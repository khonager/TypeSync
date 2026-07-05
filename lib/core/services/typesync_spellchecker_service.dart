// ignore_for_file: deprecated_member_use

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spell_check_on_client/spell_check_on_client.dart';

enum TypeSyncSpellcheckLanguage {
  english('en', 'English', 'assets/dictionaries/en_words.txt'),
  german('de', 'German', 'assets/dictionaries/de_words.txt');

  const TypeSyncSpellcheckLanguage(this.code, this.label, this.assetPath);

  final String code;
  final String label;
  final String assetPath;

  static TypeSyncSpellcheckLanguage fromCode(String? code) {
    return values.firstWhere(
      (language) => language.code == code,
      orElse: () => english,
    );
  }
}

class TypeSyncSpellcheckerService extends SpellCheckerService<String> {
  TypeSyncSpellcheckerService._()
      : _language = TypeSyncSpellcheckLanguage.english,
        super(language: TypeSyncSpellcheckLanguage.english.code);

  static const String enabledPreferenceKey = 'typesync_spellcheck_enabled_v1';
  static const String languagePreferenceKey = 'typesync_spellcheck_language_v1';
  static final TypeSyncSpellcheckerService instance =
      TypeSyncSpellcheckerService._();

  final Map<TypeSyncSpellcheckLanguage, SpellCheck> _checkers = {};
  final RegExp _wordPattern = RegExp(
    r"[A-Za-zÀ-ÖØ-öø-ÿ]+(?:['’][A-Za-zÀ-ÖØ-öø-ÿ]+)?",
  );

  bool _isEnabled = true;
  bool _isInitialized = false;
  TypeSyncSpellcheckLanguage _language;

  bool get isEnabled => _isEnabled;
  bool get isInitialized => _isInitialized;
  TypeSyncSpellcheckLanguage get activeLanguage => _language;

  Future<void> initialize() async {
    if (_isInitialized) return;

    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool(enabledPreferenceKey) ?? true;
    _language = TypeSyncSpellcheckLanguage.fromCode(
      prefs.getString(languagePreferenceKey),
    );

    await _loadLanguage(_language);
    _isInitialized = true;
  }

  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledPreferenceKey, enabled);
  }

  Future<void> setLanguage(TypeSyncSpellcheckLanguage language) async {
    _language = language;
    await _loadLanguage(language);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(languagePreferenceKey, language.code);
  }

  Future<void> _loadLanguage(TypeSyncSpellcheckLanguage language) async {
    if (_checkers.containsKey(language)) return;

    final content = await rootBundle.loadString(language.assetPath);
    _checkers[language] = SpellCheck.fromWordsContent(
      content,
      letters: LanguageLetters.getLanguageForLanguage(language.code),
      iterations: 1,
    );
  }

  @override
  List<TextSpan>? checkSpelling(
    String text, {
    LongPressGestureRecognizer Function(String)?
        customLongPressRecognizerOnWrongSpan,
  }) {
    if (!_isEnabled || text.trim().isEmpty) return null;

    final checker = _checkers[_language];
    if (checker == null) return null;

    final spans = <TextSpan>[];
    var cursor = 0;
    var foundMisspelling = false;

    for (final match in _wordPattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }

      final word = match.group(0)!;
      if (_shouldSkipWord(word) || checker.isCorrect(word)) {
        spans.add(TextSpan(text: word));
      } else {
        foundMisspelling = true;
        spans.add(
          TextSpan(
            text: word,
            style: const TextStyle(
              decoration: TextDecoration.underline,
              decorationColor: Color(0xFFFF5A66),
              decorationStyle: TextDecorationStyle.wavy,
              decorationThickness: 1.8,
            ),
          ),
        );
      }

      cursor = match.end;
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return foundMisspelling ? spans : null;
  }

  bool _shouldSkipWord(String word) {
    if (word.length <= 1) return true;
    if (word.contains(RegExp(r'\d'))) return true;
    if (word.contains('_')) return true;
    if (word.toUpperCase() == word && word.length <= 5) return true;
    return false;
  }

  @override
  void toggleChecker() {
    _isEnabled = !_isEnabled;
  }

  @override
  bool isServiceActive() => _isEnabled;

  @override
  void dispose({bool onlyPartial = false}) {}

  @override
  void setNewLanguageState({required String language}) {
    final parsed = TypeSyncSpellcheckLanguage.fromCode(language);
    _language = parsed;
    _loadLanguage(parsed);
  }

  @override
  void updateCustomLanguageIfExist({required String languageIdentifier}) {}

  @override
  void addCustomLanguage({required String languageIdentifier}) {}
}
