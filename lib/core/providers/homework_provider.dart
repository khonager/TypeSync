/// Homework Provider
///
/// State management for homework tasks including CRUD operations,
/// filtering, and sync status tracking.

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/homework.dart';
import '../services/sync_service.dart';

/// Provider for managing homework state
///
/// Handles local storage with Hive and coordinates with
/// SyncService for cloud synchronization.
class HomeworkProvider extends ChangeNotifier {
  // Local storage box
  Box<Homework>? _homeworkBox;

  // In-memory homework list
  List<Homework> _homework = [];

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

  List<Homework> get homework => _homework.where((h) => !h.isDeleted).toList();
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Get homework by completion status
  List<Homework> getHomeworkByStatus(bool showCompleted) {
    if (showCompleted) {
      return homework;
    }
    return homework.where((h) => !h.isCompleted).toList()
      ..sort((a, b) {
        // Sort by due date (overdue first), then priority
        if (a.isOverdue && !b.isOverdue) return -1;
        if (!a.isOverdue && b.isOverdue) return 1;
        if (a.dueDate != null && b.dueDate != null) {
          final dateCompare = a.dueDate!.compareTo(b.dueDate!);
          if (dateCompare != 0) return dateCompare;
        }
        return b.priority.index.compareTo(a.priority.index);
      });
  }

  /// Get overdue homework
  List<Homework> get overdueHomework =>
      homework.where((h) => h.isOverdue).toList();

  /// Get homework with unsynced changes
  List<Homework> get dirtyHomework =>
      _homework.where((h) => h.isDirty).toList();

  // ===========================================
  // INITIALIZATION
  // ===========================================

  /// Initialize the provider
  Future<void> initialize(String userId) async {
    _isLoading = true;
    Future.microtask(() => notifyListeners());

    try {
      if (!Hive.isAdapterRegistered(4)) {
        Hive.registerAdapter(HomeworkAdapter());
      }

      _homeworkBox = await Hive.openBox<Homework>('homework_$userId');
      _homework = _homeworkBox!.values.toList();

      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to load homework';
      debugPrint('Homework initialization error: $e');
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

  /// Create a new homework task
  Future<Homework?> createHomework({
    required String userId,
    required String title,
    String? description,
    String? subject,
    DateTime? dueDate,
    HomeworkPriority priority = HomeworkPriority.medium,
  }) async {
    try {
      final now = DateTime.now();
      final homework = Homework(
        id: _uuid.v4(),
        userId: userId,
        title: title,
        description: description,
        subject: subject,
        dueDate: dueDate,
        priority: priority,
        createdAt: now,
        updatedAt: now,
      );

      await _homeworkBox?.put(homework.id, homework);
      _homework.add(homework);

      _syncService?.syncHomework(homework.toJson());

      notifyListeners();
      return homework;
    } catch (e) {
      _errorMessage = 'Failed to create homework';
      notifyListeners();
      return null;
    }
  }

  /// Update a homework task
  Future<bool> updateHomework(Homework homework) async {
    try {
      final updatedHomework = homework.copyWith(
        updatedAt: DateTime.now(),
        isDirty: true,
      );

      await _homeworkBox?.put(updatedHomework.id, updatedHomework);

      final index = _homework.indexWhere((h) => h.id == homework.id);
      if (index >= 0) {
        _homework[index] = updatedHomework;
      }

      _syncService?.syncHomework(updatedHomework.toJson());

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to update homework';
      notifyListeners();
      return false;
    }
  }

  /// Delete a homework task (soft delete)
  Future<bool> deleteHomework(String homeworkId) async {
    try {
      final index = _homework.indexWhere((h) => h.id == homeworkId);
      if (index < 0) return false;

      final deletedHomework = _homework[index].copyWith(
        isDeleted: true,
        updatedAt: DateTime.now(),
        isDirty: true,
      );

      _homework[index] = deletedHomework;
      await _homeworkBox?.put(homeworkId, deletedHomework);

      _syncService?.deleteHomework(homeworkId);

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to delete homework';
      notifyListeners();
      return false;
    }
  }

  /// Toggle completion status
  Future<void> toggleCompletion(String homeworkId) async {
    final index = _homework.indexWhere((h) => h.id == homeworkId);
    if (index < 0) return;

    final homework = _homework[index];
    await updateHomework(homework.copyWith(isCompleted: !homework.isCompleted));
  }

  /// Get homework by ID
  Homework? getHomeworkById(String homeworkId) {
    try {
      return _homework.firstWhere((h) => h.id == homeworkId && !h.isDeleted);
    } catch (e) {
      return null;
    }
  }
}

// Hive type adapter for Homework
class HomeworkAdapter extends TypeAdapter<Homework> {
  @override
  final int typeId = 4;

  @override
  Homework read(BinaryReader reader) {
    return Homework(
      id: reader.readString(),
      title: reader.readString(),
      description: reader.readBool() ? reader.readString() : null,
      subject: reader.readBool() ? reader.readString() : null,
      dueDate: reader.readBool() ? DateTime.parse(reader.readString()) : null,
      priority: HomeworkPriority.values[reader.readInt()],
      isCompleted: reader.readBool(),
      noteId: reader.readBool() ? reader.readString() : null,
      userId: reader.readString(),
      createdAt: DateTime.parse(reader.readString()),
      updatedAt: DateTime.parse(reader.readString()),
      isDirty: reader.readBool(),
      isDeleted: reader.readBool(),
    );
  }

  @override
  void write(BinaryWriter writer, Homework obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.title);
    writer.writeBool(obj.description != null);
    if (obj.description != null) {
      writer.writeString(obj.description!);
    }
    writer.writeBool(obj.subject != null);
    if (obj.subject != null) {
      writer.writeString(obj.subject!);
    }
    writer.writeBool(obj.dueDate != null);
    if (obj.dueDate != null) {
      writer.writeString(obj.dueDate!.toIso8601String());
    }
    writer.writeInt(obj.priority.index);
    writer.writeBool(obj.isCompleted);
    writer.writeBool(obj.noteId != null);
    if (obj.noteId != null) {
      writer.writeString(obj.noteId!);
    }
    writer.writeString(obj.userId);
    writer.writeString(obj.createdAt.toIso8601String());
    writer.writeString(obj.updatedAt.toIso8601String());
    writer.writeBool(obj.isDirty);
    writer.writeBool(obj.isDeleted);
  }
}
