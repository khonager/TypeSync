/// Notes Provider
/// 
/// State management for notes including CRUD operations,
/// filtering, and sync status tracking.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/note.dart';
import '../services/sync_service.dart';

/// Provider for managing note state
/// 
/// Handles local storage with Hive and coordinates with
/// SyncService for cloud synchronization.
class NotesProvider extends ChangeNotifier {
  // Local storage box
  Box<Note>? _notesBox;
  
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

  // ===========================================
  // GETTERS
  // ===========================================
  
  List<Note> get notes => _notes.where((n) => !n.isDeleted).toList();
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  
  /// Get notes for a specific folder
  List<Note> getNotesInFolder(String? folderId) {
    return _notes
        .where((n) => !n.isDeleted && n.folderId == folderId)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }
  
  /// Get favorite notes
  List<Note> get favoriteNotes => _notes
      .where((n) => !n.isDeleted && n.isFavorite)
      .toList();
  
  /// Get recently edited notes
  List<Note> get recentNotes {
    final sorted = _notes
        .where((n) => !n.isDeleted)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sorted.take(10).toList();
  }
  
  /// Get notes with unsynced changes
  List<Note> get dirtyNotes => _notes.where((n) => n.isDirty).toList();
  
  /// Search notes by title and content
  List<Note> searchNotes(String query) {
    final lowerQuery = query.toLowerCase();
    return _notes
        .where((n) => !n.isDeleted && (
            n.title.toLowerCase().contains(lowerQuery) ||
            n.content.toLowerCase().contains(lowerQuery)
        ))
        .toList();
  }
  
  /// Get notes by tag
  List<Note> getNotesByTag(String tagId) {
    return _notes
        .where((n) => !n.isDeleted && n.tags.contains(tagId))
        .toList();
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
      // Open Hive box for notes
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(NoteAdapter());
      }
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(NoteTypeAdapter());
      }
      
      _notesBox = await Hive.openBox<Note>('notes_$userId');
      _notes = _notesBox!.values.toList();
      
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to load notes';
      debugPrint('Notes initialization error: $e');
    }
    
    _isLoading = false;
    Future.microtask(() => notifyListeners());
  }

  /// Set sync service reference (null to disable sync)
  void setSyncService(SyncService? service) {
    _syncService = service;
  }

  // ===========================================
  // CRUD OPERATIONS
  // ===========================================
  
  /// Create a new note
  Future<Note?> createNote({
    required String userId,
    String title = 'No name',
    String content = '',
    String? folderId,
    NoteType type = NoteType.text,
  }) async {
    try {
      final note = Note.create(
        id: _uuid.v4(),
        userId: userId,
        title: title,
        content: content,
        folderId: folderId,
        type: type,
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
      
      debugPrint('updateNote: Updating note ${note.id}, backgroundColor: ${updatedNote.backgroundColor}');
      
      // Update locally
      await _notesBox?.put(updatedNote.id, updatedNote);
      
      final index = _notes.indexWhere((n) => n.id == note.id);
      if (index >= 0) {
        _notes[index] = updatedNote;
        debugPrint('updateNote: Updated note at index $index, new backgroundColor: ${_notes[index].backgroundColor}');
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
      updatedAt: DateTime.now(),
      isDirty: true,
    );
    
    _notes[index] = updatedNote;
    await _notesBox?.put(noteId, updatedNote);
    
    // Trigger sync (debounced in sync service)
    _syncService?.triggerSync();
    
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
    await updateNote(note.copyWith(
      tags: note.tags.where((t) => t != tagId).toList(),
    ));
  }

  /// Set note background color
  Future<void> setBackgroundColor(String noteId, String? color) async {
    final index = _notes.indexWhere((n) => n.id == noteId);
    if (index < 0) {
      debugPrint('setBackgroundColor: Note $noteId not found');
      return;
    }
    
    final note = _notes[index];
    final updatedNote = note.copyWith(backgroundColor: color, backgroundColorSet: true);
    debugPrint('setBackgroundColor: Updating note ${note.id} from ${note.backgroundColor} to $color');
    final success = await updateNote(updatedNote);
    if (success) {
      // Verify the update
      final verifyIndex = _notes.indexWhere((n) => n.id == noteId);
      if (verifyIndex >= 0) {
        debugPrint('setBackgroundColor: Verified update - note backgroundColor is now ${_notes[verifyIndex].backgroundColor}');
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
    for (final cloudNote in cloudNotes) {
      final localIndex = _notes.indexWhere((n) => n.id == cloudNote.id);
      
      if (localIndex >= 0) {
        final localNote = _notes[localIndex];
        
        // Cloud wins if local isn't dirty, or if cloud is newer
        if (!localNote.isDirty || cloudNote.updatedAt.isAfter(localNote.updatedAt)) {
          _notes[localIndex] = cloudNote;
          _notesBox?.put(cloudNote.id, cloudNote);
        }
      } else {
        // New note from cloud
        _notes.add(cloudNote);
        _notesBox?.put(cloudNote.id, cloudNote);
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

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}

// Hive type adapter for Note
class NoteAdapter extends TypeAdapter<Note> {
  @override
  final int typeId = 0;

  @override
  Note read(BinaryReader reader) {
    return Note(
      id: reader.readString(),
      title: reader.readString(),
      content: reader.readString(),
      type: NoteType.values[reader.readInt()],
      folderId: reader.readString(),
      tags: reader.readStringList(),
      backgroundColor: reader.readString(),
      createdAt: DateTime.parse(reader.readString()),
      updatedAt: DateTime.parse(reader.readString()),
      syncedAt: reader.readBool() ? DateTime.parse(reader.readString()) : null,
      isDirty: reader.readBool(),
      isFavorite: reader.readBool(),
      isDeleted: reader.readBool(),
      characterCount: reader.readInt(),
      lineCount: reader.readInt(),
      userId: reader.readString(),
      pdfPath: reader.readString(),
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



