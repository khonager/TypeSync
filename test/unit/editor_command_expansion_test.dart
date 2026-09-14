import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/features/editor/utils/editor_command_expansion.dart';

void main() {
  group('commandExpansionAt', () {
    const templates = {
      '/list': 'First item\nSecond item',
      '/hello': 'Hello!',
    };

    String? resolve(String trigger) => templates[trigger];

    test('expands an exact command on the current line', () {
      final expansion = commandExpansionAt(
        documentText: 'Before\n/list\n',
        insertionOffset: 12,
        resolveTemplate: resolve,
      );

      expect(expansion, isNotNull);
      expect(expansion!.start, 7);
      expect(expansion.length, 5);
      expect(expansion.replacement, 'First item\nSecond item');
    });

    test('does not expand command text embedded in a sentence', () {
      final expansion = commandExpansionAt(
        documentText: 'Try /list\n',
        insertionOffset: 9,
        resolveTemplate: resolve,
      );

      expect(expansion, isNull);
    });

    test('does not expand unknown commands', () {
      final expansion = commandExpansionAt(
        documentText: '/unknown\n',
        insertionOffset: 8,
        resolveTemplate: resolve,
      );

      expect(expansion, isNull);
    });
  });
}
