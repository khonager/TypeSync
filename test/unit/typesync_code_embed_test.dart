import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/core/models/typesync_code_embed.dart';

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
}
