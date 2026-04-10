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
  });
}
