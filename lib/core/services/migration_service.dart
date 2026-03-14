import 'package:hive_flutter/hive_flutter.dart';

import '../models/folder.dart';
import '../models/note.dart';
import '../providers/notes_provider.dart';
import '../providers/folders_provider.dart';
import 'diagnostics_service.dart';
import 'local_file_service.dart';

class MigrationService {
  final DiagnosticsService _diagnostics = DiagnosticsService.instance;

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

  Future<bool> workspaceHasData(String workspaceId) async {
    final inventory = await _inspectWorkspace(workspaceId);
    final hasData = inventory.noteCount > 0 || inventory.folderCount > 0;
    _diagnostics.info(
      'MigrationService',
      'GUEST_IMPORT workspaceHasData workspace=$workspaceId notes=${inventory.noteCount} folders=${inventory.folderCount} hasData=$hasData',
    );
    return hasData;
  }

  Future<int> importWorkspace({
    required String sourceWorkspaceId,
    required String targetUserId,
    required NotesProvider notesProvider,
    required FoldersProvider foldersProvider,
  }) async {
    final sourceBefore = await _inspectWorkspace(sourceWorkspaceId);
    final targetBefore = await _inspectWorkspace(targetUserId);

    _diagnostics.info(
      'MigrationService',
      'GUEST_IMPORT import start source=$sourceWorkspaceId target=$targetUserId sourceNotes=${sourceBefore.noteCount} sourceFolders=${sourceBefore.folderCount} targetNotes=${targetBefore.noteCount} targetFolders=${targetBefore.folderCount}',
    );

    final copiedFiles = await LocalFileService.instance.cloneWorkspaceFiles(
      sourceWorkspaceId,
      targetUserId,
    );

    final clonedFolders = await foldersProvider.cloneWorkspace(
      sourceUserId: sourceWorkspaceId,
      targetUserId: targetUserId,
      overwriteTarget: false,
    );
    final clonedNotes = await notesProvider.cloneWorkspace(
      sourceUserId: sourceWorkspaceId,
      targetUserId: targetUserId,
      overwriteTarget: false,
    );
    final sourceAfter = await _inspectWorkspace(sourceWorkspaceId);
    final targetAfter = await _inspectWorkspace(targetUserId);

    _diagnostics.info(
      'MigrationService',
      'GUEST_IMPORT import complete source=$sourceWorkspaceId target=$targetUserId copiedFiles=$copiedFiles clonedFolders=$clonedFolders clonedNotes=$clonedNotes sourceNotesAfter=${sourceAfter.noteCount} sourceFoldersAfter=${sourceAfter.folderCount} targetNotesAfter=${targetAfter.noteCount} targetFoldersAfter=${targetAfter.folderCount}',
    );

    return clonedFolders + clonedNotes;
  }

  Future<void> deleteWorkspace(String workspaceId) async {
    final boxNames = [
      'notes_$workspaceId',
      'folders_$workspaceId',
      'calendar_events_$workspaceId',
      'homework_$workspaceId',
      'timetable_$workspaceId',
    ];

    for (final boxName in boxNames) {
      if (Hive.isBoxOpen(boxName)) {
        await Hive.box(boxName).close();
      }
      await Hive.deleteBoxFromDisk(boxName);
    }

    await LocalFileService.instance.deleteWorkspaceFiles(workspaceId);
  }

  Future<_WorkspaceInventory> _inspectWorkspace(String workspaceId) async {
    _ensureAdaptersRegistered();

    final notesBoxName = 'notes_$workspaceId';
    final foldersBoxName = 'folders_$workspaceId';
    final notesBoxResult = await _openNotesBox(notesBoxName);
    final foldersBoxResult = await _openFoldersBox(foldersBoxName);

    try {
      final noteCount = notesBoxResult.box.values.whereType<Note>().length;
      final folderCount =
          foldersBoxResult.box.values.whereType<Folder>().length;

      _diagnostics.info(
        'MigrationService',
        'HIVE_BOX inventory workspace=$workspaceId notesBox=$notesBoxName notesType=${notesBoxResult.box.runtimeType} notesOpenMode=${notesBoxResult.wasOpen ? 'reuse' : 'typed'} foldersBox=$foldersBoxName foldersType=${foldersBoxResult.box.runtimeType} foldersOpenMode=${foldersBoxResult.wasOpen ? 'reuse' : 'typed'} noteCount=$noteCount folderCount=$folderCount',
      );

      return _WorkspaceInventory(
        noteCount: noteCount,
        folderCount: folderCount,
      );
    } finally {
      if (!notesBoxResult.wasOpen) {
        await notesBoxResult.box.close();
      }
      if (!foldersBoxResult.wasOpen) {
        await foldersBoxResult.box.close();
      }
    }
  }

  Future<_OpenedBox> _openNotesBox(String boxName) async {
    final wasOpen = Hive.isBoxOpen(boxName);
    if (wasOpen) {
      final box = Hive.box(boxName);
      return _OpenedBox(box: box, wasOpen: true);
    }

    final box = await Hive.openBox<Note>(boxName);
    return _OpenedBox(box: box, wasOpen: false);
  }

  Future<_OpenedBox> _openFoldersBox(String boxName) async {
    final wasOpen = Hive.isBoxOpen(boxName);
    if (wasOpen) {
      final box = Hive.box(boxName);
      return _OpenedBox(box: box, wasOpen: true);
    }

    final box = await Hive.openBox<Folder>(boxName);
    return _OpenedBox(box: box, wasOpen: false);
  }

  void _ensureAdaptersRegistered() {
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(NoteAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(NoteTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(FolderAdapter());
    }
  }
}

class _WorkspaceInventory {
  const _WorkspaceInventory({
    required this.noteCount,
    required this.folderCount,
  });

  final int noteCount;
  final int folderCount;
}

class _OpenedBox {
  const _OpenedBox({
    required this.box,
    required this.wasOpen,
  });

  final Box<dynamic> box;
  final bool wasOpen;
}
