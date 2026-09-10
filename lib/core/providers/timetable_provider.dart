/// Timetable Provider
///
/// State management for timetable entries including CRUD operations,
/// filtering, and sync status tracking.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/timetable_entry.dart';
import '../services/diagnostics_service.dart';
import '../services/sync_service.dart';

/// Provider for managing timetable entry state
///
/// Handles local storage with Hive and coordinates with
/// SyncService for cloud synchronization.
class TimetableProvider extends ChangeNotifier {
  final DiagnosticsService _diagnostics = DiagnosticsService.instance;

  // Local storage box
  Box<TimetableEntry>? _entriesBox;
  Box<dynamic>? _settingsBox;
  String? _activeUserId;

  // In-memory entries list
  List<TimetableEntry> _entries = [];
  List<TimetableDefinition> _timetables = const [
    TimetableDefinition(id: 'default', name: 'My timetable'),
  ];
  String _activeTimetableId = 'default';

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

  List<TimetableEntry> get entries => _entries
      .where((e) => !e.isDeleted && e.timetableId == _activeTimetableId)
      .toList();
  List<TimetableDefinition> get timetables => List.unmodifiable(_timetables);
  String get activeTimetableId => _activeTimetableId;
  TimetableDefinition get activeTimetable => _timetables.firstWhere(
        (timetable) => timetable.id == _activeTimetableId,
        orElse: () => _timetables.first,
      );
  List<String> get teacherSuggestions => _uniqueValues(
        _entries
            .where((entry) => !entry.isDeleted)
            .map((entry) => entry.teacher),
      );
  List<String> get roomSuggestions => _uniqueValues(
        _entries.where((entry) => !entry.isDeleted).map((entry) => entry.room),
      );
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Get entries for a specific weekday
  List<TimetableEntry> getEntriesForDay(Weekday weekday) {
    return entries.where((e) => e.weekday == weekday).toList()
      ..sort((a, b) {
        final aTime = a.startHour * 60 + a.startMinute;
        final bTime = b.startHour * 60 + b.startMinute;
        return aTime.compareTo(bTime);
      });
  }

  /// Get entries with unsynced changes
  List<TimetableEntry> get dirtyEntries =>
      _entries.where((e) => e.isDirty).toList();

  // ===========================================
  // INITIALIZATION
  // ===========================================

  /// Initialize the provider
  Future<void> initialize(String userId) async {
    if (_activeUserId == userId && _entriesBox != null && _entriesBox!.isOpen) {
      return;
    }

    _isLoading = true;
    // Defer notifyListeners to avoid calling during build
    Future.microtask(() => notifyListeners());

    try {
      if (!Hive.isAdapterRegistered(3)) {
        Hive.registerAdapter(TimetableEntryAdapter());
      }

      if (_entriesBox != null &&
          _entriesBox!.isOpen &&
          _activeUserId != null &&
          _activeUserId != userId) {
        await _entriesBox!.close();
      }

      _entriesBox = await Hive.openBox<TimetableEntry>('timetable_$userId');
      _settingsBox = await Hive.openBox<dynamic>('timetable_settings_$userId');
      _activeUserId = userId;
      _entries = _entriesBox!.values.toList();
      await _loadTimetables();
      final visibleCount = _entries.where((entry) => !entry.isDeleted).length;
      final deletedCount = _entries.length - visibleCount;
      _diagnostics.info(
        'TimetableProvider',
        'WORKSPACE_FLOW timetable initialized workspace=$userId rawCount=${_entries.length} visibleCount=$visibleCount deletedCount=$deletedCount',
      );

      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to load timetable entries';
      debugPrint('Timetable initialization error: $e');
      _diagnostics.error(
        'TimetableProvider',
        'HIVE_BOX failed to initialize timetable workspace=$userId error=$e',
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
        final dirty = dirtyEntries;
        if (dirty.isNotEmpty) {
          debugPrint(
            'TimetableProvider: Syncing ${dirty.length} dirty entries',
          );
          final success = await service.syncDirtyItems(dirtyEntries: dirty);
          if (success) {
            debugPrint(
              'TimetableProvider: Sync successful, clearing dirty flags',
            );
            _clearDirtyFlags(dirty);
          }
        }
      });
    }
  }

  /// Clear dirty flags for a list of entries
  void _clearDirtyFlags(List<TimetableEntry> entriesToClear) {
    for (final entry in entriesToClear) {
      final index = _entries.indexWhere((e) => e.id == entry.id);
      if (index >= 0) {
        final cleanedEntry = _entries[index].copyWith(isDirty: false);
        _entries[index] = cleanedEntry;
        _entriesBox?.put(entry.id, cleanedEntry);
      }
    }
    notifyListeners();
  }

  // ===========================================
  // CRUD OPERATIONS
  // ===========================================

  /// Create a new timetable entry
  Future<TimetableEntry?> createEntry({
    required String userId,
    required String subject,
    required Weekday weekday,
    required int startHour,
    required int startMinute,
    required int endHour,
    required int endMinute,
    String? teacher,
    String? room,
    String? color,
    String? timetableId,
    String? timetableName,
  }) async {
    try {
      final entry = TimetableEntry(
        id: _uuid.v4(),
        userId: userId,
        subject: subject,
        teacher: teacher,
        room: room,
        weekday: weekday,
        startHour: startHour,
        startMinute: startMinute,
        endHour: endHour,
        endMinute: endMinute,
        color: color ?? '#64D2FF',
        timetableId: timetableId ?? _activeTimetableId,
        timetableName: timetableName ?? activeTimetable.name,
      );

      await _entriesBox?.put(entry.id, entry);
      _entries.add(entry);

      _syncService?.syncTimetableEntry(entry.toJson());

      notifyListeners();
      return entry;
    } catch (e) {
      _errorMessage = 'Failed to create timetable entry';
      notifyListeners();
      return null;
    }
  }

  /// Update a timetable entry
  Future<bool> updateEntry(TimetableEntry entry) async {
    try {
      final updatedEntry = entry.copyWith(
        isDirty: true,
      );

      await _entriesBox?.put(updatedEntry.id, updatedEntry);

      final index = _entries.indexWhere((e) => e.id == entry.id);
      if (index >= 0) {
        _entries[index] = updatedEntry;
      }

      _syncService?.syncTimetableEntry(updatedEntry.toJson());

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to update timetable entry';
      notifyListeners();
      return false;
    }
  }

  /// Delete a timetable entry (soft delete)
  Future<bool> deleteEntry(String entryId) async {
    try {
      final entry = _entries.firstWhere((e) => e.id == entryId);
      final deletedEntry = entry.copyWith(
        isDeleted: true,
        isDirty: true,
      );

      await _entriesBox?.put(deletedEntry.id, deletedEntry);

      final index = _entries.indexWhere((e) => e.id == entryId);
      if (index >= 0) {
        _entries[index] = deletedEntry;
      }

      _syncService?.syncTimetableEntry(deletedEntry.toJson());

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to delete timetable entry';
      notifyListeners();
      return false;
    }
  }

  /// Get entry by ID
  TimetableEntry? getEntryById(String entryId) {
    try {
      return _entries.firstWhere((e) => e.id == entryId && !e.isDeleted);
    } catch (e) {
      return null;
    }
  }

  Future<void> selectTimetable(String timetableId) async {
    if (!_timetables.any((timetable) => timetable.id == timetableId)) return;
    _activeTimetableId = timetableId;
    await _settingsBox?.put('activeTimetableId', timetableId);
    notifyListeners();
  }

  Future<TimetableDefinition?> createTimetable(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return null;
    final timetable = TimetableDefinition(id: _uuid.v4(), name: trimmedName);
    _timetables = [..._timetables, timetable];
    _activeTimetableId = timetable.id;
    await _saveTimetableSettings();
    notifyListeners();
    return timetable;
  }

  Future<bool> renameActiveTimetable(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return false;
    final index = _timetables.indexWhere(
      (timetable) => timetable.id == _activeTimetableId,
    );
    if (index < 0) return false;
    _timetables = [..._timetables]..[index] = TimetableDefinition(
        id: _activeTimetableId,
        name: trimmedName,
      );
    final affectedEntries = _entries
        .where((entry) => entry.timetableId == _activeTimetableId)
        .toList();
    for (final entry in affectedEntries) {
      await updateEntry(entry.copyWith(timetableName: trimmedName));
    }
    await _saveTimetableSettings();
    notifyListeners();
    return true;
  }

  Future<bool> deleteActiveTimetable() async {
    if (_timetables.length == 1) return false;
    final deletedId = _activeTimetableId;
    final affectedEntries = _entries
        .where((entry) => entry.timetableId == deletedId && !entry.isDeleted)
        .toList();
    for (final entry in affectedEntries) {
      await deleteEntry(entry.id);
    }
    _timetables =
        _timetables.where((timetable) => timetable.id != deletedId).toList();
    _activeTimetableId = _timetables.first.id;
    await _saveTimetableSettings();
    notifyListeners();
    return true;
  }

  Future<void> closeWorkspace() async {
    _entries = [];
    if (_entriesBox != null && _entriesBox!.isOpen) {
      await _entriesBox!.close();
    }
    if (_settingsBox != null && _settingsBox!.isOpen) {
      await _settingsBox!.close();
    }
    _entriesBox = null;
    _settingsBox = null;
    _activeUserId = null;
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  // ===========================================
  // SYNC OPERATIONS
  // ===========================================

  /// Handle cloud update (called by SyncService)
  void handleCloudUpdate(List<TimetableEntry> cloudEntries) {
    final cloudIds = cloudEntries.map((entry) => entry.id).toSet();
    final localVisibleEntries = _entries
        .where((entry) => !entry.isDeleted && entry.userId == _activeUserId)
        .toList();
    final localVisibleCount = localVisibleEntries.length;
    final localDeletedCount = _entries
        .where((entry) => entry.isDeleted && entry.userId == _activeUserId)
        .length;
    final staleVisibleDirtyIds = localVisibleEntries
        .where((entry) => entry.isDirty && !cloudIds.contains(entry.id))
        .map((entry) => entry.id)
        .toList();
    final staleVisibleCleanIds = localVisibleEntries
        .where((entry) => !entry.isDirty && !cloudIds.contains(entry.id))
        .map((entry) => entry.id)
        .toList();

    _diagnostics.info(
      'TimetableProvider',
      'SYNC_LIFECYCLE applying cloud timetable workspace=$_activeUserId cloudCount=${cloudEntries.length} localVisibleBefore=$localVisibleCount localDeleted=$localDeletedCount staleVisibleClean=${staleVisibleCleanIds.length} staleVisibleDirty=${staleVisibleDirtyIds.length}',
    );

    if (staleVisibleCleanIds.isNotEmpty || staleVisibleDirtyIds.isNotEmpty) {
      _diagnostics.warning(
        'TimetableProvider',
        'SYNC_LIFECYCLE timetable mismatch workspace=$_activeUserId missingFromCloudClean=${_sampleIds(staleVisibleCleanIds)} missingFromCloudDirty=${_sampleIds(staleVisibleDirtyIds)}',
      );
    }

    var timetableSettingsChanged = false;
    for (final cloudEntry in cloudEntries) {
      if (!cloudEntry.isDeleted) {
        final timetableIndex = _timetables.indexWhere(
          (timetable) => timetable.id == cloudEntry.timetableId,
        );
        if (timetableIndex < 0) {
          _timetables = [
            ..._timetables,
            TimetableDefinition(
              id: cloudEntry.timetableId,
              name: cloudEntry.timetableName,
            ),
          ];
          timetableSettingsChanged = true;
        } else if (_timetables[timetableIndex].name !=
            cloudEntry.timetableName) {
          _timetables = [..._timetables]
            ..[timetableIndex] = TimetableDefinition(
              id: cloudEntry.timetableId,
              name: cloudEntry.timetableName,
            );
          timetableSettingsChanged = true;
        }
      }
      final localIndex = _entries.indexWhere((e) => e.id == cloudEntry.id);

      if (localIndex >= 0) {
        final localEntry = _entries[localIndex];
        // Only update if local entry is not dirty (no local changes)
        if (!localEntry.isDirty) {
          _entries[localIndex] = cloudEntry;
          _entriesBox?.put(cloudEntry.id, cloudEntry);
        }
      } else {
        // New entry from cloud
        _entries.add(cloudEntry);
        _entriesBox?.put(cloudEntry.id, cloudEntry);
      }
    }

    if (timetableSettingsChanged) unawaited(_saveTimetableSettings());

    final visibleAfter = entries.length;
    _diagnostics.info(
      'TimetableProvider',
      'SYNC_LIFECYCLE cloud timetable applied workspace=$_activeUserId visibleAfter=$visibleAfter unresolvedMissingClean=${staleVisibleCleanIds.length} unresolvedMissingDirty=${staleVisibleDirtyIds.length}',
    );
    notifyListeners();
  }

  Future<void> _loadTimetables() async {
    final stored = _settingsBox?.get('timetables');
    final loaded = <TimetableDefinition>[];
    if (stored is List) {
      for (final value in stored) {
        if (value is Map) {
          try {
            loaded.add(TimetableDefinition.fromJson(value));
          } catch (_) {
            // Ignore an individual malformed saved timetable.
          }
        }
      }
    }

    for (final entry in _entries.where((entry) => !entry.isDeleted)) {
      if (!loaded.any((timetable) => timetable.id == entry.timetableId)) {
        loaded.add(
          TimetableDefinition(
            id: entry.timetableId,
            name: entry.timetableName,
          ),
        );
      }
    }
    _timetables = loaded.isEmpty
        ? const [TimetableDefinition(id: 'default', name: 'My timetable')]
        : loaded;
    final savedActive = _settingsBox?.get('activeTimetableId') as String?;
    _activeTimetableId = _timetables.any((item) => item.id == savedActive)
        ? savedActive!
        : _timetables.first.id;
    await _saveTimetableSettings();
  }

  Future<void> _saveTimetableSettings() async {
    await _settingsBox?.put(
      'timetables',
      _timetables.map((timetable) => timetable.toJson()).toList(),
    );
    await _settingsBox?.put('activeTimetableId', _activeTimetableId);
  }

  List<String> _uniqueValues(Iterable<String?> values) {
    final byLowercase = <String, String>{};
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        byLowercase.putIfAbsent(trimmed.toLowerCase(), () => trimmed);
      }
    }
    final result = byLowercase.values.toList();
    result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  String _sampleIds(List<String> ids) {
    if (ids.isEmpty) {
      return '[]';
    }
    final preview = ids.take(5).join(', ');
    final suffix = ids.length > 5 ? ', ...' : '';
    return '[$preview$suffix]';
  }
}

// Hive type adapter for TimetableEntry
class TimetableEntryAdapter extends TypeAdapter<TimetableEntry> {
  @override
  final int typeId = 3;

  @override
  TimetableEntry read(BinaryReader reader) {
    final id = reader.readString();
    final subject = reader.readString();
    final teacher = reader.readBool() ? reader.readString() : null;
    final room = reader.readBool() ? reader.readString() : null;
    final weekday = Weekday.values[reader.readInt()];
    final startHour = reader.readInt();
    final startMinute = reader.readInt();
    final endHour = reader.readInt();
    final endMinute = reader.readInt();
    final color = reader.readString();
    final userId = reader.readString();
    final isDirty = reader.readBool();
    final isDeleted = reader.readBool();
    var timetableId = 'default';
    var timetableName = 'My timetable';
    if (reader.availableBytes > 0) {
      timetableId = reader.readString();
    }
    if (reader.availableBytes > 0) {
      timetableName = reader.readString();
    }
    return TimetableEntry(
      id: id,
      subject: subject,
      teacher: teacher,
      room: room,
      weekday: weekday,
      startHour: startHour,
      startMinute: startMinute,
      endHour: endHour,
      endMinute: endMinute,
      color: color,
      userId: userId,
      isDirty: isDirty,
      isDeleted: isDeleted,
      timetableId: timetableId,
      timetableName: timetableName,
    );
  }

  @override
  void write(BinaryWriter writer, TimetableEntry obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.subject);
    writer.writeBool(obj.teacher != null);
    if (obj.teacher != null) {
      writer.writeString(obj.teacher!);
    }
    writer.writeBool(obj.room != null);
    if (obj.room != null) {
      writer.writeString(obj.room!);
    }
    writer.writeInt(obj.weekday.index);
    writer.writeInt(obj.startHour);
    writer.writeInt(obj.startMinute);
    writer.writeInt(obj.endHour);
    writer.writeInt(obj.endMinute);
    writer.writeString(obj.color);
    writer.writeString(obj.userId);
    writer.writeBool(obj.isDirty);
    writer.writeBool(obj.isDeleted);
    writer.writeString(obj.timetableId);
    writer.writeString(obj.timetableName);
  }
}
