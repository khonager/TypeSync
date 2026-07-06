import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/core/services/hunspell_dictionary.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
  });
}
