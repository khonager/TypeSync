import 'dart:collection';

import 'package:flutter/services.dart';

class HunspellDictionary {
  HunspellDictionary._({
    required Map<String, Set<String>> words,
    required Map<String, List<_AffixRule>> prefixes,
    required Map<String, List<_AffixRule>> suffixes,
    required List<String> tryCharacters,
  })  : _words = words,
        _prefixes = prefixes,
        _suffixes = suffixes,
        _tryCharacters = tryCharacters;

  final Map<String, Set<String>> _words;
  final Map<String, List<_AffixRule>> _prefixes;
  final Map<String, List<_AffixRule>> _suffixes;
  final List<String> _tryCharacters;
  final Map<String, bool> _checkCache = HashMap<String, bool>();
  final Map<String, List<String>> _suggestCache =
      HashMap<String, List<String>>();

  static Future<HunspellDictionary> load({
    required String affPath,
    required String dicPath,
  }) async {
    final affContent = await rootBundle.loadString(affPath);
    final dicContent = await rootBundle.loadString(dicPath);
    final aff = _ParsedAffix.parse(affContent);
    final words = _parseDictionary(dicContent);
    return HunspellDictionary._(
      words: words,
      prefixes: aff.prefixes,
      suffixes: aff.suffixes,
      tryCharacters: aff.tryCharacters,
    );
  }

  bool isCorrect(String word) {
    if (word.trim().isEmpty) return true;
    return _checkCache.putIfAbsent(word, () => _isCorrectUncached(word));
  }

  List<String> suggest(String word, {int maxSuggestions = 5}) {
    if (word.length > 28) return const <String>[];
    return _suggestCache.putIfAbsent(word, () {
      final candidates = <String>{};
      var checkedCandidates = 0;
      for (final candidate in _edits1(word)) {
        // Suggestions run on the UI thread when the user opens a spelling
        // popup. Keep this work strictly bounded; exhaustive two-edit search
        // can produce tens of thousands of dictionary checks.
        if (checkedCandidates >= 1024) break;
        checkedCandidates++;
        if (isCorrect(candidate)) {
          candidates.add(_matchCapitalization(word, candidate));
          if (candidates.length >= maxSuggestions) break;
        }
      }

      return candidates.take(maxSuggestions).toList();
    });
  }

  bool _isCorrectUncached(String word) {
    if (_hasWord(word)) return true;

    final lower = word.toLowerCase();
    if (lower != word && _hasWord(lower)) return true;

    final title = _titleCase(lower);
    if (title != word && _hasWord(title)) return true;

    return _hasAffixedForm(word) ||
        _hasAffixedForm(lower) ||
        _hasAffixedForm(title) ||
        _hasGermanicFallback(word) ||
        _hasGermanicFallback(lower) ||
        _hasGermanicFallback(title) ||
        _isCompound(word) ||
        _isCompound(title);
  }

  bool _hasWord(String word, [String? requiredFlag]) {
    final flags = _words[word];
    if (flags == null) return false;
    return requiredFlag == null || flags.contains(requiredFlag);
  }

  bool _hasAffixedForm(String word) {
    for (final rules in _suffixes.values) {
      for (final rule in rules) {
        final stem = rule.reverseSuffix(word);
        if (stem != null && _hasWord(stem, rule.flag)) return true;

        if (stem != null && rule.crossProduct) {
          for (final prefixRules in _prefixes.values) {
            for (final prefixRule in prefixRules) {
              if (!prefixRule.crossProduct) continue;
              final crossStem = prefixRule.reversePrefix(stem);
              if (crossStem != null &&
                  _hasWord(crossStem, rule.flag) &&
                  _words[crossStem]!.contains(prefixRule.flag)) {
                return true;
              }
            }
          }
        }
      }
    }

    for (final rules in _prefixes.values) {
      for (final rule in rules) {
        final stem = rule.reversePrefix(word);
        if (stem != null && _hasWord(stem, rule.flag)) return true;
      }
    }

    return false;
  }

  bool _isCompound(String word) {
    if (word.length < 8 || word.contains('-')) return false;
    final lower = word.toLowerCase();
    return _canSplitCompound(lower, 0, 0, <int>{});
  }

  bool _hasGermanicFallback(String word) {
    final candidates = <String>{};
    final lower = word.toLowerCase();

    if (lower.endsWith('et') && lower.length > 4) {
      final stem = word.substring(0, word.length - 2);
      candidates.addAll([stem, '${stem}en', '${stem}n']);
    }
    if (lower.endsWith('t') && lower.length > 3) {
      final stem = word.substring(0, word.length - 1);
      candidates.addAll([stem, '${stem}en', '${stem}n']);
    }
    if (lower.endsWith('st') && lower.length > 4) {
      final stem = word.substring(0, word.length - 2);
      candidates.addAll([stem, '${stem}en', '${stem}n']);
    }

    for (final ending in const [
      'liches',
      'liche',
      'licher',
      'lichen',
      'lichem',
      'lich',
    ]) {
      if (!lower.endsWith(ending) || lower.length <= ending.length + 2) {
        continue;
      }
      final stem = word.substring(0, word.length - ending.length);
      candidates.addAll([stem, _titleCase(stem)]);
    }

    for (final candidate in candidates) {
      if (_hasWord(candidate) ||
          _hasWord(_titleCase(candidate)) ||
          _hasAffixedForm(candidate)) {
        return true;
      }
    }

    return false;
  }

  bool _canSplitCompound(
    String word,
    int start,
    int parts,
    Set<int> visited,
  ) {
    if (parts > 5) return false;
    if (!visited.add(start)) return false;

    final remaining = word.length - start;
    if (parts >= 1 && remaining >= 3) {
      final tail = word.substring(start);
      if (_hasWord(tail) ||
          _hasWord(_titleCase(tail)) ||
          _hasAffixedForm(tail)) {
        return true;
      }
    }

    for (var end = start + 3; end <= word.length - 3; end++) {
      final part = word.substring(start, end);
      final knownPart =
          _hasWord(part) || _hasWord(_titleCase(part)) || _hasAffixedForm(part);
      if (knownPart && _canSplitCompound(word, end, parts + 1, visited)) {
        return true;
      }
    }

    return false;
  }

  Iterable<String> _edits1(String word) sync* {
    final lower = word.toLowerCase();
    final letters = _tryCharacters.isEmpty
        ? 'abcdefghijklmnopqrstuvwxyzäöüß'.split('')
        : _tryCharacters;

    for (var i = 0; i < lower.length; i++) {
      yield lower.substring(0, i) + lower.substring(i + 1);
    }

    for (var i = 0; i < lower.length - 1; i++) {
      yield lower.substring(0, i) +
          lower[i + 1] +
          lower[i] +
          lower.substring(i + 2);
    }

    for (var i = 0; i < lower.length; i++) {
      for (final letter in letters) {
        yield lower.substring(0, i) + letter + lower.substring(i + 1);
      }
    }

    for (var i = 0; i <= lower.length; i++) {
      for (final letter in letters) {
        yield lower.substring(0, i) + letter + lower.substring(i);
      }
    }
  }

  static Map<String, Set<String>> _parseDictionary(String content) {
    final words = <String, Set<String>>{};
    final lines = content.split(RegExp(r'\r?\n'));
    for (var i = 1; i < lines.length; i++) {
      final raw = lines[i].trim();
      if (raw.isEmpty) continue;
      if (lines[i].startsWith('\t') || raw.startsWith('#')) continue;

      final entry = raw.split(RegExp(r'\s+')).first;
      final slashIndex = entry.indexOf('/');
      final word = slashIndex == -1 ? entry : entry.substring(0, slashIndex);
      final flags = slashIndex == -1
          ? <String>{}
          : entry.substring(slashIndex + 1).split('').toSet();
      words[word] = flags;
    }
    return words;
  }

  static String _titleCase(String word) {
    if (word.isEmpty) return word;
    return word[0].toUpperCase() + word.substring(1);
  }

  static String _matchCapitalization(String source, String suggestion) {
    if (source.isEmpty || suggestion.isEmpty) return suggestion;
    if (source.toUpperCase() == source) return suggestion.toUpperCase();
    if (source[0].toUpperCase() == source[0]) return _titleCase(suggestion);
    return suggestion;
  }
}

class _ParsedAffix {
  const _ParsedAffix({
    required this.prefixes,
    required this.suffixes,
    required this.tryCharacters,
  });

  final Map<String, List<_AffixRule>> prefixes;
  final Map<String, List<_AffixRule>> suffixes;
  final List<String> tryCharacters;

  static _ParsedAffix parse(String content) {
    final prefixes = <String, List<_AffixRule>>{};
    final suffixes = <String, List<_AffixRule>>{};
    var tryCharacters = <String>[];

    for (final rawLine in content.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      if (line.startsWith('TRY ')) {
        tryCharacters = line.substring(4).trim().split('');
        continue;
      }

      if (!line.startsWith('PFX ') && !line.startsWith('SFX ')) continue;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 4) continue;

      final type = parts[0];
      final flag = parts[1];
      final isHeader = parts[2] == 'Y' || parts[2] == 'N';
      if (isHeader) continue;
      if (parts.length < 5) continue;

      final strip = parts[2] == '0' ? '' : parts[2];
      final add = parts[3] == '0' ? '' : parts[3].split('/').first;
      final condition = parts[4];
      final crossProduct = _findCrossProduct(content, type, flag);
      final rule = _AffixRule(
        flag: flag,
        strip: strip,
        add: add,
        condition: condition,
        crossProduct: crossProduct,
      );

      final target = type == 'PFX' ? prefixes : suffixes;
      target.putIfAbsent(flag, () => <_AffixRule>[]).add(rule);
    }

    return _ParsedAffix(
      prefixes: prefixes,
      suffixes: suffixes,
      tryCharacters: tryCharacters,
    );
  }

  static bool _findCrossProduct(String content, String type, String flag) {
    final headerPattern =
        RegExp('^$type\\s+$flag\\s+([YN])\\s+', multiLine: true);
    return headerPattern.firstMatch(content)?.group(1) == 'Y';
  }
}

class _AffixRule {
  const _AffixRule({
    required this.flag,
    required this.strip,
    required this.add,
    required this.condition,
    required this.crossProduct,
  });

  final String flag;
  final String strip;
  final String add;
  final String condition;
  final bool crossProduct;

  String? reverseSuffix(String word) {
    if (add.isNotEmpty && !word.endsWith(add)) return null;
    final withoutAdd =
        add.isEmpty ? word : word.substring(0, word.length - add.length);
    final stem = withoutAdd + strip;
    return _matchesSuffixCondition(stem) ? stem : null;
  }

  String? reversePrefix(String word) {
    if (add.isNotEmpty && !word.startsWith(add)) return null;
    final withoutAdd = add.isEmpty ? word : word.substring(add.length);
    final stem = strip + withoutAdd;
    return _matchesPrefixCondition(stem) ? stem : null;
  }

  bool _matchesSuffixCondition(String stem) {
    if (condition == '.') return true;
    try {
      return RegExp('$condition\$').hasMatch(stem);
    } catch (_) {
      return true;
    }
  }

  bool _matchesPrefixCondition(String stem) {
    if (condition == '.') return true;
    try {
      return RegExp('^$condition').hasMatch(stem);
    } catch (_) {
      return true;
    }
  }
}
