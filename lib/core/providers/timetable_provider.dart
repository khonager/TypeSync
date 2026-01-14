/// Timetable Provider
///
/// State management for timetable entries including CRUD operations,
/// filtering, and sync status tracking.
library;

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/timetable_entry.dart';
import '../services/sync_service.dart';

/// Provider for managing timetable entry state
///
/// Handles local storage with Hive and coordinates with
/// SyncService for cloud synchronization.
class TimetableProvider extends ChangeNotifier {
  // Local storage box
  Box<TimetableEntry>? _entriesBox;

  // In-memory entries list
  List<TimetableEntry> _entries = [];

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

  List<TimetableEntry> get entries =>
      _entries.where((e) => !e.isDeleted).toList();
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Get entries for a specific weekday
  List<TimetableEntry> getEntriesForDay(Weekday weekday) {
    return _entries.where((e) => !e.isDeleted && e.weekday == weekday).toList()
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
    _isLoading = true;
    // Defer notifyListeners to avoid calling during build
    Future.microtask(() => notifyListeners());

    try {
      if (!Hive.isAdapterRegistered(3)) {
        Hive.registerAdapter(TimetableEntryAdapter());
      }

      _entriesBox = await Hive.openBox<TimetableEntry>('timetable_$userId');
      _entries = _entriesBox!.values.toList();

      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to load timetable entries';
      debugPrint('Timetable initialization error: $e');
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

  /// Create a new timetable entry
  Future<TimetableEntry?> createEntry({
    required String userId,
    required String subject,
    required Weekday weekday, required int startHour, required int startMinute, required int endHour, required int endMinute, String? teacher,
    String? room,
    String? color,
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

  // ===========================================
  // SYNC OPERATIONS
  // ===========================================

  /// Handle cloud update (called by SyncService)
  void handleCloudUpdate(List<TimetableEntry> cloudEntries) {
    for (final cloudEntry in cloudEntries) {
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

    notifyListeners();
  }
}

// Hive type adapter for TimetableEntry
class TimetableEntryAdapter extends TypeAdapter<TimetableEntry> {
  @override
  final int typeId = 3;

  @override
  TimetableEntry read(BinaryReader reader) {
    return TimetableEntry(
      id: reader.readString(),
      subject: reader.readString(),
      teacher: reader.readBool() ? reader.readString() : null,
      room: reader.readBool() ? reader.readString() : null,
      weekday: Weekday.values[reader.readInt()],
      startHour: reader.readInt(),
      startMinute: reader.readInt(),
      endHour: reader.readInt(),
      endMinute: reader.readInt(),
      color: reader.readString(),
      userId: reader.readString(),
      isDirty: reader.readBool(),
      isDeleted: reader.readBool(),
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
  }
}
