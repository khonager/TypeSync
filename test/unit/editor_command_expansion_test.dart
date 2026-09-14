import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/core/models/editor_command.dart';
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

  group('commandMenuStateAt', () {
    const commands = [
      EditorCommand(trigger: '/daily', template: 'Daily template'),
      EditorCommand(trigger: '/date', template: 'Date template'),
      EditorCommand(trigger: '/list', template: 'List template'),
    ];

    test('shows every command for a slash on its own line', () {
      final state = commandMenuStateAt(
        documentText: 'Before\n/\n',
        caretOffset: 8,
        commands: commands,
      );

      expect(state, isNotNull);
      expect(state!.matches, hasLength(3));
    });

    test('filters commands by the typed prefix', () {
      final state = commandMenuStateAt(
        documentText: '/da\n',
        caretOffset: 3,
        commands: commands,
      );

      expect(
        state!.matches.map((command) => command.trigger),
        ['/daily', '/date'],
      );
      expect(state.exactMatch, isNull);
    });

    test('exposes an exact match for the enter preview', () {
      final state = commandMenuStateAt(
        documentText: '/list\n',
        caretOffset: 5,
        commands: commands,
      );

      expect(state!.exactMatch?.template, 'List template');
    });

    test('hides the menu after whitespace or for no matches', () {
      expect(
        commandMenuStateAt(
          documentText: '/da extra\n',
          caretOffset: 9,
          commands: commands,
        ),
        isNull,
      );
      expect(
        commandMenuStateAt(
          documentText: '/missing\n',
          caretOffset: 8,
          commands: commands,
        ),
        isNull,
      );
    });
  });
}
