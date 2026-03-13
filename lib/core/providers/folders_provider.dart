/// Folders Provider
///
/// State management for folders including CRUD operations
/// and hierarchical structure management.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/folder.dart';
import '../services/sync_service.dart';

/// Provider for managing folder state
class FoldersProvider extends ChangeNotifier {
  // Local storage box
  Box<Folder>? _foldersBox;
  String? _activeUserId;

  // In-memory folders list
  List<Folder> _folders = [];

  // Loading state
  bool _isLoading = false;

  // Error state
  String? _errorMessage;

  // UUID generator
  final Uuid _uuid = const Uuid();

  // Sync service reference
  SyncService? _syncService;
  StreamSubscription<void>? _syncSubscription;

  // ===========================================
  // GETTERS
  // ===========================================

  List<Folder> get folders => _folders.where((f) => !f.isDeleted).toList();
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Get root level folders (no parent)
  List<Folder> get rootFolders =>
      _folders.where((f) => !f.isDeleted && f.parentId == null).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// Get subfolders of a parent folder
  List<Folder> getSubfolders(String parentId) {
    return _folders
        .where((f) => !f.isDeleted && f.parentId == parentId)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  /// Get folder by ID
  Folder? getFolderById(String id) {
    try {
      return _folders.firstWhere((f) => f.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Get folder path (breadcrumb)
  List<Folder> getFolderPath(String? folderId) {
    if (folderId == null) return [];

    final path = <Folder>[];
    String? currentId = folderId;

    while (currentId != null) {
      final folder = getFolderById(currentId);
      if (folder != null) {
        path.insert(0, folder);
        currentId = folder.parentId;
      } else {
        break;
      }
    }

    return path;
  }

  /// Get dirty folders for sync
  List<Folder> get dirtyFolders => _folders.where((f) => f.isDirty).toList();

  // ===========================================
  // INITIALIZATION
  // ===========================================

  /// Initialize the provider
  Future<void> initialize(String userId) async {
    _isLoading = true;
    // Defer notifyListeners to avoid calling during build
    Future.microtask(() => notifyListeners());

    try {
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(FolderAdapter());
      }

      if (_activeUserId != null &&
          _activeUserId != userId &&
          _foldersBox != null &&
          _foldersBox!.isOpen) {
        await _foldersBox!.close();
      }

      _foldersBox = await Hive.openBox<Folder>('folders_$userId');
      _activeUserId = userId;
      _folders = _foldersBox!.values.toList();

      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to load folders';
      debugPrint('Folders initialization error: $e');
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
        final dirty = dirtyFolders;
        if (dirty.isNotEmpty) {
          debugPrint('FoldersProvider: Syncing ${dirty.length} dirty folders');
          final success =
              await service.syncDirtyItems(dirtyNotes: [], dirtyFolders: dirty);
          if (success) {
            debugPrint(
              'FoldersProvider: Sync successful, clearing dirty flags',
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

  /// Create a new folder
  Future<Folder?> createFolder({
    required String userId,
    required String name,
    String? subtitle,
    String? parentId,
    String? backgroundColor,
  }) async {
    try {
      final folder = Folder.create(
        id: _uuid.v4(),
        userId: userId,
        name: name,
        subtitle: subtitle,
        parentId: parentId,
      ).copyWith(backgroundColor: backgroundColor);

      await _foldersBox?.put(folder.id, folder);
      _folders.add(folder);

      _syncService?.syncFolder(folder);

      notifyListeners();
      return folder;
    } catch (e) {
      _errorMessage = 'Failed to create folder';
      notifyListeners();
      return null;
    }
  }

  /// Update a folder
  Future<bool> updateFolder(Folder folder) async {
    try {
      final updatedFolder = folder.copyWith(
        updatedAt: DateTime.now(),
        isDirty: true,
      );

      await _foldersBox?.put(updatedFolder.id, updatedFolder);

      final index = _folders.indexWhere((f) => f.id == folder.id);
      if (index >= 0) {
        _folders[index] = updatedFolder;
      }

      _syncService?.syncFolder(updatedFolder);

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to update folder';
      notifyListeners();
      return false;
    }
  }

  /// Rename a folder
  Future<bool> renameFolder(String folderId, String newName) async {
    final folder = getFolderById(folderId);
    if (folder == null) return false;

    return updateFolder(folder.copyWith(name: newName));
  }

  /// Delete a folder (soft delete)
  Future<bool> deleteFolder(String folderId) async {
    try {
      final index = _folders.indexWhere((f) => f.id == folderId);
      if (index < 0) return false;

      final deletedFolder = _folders[index].copyWith(
        isDeleted: true,
        updatedAt: DateTime.now(),
        isDirty: true,
      );

      _folders[index] = deletedFolder;
      await _foldersBox?.put(folderId, deletedFolder);

      _syncService?.deleteFolder(folderId);

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to delete folder';
      notifyListeners();
      return false;
    }
  }

  /// Move folder to a new parent
  Future<bool> moveFolder(String folderId, String? newParentId) async {
    final folder = getFolderById(folderId);
    if (folder == null) return false;

    // Prevent moving folder into itself or its descendants
    if (newParentId != null) {
      final descendants = _getDescendantIds(folderId);
      if (descendants.contains(newParentId) || folderId == newParentId) {
        _errorMessage = 'Cannot move folder into itself';
        notifyListeners();
        return false;
      }
    }

    return updateFolder(folder.copyWith(parentId: newParentId));
  }

  /// Set folder background color
  Future<bool> setFolderColor(String folderId, String? color) async {
    final folder = getFolderById(folderId);
    if (folder == null) return false;

    return updateFolder(folder.copyWith(backgroundColor: color));
  }

  /// Reorder folders within same parent
  Future<void> reorderFolders(List<String> folderIds) async {
    for (int i = 0; i < folderIds.length; i++) {
      final folder = getFolderById(folderIds[i]);
      if (folder != null && folder.sortOrder != i) {
        await updateFolder(folder.copyWith(sortOrder: i));
      }
    }
  }

  // ===========================================
  // SYNC OPERATIONS
  // ===========================================

  /// Handle folders updated from cloud
  void handleCloudUpdate(List<Folder> cloudFolders) {
    for (final cloudFolder in cloudFolders) {
      final localIndex = _folders.indexWhere((f) => f.id == cloudFolder.id);

      if (localIndex >= 0) {
        final localFolder = _folders[localIndex];

        if (!localFolder.isDirty ||
            cloudFolder.updatedAt.isAfter(localFolder.updatedAt)) {
          _folders[localIndex] = cloudFolder;
          _foldersBox?.put(cloudFolder.id, cloudFolder);
        }
      } else {
        _folders.add(cloudFolder);
        _foldersBox?.put(cloudFolder.id, cloudFolder);
      }
    }

    notifyListeners();
  }

  // ===========================================
  // PRIVATE METHODS
  // ===========================================

  /// Get all descendant folder IDs
  Set<String> _getDescendantIds(String folderId) {
    final descendants = <String>{};
    final children = getSubfolders(folderId);

    for (final child in children) {
      descendants.add(child.id);
      descendants.addAll(_getDescendantIds(child.id));
    }

    return descendants;
  }

  /// Clear dirty flags for a list of folders
  void _clearDirtyFlags(List<Folder> foldersToClear) {
    for (final folder in foldersToClear) {
      final index = _folders.indexWhere((f) => f.id == folder.id);
      if (index >= 0) {
        final cleanedFolder = _folders[index].copyWith(isDirty: false);
        _folders[index] = cleanedFolder;
        _foldersBox?.put(cleanedFolder.id, cleanedFolder);
      }
    }
    notifyListeners();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Clone all local folders from one workspace box to another.
  ///
  /// Returns number of folders copied.
  Future<int> cloneWorkspace({
    required String sourceUserId,
    required String targetUserId,
    bool overwriteTarget = false,
  }) async {
    if (sourceUserId == targetUserId) return 0;

    final sourceBox = await Hive.openBox<Folder>('folders_$sourceUserId');
    final targetBox = await Hive.openBox<Folder>('folders_$targetUserId');

    if (!overwriteTarget && targetBox.isNotEmpty) {
      return 0;
    }
    if (overwriteTarget) {
      await targetBox.clear();
    }

    int copied = 0;
    for (final folder in sourceBox.values) {
      final cloned = folder.copyWith(
        userId: targetUserId,
        isDirty: true,
        syncedAt: null,
      );
      await targetBox.put(cloned.id, cloned);
      copied++;
    }
    return copied;
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }
}

// Hive type adapter for Folder
class FolderAdapter extends TypeAdapter<Folder> {
  @override
  final int typeId = 2;

  @override
  Folder read(BinaryReader reader) {
    final id = reader.readString();
    final name = reader.readString();
    final subtitleRaw = reader.readString();
    final parentIdRaw = reader.readString();
    final backgroundColorRaw = reader.readString();

    return Folder(
      id: id,
      name: name,
      subtitle: subtitleRaw.isEmpty ? null : subtitleRaw,
      parentId: parentIdRaw.isEmpty ? null : parentIdRaw,
      backgroundColor: backgroundColorRaw.isEmpty ? null : backgroundColorRaw,
      icon: reader.readString(),
      createdAt: DateTime.parse(reader.readString()),
      updatedAt: DateTime.parse(reader.readString()),
      syncedAt: reader.readBool() ? DateTime.parse(reader.readString()) : null,
      isDirty: reader.readBool(),
      isDeleted: reader.readBool(),
      userId: reader.readString(),
      sortOrder: reader.readInt(),
    );
  }

  @override
  void write(BinaryWriter writer, Folder obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.name);
    writer.writeString(obj.subtitle ?? '');
    writer.writeString(obj.parentId ?? '');
    writer.writeString(obj.backgroundColor ?? '');
    writer.writeString(obj.icon);
    writer.writeString(obj.createdAt.toIso8601String());
    writer.writeString(obj.updatedAt.toIso8601String());
    writer.writeBool(obj.syncedAt != null);
    if (obj.syncedAt != null) {
      writer.writeString(obj.syncedAt!.toIso8601String());
    }
    writer.writeBool(obj.isDirty);
    writer.writeBool(obj.isDeleted);
    writer.writeString(obj.userId);
    writer.writeInt(obj.sortOrder);
  }
}
