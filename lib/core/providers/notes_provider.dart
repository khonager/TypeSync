/// Notes Provider
///
/// State management for notes including CRUD operations,
/// filtering, and sync status tracking.
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/note.dart';
import '../services/diagnostics_service.dart';
import '../services/sync_service.dart';

/// Provider for managing note state
///
/// Handles local storage with Hive and coordinates with
/// SyncService for cloud synchronization.
class NotesProvider extends ChangeNotifier {
  static const String emptyDocumentJson = '[{"insert":"\\n"}]';
  final DiagnosticsService _diagnostics = DiagnosticsService.instance;

  // Local storage box
  Box<Note>? _notesBox;
  String? _activeUserId;

  // In-memory notes list
  List<Note> _notes = [];

  // Loading state
  bool _isLoading = false;

  // Error state
  String? _errorMessage;

  // UUID generator
  final Uuid _uuid = const Uuid();

  // Sync service reference (set by parent)
  SyncService? _syncService;
  StreamSubscription<void>? _syncSubscription;

  // ===========================================
  // GETTERS
  // ===========================================

  List<Note> get notes => _notes.where((n) => !n.isDeleted).toList();
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Get notes for a specific folder
  List<Note> getNotesInFolder(String? folderId) {
    return _notes.where((n) => !n.isDeleted && n.folderId == folderId).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Get favorite notes
  List<Note> get favoriteNotes =>
      _notes.where((n) => !n.isDeleted && n.isFavorite).toList();

  /// Get recently edited notes
  List<Note> get recentNotes {
    final sorted = _notes.where((n) => !n.isDeleted).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sorted.take(10).toList();
  }

  /// Get notes with unsynced changes that are eligible for cloud sync.
  List<Note> get dirtyNotes =>
      _notes.where((n) => n.isDirty && !n.localOnly).toList();

  /// Search notes by title and content
  List<Note> searchNotes(String query) {
    final lowerQuery = query.toLowerCase();
    return _notes
        .where(
          (n) =>
              !n.isDeleted &&
              (n.title.toLowerCase().contains(lowerQuery) ||
                  n.content.toLowerCase().contains(lowerQuery)),
        )
        .toList();
  }

  /// Get notes by tag
  List<Note> getNotesByTag(String tagId) {
    return _notes.where((n) => !n.isDeleted && n.tags.contains(tagId)).toList();
  }

  // ===========================================
  // INITIALIZATION
  // ===========================================

  /// Initialize the provider and load local data
  Future<void> initialize(String userId) async {
    _isLoading = true;
    // Defer notifyListeners to avoid calling during build
    Future.microtask(() => notifyListeners());

    try {
      final boxName = 'notes_$userId';
      // Open Hive box for notes
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(NoteAdapter());
      }
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(NoteTypeAdapter());
      }

      if (_activeUserId != null &&
          _activeUserId != userId &&
          _notesBox != null &&
          _notesBox!.isOpen) {
        _diagnostics.info(
          'NotesProvider',
          'HIVE_BOX closing notes box for previous workspace=$_activeUserId',
        );
        await _notesBox!.close();
      }

      _diagnostics.info(
        'NotesProvider',
        'HIVE_BOX opening notes box name=$boxName requestedType=Note alreadyOpen=${Hive.isBoxOpen(boxName)}',
      );
      _notesBox = await Hive.openBox<Note>(boxName);
      _activeUserId = userId;
      _notes = _notesBox!.values.toList();
      _diagnostics.info(
        'NotesProvider',
        'WORKSPACE_FLOW notes initialized workspace=$userId boxType=${_notesBox.runtimeType} noteCount=${_notes.length}',
      );

      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to load notes';
      debugPrint('Notes initialization error: $e');
      _diagnostics.error(
        'NotesProvider',
        'HIVE_BOX failed to initialize notes workspace=$userId error=$e',
      );
    }

    _isLoading = false;
    Future.microtask(() => notifyListeners());
  }

  /// Set sync service reference (null to disable sync)
  void setSyncService(SyncService? service) {
    _syncSubscription?.cancel();
    _syncService = service;

    if (service != null) {
      _syncSubscription = service.syncTriggerStream.listen((_) async {
        final dirty = dirtyNotes;
        if (dirty.isNotEmpty) {
          debugPrint('NotesProvider: Syncing ${dirty.length} dirty notes');
          final success =
              await service.syncDirtyItems(dirtyNotes: dirty, dirtyFolders: []);
          if (success) {
            debugPrint(
              'NotesProvider: Sync successful, clearing dirty flags',
            );
            _clearDirtyFlags(dirty);
          }
        }
      });
    }
  }

  // ===========================================
  // CRUD OPERATIONS
  // ===========================================

  /// Create a new note
  Future<Note?> createNote({
    required String userId,
    String title = 'No name',
    String content = emptyDocumentJson,
    String? folderId,
    NoteType type = NoteType.text,
    int? size,
    bool localOnly = false,
  }) async {
    try {
      final note = Note.create(
        id: _uuid.v4(),
        userId: userId,
        title: title,
        content: content,
        folderId: folderId,
        type: type,
      ).copyWith(
        size: size ?? (type == NoteType.pdf ? 0 : 1),
        localOnly: localOnly,
      );

      // Save locally
      await _notesBox?.put(note.id, note);
      _notes.add(note);

      // Trigger sync
      _syncService?.syncNote(note);

      notifyListeners();
      return note;
    } catch (e) {
      _errorMessage = 'Failed to create note';
      notifyListeners();
      return null;
    }
  }

  /// Update an existing note
  Future<bool> updateNote(Note note) async {
    try {
      // Don't call copyWith again - the note passed in already has all updates
      final updatedNote = note.copyWith(
        updatedAt: DateTime.now(),
        isDirty: true,
      );

      debugPrint(
        'updateNote: Updating note ${note.id}, backgroundColor: ${updatedNote.backgroundColor}',
      );

      // Update locally
      await _notesBox?.put(updatedNote.id, updatedNote);

      final index = _notes.indexWhere((n) => n.id == note.id);
      if (index >= 0) {
        _notes[index] = updatedNote;
        debugPrint(
          'updateNote: Updated note at index $index, new backgroundColor: ${_notes[index].backgroundColor}',
        );
      } else {
        debugPrint('updateNote: Note ${note.id} not found in list');
      }

      // Trigger sync
      _syncService?.syncNote(updatedNote);

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('updateNote error: $e');
      _errorMessage = 'Failed to update note';
      notifyListeners();
      return false;
    }
  }

  /// Update note content (optimized for live editing)
  Future<void> updateNoteContent({
    required String noteId,
    required String content,
    required int characterCount,
    required int lineCount,
  }) async {
    final index = _notes.indexWhere((n) => n.id == noteId);
    if (index < 0) return;

    final updatedNote = _notes[index].copyWith(
      content: content,
      characterCount: characterCount,
      lineCount: lineCount,
      size: content.length,
      updatedAt: DateTime.now(),
      isDirty: true,
    );

    _notes[index] = updatedNote;
    await _notesBox?.put(noteId, updatedNote);

    // Trigger cloud sync only for syncable notes.
    if (!updatedNote.localOnly) {
      _syncService?.triggerSync();
    }

    notifyListeners();
  }

  /// Delete a note (soft delete)
  Future<bool> deleteNote(String noteId) async {
    try {
      final index = _notes.indexWhere((n) => n.id == noteId);
      if (index < 0) return false;

      final deletedNote = _notes[index].copyWith(
        isDeleted: true,
        updatedAt: DateTime.now(),
        isDirty: true,
      );

      _notes[index] = deletedNote;
      await _notesBox?.put(noteId, deletedNote);

      // Sync deletion
      _syncService?.deleteNote(noteId);

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to delete note';
      notifyListeners();
      return false;
    }
  }

  /// Toggle favorite status
  Future<void> toggleFavorite(String noteId) async {
    final index = _notes.indexWhere((n) => n.id == noteId);
    if (index < 0) return;

    final note = _notes[index];
    await updateNote(note.copyWith(isFavorite: !note.isFavorite));
  }

  /// Move note to a folder
  Future<void> moveToFolder(String noteId, String? folderId) async {
    final index = _notes.indexWhere((n) => n.id == noteId);
    if (index < 0) return;

    final note = _notes[index];
    await updateNote(note.copyWith(folderId: folderId));
  }

  /// Add tag to note
  Future<void> addTag(String noteId, String tagId) async {
    final index = _notes.indexWhere((n) => n.id == noteId);
    if (index < 0) return;

    final note = _notes[index];
    if (note.tags.contains(tagId)) return;

    await updateNote(note.copyWith(tags: [...note.tags, tagId]));
  }

  /// Remove tag from note
  Future<void> removeTag(String noteId, String tagId) async {
    final index = _notes.indexWhere((n) => n.id == noteId);
    if (index < 0) return;

    final note = _notes[index];
    await updateNote(
      note.copyWith(
        tags: note.tags.where((t) => t != tagId).toList(),
      ),
    );
  }

  /// Set note background color
  Future<void> setBackgroundColor(String noteId, String? color) async {
    final index = _notes.indexWhere((n) => n.id == noteId);
    if (index < 0) {
      debugPrint('setBackgroundColor: Note $noteId not found');
      return;
    }

    final note = _notes[index];
    final updatedNote =
        note.copyWith(backgroundColor: color, backgroundColorSet: true);
    debugPrint(
      'setBackgroundColor: Updating note ${note.id} from ${note.backgroundColor} to $color',
    );
    final success = await updateNote(updatedNote);
    if (success) {
      // Verify the update
      final verifyIndex = _notes.indexWhere((n) => n.id == noteId);
      if (verifyIndex >= 0) {
        debugPrint(
          'setBackgroundColor: Verified update - note backgroundColor is now ${_notes[verifyIndex].backgroundColor}',
        );
      }
    } else {
      debugPrint('setBackgroundColor: Update failed');
    }
  }

  // ===========================================
  // SYNC OPERATIONS
  // ===========================================

  /// Handle notes updated from cloud
  void handleCloudUpdate(List<Note> cloudNotes) {
    final cloudIds = cloudNotes.map((note) => note.id).toSet();
    final localVisibleCount = _notes
        .where((note) => !note.isDeleted && note.userId == _activeUserId)
        .length;

    _diagnostics.info(
      'NotesProvider',
      'SYNC_LIFECYCLE applying cloud notes workspace=$_activeUserId cloudCount=${cloudNotes.length} localVisibleBefore=$localVisibleCount',
    );

    for (final cloudNote in cloudNotes) {
      final localIndex = _notes.indexWhere((n) => n.id == cloudNote.id);

      if (localIndex >= 0) {
        final localNote = _notes[localIndex];

        // Local-only notes intentionally do not accept cloud writes.
        if (localNote.localOnly) {
          continue;
        }

        if (localNote.isDirty &&
            cloudNote.updatedAt.isAfter(localNote.updatedAt) &&
            localNote.content != cloudNote.content) {
          // Conflict detected!
          // We keep our local changes as the main content but flag it and save cloud content
          final conflictedNote = localNote.copyWith(
            hasConflict: true,
            conflictContent: cloudNote.content,
          );
          _notes[localIndex] = conflictedNote;
          _notesBox?.put(cloudNote.id, conflictedNote);
          debugPrint(
            'NotesProvider: Conflict detected for note ${localNote.id}',
          );
        } else if (!localNote.isDirty ||
            cloudNote.updatedAt.isAfter(localNote.updatedAt)) {
          // Cloud wins if local isn't dirty, or if cloud is newer (and wasn't dirty, or content matched)
          // Also, if local WAS dirty but the incoming cloud update is newer and NO conflict arose
          // (e.g., contents match, or we just want to overwrite because we weren't dirty), we take cloud.
          final updatedNote = cloudNote.copyWith(
            hasConflict: false,
            clearConflictContent: true,
          );
          _notes[localIndex] = updatedNote;
          _notesBox?.put(cloudNote.id, updatedNote);
        }
      } else {
        // New note from cloud
        _notes.add(cloudNote);
        _notesBox?.put(cloudNote.id, cloudNote);
      }
    }

    if (cloudNotes.isEmpty && localVisibleCount > 0) {
      _diagnostics.warning(
        'NotesProvider',
        'SYNC_LIFECYCLE skipping empty cloud prune workspace=$_activeUserId localVisibleBefore=$localVisibleCount',
      );
      notifyListeners();
      return;
    }

    final staleNoteIds = _notes
        .where(
          (note) =>
              note.userId == _activeUserId &&
              !note.localOnly &&
              !note.isDirty &&
              !note.isDeleted &&
              !cloudIds.contains(note.id),
        )
        .map((note) => note.id)
        .toList();

    if (staleNoteIds.isNotEmpty) {
      _notes.removeWhere((note) => staleNoteIds.contains(note.id));
      for (final noteId in staleNoteIds) {
        _notesBox?.delete(noteId);
      }
      _diagnostics.warning(
        'NotesProvider',
        'SYNC_LIFECYCLE pruned stale notes workspace=$_activeUserId prunedCount=${staleNoteIds.length}',
      );
    }

    _diagnostics.info(
      'NotesProvider',
      'SYNC_LIFECYCLE cloud notes applied workspace=$_activeUserId visibleAfter=${notes.length}',
    );
    notifyListeners();
  }

  /// Resolves a merge conflict for a given note
  /// [strategy] can be 'local', 'cloud', or 'merge'
  Future<void> resolveConflict(String noteId, String strategy) async {
    final index = _notes.indexWhere((n) => n.id == noteId);
    if (index < 0) return;

    final note = _notes[index];
    if (!note.hasConflict) return;

    String resolvedContent = note.content;

    switch (strategy) {
      case 'local':
        resolvedContent = note.content;
        break;
      case 'cloud':
        resolvedContent = note.conflictContent ?? note.content;
        break;
      case 'merge':
        // For text or markdown, we append them.
        // For Delta JSON (Flutter Quill), simple string append breaks the JSON format.
        // For now, we will try to parse Delta, append a divider, and append the cloud Delta.
        try {
          final localDelta =
              List<dynamic>.from(jsonDecode(note.content) as Iterable<dynamic>);
          final cloudDelta = note.conflictContent != null
              ? List<dynamic>.from(
                  jsonDecode(note.conflictContent!) as Iterable<dynamic>,
                )
              : [];

          final mergedDelta = [
            ...localDelta,
            {'insert': '\n\n=== CLOUD VERSION ===\n\n'},
            ...cloudDelta,
          ];
          resolvedContent = jsonEncode(mergedDelta);
        } catch (e) {
          // Fallback if not valid JSON (e.g. plain text or older format)
          resolvedContent =
              '${note.content}\n\n=== CLOUD VERSION ===\n\n${note.conflictContent ?? ""}';
        }
        break;
    }

    // Update the note with the resolved content and clear conflict flags
    final resolvedNote = note.copyWith(
      content: resolvedContent,
      hasConflict: false,
      clearConflictContent: true,
      updatedAt: DateTime.now(),
      isDirty: true, // Needs to be synced back to cloud
    );

    _notes[index] = resolvedNote;
    await _notesBox?.put(noteId, resolvedNote);

    // Trigger sync
    _syncService?.triggerSync();

    notifyListeners();
  }

  /// Clear dirty flags for a list of notes
  void _clearDirtyFlags(List<Note> notesToClear) {
    for (final note in notesToClear) {
      final index = _notes.indexWhere((n) => n.id == note.id);
      if (index >= 0) {
        final cleanedNote = _notes[index].copyWith(isDirty: false);
        _notes[index] = cleanedNote;
        _notesBox?.put(cleanedNote.id, cleanedNote);
      }
    }
    notifyListeners();
  }

  /// Get a note by ID
  Note? getNoteById(String id) {
    try {
      return _notes.firstWhere((n) => n.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Clone all local notes from one workspace box to another.
  ///
  /// Returns number of notes copied.
  Future<int> cloneWorkspace({
    required String sourceUserId,
    required String targetUserId,
    bool overwriteTarget = false,
  }) async {
    if (sourceUserId == targetUserId) return 0;

    final sourceBoxName = 'notes_$sourceUserId';
    final targetBoxName = 'notes_$targetUserId';
    final sourceBoxResult = await _openCloneBox(sourceBoxName, sourceUserId);
    final targetBoxResult = await _openCloneBox(targetBoxName, targetUserId);
    final sourceBox = sourceBoxResult.box;
    final targetBox = targetBoxResult.box;

    try {
      if (overwriteTarget) {
        await targetBox.clear();
      }

      var copied = 0;
      var skipped = 0;
      final sourceValues =
          List<Note>.from((sourceBox.values as Iterable).whereType<Note>());
      final targetCountBefore =
          (targetBox.values as Iterable).whereType<Note>().length;

      for (final note in sourceValues) {
        if (!overwriteTarget && targetBox.containsKey(note.id) == true) {
          skipped++;
          continue;
        }

        final cloned = note.copyWith(
          userId: targetUserId,
          isDirty: true,
          syncedAt: null,
          pdfPath: _rewriteWorkspacePath(
            note.pdfPath,
            sourceUserId: sourceUserId,
            targetUserId: targetUserId,
          ),
          attachments: note.attachments
              .map(
                (attachment) => attachment.copyWith(
                  path: _rewriteWorkspacePath(
                        attachment.path,
                        sourceUserId: sourceUserId,
                        targetUserId: targetUserId,
                      ) ??
                      attachment.path,
                ),
              )
              .toList(),
        );
        await targetBox.put(cloned.id, cloned);
        copied++;
      }

      _diagnostics.info(
        'NotesProvider',
        'GUEST_IMPORT cloned notes source=$sourceUserId target=$targetUserId sourceCount=${sourceValues.length} targetCountBefore=$targetCountBefore copied=$copied skipped=$skipped targetCountAfter=${(targetBox.values as Iterable).whereType<Note>().length}',
      );

      return copied;
    } finally {
      if (!sourceBoxResult.wasOpen) {
        await sourceBox.close();
      }
      if (!targetBoxResult.wasOpen) {
        await targetBox.close();
      }
    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  String? _rewriteWorkspacePath(
    String? originalPath, {
    required String sourceUserId,
    required String targetUserId,
  }) {
    if (originalPath == null || originalPath.isEmpty) {
      return originalPath;
    }

    if (originalPath.startsWith('http://') ||
        originalPath.startsWith('https://') ||
        originalPath.startsWith('data:')) {
      return originalPath;
    }

    final sourceSegment = p.join('typesync_files', sourceUserId) + p.separator;
    final targetSegment = p.join('typesync_files', targetUserId) + p.separator;

    if (!originalPath.contains(sourceSegment)) {
      return originalPath;
    }

    return originalPath.replaceFirst(sourceSegment, targetSegment);
  }

  Future<void> closeWorkspace() async {
    _notes = [];
    _activeUserId = null;
    if (_notesBox != null && _notesBox!.isOpen) {
      await _notesBox!.close();
    }
    _notesBox = null;
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<_OpenedCloneBox> _openCloneBox(
    String boxName,
    String workspaceId,
  ) async {
    final wasOpen = Hive.isBoxOpen(boxName);
    if (wasOpen) {
      final box = Hive.box(boxName);
      _diagnostics.info(
        'NotesProvider',
        'HIVE_BOX reusing open notes box name=$boxName workspace=$workspaceId runtimeType=${box.runtimeType}',
      );
      return _OpenedCloneBox(box: box, wasOpen: true);
    }

    _diagnostics.info(
      'NotesProvider',
      'HIVE_BOX opening clone notes box name=$boxName workspace=$workspaceId requestedType=Note',
    );
    final box = await Hive.openBox<Note>(boxName);
    return _OpenedCloneBox(box: box, wasOpen: false);
  }
}

class _OpenedCloneBox {
  const _OpenedCloneBox({
    required this.box,
    required this.wasOpen,
  });

  final dynamic box;
  final bool wasOpen;
}

// Hive type adapter for Note
class NoteAdapter extends TypeAdapter<Note> {
  @override
  final int typeId = 0;

  @override
  Note read(BinaryReader reader) {
    final id = reader.readString();
    final title = reader.readString();
    final content = reader.readString();
    final type = NoteType.values[reader.readInt()];
    final folderIdRaw = reader.readString();
    final tags = reader.readStringList();
    final backgroundColorRaw = reader.readString();
    final createdAt = DateTime.parse(reader.readString());
    final updatedAt = DateTime.parse(reader.readString());
    final hasSyncedAt = reader.readBool();
    final syncedAtRaw = hasSyncedAt ? reader.readString() : null;
    final isDirty = reader.readBool();
    final isFavorite = reader.readBool();
    final isDeleted = reader.readBool();
    final characterCount = reader.readInt();
    final lineCount = reader.readInt();
    final userId = reader.readString();
    final pdfPathRaw = reader.readString();
    final hasConflict = reader.availableBytes > 0 ? reader.readBool() : false;
    final conflictContentRaw =
        reader.availableBytes > 0 ? reader.readString() : '';
    final size = reader.availableBytes > 0 ? reader.readInt() : 0;

    final attachments = <NoteAttachment>[];
    if (reader.availableBytes > 0) {
      final attachmentCount = reader.readInt();
      for (int i = 0; i < attachmentCount; i++) {
        final attachmentId = reader.readString();
        final attachmentName = reader.readString();
        final attachmentPath = reader.readString();
        final mimeTypeRaw = reader.readString();
        attachments.add(
          NoteAttachment(
            id: attachmentId,
            name: attachmentName,
            path: attachmentPath,
            mimeType: mimeTypeRaw.isEmpty ? null : mimeTypeRaw,
            size: reader.readInt(),
            addedAt: DateTime.parse(reader.readString()),
          ),
        );
      }
    }

    final localOnly = reader.availableBytes > 0 ? reader.readBool() : false;

    return Note(
      id: id,
      title: title,
      content: content,
      type: type,
      folderId: folderIdRaw.isEmpty ? null : folderIdRaw,
      tags: tags,
      backgroundColor: backgroundColorRaw.isEmpty ? null : backgroundColorRaw,
      createdAt: createdAt,
      updatedAt: updatedAt,
      syncedAt: syncedAtRaw != null ? DateTime.parse(syncedAtRaw) : null,
      isDirty: isDirty,
      isFavorite: isFavorite,
      isDeleted: isDeleted,
      characterCount: characterCount,
      lineCount: lineCount,
      userId: userId,
      pdfPath: pdfPathRaw.isEmpty ? null : pdfPathRaw,
      hasConflict: hasConflict,
      conflictContent: conflictContentRaw.isEmpty ? null : conflictContentRaw,
      size: size,
      attachments: attachments,
      localOnly: localOnly,
    );
  }

  @override
  void write(BinaryWriter writer, Note obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.title);
    writer.writeString(obj.content);
    writer.writeInt(obj.type.index);
    writer.writeString(obj.folderId ?? '');
    writer.writeStringList(obj.tags);
    writer.writeString(obj.backgroundColor ?? '');
    writer.writeString(obj.createdAt.toIso8601String());
    writer.writeString(obj.updatedAt.toIso8601String());
    writer.writeBool(obj.syncedAt != null);
    if (obj.syncedAt != null) {
      writer.writeString(obj.syncedAt!.toIso8601String());
    }
    writer.writeBool(obj.isDirty);
    writer.writeBool(obj.isFavorite);
    writer.writeBool(obj.isDeleted);
    writer.writeInt(obj.characterCount);
    writer.writeInt(obj.lineCount);
    writer.writeString(obj.userId);
    writer.writeString(obj.pdfPath ?? '');
    writer.writeBool(obj.hasConflict);
    writer.writeString(obj.conflictContent ?? '');
    writer.writeInt(obj.size);
    writer.writeInt(obj.attachments.length);
    for (final attachment in obj.attachments) {
      writer.writeString(attachment.id);
      writer.writeString(attachment.name);
      writer.writeString(attachment.path);
      writer.writeString(attachment.mimeType ?? '');
      writer.writeInt(attachment.size);
      writer.writeString(attachment.addedAt.toIso8601String());
    }
    writer.writeBool(obj.localOnly);
  }
}

// Hive type adapter for NoteType
class NoteTypeAdapter extends TypeAdapter<NoteType> {
  @override
  final int typeId = 1;

  @override
  NoteType read(BinaryReader reader) {
    return NoteType.values[reader.readInt()];
  }

  @override
  void write(BinaryWriter writer, NoteType obj) {
    writer.writeInt(obj.index);
  }
}
