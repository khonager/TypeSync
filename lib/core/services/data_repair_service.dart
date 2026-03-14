library;

import '../models/folder.dart';
import '../models/note.dart';
import '../providers/folders_provider.dart';
import '../providers/notes_provider.dart';

enum RepairItemType { folder, note }

class RepairCandidate {
  final RepairItemType type;
  final String id;
  final String name;
  final List<String> changes;
  final Folder? repairedFolder;
  final Note? repairedNote;

  const RepairCandidate.folder({
    required this.id,
    required this.name,
    required this.changes,
    required Folder this.repairedFolder,
  })  : type = RepairItemType.folder,
        repairedNote = null;

  const RepairCandidate.note({
    required this.id,
    required this.name,
    required this.changes,
    required Note this.repairedNote,
  })  : type = RepairItemType.note,
        repairedFolder = null;

  String get signature => '${type.name}:$id:${changes.join("|")}';
}

class RepairPlan {
  final List<RepairCandidate> folders;
  final List<RepairCandidate> notes;

  const RepairPlan({
    required this.folders,
    required this.notes,
  });

  bool get hasChanges => folders.isNotEmpty || notes.isNotEmpty;

  int get totalItems => folders.length + notes.length;

  List<RepairCandidate> get allItems => [...folders, ...notes];

  String get signature => allItems.map((item) => item.signature).join('||');
}

class DataRepairService {
  static final RegExp _hexColorPattern = RegExp(r'^#([0-9A-Fa-f]{6})$');

  RepairPlan buildRepairPlan({
    required String currentUserId,
    required FoldersProvider foldersProvider,
    required NotesProvider notesProvider,
  }) {
    return buildRepairPlanFromItems(
      currentUserId: currentUserId,
      folders: foldersProvider.folders,
      notes: notesProvider.notes,
    );
  }

  RepairPlan buildRepairPlanFromItems({
    required String currentUserId,
    required List<Folder> folders,
    required List<Note> notes,
  }) {
    final folderIds = folders.map((folder) => folder.id).toSet();

    final folderRepairs = <RepairCandidate>[];
    for (final folder in folders) {
      final changes = <String>[];
      Folder repaired = folder;

      final normalizedParentId = _normalizeOptionalText(folder.parentId);
      if (normalizedParentId != folder.parentId) {
        repaired = repaired.copyWith(parentId: normalizedParentId);
        changes.add(
          normalizedParentId == null
              ? 'move to root folder'
              : 'normalize parent folder reference',
        );
      }

      final normalizedSubtitle = _normalizeOptionalText(folder.subtitle);
      if (normalizedSubtitle != folder.subtitle) {
        repaired = repaired.copyWith(subtitle: normalizedSubtitle);
        changes.add('clear empty subtitle');
      }

      final normalizedIcon = _normalizeOptionalText(folder.icon);
      if (normalizedIcon == null) {
        repaired = repaired.copyWith(icon: 'folder');
        changes.add('restore missing folder icon');
      }

      final normalizedColor = _normalizeColor(folder.backgroundColor);
      if (normalizedColor != folder.backgroundColor) {
        repaired = repaired.copyWith(backgroundColor: normalizedColor);
        changes.add(
          normalizedColor == null
              ? 'clear invalid folder color'
              : 'normalize folder color',
        );
      }

      if (folder.userId != currentUserId) {
        repaired = repaired.copyWith(userId: currentUserId);
        changes.add('assign to your account');
      }

      if (changes.isNotEmpty) {
        folderRepairs.add(
          RepairCandidate.folder(
            id: folder.id,
            name: folder.name,
            changes: changes,
            repairedFolder: repaired.copyWith(
              isDirty: true,
              updatedAt: DateTime.now(),
            ),
          ),
        );
      }
    }

    final noteRepairs = <RepairCandidate>[];
    for (final note in notes) {
      final changes = <String>[];
      Note repaired = note;

      final normalizedFolderId = _normalizeOptionalText(note.folderId);
      if (normalizedFolderId != note.folderId) {
        repaired = repaired.copyWith(folderId: normalizedFolderId);
        changes.add(
          normalizedFolderId == null
              ? 'move note to root'
              : 'normalize note folder reference',
        );
      }

      if (repaired.folderId != null && !folderIds.contains(repaired.folderId)) {
        repaired = repaired.copyWith(folderId: null);
        changes.add('remove missing folder link');
      }

      final normalizedColor = _normalizeColor(note.backgroundColor);
      if (normalizedColor != note.backgroundColor) {
        repaired = repaired.copyWith(
          backgroundColor: normalizedColor,
          backgroundColorSet: true,
        );
        changes.add(
          normalizedColor == null
              ? 'clear invalid note color'
              : 'normalize note color',
        );
      }

      if (note.userId != currentUserId) {
        repaired = repaired.copyWith(userId: currentUserId);
        changes.add('assign to your account');
      }

      if (changes.isNotEmpty) {
        noteRepairs.add(
          RepairCandidate.note(
            id: note.id,
            name: note.title,
            changes: changes,
            repairedNote: repaired.copyWith(
              isDirty: true,
              updatedAt: DateTime.now(),
            ),
          ),
        );
      }
    }

    return RepairPlan(folders: folderRepairs, notes: noteRepairs);
  }

  Future<int> applyRepairPlan({
    required RepairPlan plan,
    required FoldersProvider foldersProvider,
    required NotesProvider notesProvider,
  }) async {
    int repairedCount = 0;

    for (final candidate in plan.folders) {
      final folder = candidate.repairedFolder;
      if (folder == null) {
        continue;
      }
      final success = await foldersProvider.updateFolder(folder);
      if (success) {
        repairedCount++;
      }
    }

    for (final candidate in plan.notes) {
      final note = candidate.repairedNote;
      if (note == null) {
        continue;
      }
      final success = await notesProvider.updateNote(note);
      if (success) {
        repairedCount++;
      }
    }

    return repairedCount;
  }

  String? _normalizeOptionalText(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _normalizeColor(String? value) {
    final normalized = _normalizeOptionalText(value);
    if (normalized == null) {
      return null;
    }
    if (_hexColorPattern.hasMatch(normalized)) {
      return normalized.toUpperCase();
    }
    return null;
  }
}
