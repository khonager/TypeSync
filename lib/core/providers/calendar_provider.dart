/// Calendar Provider
///
/// State management for calendar events including CRUD operations,
/// filtering, and sync status tracking.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/calendar_event.dart';
import '../services/sync_service.dart';

/// Provider for managing calendar event state
///
/// Handles local storage with Hive and coordinates with
/// SyncService for cloud synchronization.
class CalendarProvider extends ChangeNotifier {
  // Local storage box
  Box<CalendarEvent>? _eventsBox;
  String? _activeUserId;

  // In-memory events list
  List<CalendarEvent> _events = [];

  // Loading state
  bool _isLoading = false;

  // Error state
  String? _errorMessage;

  // UUID generator
  final Uuid _uuid = const Uuid();

  // Sync service reference (set by parent)
  SyncService? _syncService;
  StreamSubscription<void>? _syncSubscription;
  DateTime? _lastTodoMaintenanceDay;

  // ===========================================
  // GETTERS
  // ===========================================

  List<CalendarEvent> get events => _events.where((e) => !e.isDeleted).toList();
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Get events for a specific date
  List<CalendarEvent> getEventsForDate(DateTime date) {
    return _events
        .where(
          (e) =>
              !e.isDeleted &&
              e.startTime.year == date.year &&
              e.startTime.month == date.month &&
              e.startTime.day == date.day,
        )
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  /// Get upcoming events
  List<CalendarEvent> get upcomingEvents {
    final now = DateTime.now();
    return _events
        .where((e) => !e.isDeleted && e.startTime.isAfter(now))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  /// Get events with unsynced changes
  List<CalendarEvent> get dirtyEvents =>
      _events.where((e) => e.isDirty).toList();

  // ===========================================
  // INITIALIZATION
  // ===========================================

  /// Initialize the provider
  Future<void> initialize(String userId) async {
    if (_activeUserId == userId && _eventsBox != null && _eventsBox!.isOpen) {
      return;
    }

    _isLoading = true;
    Future.microtask(() => notifyListeners());

    try {
      if (!Hive.isAdapterRegistered(5)) {
        Hive.registerAdapter(CalendarEventAdapter());
      }

      if (_eventsBox != null &&
          _eventsBox!.isOpen &&
          _activeUserId != null &&
          _activeUserId != userId) {
        await _eventsBox!.close();
      }

      _eventsBox = await Hive.openBox<CalendarEvent>('calendar_events_$userId');
      _activeUserId = userId;
      _events = _eventsBox!.values.toList();
      await rollOverPendingTodos();

      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to load calendar events';
      debugPrint('Calendar initialization error: $e');
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
        final dirty = dirtyEvents;
        if (dirty.isNotEmpty) {
          debugPrint('CalendarProvider: Syncing ${dirty.length} dirty events');
          final success = await service.syncDirtyItems(dirtyEvents: dirty);
          if (success) {
            debugPrint(
              'CalendarProvider: Sync successful, clearing dirty flags',
            );
            _clearDirtyFlags(dirty);
          }
        }
      });
    }
  }

  /// Handle cloud update (called by SyncService)
  void handleCloudUpdate(List<CalendarEvent> cloudEvents) {
    for (final cloudEvent in cloudEvents) {
      final localIndex = _events.indexWhere((e) => e.id == cloudEvent.id);

      if (localIndex >= 0) {
        final localEvent = _events[localIndex];
        // Only update if local event is not dirty (no local changes)
        if (!localEvent.isDirty) {
          _events[localIndex] = cloudEvent;
          _eventsBox?.put(cloudEvent.id, cloudEvent);
        }
      } else {
        // New event from cloud
        _events.add(cloudEvent);
        _eventsBox?.put(cloudEvent.id, cloudEvent);
      }
    }

    notifyListeners();
  }

  /// Clear dirty flags for a list of events
  void _clearDirtyFlags(List<CalendarEvent> eventsToClear) {
    for (final event in eventsToClear) {
      final index = _events.indexWhere((e) => e.id == event.id);
      if (index >= 0) {
        final cleanedEvent = _events[index].copyWith(isDirty: false);
        _events[index] = cleanedEvent;
        _eventsBox?.put(event.id, cleanedEvent);
      }
    }
    notifyListeners();
  }

  // ===========================================
  // CRUD OPERATIONS
  // ===========================================

  /// Create a new calendar event
  Future<CalendarEvent?> createEvent({
    required String userId,
    required String title,
    required DateTime startTime,
    String? description,
    EventType type = EventType.todo,
    DateTime? endTime,
    String? subject,
    String? location,
    String? color,
    bool hasReminder = true,
    int reminderMinutesBefore = 30,
  }) async {
    try {
      final now = DateTime.now();
      final event = CalendarEvent(
        id: _uuid.v4(),
        userId: userId,
        title: title,
        description: description,
        type: type,
        startTime: startTime,
        endTime: endTime,
        subject: subject,
        location: location,
        color: color,
        hasReminder: hasReminder,
        reminderMinutesBefore: reminderMinutesBefore,
        createdAt: now,
      );

      await _eventsBox?.put(event.id, event);
      _events.add(event);

      _syncService?.syncCalendarEvent(event.toJson());

      notifyListeners();
      return event;
    } catch (e) {
      _errorMessage = 'Failed to create calendar event';
      notifyListeners();
      return null;
    }
  }

  Future<void> rollOverPendingTodos() async {
    final today = _dateOnly(DateTime.now());
    if (_lastTodoMaintenanceDay != null &&
        _dateOnly(_lastTodoMaintenanceDay!) == today) {
      return;
    }

    var changed = false;

    for (var i = 0; i < _events.length; i++) {
      final event = _events[i];
      if (!event.isTodo || event.isCompleted || event.isDeleted) {
        continue;
      }

      final eventDate = _dateOnly(event.startTime);
      if (!eventDate.isBefore(today)) {
        continue;
      }

      final overdueDays = today.difference(eventDate).inDays;
      final updatedEvent = event.copyWith(
        startTime: DateTime(
          today.year,
          today.month,
          today.day,
          event.startTime.hour,
          event.startTime.minute,
          event.startTime.second,
          event.startTime.millisecond,
          event.startTime.microsecond,
        ),
        endTime: event.endTime == null
            ? null
            : DateTime(
                today.year,
                today.month,
                today.day,
                event.endTime!.hour,
                event.endTime!.minute,
                event.endTime!.second,
                event.endTime!.millisecond,
                event.endTime!.microsecond,
              ),
        rolloverCount: event.rolloverCount + overdueDays,
        isDirty: true,
      );

      _events[i] = updatedEvent;
      await _eventsBox?.put(updatedEvent.id, updatedEvent);
      _syncService?.syncCalendarEvent(updatedEvent.toJson());
      changed = true;
    }

    _lastTodoMaintenanceDay = today;
    if (changed) {
      notifyListeners();
    }
  }

  /// Update a calendar event
  Future<bool> updateEvent(CalendarEvent event) async {
    try {
      final updatedEvent = event.copyWith(
        isDirty: true,
      );

      await _eventsBox?.put(updatedEvent.id, updatedEvent);

      final index = _events.indexWhere((e) => e.id == event.id);
      if (index >= 0) {
        _events[index] = updatedEvent;
      }

      _syncService?.syncCalendarEvent(updatedEvent.toJson());

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to update calendar event';
      notifyListeners();
      return false;
    }
  }

  Future<bool> toggleTodoCompletion({
    required String eventId,
    required bool isCompleted,
  }) async {
    final event = getEventById(eventId);
    if (event == null || !event.isTodo) {
      return false;
    }

    return updateEvent(
      event.copyWith(
        isCompleted: isCompleted,
      ),
    );
  }

  /// Delete a calendar event (soft delete)
  Future<bool> deleteEvent(String eventId) async {
    try {
      final index = _events.indexWhere((e) => e.id == eventId);
      if (index < 0) return false;

      final deletedEvent = _events[index].copyWith(
        isDeleted: true,
        isDirty: true,
      );

      _events[index] = deletedEvent;
      await _eventsBox?.put(eventId, deletedEvent);

      _syncService?.deleteCalendarEvent(eventId);

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to delete calendar event';
      notifyListeners();
      return false;
    }
  }

  /// Get event by ID
  CalendarEvent? getEventById(String eventId) {
    try {
      return _events.firstWhere((e) => e.id == eventId && !e.isDeleted);
    } catch (e) {
      return null;
    }
  }

  Future<void> closeWorkspace() async {
    _events = [];
    if (_eventsBox != null && _eventsBox!.isOpen) {
      await _eventsBox!.close();
    }
    _eventsBox = null;
    _activeUserId = null;
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}

// Hive type adapter for CalendarEvent
class CalendarEventAdapter extends TypeAdapter<CalendarEvent> {
  @override
  final int typeId = 5;

  @override
  CalendarEvent read(BinaryReader reader) {
    final id = reader.readString();
    final title = reader.readString();
    final description = reader.readBool() ? reader.readString() : null;
    final type = EventType.values[reader.readInt()];
    final startTime = DateTime.parse(reader.readString());
    final endTime =
        reader.readBool() ? DateTime.parse(reader.readString()) : null;
    final subject = reader.readBool() ? reader.readString() : null;
    final location = reader.readBool() ? reader.readString() : null;
    final color = reader.readBool() ? reader.readString() : null;
    final hasReminder = reader.readBool();
    final reminderMinutesBefore = reader.readInt();
    final noteId = reader.readBool() ? reader.readString() : null;
    final userId = reader.readString();
    final createdAt = DateTime.parse(reader.readString());
    final isDirty = reader.readBool();
    final isDeleted = reader.readBool();

    var isCompleted = false;
    var rolloverCount = 0;
    try {
      isCompleted = reader.readBool();
      rolloverCount = reader.readInt();
    } catch (_) {}

    return CalendarEvent(
      id: id,
      title: title,
      description: description,
      type: type,
      startTime: startTime,
      endTime: endTime,
      subject: subject,
      location: location,
      color: color,
      hasReminder: hasReminder,
      reminderMinutesBefore: reminderMinutesBefore,
      noteId: noteId,
      userId: userId,
      createdAt: createdAt,
      isDirty: isDirty,
      isDeleted: isDeleted,
      isCompleted: isCompleted,
      rolloverCount: rolloverCount,
    );
  }

  @override
  void write(BinaryWriter writer, CalendarEvent obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.title);
    writer.writeBool(obj.description != null);
    if (obj.description != null) {
      writer.writeString(obj.description!);
    }
    writer.writeInt(obj.type.index);
    writer.writeString(obj.startTime.toIso8601String());
    writer.writeBool(obj.endTime != null);
    if (obj.endTime != null) {
      writer.writeString(obj.endTime!.toIso8601String());
    }
    writer.writeBool(obj.subject != null);
    if (obj.subject != null) {
      writer.writeString(obj.subject!);
    }
    writer.writeBool(obj.location != null);
    if (obj.location != null) {
      writer.writeString(obj.location!);
    }
    writer.writeBool(obj.color != null);
    if (obj.color != null) {
      writer.writeString(obj.color!);
    }
    writer.writeBool(obj.hasReminder);
    writer.writeInt(obj.reminderMinutesBefore);
    writer.writeBool(obj.noteId != null);
    if (obj.noteId != null) {
      writer.writeString(obj.noteId!);
    }
    writer.writeString(obj.userId);
    writer.writeString(obj.createdAt.toIso8601String());
    writer.writeBool(obj.isDirty);
    writer.writeBool(obj.isDeleted);
    writer.writeBool(obj.isCompleted);
    writer.writeInt(obj.rolloverCount);
  }
}
