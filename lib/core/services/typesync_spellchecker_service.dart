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

enum TypeSyncSpellcheckIssueKind {
  spelling,
  repeatedWord,
  spacing,
  punctuation,
  capitalization,
}

class TypeSyncSpellcheckIssue {
  const TypeSyncSpellcheckIssue({
    required this.start,
    required this.end,
    required this.text,
    required this.kind,
    required this.message,
    this.suggestions = const <String>[],
  });

  final int start;
  final int end;
  final String text;
  final TypeSyncSpellcheckIssueKind kind;
  final String message;
  final List<String> suggestions;

  int get length => end - start;

  bool get hasReplacement => suggestions.isNotEmpty;

  Color get underlineColor {
    return switch (kind) {
      TypeSyncSpellcheckIssueKind.spelling => const Color(0xFFFF5A66),
      TypeSyncSpellcheckIssueKind.repeatedWord => const Color(0xFFFFB23F),
      TypeSyncSpellcheckIssueKind.spacing => const Color(0xFFFFB23F),
      TypeSyncSpellcheckIssueKind.punctuation => const Color(0xFFFFB23F),
      TypeSyncSpellcheckIssueKind.capitalization => const Color(0xFFFFB23F),
    };
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
  final RegExp _multiSpacePattern = RegExp(r' {2,}');
  final RegExp _repeatedPunctuationPattern =
      RegExp(r'([!?])\1{1,}|\.{4,}|,{2,}|;{2,}|:{2,}');

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

    final issues = collectIssues(text, includeCapitalization: false);
    if (issues.isEmpty) return null;
    final spans = <TextSpan>[];
    var cursor = 0;

    for (final issue in issues) {
      if (issue.start < cursor) continue;
      if (issue.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, issue.start)));
      }

      spans.add(
        TextSpan(
          text: text.substring(issue.start, issue.end),
          style: TextStyle(
            decoration: TextDecoration.underline,
            decorationColor: issue.underlineColor,
            decorationStyle: TextDecorationStyle.wavy,
            decorationThickness: 1.8,
          ),
        ),
      );
      cursor = issue.end;
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return spans;
  }

  List<TypeSyncSpellcheckIssue> collectIssues(
    String text, {
    bool includeSuggestions = false,
    bool includeCapitalization = true,
    int maxIssues = 120,
  }) {
    if (!_isEnabled || text.trim().isEmpty) {
      return const <TypeSyncSpellcheckIssue>[];
    }

    final checker = _checkers[_language];
    if (checker == null) return const <TypeSyncSpellcheckIssue>[];

    final issues = <TypeSyncSpellcheckIssue>[
      ..._collectSpacingIssues(text),
      ..._collectPunctuationIssues(text),
      ..._collectRepeatedWordIssues(text),
      if (includeCapitalization) ..._collectCapitalizationIssues(text),
      ..._collectSpellingIssues(
        text,
        checker,
        includeSuggestions: includeSuggestions,
      ),
    ];

    issues.sort((a, b) {
      final startCompare = a.start.compareTo(b.start);
      if (startCompare != 0) return startCompare;
      return b.length.compareTo(a.length);
    });

    final filtered = <TypeSyncSpellcheckIssue>[];
    var cursor = -1;
    for (final issue in issues) {
      if (issue.start < cursor) continue;
      filtered.add(issue);
      cursor = issue.end;
      if (filtered.length >= maxIssues) break;
    }

    return filtered;
  }

  List<TypeSyncSpellcheckIssue> _collectSpellingIssues(
    String text,
    SpellCheck checker, {
    required bool includeSuggestions,
  }) {
    final issues = <TypeSyncSpellcheckIssue>[];

    for (final match in _wordPattern.allMatches(text)) {
      final word = match.group(0)!;
      if (_shouldSkipWord(word) || checker.isCorrect(word)) continue;

      final suggestions =
          includeSuggestions ? _suggestWords(checker, word) : const <String>[];
      issues.add(
        TypeSyncSpellcheckIssue(
          start: match.start,
          end: match.end,
          text: word,
          kind: TypeSyncSpellcheckIssueKind.spelling,
          message: 'Unknown word',
          suggestions: suggestions,
        ),
      );
    }

    return issues;
  }

  List<TypeSyncSpellcheckIssue> _collectSpacingIssues(String text) {
    return _multiSpacePattern
        .allMatches(text)
        .map(
          (match) => TypeSyncSpellcheckIssue(
            start: match.start,
            end: match.end,
            text: match.group(0)!,
            kind: TypeSyncSpellcheckIssueKind.spacing,
            message: 'Repeated spaces',
            suggestions: const [' '],
          ),
        )
        .toList();
  }

  List<TypeSyncSpellcheckIssue> _collectPunctuationIssues(String text) {
    final issues = <TypeSyncSpellcheckIssue>[];

    for (final match in _repeatedPunctuationPattern.allMatches(text)) {
      final value = match.group(0)!;
      issues.add(
        TypeSyncSpellcheckIssue(
          start: match.start,
          end: match.end,
          text: value,
          kind: TypeSyncSpellcheckIssueKind.punctuation,
          message: 'Repeated punctuation',
          suggestions: [value.startsWith('.') ? '...' : value[0]],
        ),
      );
    }

    for (var i = 0; i < text.length - 1; i++) {
      final char = text[i];
      final next = text[i + 1];
      if (!'.!?,;:'.contains(char) || !_isLetter(next)) continue;
      if (char == '.' && _looksLikeAbbreviationDot(text, i)) continue;

      issues.add(
        TypeSyncSpellcheckIssue(
          start: i,
          end: i + 1,
          text: char,
          kind: TypeSyncSpellcheckIssueKind.spacing,
          message: 'Missing space after punctuation',
          suggestions: ['$char '],
        ),
      );
    }

    return issues;
  }

  List<TypeSyncSpellcheckIssue> _collectRepeatedWordIssues(String text) {
    final issues = <TypeSyncSpellcheckIssue>[];
    RegExpMatch? previous;

    for (final match in _wordPattern.allMatches(text)) {
      final last = previous;
      if (last != null &&
          text.substring(last.end, match.start).trim().isEmpty &&
          last.group(0)!.toLowerCase() == match.group(0)!.toLowerCase()) {
        issues.add(
          TypeSyncSpellcheckIssue(
            start: last.start,
            end: match.end,
            text: text.substring(last.start, match.end),
            kind: TypeSyncSpellcheckIssueKind.repeatedWord,
            message: 'Repeated word',
            suggestions: [last.group(0)!],
          ),
        );
      }
      previous = match;
    }

    return issues;
  }

  List<TypeSyncSpellcheckIssue> _collectCapitalizationIssues(String text) {
    final issues = <TypeSyncSpellcheckIssue>[];
    var expectsSentenceStart = true;

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (!_isLetter(char)) {
        if ('.!?'.contains(char)) {
          expectsSentenceStart = true;
        }
        continue;
      }

      if (expectsSentenceStart && _isLowercaseLetter(char)) {
        final replacement = char.toUpperCase();
        issues.add(
          TypeSyncSpellcheckIssue(
            start: i,
            end: i + 1,
            text: char,
            kind: TypeSyncSpellcheckIssueKind.capitalization,
            message: 'Sentence should start with a capital letter',
            suggestions: [replacement],
          ),
        );
      }
      expectsSentenceStart = false;

      while (i + 1 < text.length && _isLetter(text[i + 1])) {
        i++;
      }
    }

    return issues;
  }

  List<String> _suggestWords(SpellCheck checker, String word) {
    return checker
        .didYouMeanAny(word, maxWords: 5)
        .where((suggestion) => suggestion.isNotEmpty)
        .map((suggestion) => _matchCapitalization(word, suggestion))
        .toSet()
        .take(4)
        .toList();
  }

  bool _looksLikeAbbreviationDot(String text, int dotIndex) {
    if (dotIndex == 0) return false;
    final before = text[dotIndex - 1];
    return _isUppercaseLetter(before);
  }

  bool _isLetter(String value) {
    return RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]').hasMatch(value);
  }

  bool _isLowercaseLetter(String value) {
    return _isLetter(value) && value.toLowerCase() == value;
  }

  bool _isUppercaseLetter(String value) {
    return _isLetter(value) && value.toUpperCase() == value;
  }

  String _matchCapitalization(String source, String suggestion) {
    if (source.isEmpty || suggestion.isEmpty) return suggestion;
    if (source.toUpperCase() == source) return suggestion.toUpperCase();
    if (_isUppercaseLetter(source[0])) {
      return suggestion[0].toUpperCase() + suggestion.substring(1);
    }
    return suggestion;
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
