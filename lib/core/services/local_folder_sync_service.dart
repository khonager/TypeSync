/// Local Folder Sync Service
///
/// Manages synchronization between a local folder on disk and the app's data.
/// Handles conflict resolution when files differ between local and cloud storage.

import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

import '../utils/file_picker_helper.dart';

import '../models/note.dart';
import '../models/folder.dart';
import '../providers/notes_provider.dart';
import '../providers/folders_provider.dart';
import 'local_file_service.dart';

/// Conflict resolution choice
enum ConflictResolution {
  useLocal,
  useCloud,
  keepBoth,
  skip,
}

/// Conflict information
class ConflictInfo {
  final String itemId;
  final String itemName;
  final DateTime localModified;
  final DateTime cloudModified;
  final bool isNote;

  ConflictInfo({
    required this.itemId,
    required this.itemName,
    required this.localModified,
    required this.cloudModified,
    required this.isNote,
  });
}

/// Service for syncing with a local folder
class LocalFolderSyncService extends ChangeNotifier {
  Directory? _syncFolder;
  bool _isSyncing = false;
  String? _errorMessage;
  List<ConflictInfo> _conflicts = [];
  bool _isInitialized = false;

  // Callbacks for conflict resolution UI
  Function(List<ConflictInfo>)? onConflictsDetected;
  Function(ConflictInfo, ConflictResolution)? onConflictResolved;

  // ===========================================
  // GETTERS
  // ===========================================

  Directory? get syncFolder => _syncFolder;
  bool get isSyncing => _isSyncing;
  String? get errorMessage => _errorMessage;
  List<ConflictInfo> get conflicts => _conflicts;
  bool get isInitialized => _isInitialized;

  // ===========================================
  // INITIALIZATION
  // ===========================================

  /// Set the sync folder path
  Future<bool> setSyncFolder(String folderPath) async {
    try {
      final dir = Directory(folderPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _syncFolder = dir;
      _isInitialized = true;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to set sync folder: $e';
      notifyListeners();
      return false;
    }
  }

  /// Choose sync folder using file picker
  ///
  /// [context] is required for the file browser dialog
  Future<bool> chooseSyncFolder({required BuildContext context}) async {
    try {
      // Use helper with file browser fallback
      final directory = await FilePickerHelper.pickDirectory(
        context: context,
        dialogTitle: 'Choose folder to sync with',
      );

      if (directory != null) {
        return await setSyncFolder(directory);
      }

      return false;
    } catch (e) {
      _errorMessage = 'Failed to choose sync folder: $e';
      notifyListeners();
      return false;
    }
  }

  // ===========================================
  // SYNC OPERATIONS
  // ===========================================

  /// Perform a full sync between local folder and app data
  Future<void> sync({
    required NotesProvider notesProvider,
    required FoldersProvider foldersProvider,
    required String userId,
  }) async {
    if (_syncFolder == null || !_isInitialized) {
      _errorMessage = 'Sync folder not set';
      notifyListeners();
      return;
    }

    _isSyncing = true;
    _errorMessage = null;
    _conflicts.clear();
    notifyListeners();

    try {
      // Initialize local file service
      await LocalFileService.instance.initialize(userId);

      // Scan local folder for files
      final localFiles = await _scanLocalFolder();

      // Get app data
      final appNotes = notesProvider.notes;
      final appFolders = foldersProvider.folders;

      // Detect conflicts
      await _detectConflicts(
        localFiles: localFiles,
        appNotes: appNotes,
        appFolders: appFolders,
      );

      // If conflicts detected, notify UI
      if (_conflicts.isNotEmpty && onConflictsDetected != null) {
        onConflictsDetected!(_conflicts);
        // Wait for conflicts to be resolved
        // The UI should call resolveConflict for each conflict
        return;
      }

      // Perform sync
      await _performSync(
        localFiles: localFiles,
        notesProvider: notesProvider,
        foldersProvider: foldersProvider,
        userId: userId,
      );

      _isSyncing = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Sync failed: $e';
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Resolve a conflict
  Future<void> resolveConflict(
    ConflictInfo conflict,
    ConflictResolution resolution, {
    required NotesProvider notesProvider,
    required FoldersProvider foldersProvider,
    required String userId,
  }) async {
    try {
      if (conflict.isNote) {
        await _resolveNoteConflict(
          conflict,
          resolution,
          notesProvider: notesProvider,
          userId: userId,
        );
      } else {
        await _resolveFolderConflict(
          conflict,
          resolution,
          foldersProvider: foldersProvider,
        );
      }

      _conflicts.removeWhere((c) => c.itemId == conflict.itemId);
      if (onConflictResolved != null) {
        onConflictResolved!(conflict, resolution);
      }
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to resolve conflict: $e';
      notifyListeners();
    }
  }

  // ===========================================
  // PRIVATE METHODS
  // ===========================================

  /// Scan local folder for files
  Future<Map<String, FileSystemEntity>> _scanLocalFolder() async {
    final files = <String, FileSystemEntity>{};

    if (_syncFolder == null) return files;

    try {
      await for (final entity in _syncFolder!.list(recursive: true)) {
        if (entity is File) {
          final relativePath =
              path.relative(entity.path, from: _syncFolder!.path);
          files[relativePath] = entity;
        }
      }
    } catch (e) {
      debugPrint('Error scanning local folder: $e');
    }

    return files;
  }

  /// Detect conflicts between local folder and app data
  Future<void> _detectConflicts({
    required Map<String, FileSystemEntity> localFiles,
    required List<Note> appNotes,
    required List<Folder> appFolders,
  }) async {
    _conflicts.clear();

    // Check notes for conflicts
    for (final note in appNotes) {
      final localPath = _getLocalPathForNote(note);
      final localFile = localFiles[localPath];

      if (localFile != null && localFile is File) {
        final localModified = await localFile.lastModified();
        final cloudModified = note.updatedAt;

        // If both exist and modified times differ significantly, it's a conflict
        if (localModified.difference(cloudModified).abs().inMinutes > 1) {
          _conflicts.add(ConflictInfo(
            itemId: note.id,
            itemName: note.title,
            localModified: localModified,
            cloudModified: cloudModified,
            isNote: true,
          ));
        }
      }
    }

    // Check folders for conflicts (simplified - just check if folder exists)
    for (final folder in appFolders) {
      final localPath = _getLocalPathForFolder(folder);
      final localDir = Directory(path.join(_syncFolder!.path, localPath));

      if (await localDir.exists()) {
        // Get directory modification time using stat
        final stat = await localDir.stat();
        final localModified = stat.modified;
        final cloudModified = folder.updatedAt;

        if (localModified.difference(cloudModified).abs().inMinutes > 1) {
          _conflicts.add(ConflictInfo(
            itemId: folder.id,
            itemName: folder.name,
            localModified: localModified,
            cloudModified: cloudModified,
            isNote: false,
          ));
        }
      }
    }
  }

  /// Perform the actual sync
  Future<void> _performSync({
    required Map<String, FileSystemEntity> localFiles,
    required NotesProvider notesProvider,
    required FoldersProvider foldersProvider,
    required String userId,
  }) async {
    // Import files from local folder that don't exist in app
    for (final entry in localFiles.entries) {
      final file = entry.value;
      if (file is! File) continue;

      final fileName = path.basename(file.path);
      final fileExtension = path.extension(fileName).toLowerCase();

      // Check if note already exists
      final noteTitle = fileName.replaceAll(fileExtension, '');
      bool noteExists = false;
      try {
        notesProvider.notes.firstWhere(
          (n) => n.title == noteTitle,
        );
        noteExists = true;
      } catch (e) {
        // Note doesn't exist
        noteExists = false;
      }

      if (!noteExists) {
        // Import new file
        await _importLocalFile(file, notesProvider, userId);
      }
    }

    // Export app notes that don't exist in local folder
    for (final note in notesProvider.notes) {
      final localPath = _getLocalPathForNote(note);
      final localFile = File(path.join(_syncFolder!.path, localPath));

      if (!await localFile.exists()) {
        await _exportNoteToLocal(note, localFile);
      }
    }
  }

  /// Import a local file into the app
  Future<void> _importLocalFile(
    File file,
    NotesProvider notesProvider,
    String userId,
  ) async {
    try {
      final fileName = path.basename(file.path);
      final fileExtension = path.extension(fileName).toLowerCase();

      if (fileExtension == '.pdf') {
        // Import PDF
        final storedPath = await LocalFileService.instance.copyFileToStorage(
          file.path,
          fileName: fileName,
        );

        if (storedPath != null) {
          await notesProvider
              .createNote(
            userId: userId,
            title: fileName.replaceAll('.pdf', ''),
            content: '',
            type: NoteType.pdf,
          )
              .then((note) {
            if (note != null) {
              notesProvider.updateNote(note.copyWith(pdfPath: storedPath));
            }
          });
        }
      } else if (fileExtension == '.md' || fileExtension == '.markdown') {
        // Import markdown
        final content = await file.readAsString();
        await notesProvider.createNote(
          userId: userId,
          title: fileName.replaceAll(fileExtension, ''),
          content: content,
          type: NoteType.markdown,
        );
      } else if (fileExtension == '.txt') {
        // Import text
        final content = await file.readAsString();
        await notesProvider.createNote(
          userId: userId,
          title: fileName.replaceAll('.txt', ''),
          content: content,
          type: NoteType.text,
        );
      }
    } catch (e) {
      debugPrint('Failed to import local file ${file.path}: $e');
    }
  }

  /// Export a note to local folder
  Future<void> _exportNoteToLocal(Note note, File localFile) async {
    try {
      // Ensure parent directory exists
      await localFile.parent.create(recursive: true);

      if (note.type == NoteType.pdf && note.pdfPath != null) {
        // Copy PDF file
        final pdfFile = File(note.pdfPath!);
        if (await pdfFile.exists()) {
          await pdfFile.copy(localFile.path);
        }
      } else {
        // Export as text/markdown
        String content = note.content;
        String extension = '.txt';

        if (note.type == NoteType.markdown) {
          extension = '.md';
        } else {
          // Convert Quill Delta to plain text
          try {
            final jsonData = jsonDecode(note.content) as List<dynamic>;
            // For now, just use plain text - would need Document import
            content = note.content;
          } catch (e) {
            content = note.content;
          }
        }

        final fileName = '${note.title}$extension';
        final filePath = path.join(localFile.parent.path, fileName);
        await File(filePath).writeAsString(content);
      }
    } catch (e) {
      debugPrint('Failed to export note to local: $e');
    }
  }

  /// Resolve a note conflict
  Future<void> _resolveNoteConflict(
    ConflictInfo conflict,
    ConflictResolution resolution, {
    required NotesProvider notesProvider,
    required String userId,
  }) async {
    final note = notesProvider.getNoteById(conflict.itemId);
    if (note == null) return;

    final localPath = _getLocalPathForNote(note);
    final localFile = File(path.join(_syncFolder!.path, localPath));

    switch (resolution) {
      case ConflictResolution.useLocal:
        // Import local file, overwriting app version
        if (await localFile.exists()) {
          await _importLocalFile(localFile, notesProvider, userId);
        }
        break;
      case ConflictResolution.useCloud:
        // Export app version, overwriting local file
        await _exportNoteToLocal(note, localFile);
        break;
      case ConflictResolution.keepBoth:
        // Keep both - rename local file
        final renamedPath =
            '${localPath}_local_${DateTime.now().millisecondsSinceEpoch}';
        final renamedFile = File(path.join(_syncFolder!.path, renamedPath));
        await localFile.copy(renamedFile.path);
        // Also export app version
        await _exportNoteToLocal(note, localFile);
        break;
      case ConflictResolution.skip:
        // Do nothing
        break;
    }
  }

  /// Resolve a folder conflict
  Future<void> _resolveFolderConflict(
    ConflictInfo conflict,
    ConflictResolution resolution, {
    required FoldersProvider foldersProvider,
  }) async {
    final folder = foldersProvider.getFolderById(conflict.itemId);
    if (folder == null) return;

    final localPath = _getLocalPathForFolder(folder);
    final localDir = Directory(path.join(_syncFolder!.path, localPath));

    switch (resolution) {
      case ConflictResolution.useLocal:
        // Use local folder structure (simplified - just update timestamps)
        if (await localDir.exists()) {
          // Could update folder metadata here
        }
        break;
      case ConflictResolution.useCloud:
        // Use cloud folder structure
        if (!await localDir.exists()) {
          await localDir.create(recursive: true);
        }
        break;
      case ConflictResolution.keepBoth:
        // Keep both - rename local folder
        final renamedPath =
            '${localPath}_local_${DateTime.now().millisecondsSinceEpoch}';
        final renamedDir = Directory(path.join(_syncFolder!.path, renamedPath));
        if (await localDir.exists()) {
          await localDir.rename(renamedDir.path);
        }
        await localDir.create(recursive: true);
        break;
      case ConflictResolution.skip:
        // Do nothing
        break;
    }
  }

  /// Get local path for a note
  String _getLocalPathForNote(Note note) {
    String fileName = note.title;
    if (note.type == NoteType.pdf) {
      fileName = '$fileName.pdf';
    } else if (note.type == NoteType.markdown) {
      fileName = '$fileName.md';
    } else {
      fileName = '$fileName.txt';
    }
    return fileName;
  }

  /// Get local path for a folder
  String _getLocalPathForFolder(Folder folder) {
    // Simplified - just use folder name
    // In a full implementation, would build full path from parent folders
    return folder.name;
  }
}
