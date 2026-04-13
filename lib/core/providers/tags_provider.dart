/// Tags Provider
///
/// State management for tags including CRUD operations,
/// Hive persistence, and cloud sync.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/tag.dart';
import '../services/diagnostics_service.dart';
import '../services/sync_service.dart';

/// Hive type adapter for Tag
class TagAdapter extends TypeAdapter<Tag> {
  @override
  final int typeId = 6;

  @override
  Tag read(BinaryReader reader) {
    final id = reader.readString();
    final name = reader.readString();
    final color = reader.readString();
    final userId = reader.readString();
    final createdAt = DateTime.parse(reader.readString());
    final isDirty = reader.readBool();
    return Tag(
      id: id,
      name: name,
      color: color,
      userId: userId,
      createdAt: createdAt,
      isDirty: isDirty,
    );
  }

  @override
  void write(BinaryWriter writer, Tag obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.name);
    writer.writeString(obj.color);
    writer.writeString(obj.userId);
    writer.writeString(obj.createdAt.toIso8601String());
    writer.writeBool(obj.isDirty);
  }
}

/// Provider for managing tag state
class TagsProvider extends ChangeNotifier {
  final DiagnosticsService _diagnostics = DiagnosticsService.instance;

  // Local storage box
  Box<Tag>? _tagsBox;
  String? _activeUserId;

  // In-memory tags list
  List<Tag> _tags = [];

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

  List<Tag> get tags => List.unmodifiable(_tags);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Get dirty tags for sync
  List<Tag> get dirtyTags => _tags.where((t) => t.isDirty).toList();

  /// Get tag by ID
  Tag? getTagById(String id) {
    try {
      return _tags.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get tag by name (case-insensitive)
  Tag? getTagByName(String name) {
    final lower = name.trim().toLowerCase();
    try {
      return _tags.firstWhere((t) => t.name.toLowerCase() == lower);
    } catch (_) {
      return null;
    }
  }

  /// Get tags by a list of IDs
  List<Tag> getTagsByIds(List<String> ids) {
    return _tags.where((t) => ids.contains(t.id)).toList();
  }

  /// Get all tag names for autocomplete
  List<String> get tagNames => _tags.map((t) => t.name).toList()..sort();

  // ===========================================
  // INITIALIZATION
  // ===========================================

  /// Initialize the provider
  Future<void> initialize(String userId) async {
    _isLoading = true;
    Future.microtask(() => notifyListeners());

    try {
      final boxName = 'tags_$userId';
      if (!Hive.isAdapterRegistered(6)) {
        Hive.registerAdapter(TagAdapter());
      }

      if (_activeUserId != null &&
          _activeUserId != userId &&
          _tagsBox != null &&
          _tagsBox!.isOpen) {
        _diagnostics.info(
          'TagsProvider',
          'HIVE_BOX closing tags box for previous workspace=$_activeUserId',
        );
        await _tagsBox!.close();
      }

      _diagnostics.info(
        'TagsProvider',
        'HIVE_BOX opening tags box name=$boxName alreadyOpen=${Hive.isBoxOpen(boxName)}',
      );
      _tagsBox = await Hive.openBox<Tag>(boxName);
      _activeUserId = userId;
      _tags = _tagsBox!.values.toList();
      _diagnostics.info(
        'TagsProvider',
        'WORKSPACE_FLOW tags initialized workspace=$userId tagCount=${_tags.length}',
      );

      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to load tags';
      debugPrint('Tags initialization error: $e');
      _diagnostics.error(
        'TagsProvider',
        'HIVE_BOX failed to initialize tags workspace=$userId error=$e',
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
        final dirty = dirtyTags;
        if (dirty.isNotEmpty) {
          debugPrint('TagsProvider: Syncing ${dirty.length} dirty tags');
          final success = await service.syncDirtyItems(dirtyTags: dirty);
          if (success) {
            debugPrint('TagsProvider: Sync successful, clearing dirty flags');
            _clearDirtyFlags(dirty);
          }
        }
      });
    }
  }

  // ===========================================
  // CRUD OPERATIONS
  // ===========================================

  /// Create a new tag
  Future<Tag?> createTag({
    required String userId,
    required String name,
    String color = '#64D2FF',
  }) async {
    // Don't create duplicates (case-insensitive)
    final existing = getTagByName(name);
    if (existing != null) return existing;

    try {
      final tag = Tag.create(
        id: _uuid.v4(),
        userId: userId,
        name: name.trim(),
        color: color,
      );

      await _tagsBox?.put(tag.id, tag);
      _tags.add(tag);

      _syncService?.syncTag(tag);

      notifyListeners();
      return tag;
    } catch (e) {
      _errorMessage = 'Failed to create tag';
      notifyListeners();
      return null;
    }
  }

  /// Find or create a tag by name (useful during import)
  Future<Tag?> findOrCreateTag({
    required String userId,
    required String name,
    String color = '#64D2FF',
  }) async {
    final existing = getTagByName(name);
    if (existing != null) return existing;
    return createTag(userId: userId, name: name, color: color);
  }

  /// Update a tag
  Future<bool> updateTag(Tag tag) async {
    try {
      final updatedTag = tag.copyWith(isDirty: true);

      await _tagsBox?.put(updatedTag.id, updatedTag);

      final index = _tags.indexWhere((t) => t.id == tag.id);
      if (index >= 0) {
        _tags[index] = updatedTag;
      }

      _syncService?.syncTag(updatedTag);

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to update tag';
      notifyListeners();
      return false;
    }
  }

  /// Delete a tag
  Future<bool> deleteTag(String tagId) async {
    try {
      await _tagsBox?.delete(tagId);
      _tags.removeWhere((t) => t.id == tagId);

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to delete tag';
      notifyListeners();
      return false;
    }
  }

  /// Apply tags from cloud sync
  Future<void> applyCloudTags(List<Tag> cloudTags) async {
    for (final cloudTag in cloudTags) {
      final localTag = getTagById(cloudTag.id);
      if (localTag == null) {
        _tags.add(cloudTag);
        await _tagsBox?.put(cloudTag.id, cloudTag);
      } else if (!localTag.isDirty) {
        final index = _tags.indexWhere((t) => t.id == cloudTag.id);
        if (index >= 0) {
          _tags[index] = cloudTag;
          await _tagsBox?.put(cloudTag.id, cloudTag);
        }
      }
    }
    notifyListeners();
  }

  // ===========================================
  // INTERNAL
  // ===========================================

  void _clearDirtyFlags(List<Tag> tags) {
    for (final tag in tags) {
      final index = _tags.indexWhere((t) => t.id == tag.id);
      if (index >= 0) {
        final cleared = _tags[index].copyWith(isDirty: false);
        _tags[index] = cleared;
        _tagsBox?.put(cleared.id, cleared);
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }
}
