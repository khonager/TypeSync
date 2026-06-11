library;

import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/core/models/note.dart';
import 'package:typesync/core/services/storage_service.dart';

void main() {
  group('resolveStorageObjectPath', () {
    test('resolves Firebase download URLs to object paths', () {
      const url =
          'https://firebasestorage.googleapis.com/v0/b/example.appspot.com/o/users%2Fuser-1%2Fattachments%2Fnote-1%2Fattachment-1_file.pdf?alt=media&token=abc';

      final resolved = resolveStorageObjectPath(url, userId: 'user-1');

      expect(
        resolved,
        'users/user-1/attachments/note-1/attachment-1_file.pdf',
      );
    });

    test('preserves raw relative storage paths', () {
      final resolved = resolveStorageObjectPath(
        'attachments/note-1/attachment-1_file.pdf',
        userId: 'user-1',
      );

      expect(
        resolved,
        'users/user-1/attachments/note-1/attachment-1_file.pdf',
      );
    });

    test('preserves fully-qualified storage paths', () {
      final resolved = resolveStorageObjectPath(
        'users/user-1/attachments/note-1/attachment-1_file.pdf',
        userId: 'user-1',
      );

      expect(
        resolved,
        'users/user-1/attachments/note-1/attachment-1_file.pdf',
      );
    });
  });

  group('Note.copyWith', () {
    test('can clear pdfPath explicitly', () {
      final original = Note(
        id: 'note-1',
        title: 'PDF note',
        content: '',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
        userId: 'user-1',
        pdfPath: 'https://example.test/file.pdf',
      );

      final updated = original.copyWith(pdfPath: null);

      expect(updated.pdfPath, isNull);
    });
  });
}
