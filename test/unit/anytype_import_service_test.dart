import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/core/services/anytype_import_service.dart';
import 'package:typesync/core/services/markdown_rich_text_service.dart';
import 'package:typesync/core/models/typesync_kanban_embed.dart';
import 'package:typesync/core/models/typesync_table_embed.dart';

void main() {
  group('AnytypeImportService.extractReferencedLocalPaths', () {
    test('returns local markdown targets and ignores remote links', () {
      const markdown = '''
# Imported note

[Doc](files/Reference%20Doc.pdf)
![Image](assets/cover.png)
[Site](https://example.com)
[Mail](mailto:test@example.com)
[Anchor](#section)
''';

      expect(
        AnytypeImportService.extractReferencedLocalPaths(markdown),
        equals(['files/Reference Doc.pdf', 'assets/cover.png']),
      );
    });

    test('supports angle-bracket targets', () {
      const markdown = '''
![Diagram](<assets/diagram final.svg>)
''';

      expect(
        AnytypeImportService.extractReferencedLocalPaths(markdown),
        equals(['assets/diagram final.svg']),
      );
    });
  });

  group('MarkdownRichTextService.extractAnytypeBodyAndTitle', () {
    test('removes Anytype front matter and leading heading', () {
      const rawMarkdown = '''
---
Object type:
  - Page
id: abc123
---
# Imported title

Paragraph text
''';

      final extracted = MarkdownRichTextService.extractAnytypeBodyAndTitle(
        rawMarkdown: rawMarkdown,
        fallbackTitle: 'fallback',
      );

      expect(extracted.title, 'Imported title');
      expect(extracted.body, 'Paragraph text');
    });

    test('keeps fallback title when no heading is present', () {
      const rawMarkdown = '''
---
Object type:
  - Page
---
Body only
''';

      final extracted = MarkdownRichTextService.extractAnytypeBodyAndTitle(
        rawMarkdown: rawMarkdown,
        fallbackTitle: 'fallback title',
      );

      expect(extracted.title, 'fallback title');
      expect(extracted.body, 'Body only');
    });

    test('reads Object type from Anytype front matter', () {
      const rawMarkdown = '''
---
# yaml-language-server: \$schema=schemas/lernfeld_1.schema.json
Object type:
    - Lernfeld 1
Creation date: "2026-03-09T12:06:42Z"
id: abc123
---
# Imported title
''';

      expect(
        MarkdownRichTextService.extractAnytypeFrontMatterValue(
          rawMarkdown: rawMarkdown,
          key: 'Object type',
        ),
        'Lernfeld 1',
      );
    });

    test('reads front matter list values for custom relations', () {
      const rawMarkdown = '''
---
Tags:
  - Deutsch
Object type:
  - Tag
---
''';

      expect(
        MarkdownRichTextService.extractAnytypeFrontMatterValues(
          rawMarkdown: rawMarkdown,
        ),
        containsPair('Tags', ['Deutsch']),
      );
    });
  });

  group('AnytypeImportService.inferFolderPathFromMarkdownMetadata', () {
    test('prefers relation values over generic object types', () {
      const rawMarkdown = '''
---
Tags:
  - Deutsch
Object type:
  - Tag
---
# Werbebrief
''';

      expect(
        AnytypeImportService.inferFolderPathFromMarkdownMetadata(
          rawMarkdown: rawMarkdown,
        ),
        'Deutsch',
      );
    });
  });

  group('MarkdownRichTextService.convertAnytypeMarkdown', () {
    test('keeps underline and color formatting from html-rich markdown', () {
      const rawMarkdown = '''
---
Object type:
  - Note
---
# Werbebrief

<span style="color: #4F46E5">Mit Werbung verdient ein Unternehmer Geld.</span>

<u>Aufgaben:</u>

- konkrete Produkt-/Servicedienstleistung
''';

      final converted = MarkdownRichTextService.instance.convertAnytypeMarkdown(
        rawMarkdown: rawMarkdown,
        fallbackTitle: 'fallback',
      );
      final operations =
          jsonDecode(converted.quillContentJson) as List<dynamic>;
      final textContent = operations
          .map((operation) => (operation as Map<String, dynamic>)['insert'])
          .whereType<String>()
          .join();

      expect(
        textContent,
        contains('Mit Werbung verdient ein Unternehmer Geld.'),
      );
      expect(textContent, contains('Aufgaben:'));
      expect(textContent, isNot(contains('<u>')));

      final coloredOperation =
          operations.cast<Map<String, dynamic>>().firstWhere(
                (operation) =>
                    operation['attributes'] is Map<String, dynamic> &&
                    (operation['attributes'] as Map<String, dynamic>)
                        .containsKey('color'),
              );
      expect(
        (coloredOperation['attributes'] as Map<String, dynamic>)['color'],
        anyOf('#4F46E5', '#FF4F46E5'),
      );

      final underlinedOperation =
          operations.cast<Map<String, dynamic>>().firstWhere(
                (operation) =>
                    operation['attributes'] is Map<String, dynamic> &&
                    (operation['attributes'] as Map<String, dynamic>)
                        .containsKey('underline'),
              );
      expect(
        (underlinedOperation['attributes']
            as Map<String, dynamic>)['underline'],
        true,
      );
    });

    test('flattens unsupported image embeds into safe text', () {
      const rawMarkdown = '''
# Images

![Cover](assets/cover.png)
''';

      final converted = MarkdownRichTextService.instance.convertAnytypeMarkdown(
        rawMarkdown: rawMarkdown,
        fallbackTitle: 'fallback',
      );
      final operations =
          jsonDecode(converted.quillContentJson) as List<dynamic>;

      expect(
        operations.every(
          (operation) =>
              (operation as Map<String, dynamic>)['insert'] is String,
        ),
        isTrue,
      );
      expect(
        operations
            .map((operation) => (operation as Map<String, dynamic>)['insert'])
            .whereType<String>()
            .join(),
        contains('[Image attachment: cover.png]'),
      );
    });

    test('keeps multiple markdown tables with short dividers and spacer rows',
        () {
      const rawMarkdown = '''
# Fall 3 Sachbeschädigung Dogge und Gartenzwerg
Example
|  Defensiver Notstand § 228 BGB |      |                                                                   |                                                                                                         |   |
|:-------------------------------|:-----|:------------------------------------------------------------------|:--------------------------------------------------------------------------------------------------------|:--|
|               Voraussetzungen: |    + |                                                            Gefahr | Situation in der es zu negativen Auswirkungen auf Personen, Sachen, Sachverhalte oder Tiere kommen kann |   |
|                                |    + | Retrieving data. Wait a few seconds and try to cut or copy again. |                                                                                                         |   |
|                                |    + |                                                                   |                                                                                                         |   |
|                     Maßnahmen: |    + |                                  Sache von der die Gefahr ausgeht |                                                                                                         |   |
|                                |    + |                                                       beschädigen |                                                                                                         |   |
|                                | oder |                                                         zerstören |                                                                                                         |   |
|                                |    + |                                                  Erforderlichkeit |                                                                                        mildestes Mittel |   |
|                                |    + |                                               Verhältnismäßigkeit |                                                (Schaden durch Gefahr — Schaden durch Notstandshandlung) |   |
|                                |      |                                                                   |                                                                                                         |   |
|                     Sonstiges: |      |     Schadenersatz bei Verschulden der Gefahr durch den Handelnden |                                                                                                         |   |

|  Defensiver Notstand § 228 BGB |         |                                                               |                                                                                                         |                                                                                                     |
|:-------------------------------|:--------|:--------------------------------------------------------------|:--------------------------------------------------------------------------------------------------------|:----------------------------------------------------------------------------------------------------|
|               Voraussetzungen: |       + |                                                        Gefahr | Situation in der es zu negativen Auswirkungen auf Personen, Sachen, Sachverhalte oder Tiere kommen kann |                                                       Gefahr auf Person durch verletzung durch Tier |
|                                |       + |                               ausgehend von Sache (oder Tier) |                                                                                                         |                                                                Ja, durch eine Kampfdogge (Caligula) |
|                                |         |                                                               |                                                                                                         |                                                                                                     |
|                     Maßnahmen: |       + |                              Sache von der die Gefahr ausgeht |                                                                                                         |                                                                                Eine Kampfdogge/Tier |
|                                |       + |                                                   beschädigen |                                                                                                         |                                                                                         Kieferbruch |
|                                | oder: - |                                                     zerstören |                                                                                                         |                                                                                                Nein |
|                                |       - |                                              Erforderlichkeit |                                                                                        mildestes Mittel |                                                                    Nein, hätte auch schreien können |
|                                |       + |                                           Verhältnismäßigkeit |                                                (Schaden durch Gefahr — Schaden durch Notstandshandlung) |                                                          Gartenzwerg geht zu bruch. Verhaltensmäßig |
|                                |         |                                                               |                                                                                                         |                                                                                                     |
|                     Sonstiges: |         | Schadenersatz bei Verschulden der Gefahr durch den Handelnden |                                                                                                         | Nein, da er die Gefhr nicht verschuldet hat und es ein defensiver und nicht aggresiver Notstand ist |
''';

      final converted = MarkdownRichTextService.instance.convertAnytypeMarkdown(
        rawMarkdown: rawMarkdown,
        fallbackTitle: 'fallback',
      );
      final operations =
          jsonDecode(converted.quillContentJson) as List<dynamic>;

      final customTableOps = operations
          .map((operation) => (operation as Map<String, dynamic>)['insert'])
          .whereType<Map<String, dynamic>>()
          .where((insert) => insert.containsKey('custom'))
          .map((insert) => jsonDecode(insert['custom'] as String))
          .whereType<Map<String, dynamic>>()
          .where((insert) => insert.containsKey(TypeSyncTableEmbed.tableType))
          .toList();

      expect(customTableOps, hasLength(2));

      final firstTable = TypeSyncTableEmbed.parseData(
        customTableOps.first[TypeSyncTableEmbed.tableType] as String,
      );
      final secondTable = TypeSyncTableEmbed.parseData(
        customTableOps.last[TypeSyncTableEmbed.tableType] as String,
      );

      expect(firstTable.rows.first.first, 'Defensiver Notstand § 228 BGB');
      expect(
        firstTable.rows.any(
          (row) => row.contains(
            'Schadenersatz bei Verschulden der Gefahr durch den Handelnden',
          ),
        ),
        isTrue,
      );
      expect(
        secondTable.rows.any(
          (row) => row.contains('Eine Kampfdogge/Tier'),
        ),
        isTrue,
      );
      expect(
        operations
            .map((operation) => (operation as Map<String, dynamic>)['insert'])
            .whereType<String>()
            .join(),
        contains('Example'),
      );
    });

    test('preserves paragraph and label line breaks from Anytype markdown', () {
      const rawMarkdown = '''
Präsentation Elektronische Sicherheitstechnik (was gibt es alles)   
   
Grundlagen des Einbruchsschutzen   
  Top prinzip   
     
Präsentation 3-5 Minuten   
an:    
von:    
Auflistung:   
- BMA    
- EMA   
• Brandschutzanlage   
''';

      final converted = MarkdownRichTextService.instance.convertAnytypeMarkdown(
        rawMarkdown: rawMarkdown,
        fallbackTitle: 'fallback',
      );
      final operations =
          jsonDecode(converted.quillContentJson) as List<dynamic>;
      final text = operations
          .map((operation) => (operation as Map<String, dynamic>)['insert'])
          .whereType<String>()
          .join();

      expect(
        text,
        contains(
          'Präsentation Elektronische Sicherheitstechnik (was gibt es alles)\n',
        ),
      );
      expect(
        text,
        contains(
          'Präsentation Elektronische Sicherheitstechnik (was gibt es alles)\n\nGrundlagen des Einbruchsschutzen',
        ),
      );
      expect(
        text,
        contains(
          'Grundlagen des Einbruchsschutzen\n\u00A0\u00A0Top prinzip',
        ),
      );
      expect(text, contains('Präsentation 3-5 Minuten\n'));
      expect(text, contains('an:'));
      expect(text, contains('von:'));
      expect(text, contains('Auflistung:'));
      expect(text.contains('an:von:Auflistung:'), isFalse);
      expect(text, contains('BMA'));
      expect(text, contains('EMA'));
      expect(text, contains('Brandschutzanlage'));
      expect(
        text.contains(
          'Präsentation Elektronische Sicherheitstechnik (was gibt es alles)Grundlagen des Einbruchsschutzen',
        ),
        isFalse,
      );

      final bulletLineCount = operations.where((operation) {
        final map = operation as Map<String, dynamic>;
        return map['attributes'] is Map<String, dynamic> &&
            (map['attributes'] as Map<String, dynamic>)['list'] == 'bullet';
      }).length;
      expect(bulletLineCount, greaterThanOrEqualTo(3));

      expect(
        operations.any((operation) {
          final map = operation as Map<String, dynamic>;
          return map['insert'] is String &&
              (map['insert'] as String).contains('\u00A0\u00A0Top prinzip');
        }),
        isTrue,
      );
      expect(
        operations.any((operation) {
          final map = operation as Map<String, dynamic>;
          final insert = map['insert'];
          final attributes = map['attributes'];
          if (insert is! String || attributes is! Map<String, dynamic>) {
            return false;
          }
          final isLabel = insert.contains('an:') ||
              insert.contains('von:') ||
              insert.contains('Auflistung:');
          return isLabel && attributes['underline'] == true;
        }),
        isFalse,
      );
    });
  });

  group('AnytypeImportService.convertNativeObjectToQuillJsonForTesting', () {
    test('converts native Anytype tables into TypeSync table embeds', () {
      final content =
          AnytypeImportService.convertNativeObjectToQuillJsonForTesting({
        'blocks': [
          {
            'id': 'root',
            'childrenIds': ['header', 'table-1'],
          },
          {
            'id': 'header',
            'childrenIds': ['title', 'featuredRelations'],
          },
          {
            'id': 'table-1',
            'childrenIds': ['table-columns', 'table-rows'],
            'table': <String, dynamic>{},
          },
          {
            'id': 'table-columns',
            'childrenIds': ['col-1', 'col-2'],
            'layout': {'style': 'TableColumns'},
          },
          {
            'id': 'table-rows',
            'childrenIds': ['row-1', 'row-2'],
            'layout': {'style': 'TableRows'},
          },
          {
            'id': 'col-1',
            'fields': {'width': 220},
            'tableColumn': <String, dynamic>{},
          },
          {
            'id': 'col-2',
            'fields': {'width': 140},
            'tableColumn': <String, dynamic>{},
          },
          {
            'id': 'row-1',
            'childrenIds': ['row-1-col-1', 'row-1-col-2'],
            'tableRow': {'isHeader': true},
          },
          {
            'id': 'row-2',
            'childrenIds': ['row-2-col-1', 'row-2-col-2'],
            'tableRow': {'isHeader': false},
          },
          {
            'id': 'row-1-col-1',
            'text': {'text': 'Subject'},
          },
          {
            'id': 'row-1-col-2',
            'text': {'text': 'Teacher'},
          },
          {
            'id': 'row-2-col-1',
            'text': {'text': 'Deutsch'},
          },
          {
            'id': 'row-2-col-2',
            'text': {'text': 'Roescher'},
          },
        ],
      });

      final operations = jsonDecode(content) as List<dynamic>;
      final firstInsert = (operations.first as Map<String, dynamic>)['insert']
          as Map<String, dynamic>;
      final custom =
          jsonDecode(firstInsert['custom'] as String) as Map<String, dynamic>;
      expect(custom.containsKey(TypeSyncTableEmbed.tableType), isTrue);

      final table = TypeSyncTableEmbed.parseData(
        custom[TypeSyncTableEmbed.tableType] as String,
      );
      expect(table.rows, [
        ['Subject', 'Teacher'],
        ['Deutsch', 'Roescher'],
      ]);
      expect(table.headerRowCount, 1);
      expect(table.columnWidths, [220, 140]);
    });

    test('converts grouped native Anytype dataviews into kanban embeds', () {
      final content =
          AnytypeImportService.convertNativeObjectToQuillJsonForTesting(
        {
          'blocks': [
            {
              'id': 'root',
              'childrenIds': ['header', 'dataview'],
            },
            {
              'id': 'header',
              'childrenIds': ['title', 'featuredRelations'],
            },
            {
              'id': 'dataview',
              'dataview': {
                'views': [
                  {
                    'id': 'view-1',
                    'type': 'Graph',
                    'groupRelationKey': 'status',
                    'relations': [
                      {'key': 'name', 'isVisible': true, 'width': 220},
                      {'key': 'status', 'isVisible': true, 'width': 120},
                      {'key': 'tag', 'isVisible': true, 'width': 120},
                    ],
                  },
                ],
              },
            },
          ],
          'details': {
            'name': 'Homework board',
          },
          'collections': {
            'objects': ['note-1', 'note-2'],
          },
        },
        relationNamesByKey: const {
          'name': 'Name',
          'status': 'Status',
          'tag': 'Tag',
        },
        relationOptionNamesById: const {
          'status-open': 'Open',
          'status-done': 'Done',
          'teacher-a': 'Roescher',
          'teacher-b': 'Klein',
        },
        objectDataById: const {
          'note-1': {
            'details': {
              'name': 'Essay',
              'status': 'status-open',
              'tag': ['teacher-a'],
            },
          },
          'note-2': {
            'details': {
              'name': 'Worksheet',
              'status': 'status-done',
              'tag': ['teacher-b'],
            },
          },
        },
        objectNamesById: const {
          'note-1': 'Essay',
          'note-2': 'Worksheet',
        },
      );

      final operations = jsonDecode(content) as List<dynamic>;
      final firstInsert = (operations.first as Map<String, dynamic>)['insert']
          as Map<String, dynamic>;
      final custom =
          jsonDecode(firstInsert['custom'] as String) as Map<String, dynamic>;
      expect(custom.containsKey(TypeSyncKanbanEmbed.kanbanType), isTrue);

      final board = TypeSyncKanbanEmbed.parseData(
        custom[TypeSyncKanbanEmbed.kanbanType] as String,
      );
      expect(board.title, 'Homework board');
      expect(board.columns.map((column) => column.title), ['Open', 'Done']);
      expect(board.columns.first.cards.single.title, 'Essay');
      expect(
        board.columns.first.cards.single.description,
        contains('Tag: Roescher'),
      );
    });
  });
}
