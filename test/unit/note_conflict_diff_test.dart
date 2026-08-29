import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/core/services/rich_text_plain_text_service.dart';
import 'package:typesync/core/utils/note_conflict_diff.dart';

String _delta(String text) => jsonEncode(<Map<String, dynamic>>[
      <String, dynamic>{'insert': text},
    ]);

void main() {
  group('NoteConflictDiff', () {
    test('lets separate changed blocks choose local or cloud independently',
        () {
      final diff = NoteConflictDiff.fromContents(
        localContent: _delta('same\nlocal first\nmiddle\nlocal second\nend\n'),
        cloudContent: _delta('same\ncloud first\nmiddle\ncloud second\nend\n'),
      );

      expect(diff.conflictCount, 2);

      final resolved = diff.resolve(<NoteConflictChoice>[
        NoteConflictChoice.local,
        NoteConflictChoice.cloud,
      ]);

      expect(
        RichTextPlainTextService.extractPlainText(resolved),
        'same\nlocal first\nmiddle\ncloud second\nend\n',
      );
    });

    test('preserves rich-text operations from the selected side', () {
      final local = jsonEncode(<Map<String, dynamic>>[
        <String, dynamic>{
          'insert': 'Important',
          'attributes': <String, dynamic>{'bold': true},
        },
        <String, dynamic>{'insert': '\n'},
      ]);
      final cloud = _delta('Ordinary\n');
      final diff = NoteConflictDiff.fromContents(
        localContent: local,
        cloudContent: cloud,
      );

      final resolved = jsonDecode(
        diff.resolve(<NoteConflictChoice>[NoteConflictChoice.local]),
      ) as List<dynamic>;

      expect(resolved.first['insert'], 'Important');
      expect(resolved.first['attributes']['bold'], isTrue);
    });

    test('supports choosing a deletion without producing invalid Delta JSON',
        () {
      final diff = NoteConflictDiff.fromContents(
        localContent: _delta('keep\nremove locally\n'),
        cloudContent: _delta('keep\n'),
      );

      final resolved = diff.resolve(
        <NoteConflictChoice>[NoteConflictChoice.cloud],
      );

      expect(RichTextPlainTextService.extractPlainText(resolved), 'keep\n');
      expect(() => jsonDecode(resolved), returnsNormally);
    });

    test('converts legacy plain text safely during resolution', () {
      final diff = NoteConflictDiff.fromContents(
        localContent: 'local legacy text',
        cloudContent: 'cloud legacy text',
      );

      final resolved = diff.resolve(
        <NoteConflictChoice>[NoteConflictChoice.local],
      );

      expect(
        RichTextPlainTextService.extractPlainText(resolved),
        'local legacy text\n',
      );
    });
  });
}
