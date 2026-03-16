import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/core/services/anytype_import_service.dart';

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
}
