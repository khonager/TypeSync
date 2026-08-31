import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/core/models/typesync_code_embed.dart';
import 'package:typesync/core/services/rich_text_plain_text_service.dart';
import 'package:typesync/core/utils/supported_embed_types.dart';

void main() {
  test('preserves a code block language and multiline source', () {
    const code = TypeSyncCodeData(
      id: 'code-1',
      language: 'nix',
      code: '{ pkgs }: pkgs.hello\n',
    );

    final parsed = TypeSyncCodeData.fromEmbedData(code.toEmbedData());

    expect(parsed.id, 'code-1');
    expect(parsed.language, 'nix');
    expect(parsed.code, '{ pkgs }: pkgs.hello\n');
    expect(TypeSyncCodeData.toBlockEmbed(code).type, 'custom');
  });

  test('finds the intended code block among other document content', () {
    const first = TypeSyncCodeData(
      id: 'first',
      language: 'dart',
      code: 'void main() {}',
    );
    const target = TypeSyncCodeData(
      id: 'target',
      language: 'nix',
      code: '{ pkgs }: pkgs.hello',
    );

    expect(
      TypeSyncCodeData.findCodeOffset(
        [
          {'insert': 'Before\n'},
          {'insert': TypeSyncCodeData.toBlockEmbed(first).toJson()},
          {'insert': 'Between\n'},
          {'insert': TypeSyncCodeData.toBlockEmbed(target).toJson()},
        ],
        codeId: 'target',
      ),
      16,
    );
  });

  test('Markdown code blocks remain supported after save and reload', () {
    const markdown = TypeSyncCodeData(
      id: 'markdown-note',
      language: 'markdown',
      code: '# Heading\n\n- Rendered item\n',
    );
    final savedOperations = [
      {'insert': TypeSyncCodeData.toBlockEmbed(markdown).toJson()},
      {'insert': '\n'},
    ];

    final reloaded = Document.fromJson(
      jsonDecode(jsonEncode(savedOperations)) as List<dynamic>,
    );

    expect(
      isSupportedRichTextEmbedType(TypeSyncCodeEmbed.codeType),
      isTrue,
    );
    expect(
      TypeSyncCodeData.findCodeOffset(
        reloaded.toDelta().toJson(),
        codeId: markdown.id,
      ),
      0,
    );
    expect(
      RichTextPlainTextService.extractPlainTextFromDelta(
        reloaded.toDelta().toJson(),
      ),
      contains('# Heading'),
    );
  });
}
