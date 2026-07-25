import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typesync/core/services/hunspell_dictionary.dart';
import 'package:typesync/core/services/typesync_spellchecker_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const <String, Object>{});

  group('HunspellDictionary', () {
    test('checks German dictionary words and inflections', () async {
      final dictionary = await HunspellDictionary.load(
        affPath: 'assets/hunspell/de_DE/de_DE.aff',
        dicPath: 'assets/hunspell/de_DE/de_DE.dic',
      );

      expect(dictionary.isCorrect('wäre'), isTrue);
      expect(dictionary.isCorrect('weiter'), isTrue);
      expect(dictionary.isCorrect('Dateien'), isTrue);
      expect(dictionary.isCorrect('Ladeanimation'), isTrue);
      expect(dictionary.isCorrect('entscheidet'), isTrue);
      expect(dictionary.isCorrect('Öffentliches'), isTrue);
      expect(dictionary.isCorrect('Erwerbliches'), isTrue);
      expect(dictionary.isCorrect('Haftpflichtversicherung'), isTrue);
      expect(dictionary.isCorrect('geht'), isTrue);
      expect(dictionary.isCorrect('mein'), isTrue);
      expect(dictionary.isCorrect('theorecically'), isFalse);
    });

    test('checks English affixed words and suggestions', () async {
      final dictionary = await HunspellDictionary.load(
        affPath: 'assets/hunspell/en_US/en_US.aff',
        dicPath: 'assets/hunspell/en_US/en_US.dic',
      );

      expect(dictionary.isCorrect('running'), isTrue);
      expect(dictionary.isCorrect('files'), isTrue);
      expect(dictionary.isCorrect('Monday'), isTrue);
      expect(dictionary.isCorrect('theorecically'), isFalse);
      expect(dictionary.suggest('speling'), contains('spelling'));
    });

    test('detects note language automatically', () async {
      final service = TypeSyncSpellcheckerService.instance;
      if (!service.isInitialized) {
        await service.initialize();
      }

      expect(
        service
            .detectLanguage('This note explains how the spellchecker works.'),
        TypeSyncSpellcheckLanguage.english,
      );
      expect(
        service
            .detectLanguage('Das ist eine Notiz ueber die Spracheinstellung.'),
        TypeSyncSpellcheckLanguage.german,
      );
    });

    test('prefers saved note language over auto-detection', () async {
      final service = TypeSyncSpellcheckerService.instance;
      if (!service.isInitialized) {
        await service.initialize();
      }

      final resolved = service.configureLanguageForText(
        'This text is in English.',
        languageCode: 'de',
      );

      expect(resolved, TypeSyncSpellcheckLanguage.german);
      expect(service.activeLanguage, TypeSyncSpellcheckLanguage.german);
    });

    test('bounds spellchecking work for a large note', () async {
      final service = TypeSyncSpellcheckerService.instance;
      if (!service.isInitialized) {
        await service.initialize();
      }
      await service.setEnabled(true);
      service.setLanguage(TypeSyncSpellcheckLanguage.english);

      final text = List<String>.filled(
        TypeSyncSpellcheckerService.maximumCharactersPerPass ~/ 2,
        'zznotaword',
      ).join(' ');
      final issues = service.collectIssues(text, maxIssues: 10000);

      expect(
        issues.length,
        lessThanOrEqualTo(TypeSyncSpellcheckerService.maximumIssuesPerPass),
      );
      expect(
        issues.every(
          (issue) =>
              issue.end <= TypeSyncSpellcheckerService.maximumCharactersPerPass,
        ),
        isTrue,
      );
    });

    test('creates suggestions only for the bounded result set', () async {
      final service = TypeSyncSpellcheckerService.instance;
      if (!service.isInitialized) {
        await service.initialize();
      }
      await service.setEnabled(true);
      service.setLanguage(TypeSyncSpellcheckLanguage.english);

      final issues = service.collectIssues(
        List<String>.generate(
          500,
          (index) => const <String>[
            'speling',
            'splling',
            'speeling',
            'spelingz',
          ][index % 4],
        ).join(' '),
        includeSuggestions: true,
        maxIssues: 4,
      );

      expect(issues, isNotEmpty);
      expect(issues.length, lessThanOrEqualTo(4));
      final spellingIssue = issues.firstWhere(
        (issue) => issue.kind == TypeSyncSpellcheckIssueKind.spelling,
      );
      expect(spellingIssue.suggestions, isNotEmpty);
    });

    test('does not run spellcheck while editor text is being laid out',
        () async {
      final service = TypeSyncSpellcheckerService.instance;
      if (!service.isInitialized) {
        await service.initialize();
      }
      await service.setEnabled(true);
      service.clearInlineSpellcheckTextSegments();

      expect(service.checkSpelling('speling'), isNull);
    });

    test('runs inline spellcheck only for explicitly selected text', () async {
      final service = TypeSyncSpellcheckerService.instance;
      if (!service.isInitialized) {
        await service.initialize();
      }
      await service.setEnabled(true);
      service.setInlineSpellcheckTextSegments(const ['speling']);

      expect(service.checkSpelling('speling'), isNotNull);
      expect(service.checkSpelling('different text'), isNull);

      service.clearInlineSpellcheckTextSegments();
    });
  });
}
