library;

import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/core/models/typesync_kanban_embed.dart';
import 'package:typesync/core/services/rich_text_plain_text_service.dart';

void main() {
  group('TypeSyncKanbanData', () {
    test('creates a default board with stable IDs', () {
      final board = TypeSyncKanbanData.empty();

      expect(board.id, isNotEmpty);
      expect(board.columns, hasLength(3));
      expect(board.columns.every((column) => column.id.isNotEmpty), isTrue);
    });

    test('round trips through embed JSON', () {
      const board = TypeSyncKanbanData(
        id: 'board-1',
        title: 'Sprint',
        columns: [
          TypeSyncKanbanColumnData(
            id: 'column-1',
            title: 'Doing',
            cards: [
              TypeSyncKanbanCardData(
                id: 'card-1',
                title: 'Implement kanban',
                description: 'Keep IDs stable for widgets and links later.',
              ),
            ],
          ),
        ],
      );

      final restored = TypeSyncKanbanData.fromEmbedData(board.toEmbedData());

      expect(restored.id, 'board-1');
      expect(restored.title, 'Sprint');
      expect(restored.columns, hasLength(1));
      expect(restored.columns.single.title, 'Doing');
      expect(restored.columns.single.cards.single.title, 'Implement kanban');
      expect(
        restored.columns.single.cards.single.description,
        'Keep IDs stable for widgets and links later.',
      );
    });
  });

  group('RichTextPlainTextService', () {
    test('extracts kanban text from delta operations', () {
      const board = TypeSyncKanbanData(
        id: 'board-1',
        title: 'Launch plan',
        columns: [
          TypeSyncKanbanColumnData(
            id: 'column-1',
            title: 'To Do',
            cards: [
              TypeSyncKanbanCardData(
                id: 'card-1',
                title: 'Draft announcement',
                description: 'Link back to the release note later.',
              ),
            ],
          ),
        ],
      );

      final plainText = RichTextPlainTextService.extractPlainTextFromDelta([
        {'insert': 'Intro\n'},
        {'insert': TypeSyncKanbanEmbed.toBlockEmbed(board).toJson()},
        {'insert': '\nOutro\n'},
      ]);

      expect(plainText, contains('Intro'));
      expect(plainText, contains('Launch plan'));
      expect(plainText, contains('To Do'));
      expect(plainText, contains('Draft announcement'));
      expect(plainText, contains('Link back to the release note later.'));
      expect(plainText, contains('Outro'));
    });
  });
}
