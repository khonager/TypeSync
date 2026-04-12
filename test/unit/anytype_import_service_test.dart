import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/core/services/anytype_import_service.dart';
import 'package:typesync/core/services/markdown_rich_text_service.dart';

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
  });
}
