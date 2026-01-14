/// Sync Service
///
/// Handles real-time synchronization of notes and folders between
/// local storage and Firebase. Supports offline-first with background sync.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:rxdart/rxdart.dart';

import '../models/note.dart';
import '../models/folder.dart';

/// Sync status enum
enum SyncStatus {
  idle,
  syncing,
  synced,
  error,
  offline,
}

/// Real-time sync service for cross-device synchronization
///
/// Implements an offline-first approach where changes are saved
/// locally first, then synced to Firebase when online.
class SyncService extends ChangeNotifier {
  // Lazy Firebase Firestore instance
  FirebaseFirestore? _firestore;
  FirebaseFirestore get _firebaseFirestore {
    try {
      _firestore ??= FirebaseFirestore.instance;
      return _firestore!;
    } catch (e) {
      debugPrint('Firebase Firestore not available: $e');
      rethrow;
    }
  }

  final Connectivity _connectivity = Connectivity();

  // Sync state
  SyncStatus _status = SyncStatus.idle;
  String? _errorMessage;
  DateTime? _lastSyncTime;
  bool _isOnline = true;

  // Stream subscriptions for real-time updates
  StreamSubscription? _notesSubscription;
  StreamSubscription? _foldersSubscription;
  StreamSubscription? _connectivitySubscription;

  // Debounce subject for batching sync operations
  final _syncSubject = BehaviorSubject<void>();

  // Callbacks for data updates
  Function(List<Note>)? onNotesUpdated;
  Function(List<Folder>)? onFoldersUpdated;

  // Sync enabled flag (set by AuthService)
  bool _syncEnabled = true;

  /// Set whether sync is enabled
  void setSyncEnabled(bool enabled) {
    if (!enabled) {
      _stopListening();
    }
    _syncEnabled = enabled;
    notifyListeners();
  }

  /// Whether sync is currently enabled
  bool get syncEnabled => _syncEnabled;

  // ===========================================
  // GETTERS
  // ===========================================

  SyncStatus get status => _status;
  String? get errorMessage => _errorMessage;
  DateTime? get lastSyncTime => _lastSyncTime;
  bool get isOnline => _isOnline;
  bool get isSyncing => _status == SyncStatus.syncing;

  // ===========================================
  // CONSTRUCTOR & INITIALIZATION
  // ===========================================

  SyncService() {
    _initConnectivityListener();
    _initSyncDebouncer();
  }

  /// Initialize connectivity listener
  void _initConnectivityListener() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (result) {
        final wasOffline = !_isOnline;
        _isOnline = result.any((r) => r != ConnectivityResult.none);

        if (_isOnline && wasOffline) {
          // Came back online, trigger sync
          _status = SyncStatus.idle;
          triggerSync();
        } else if (!_isOnline) {
          _status = SyncStatus.offline;
        }

        notifyListeners();
      },
    );
  }

  /// Initialize sync debouncer (batches rapid updates)
  void _initSyncDebouncer() {
    _syncSubject
        .debounceTime(const Duration(milliseconds: 500))
        .listen((_) => _performSync());
  }

  // ===========================================
  // PUBLIC METHODS
  // ===========================================

  /// Start listening to real-time updates for a user
  void startListening(String userId) {
    _stopListening();

    if (!_syncEnabled) {
      debugPrint('Sync is disabled, not starting listeners');
      return;
    }

    try {
      // Listen to notes collection
      _notesSubscription = _firebaseFirestore
          .collection('notes')
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .snapshots()
          .listen(
        (snapshot) {
          final notes =
              snapshot.docs.map((doc) => Note.fromJson(doc.data())).toList();
          onNotesUpdated?.call(notes);
          _lastSyncTime = DateTime.now();
          notifyListeners();
        },
        onError: (error) {
          _setError('Failed to sync notes: $error');
        },
      );

      // Listen to folders collection
      _foldersSubscription = _firebaseFirestore
          .collection('folders')
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .snapshots()
          .listen(
        (snapshot) {
          final folders =
              snapshot.docs.map((doc) => Folder.fromJson(doc.data())).toList();
          onFoldersUpdated?.call(folders);
        },
        onError: (error) {
          _setError('Failed to sync folders: $error');
        },
      );
    } catch (e) {
      // Firebase not initialized or unavailable
      debugPrint('Cannot start listening: Firebase not available - $e');
      _setError('Sync unavailable: Firebase not initialized');
    }
  }

  /// Stop listening to real-time updates
  void _stopListening() {
    _notesSubscription?.cancel();
    _foldersSubscription?.cancel();
  }

  /// Trigger a sync operation (debounced)
  void triggerSync() {
    if (!_isOnline || !_syncEnabled) return;
    _syncSubject.add(null);
  }

  /// Sync a single note to Firebase
  Future<bool> syncNote(Note note) async {
    if (!_isOnline || !_syncEnabled) {
      return false;
    }

    try {
      _setStatus(SyncStatus.syncing);

      await _firebaseFirestore
          .collection('notes')
          .doc(note.id)
          .set(note.toJson(), SetOptions(merge: true));

      _setStatus(SyncStatus.synced);
      _lastSyncTime = DateTime.now();
      return true;
    } catch (e) {
      _setError('Failed to sync note: $e');
      return false;
    }
  }

  /// Sync a single folder to Firebase
  Future<bool> syncFolder(Folder folder) async {
    if (!_isOnline || !_syncEnabled) {
      return false;
    }

    try {
      _setStatus(SyncStatus.syncing);

      await _firebaseFirestore
          .collection('folders')
          .doc(folder.id)
          .set(folder.toJson(), SetOptions(merge: true));

      _setStatus(SyncStatus.synced);
      _lastSyncTime = DateTime.now();
      return true;
    } catch (e) {
      _setError('Failed to sync folder: $e');
      return false;
    }
  }

  /// Delete a note from Firebase (soft delete)
  Future<bool> deleteNote(String noteId) async {
    if (!_isOnline || !_syncEnabled) return false;

    try {
      await _firebaseFirestore.collection('notes').doc(noteId).update(
          {'isDeleted': true, 'updatedAt': DateTime.now().toIso8601String()},);
      return true;
    } catch (e) {
      _setError('Failed to delete note: $e');
      return false;
    }
  }

  /// Delete a folder from Firebase (soft delete)
  Future<bool> deleteFolder(String folderId) async {
    if (!_isOnline || !_syncEnabled) return false;

    try {
      await _firebaseFirestore.collection('folders').doc(folderId).update(
          {'isDeleted': true, 'updatedAt': DateTime.now().toIso8601String()},);
      return true;
    } catch (e) {
      _setError('Failed to delete folder: $e');
      return false;
    }
  }

  /// Sync a timetable entry to Firebase
  Future<bool> syncTimetableEntry(Map<String, dynamic> entryData) async {
    if (!_isOnline || !_syncEnabled) {
      return false;
    }

    try {
      _setStatus(SyncStatus.syncing);

      final entryId = entryData['id'] as String;
      await _firebaseFirestore
          .collection('timetable_entries')
          .doc(entryId)
          .set(entryData, SetOptions(merge: true));

      _setStatus(SyncStatus.synced);
      _lastSyncTime = DateTime.now();
      return true;
    } catch (e) {
      _setError('Failed to sync timetable entry: $e');
      return false;
    }
  }

  /// Sync a homework task to Firebase
  Future<bool> syncHomework(Map<String, dynamic> homeworkData) async {
    if (!_isOnline || !_syncEnabled) {
      return false;
    }

    try {
      _setStatus(SyncStatus.syncing);

      final homeworkId = homeworkData['id'] as String;
      await _firebaseFirestore
          .collection('homework')
          .doc(homeworkId)
          .set(homeworkData, SetOptions(merge: true));

      _setStatus(SyncStatus.synced);
      _lastSyncTime = DateTime.now();
      return true;
    } catch (e) {
      _setError('Failed to sync homework: $e');
      return false;
    }
  }

  /// Delete a homework task from Firebase (soft delete)
  Future<bool> deleteHomework(String homeworkId) async {
    if (!_isOnline || !_syncEnabled) return false;

    try {
      await _firebaseFirestore.collection('homework').doc(homeworkId).update(
          {'isDeleted': true, 'updatedAt': DateTime.now().toIso8601String()},);
      return true;
    } catch (e) {
      _setError('Failed to delete homework: $e');
      return false;
    }
  }

  /// Sync a calendar event to Firebase
  Future<bool> syncCalendarEvent(Map<String, dynamic> eventData) async {
    if (!_isOnline || !_syncEnabled) {
      return false;
    }

    try {
      _setStatus(SyncStatus.syncing);

      final eventId = eventData['id'] as String;
      await _firebaseFirestore
          .collection('calendar_events')
          .doc(eventId)
          .set(eventData, SetOptions(merge: true));

      _setStatus(SyncStatus.synced);
      _lastSyncTime = DateTime.now();
      return true;
    } catch (e) {
      _setError('Failed to sync calendar event: $e');
      return false;
    }
  }

  /// Delete a calendar event from Firebase (soft delete)
  Future<bool> deleteCalendarEvent(String eventId) async {
    if (!_isOnline || !_syncEnabled) return false;

    try {
      await _firebaseFirestore
          .collection('calendar_events')
          .doc(eventId)
          .update({'isDeleted': true});
      return true;
    } catch (e) {
      _setError('Failed to delete calendar event: $e');
      return false;
    }
  }

  /// Sync all dirty (unsynced) items
  Future<void> syncDirtyItems({
    required List<Note> dirtyNotes,
    required List<Folder> dirtyFolders,
  }) async {
    if (!_isOnline ||
        !_syncEnabled ||
        (dirtyNotes.isEmpty && dirtyFolders.isEmpty)) {
      return;
    }

    _setStatus(SyncStatus.syncing);

    try {
      // Use batched writes for efficiency
      final batch = _firebaseFirestore.batch();

      for (final note in dirtyNotes) {
        final ref = _firebaseFirestore.collection('notes').doc(note.id);
        batch.set(
            ref,
            note
                .copyWith(
                  isDirty: false,
                  syncedAt: DateTime.now(),
                )
                .toJson(),
            SetOptions(merge: true),);
      }

      for (final folder in dirtyFolders) {
        final ref = _firebaseFirestore.collection('folders').doc(folder.id);
        batch.set(
            ref,
            folder
                .copyWith(
                  isDirty: false,
                  syncedAt: DateTime.now(),
                )
                .toJson(),
            SetOptions(merge: true),);
      }

      await batch.commit();

      _setStatus(SyncStatus.synced);
      _lastSyncTime = DateTime.now();
    } catch (e) {
      _setError('Sync failed: $e');
    }
  }

  // ===========================================
  // PRIVATE METHODS
  // ===========================================

  /// Perform background sync
  Future<void> _performSync() async {
    if (!_isOnline || !_syncEnabled) return;

    // This is called by the debouncer
    // Actual sync logic is handled by individual sync methods
    _lastSyncTime = DateTime.now();
    notifyListeners();
  }

  void _setStatus(SyncStatus newStatus) {
    _status = newStatus;
    if (newStatus != SyncStatus.error) {
      _errorMessage = null;
    }
    notifyListeners();
  }

  void _setError(String message) {
    _status = SyncStatus.error;
    _errorMessage = message;
    notifyListeners();

    // Auto-recover after error
    Future.delayed(const Duration(seconds: 5), () {
      if (_status == SyncStatus.error) {
        _status = _isOnline ? SyncStatus.idle : SyncStatus.offline;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _stopListening();
    _connectivitySubscription?.cancel();
    _syncSubject.close();
    super.dispose();
  }
}
