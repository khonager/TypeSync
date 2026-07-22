// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hunspell_dictionary.dart';

enum TypeSyncSpellcheckLanguage {
  english(
    'en',
    'English',
    'assets/hunspell/en_US/en_US.aff',
    'assets/hunspell/en_US/en_US.dic',
  ),
  german(
    'de',
    'German',
    'assets/hunspell/de_DE/de_DE.aff',
    'assets/hunspell/de_DE/de_DE.dic',
  );

  const TypeSyncSpellcheckLanguage(
    this.code,
    this.label,
    this.affPath,
    this.dicPath,
  );

  final String code;
  final String label;
  final String affPath;
  final String dicPath;

  static TypeSyncSpellcheckLanguage fromCode(String? code) {
    return tryFromCode(code) ?? english;
  }

  static TypeSyncSpellcheckLanguage? tryFromCode(String? code) {
    for (final language in values) {
      if (language.code == code) {
        return language;
      }
    }
    return null;
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

class TypeSyncSpellcheckHover {
  const TypeSyncSpellcheckHover({
    required this.issue,
    required this.sourceText,
    required this.globalPosition,
  });

  final TypeSyncSpellcheckIssue issue;
  final String sourceText;
  final Offset globalPosition;
}

// ignore: experimental_member_use
class TypeSyncSpellcheckerService extends SpellCheckerService<String> {
  TypeSyncSpellcheckerService._()
      : _language = TypeSyncSpellcheckLanguage.english,
        super(language: TypeSyncSpellcheckLanguage.english.code);

  static const String enabledPreferenceKey = 'typesync_spellcheck_enabled_v1';
  static const String acceptedWordsPreferenceKey =
      'typesync_spellcheck_accepted_words_v1';

  /// Spellchecking is run synchronously while Flutter builds a text span.
  /// Keep every pass small enough that a large pasted note cannot block a
  /// frame. Text after this limit is still rendered normally and is omitted
  /// from that synchronous pass.
  static const int maximumCharactersPerPass = 20000;

  /// Bound dictionary lookups as well as the amount of text inspected. A
  /// dictionary lookup may itself involve affix and compound-word checks.
  static const int maximumWordsPerPass = 384;

  /// This is a safety ceiling for callers of [collectIssues]. The review UI
  /// requests fewer issues, but a public caller must not be able to remove the
  /// synchronous work bound by passing an arbitrarily large value.
  static const int maximumIssuesPerPass = 120;
  static const int _maximumInlineIssuesPerPass = 40;
  static final TypeSyncSpellcheckerService instance =
      TypeSyncSpellcheckerService._();

  final Map<TypeSyncSpellcheckLanguage, HunspellDictionary> _checkers = {};
  final Set<String> _acceptedWords = <String>{};
  final Set<String> _inlineSpellcheckTextSegments = <String>{};
  final ValueNotifier<TypeSyncSpellcheckHover?> hoveredIssue =
      ValueNotifier<TypeSyncSpellcheckHover?>(null);
  Timer? _hoverCloseTimer;
  String? _lastCheckedText;
  TypeSyncSpellcheckLanguage? _lastCheckedLanguage;
  bool? _lastCheckedEnabled;
  List<TextSpan>? _lastCheckedSpans;
  final RegExp _wordPattern = RegExp(
    r"[A-Za-zÀ-ÖØ-öø-ÿ]+(?:['’][A-Za-zÀ-ÖØ-öø-ÿ]+)?",
  );
  final RegExp _multiSpacePattern = RegExp(r' {2,}');
  final RegExp _repeatedPunctuationPattern =
      RegExp(r'([!?])\1{1,}|\.{4,}|,{2,}|;{2,}|:{2,}');
  final Set<String> _germanHintWords = const <String>{
    'der',
    'die',
    'das',
    'und',
    'ist',
    'nicht',
    'ich',
    'mit',
    'für',
    'ein',
    'eine',
    'zum',
    'zur',
    'den',
    'dem',
    'auf',
    'wie',
    'wir',
    'sie',
    'oder',
  };
  final Set<String> _englishHintWords = const <String>{
    'the',
    'and',
    'is',
    'are',
    'not',
    'with',
    'for',
    'this',
    'that',
    'you',
    'your',
    'have',
    'from',
    'will',
    'can',
    'was',
    'were',
    'about',
    'there',
    'their',
  };

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
    _acceptedWords
      ..clear()
      ..addAll(
        (prefs.getStringList(acceptedWordsPreferenceKey) ?? const <String>[])
            .map(_normalizeAcceptedWord)
            .where((word) => word.isNotEmpty),
      );

    await Future.wait(
      TypeSyncSpellcheckLanguage.values.map(_loadLanguage),
    );
    _isInitialized = true;
  }

  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    _invalidateRenderCache();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledPreferenceKey, enabled);
  }

  void setLanguage(TypeSyncSpellcheckLanguage language) {
    _language = language;
    _invalidateRenderCache();
  }

  TypeSyncSpellcheckLanguage configureLanguageForText(
    String text, {
    String? languageCode,
  }) {
    final explicitLanguage = TypeSyncSpellcheckLanguage.tryFromCode(
      languageCode,
    );
    final resolvedLanguage = explicitLanguage ?? detectLanguage(text);
    if (_language != resolvedLanguage) {
      _language = resolvedLanguage;
      _invalidateRenderCache();
    }
    return resolvedLanguage;
  }

  TypeSyncSpellcheckLanguage detectLanguage(String text) {
    final inspectedText = _textWithinPassLimit(text);
    final trimmed = inspectedText.trim();
    if (trimmed.isEmpty) {
      return TypeSyncSpellcheckLanguage.english;
    }

    if (RegExp(r'[ÄÖÜäöüß]').hasMatch(trimmed)) {
      return TypeSyncSpellcheckLanguage.german;
    }

    final candidates = _wordPattern
        .allMatches(trimmed)
        .map((match) => match.group(0)!)
        .where(
          (word) => !_shouldSkipWord(word) && !_isAcceptedWord(word),
        )
        .take(80)
        .toList(growable: false);

    if (candidates.isEmpty) {
      return TypeSyncSpellcheckLanguage.english;
    }

    var englishScore = 0;
    var germanScore = 0;
    final englishChecker = _checkers[TypeSyncSpellcheckLanguage.english];
    final germanChecker = _checkers[TypeSyncSpellcheckLanguage.german];

    for (final word in candidates) {
      final normalized = word.toLowerCase();

      if (_englishHintWords.contains(normalized)) {
        englishScore += 2;
      }
      if (_germanHintWords.contains(normalized)) {
        germanScore += 2;
      }

      if (englishChecker != null && englishChecker.isCorrect(word)) {
        englishScore += 3;
      }
      if (germanChecker != null && germanChecker.isCorrect(word)) {
        germanScore += 3;
      }
    }

    if (germanScore > englishScore) {
      return TypeSyncSpellcheckLanguage.german;
    }

    return TypeSyncSpellcheckLanguage.english;
  }

  Future<void> acceptWord(String word) async {
    final normalized = _normalizeAcceptedWord(word);
    if (normalized.isEmpty) return;

    _acceptedWords.add(normalized);
    _invalidateRenderCache();
    hoveredIssue.value = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      acceptedWordsPreferenceKey,
      _acceptedWords.toList()..sort(),
    );
  }

  /// Enables inline underlines for the text segments explicitly selected for
  /// manual checking. This is intentionally opt-in so loading or pasting a
  /// note never performs spellchecking during editor layout.
  void setInlineSpellcheckTextSegments(Iterable<String> segments) {
    final nextSegments =
        segments.where((segment) => segment.trim().isNotEmpty).toSet();
    if (_inlineSpellcheckTextSegments.length == nextSegments.length &&
        _inlineSpellcheckTextSegments.containsAll(nextSegments)) {
      return;
    }
    _inlineSpellcheckTextSegments
      ..clear()
      ..addAll(nextSegments);
    _invalidateRenderCache();
  }

  void clearInlineSpellcheckTextSegments() {
    if (_inlineSpellcheckTextSegments.isEmpty) return;
    _inlineSpellcheckTextSegments.clear();
    _invalidateRenderCache();
  }

  void keepHoverOpen() {
    _hoverCloseTimer?.cancel();
    _hoverCloseTimer = null;
  }

  void closeHoverSoon() {
    _hoverCloseTimer?.cancel();
    _hoverCloseTimer = Timer(const Duration(milliseconds: 180), () {
      hoveredIssue.value = null;
    });
  }

  Future<void> _loadLanguage(TypeSyncSpellcheckLanguage language) async {
    if (_checkers.containsKey(language)) return;

    _checkers[language] = await HunspellDictionary.load(
      affPath: language.affPath,
      dicPath: language.dicPath,
    );
  }

  @override
  List<TextSpan>? checkSpelling(
    String text, {
    LongPressGestureRecognizer Function(String)?
        customLongPressRecognizerOnWrongSpan,
  }) {
    if (!_isEnabled ||
        !_inlineSpellcheckTextSegments.contains(text) ||
        _textWithinPassLimit(text).trim().isEmpty) {
      return null;
    }

    if (identical(text, _lastCheckedText) &&
        _lastCheckedLanguage == _language &&
        _lastCheckedEnabled == _isEnabled) {
      return _lastCheckedSpans;
    }

    final issues = collectIssues(
      text,
      includeCapitalization: false,
      maxIssues: _maximumInlineIssuesPerPass,
    );
    if (issues.isEmpty) {
      _cacheRenderResult(text, null);
      return null;
    }
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
          mouseCursor: SystemMouseCursors.click,
          onEnter: (event) {
            keepHoverOpen();
            final suggestions = issue.suggestions.isEmpty &&
                    issue.kind == TypeSyncSpellcheckIssueKind.spelling
                ? _suggestWords(_checkers[_language]!, issue.text)
                : issue.suggestions;
            hoveredIssue.value = TypeSyncSpellcheckHover(
              issue: TypeSyncSpellcheckIssue(
                start: issue.start,
                end: issue.end,
                text: issue.text,
                kind: issue.kind,
                message: issue.message,
                suggestions: suggestions,
              ),
              sourceText: text,
              globalPosition: event.position,
            );
          },
          onExit: (_) {
            closeHoverSoon();
          },
        ),
      );
      cursor = issue.end;
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    _cacheRenderResult(text, spans);
    return spans;
  }

  List<TypeSyncSpellcheckIssue> collectIssues(
    String text, {
    bool includeSuggestions = false,
    bool includeCapitalization = true,
    int maxIssues = 120,
  }) {
    final inspectedText = _textWithinPassLimit(text);
    if (!_isEnabled || inspectedText.trim().isEmpty) {
      return const <TypeSyncSpellcheckIssue>[];
    }

    final checker = _checkers[_language];
    if (checker == null) return const <TypeSyncSpellcheckIssue>[];

    final safeMaxIssues = maxIssues.clamp(1, maximumIssuesPerPass);
    final issues = <TypeSyncSpellcheckIssue>[
      ..._collectSpacingIssues(inspectedText, maxIssues: safeMaxIssues),
      ..._collectPunctuationIssues(inspectedText, maxIssues: safeMaxIssues),
      ..._collectRepeatedWordIssues(inspectedText, maxIssues: safeMaxIssues),
      if (includeCapitalization)
        ..._collectCapitalizationIssues(
          inspectedText,
          maxIssues: safeMaxIssues,
        ),
      ..._collectSpellingIssues(
        inspectedText,
        checker,
        maxIssues: safeMaxIssues,
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
      if (filtered.length >= safeMaxIssues) break;
    }

    if (!includeSuggestions) return filtered;

    // Suggestions are significantly more expensive than a spelling check.
    // Generate them only for the small, already-filtered result set instead
    // of for every misspelling in the note.
    return filtered
        .map(
          (issue) => issue.kind == TypeSyncSpellcheckIssueKind.spelling
              ? TypeSyncSpellcheckIssue(
                  start: issue.start,
                  end: issue.end,
                  text: issue.text,
                  kind: issue.kind,
                  message: issue.message,
                  suggestions: _suggestWords(checker, issue.text),
                )
              : issue,
        )
        .toList(growable: false);
  }

  List<TypeSyncSpellcheckIssue> _collectSpellingIssues(
    String text,
    HunspellDictionary checker, {
    required int maxIssues,
  }) {
    final issues = <TypeSyncSpellcheckIssue>[];
    var checkedWords = 0;

    for (final match in _wordPattern.allMatches(text)) {
      if (checkedWords >= maximumWordsPerPass || issues.length >= maxIssues) {
        break;
      }
      final word = match.group(0)!;
      if (_shouldSkipWord(word) || _isAcceptedWord(word)) {
        continue;
      }

      checkedWords++;
      if (checker.isCorrect(word)) continue;

      issues.add(
        TypeSyncSpellcheckIssue(
          start: match.start,
          end: match.end,
          text: word,
          kind: TypeSyncSpellcheckIssueKind.spelling,
          message: 'Unknown word',
          suggestions: const <String>[],
        ),
      );
    }

    return issues;
  }

  List<TypeSyncSpellcheckIssue> _collectSpacingIssues(
    String text, {
    required int maxIssues,
  }) {
    return _multiSpacePattern
        .allMatches(text)
        .take(maxIssues)
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

  List<TypeSyncSpellcheckIssue> _collectPunctuationIssues(
    String text, {
    required int maxIssues,
  }) {
    final issues = <TypeSyncSpellcheckIssue>[];

    for (final match in _repeatedPunctuationPattern.allMatches(text)) {
      if (issues.length >= maxIssues) break;
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
      if (issues.length >= maxIssues) break;
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

  List<TypeSyncSpellcheckIssue> _collectRepeatedWordIssues(
    String text, {
    required int maxIssues,
  }) {
    final issues = <TypeSyncSpellcheckIssue>[];
    RegExpMatch? previous;

    for (final match in _wordPattern.allMatches(text)) {
      if (issues.length >= maxIssues) break;
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

  List<TypeSyncSpellcheckIssue> _collectCapitalizationIssues(
    String text, {
    required int maxIssues,
  }) {
    final issues = <TypeSyncSpellcheckIssue>[];
    var expectsSentenceStart = true;

    for (var i = 0; i < text.length; i++) {
      if (issues.length >= maxIssues) break;
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

  List<String> _suggestWords(HunspellDictionary checker, String word) {
    return checker.suggest(word, maxSuggestions: 4);
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

  bool _shouldSkipWord(String word) {
    if (word.length <= 1) return true;
    // Very long uninterrupted text is usually a URL, identifier, or pasted
    // data. Hunspell's affix/compound checks are not useful for it and can be
    // disproportionately expensive.
    if (word.length > 48) return true;
    if (word.contains(RegExp(r'\d'))) return true;
    if (word.contains('_')) return true;
    if (word.toUpperCase() == word && word.length <= 5) return true;
    return false;
  }

  bool _isAcceptedWord(String word) {
    return _acceptedWords.contains(_normalizeAcceptedWord(word));
  }

  static String _normalizeAcceptedWord(String word) {
    return word.trim().toLowerCase();
  }

  void _cacheRenderResult(String text, List<TextSpan>? spans) {
    _lastCheckedText = text;
    _lastCheckedLanguage = _language;
    _lastCheckedEnabled = _isEnabled;
    _lastCheckedSpans = spans;
  }

  void _invalidateRenderCache() {
    _lastCheckedText = null;
    _lastCheckedLanguage = null;
    _lastCheckedEnabled = null;
    _lastCheckedSpans = null;
  }

  String _textWithinPassLimit(String text) {
    return text.length <= maximumCharactersPerPass
        ? text
        : text.substring(0, maximumCharactersPerPass);
  }

  @override
  void toggleChecker() {
    _isEnabled = !_isEnabled;
    _invalidateRenderCache();
  }

  @override
  bool isServiceActive() => _isEnabled;

  @override
  void dispose({bool onlyPartial = false}) {}

  @override
  void setNewLanguageState({required String language}) {
    final parsed = TypeSyncSpellcheckLanguage.fromCode(language);
    _language = parsed;
    _invalidateRenderCache();
    _loadLanguage(parsed);
  }

  @override
  void updateCustomLanguageIfExist({required String languageIdentifier}) {}

  @override
  void addCustomLanguage({required String languageIdentifier}) {}
}
