library;

import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/core/models/typesync_kanban_embed.dart';
import 'package:typesync/core/models/typesync_table_embed.dart';
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

    test('finds the matching board offset when a document has multiple boards',
        () {
      const firstBoard = TypeSyncKanbanData(
        id: 'board-at-top',
        title: 'Top board',
        columns: [],
      );
      const secondBoard = TypeSyncKanbanData(
        id: 'board-at-bottom',
        title: 'Bottom board',
        columns: [],
      );
      const checklistText = 'First checklist item\nSecond checklist item\n';
      final operations = [
        {'insert': TypeSyncKanbanEmbed.toBlockEmbed(firstBoard).toJson()},
        {'insert': checklistText},
        {'insert': TypeSyncKanbanEmbed.toBlockEmbed(secondBoard).toJson()},
      ];

      expect(
        TypeSyncKanbanEmbed.findBoardOffset(
          operations,
          boardId: secondBoard.id,
        ),
        1 + checklistText.length,
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

    test('extracts custom-wrapped table embed text from delta operations', () {
      const table = TypeSyncTableData(
        rows: [
          ['Day', 'Teacher'],
          ['Wednesday', 'Roescher'],
        ],
        columnWidths: [180, 180],
      );

      final plainText = RichTextPlainTextService.extractPlainTextFromDelta([
        {'insert': TypeSyncTableEmbed.toBlockEmbed(table).toJson()},
      ]);

      expect(plainText, contains('Day\tTeacher'));
      expect(plainText, contains('Wednesday\tRoescher'));
    });
  });
}
