import 'package:flutter/foundation.dart';
import '../providers/notes_provider.dart';
import '../providers/folders_provider.dart';

class MigrationService {
  /// Checks if there are items that belong to a different user (e.g. guest items)
  /// and updates their ownership to the current user.
  Future<int> migrateData({
    required String newUserId,
    required NotesProvider notesProvider,
    required FoldersProvider foldersProvider,
    required bool
        keepLocal, // If true, we merge. If false, we might want to discard (logic for discard not implemented yet, usually we merge)
  }) async {
    int migratedCount = 0;

    // 1. Migrate Folders
    final folders = foldersProvider.folders; // Get all non-deleted folders
    for (final folder in folders) {
      if (folder.userId != newUserId) {
        // This folder belongs to someone else (Guest?), claim it!
        // We use updateFolder which handles Hive and Sync triggering,
        // but we need to modify the folder object first.
        // NOTE: updateFolder expects the object to have the SAME ID.
        // We are NOT changing the ID, just the owner.

        final migratedFolder = folder.copyWith(
          userId: newUserId,
          isDirty: true, // Mark for sync
          updatedAt: DateTime.now(),
        );

        await foldersProvider.updateFolder(migratedFolder);
        migratedCount++;
      }
    }

    // 2. Migrate Notes
    final notes = notesProvider.notes;
    for (final note in notes) {
      if (note.userId != newUserId) {
        final migratedNote = note.copyWith(
          userId: newUserId,
          isDirty: true,
          updatedAt: DateTime.now(),
        );

        await notesProvider.updateNote(migratedNote);
        migratedCount++;
      }
    }

    return migratedCount;
  }

  /// Check if migration is needed
  bool needsMigration({
    required String currentUserId,
    required NotesProvider notesProvider,
  }) {
    return notesProvider.notes.any((n) => n.userId != currentUserId);
  }
}
