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
import 'package:firedart/firedart.dart' as fd;

import '../models/note.dart';
import '../models/folder.dart';
import '../models/calendar_event.dart';
import '../models/homework.dart';
import '../models/timetable_entry.dart';

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
  FirebaseFirestore? get _firebaseFirestore {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      return null; // We use Firedart on Linux instead
    }
    try {
      _firestore ??= FirebaseFirestore.instance;
      return _firestore;
    } catch (e) {
      debugPrint('Firebase Firestore not available: $e');
      return null;
    }
  }

  // Firedart instance for Linux
  fd.Firestore? _fdFirestore;
  fd.Firestore? get _firedartFirestore {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      try {
        _fdFirestore ??= fd.Firestore.instance;
        return _fdFirestore;
      } catch (e) {
        debugPrint('Firedart Firestore not available: $e');
        return null;
      }
    }
    return null;
  }

  final Connectivity _connectivity = Connectivity();

  // Sync state
  SyncStatus _status = SyncStatus.idle;
  String? _errorMessage;
  DateTime? _lastSyncTime;
  bool _isOnline = true;

  // Stream subscriptions for real-time updates (cloud_firestore)
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _notesSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _foldersSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _calendarSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _homeworkSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _timetableSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _settingsSubscription;

  // Stream subscriptions for real-time updates (firedart)
  StreamSubscription<List<fd.Document>>? _fdNotesSubscription;
  StreamSubscription<List<fd.Document>>? _fdFoldersSubscription;
  StreamSubscription<List<fd.Document>>? _fdCalendarSubscription;
  StreamSubscription<List<fd.Document>>? _fdHomeworkSubscription;
  StreamSubscription<List<fd.Document>>? _fdTimetableSubscription;
  StreamSubscription<fd.Document?>? _fdSettingsSubscription;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Debounce subject for batching sync operations
  final _syncSubject = BehaviorSubject<void>();

  // Callbacks for data updates
  void Function(List<Note>)? onNotesUpdated;
  void Function(List<Folder>)? onFoldersUpdated;
  void Function(List<CalendarEvent>)? onCalendarUpdated;
  void Function(List<Homework>)? onHomeworkUpdated;
  void Function(List<TimetableEntry>)? onTimetableUpdated;
  void Function(Map<String, dynamic>)? onSettingsUpdated;

  // Stream for triggering sync across providers
  final _syncTriggerController = StreamController<void>.broadcast();
  Stream<void> get syncTriggerStream => _syncTriggerController.stream;

  // Sync enabled flag (set by AuthService)
  bool _syncEnabled = true;

  /// Set whether sync is enabled
  void setSyncEnabled(bool enabled) {
    if (!enabled) {
      stopListening();
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
        .debounceTime(const Duration(milliseconds: 200)) // Reduced from 500ms
        .listen((_) => _performSync());
  }

  // ===========================================
  // PUBLIC METHODS
  // ===========================================

  // Current user ID for sync
  String? _currentUserId;

  /// Start listening to real-time updates for a user
  void startListening(String userId) {
    stopListening();
    _currentUserId = userId;

    if (!_syncEnabled) {
      debugPrint('Sync is disabled, not starting listeners');
      return;
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      _startListeningFiredart(userId);
      return;
    }

    final firestore = _firebaseFirestore;
    if (firestore == null) {
      debugPrint('Cannot start listening: Firebase not available');
      _setError('Sync unavailable: Firebase not initialized');
      return;
    }

    try {
      // Listen to notes collection
      _notesSubscription = firestore
          .collection('notes')
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .snapshots()
          .listen(
        (snapshot) {
          debugPrint(
            'SyncService: Received ${snapshot.docs.length} notes from Firestore',
          );
          final notes =
              snapshot.docs.map((doc) => Note.fromJson(doc.data())).toList();
          onNotesUpdated?.call(notes);
          _lastSyncTime = DateTime.now();

          // If we were syncing/refreshing, transition back to idle/synced
          if (_status == SyncStatus.syncing) {
            _setStatus(SyncStatus.synced);
          } else if (_status != SyncStatus.error) {
            notifyListeners();
          }
        },
        onError: (Object error) {
          _setError('Failed to sync notes: $error');
        },
      );

      // Listen to folders collection
      _foldersSubscription = firestore
          .collection('folders')
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .snapshots()
          .listen(
        (snapshot) {
          debugPrint(
            'SyncService: Received ${snapshot.docs.length} folders from Firestore',
          );
          final folders =
              snapshot.docs.map((doc) => Folder.fromJson(doc.data())).toList();
          onFoldersUpdated?.call(folders);

          if (_status == SyncStatus.syncing) {
            _setStatus(SyncStatus.synced);
          } else if (_status != SyncStatus.error) {
            notifyListeners();
          }
        },
        onError: (Object error) {
          _setError('Failed to sync folders: $error');
        },
      );

      // Listen to calendar_events collection
      _calendarSubscription = firestore
          .collection('calendar_events')
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .snapshots()
          .listen(
        (snapshot) {
          debugPrint(
            'SyncService: Received ${snapshot.docs.length} calendar events from Firestore',
          );
          final events = snapshot.docs
              .map((doc) => CalendarEvent.fromJson(doc.data()))
              .toList();
          onCalendarUpdated?.call(events);
        },
        onError: (Object error) => _setError('Failed to sync calendar: $error'),
      );

      // Listen to homework collection
      _homeworkSubscription = firestore
          .collection('homework')
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .snapshots()
          .listen(
        (snapshot) {
          debugPrint(
            'SyncService: Received ${snapshot.docs.length} homework from Firestore',
          );
          final tasks = snapshot.docs
              .map((doc) => Homework.fromJson(doc.data()))
              .toList();
          onHomeworkUpdated?.call(tasks);
        },
        onError: (Object error) => _setError('Failed to sync homework: $error'),
      );

      // Listen to timetable_entries collection
      _timetableSubscription = firestore
          .collection('timetable_entries')
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .snapshots()
          .listen(
        (snapshot) {
          debugPrint(
            'SyncService: Received ${snapshot.docs.length} timetable entries from Firestore',
          );
          final entries = snapshot.docs
              .map((doc) => TimetableEntry.fromJson(doc.data()))
              .toList();
          onTimetableUpdated?.call(entries);
        },
        onError: (Object error) =>
            _setError('Failed to sync timetable: $error'),
      );

      // Listen to user settings document
      _settingsSubscription = firestore
          .collection('users')
          .doc(userId)
          .collection('settings')
          .doc('app_settings')
          .snapshots()
          .listen(
        (snapshot) {
          if (snapshot.exists && snapshot.data() != null) {
            debugPrint('SyncService: Received settings update from Firestore');
            onSettingsUpdated?.call(snapshot.data()!);
          }
        },
        onError: (Object error) => _setError('Failed to sync settings: $error'),
      );
    } catch (e) {
      // Firebase not initialized or unavailable
      debugPrint('Cannot start listening: Firebase not available - $e');
      _setError('Sync unavailable: Firebase not initialized');
    }
  }

  /// Start listening to Firedart (Linux) real-time updates
  void _startListeningFiredart(String userId) {
    final firestore = _firedartFirestore;
    if (firestore == null) {
      debugPrint('Cannot start listening: Firedart Firestore not available');
      _setError('Sync unavailable: Firedart Firestore not initialized');
      return;
    }

    try {
      // Listen to notes collection
      _fdNotesSubscription = firestore.collection('notes').stream.listen(
        (docs) {
          final filteredDocs = docs.where(
            (doc) =>
                doc.map['userId'] == userId && doc.map['isDeleted'] == false,
          );
          debugPrint(
            'SyncService [Linux]: Received ${filteredDocs.length} notes from Firestore',
          );
          final notes = filteredDocs.map((doc) {
            final data = doc.map;
            data['id'] = doc.id;
            return Note.fromJson(data);
          }).toList();
          onNotesUpdated?.call(notes);
          _lastSyncTime = DateTime.now();

          if (_status == SyncStatus.syncing) {
            _setStatus(SyncStatus.synced);
          } else if (_status != SyncStatus.error) {
            notifyListeners();
          }
        },
        onError: (Object error) {
          _setError('Failed to sync notes: $error');
        },
      );

      // Listen to folders collection
      _fdFoldersSubscription = firestore.collection('folders').stream.listen(
        (docs) {
          final filteredDocs = docs.where(
            (doc) =>
                doc.map['userId'] == userId && doc.map['isDeleted'] == false,
          );
          debugPrint(
            'SyncService [Linux]: Received ${filteredDocs.length} folders from Firestore',
          );
          final folders = filteredDocs.map((doc) {
            final data = doc.map;
            data['id'] = doc.id;
            return Folder.fromJson(data);
          }).toList();
          onFoldersUpdated?.call(folders);

          if (_status == SyncStatus.syncing) {
            _setStatus(SyncStatus.synced);
          } else if (_status != SyncStatus.error) {
            notifyListeners();
          }
        },
        onError: (Object error) {
          _setError('Failed to sync folders: $error');
        },
      );

      // Listen to calendar_events collection
      _fdCalendarSubscription =
          firestore.collection('calendar_events').stream.listen(
        (docs) {
          final filteredDocs = docs.where(
            (doc) =>
                doc.map['userId'] == userId && doc.map['isDeleted'] == false,
          );
          debugPrint(
            'SyncService [Linux]: Received ${filteredDocs.length} calendar events from Firestore',
          );
          final events = filteredDocs.map((doc) {
            final data = doc.map;
            data['id'] = doc.id;
            return CalendarEvent.fromJson(data);
          }).toList();
          onCalendarUpdated?.call(events);
        },
        onError: (Object error) => _setError('Failed to sync calendar: $error'),
      );

      // Listen to homework collection
      _fdHomeworkSubscription = firestore.collection('homework').stream.listen(
        (docs) {
          final filteredDocs = docs.where(
            (doc) =>
                doc.map['userId'] == userId && doc.map['isDeleted'] == false,
          );
          debugPrint(
            'SyncService [Linux]: Received ${filteredDocs.length} homework from Firestore',
          );
          final tasks = filteredDocs.map((doc) {
            final data = doc.map;
            data['id'] = doc.id;
            return Homework.fromJson(data);
          }).toList();
          onHomeworkUpdated?.call(tasks);
        },
        onError: (Object error) => _setError('Failed to sync homework: $error'),
      );

      // Listen to timetable_entries collection
      _fdTimetableSubscription =
          firestore.collection('timetable_entries').stream.listen(
        (docs) {
          final filteredDocs = docs.where(
            (doc) =>
                doc.map['userId'] == userId && doc.map['isDeleted'] == false,
          );
          debugPrint(
            'SyncService [Linux]: Received ${filteredDocs.length} timetable entries from Firestore',
          );
          final entries = filteredDocs.map((doc) {
            final data = doc.map;
            data['id'] = doc.id;
            return TimetableEntry.fromJson(data);
          }).toList();
          onTimetableUpdated?.call(entries);
        },
        onError: (Object error) =>
            _setError('Failed to sync timetable: $error'),
      );

      // Listen to user settings document
      _fdSettingsSubscription = firestore
          .collection('users')
          .document(userId)
          .collection('settings')
          .document('app_settings')
          .stream
          .listen(
        (doc) {
          if (doc != null) {
            debugPrint(
              'SyncService [Linux]: Received settings update from Firestore',
            );
            final data = doc.map;
            data['id'] = doc.id;
            onSettingsUpdated?.call(data);
          }
        },
        onError: (Object error) => _setError('Failed to sync settings: $error'),
      );
    } catch (e) {
      debugPrint('Cannot start Firedart listening: $e');
      _setError('Sync unavailable: Firedart error');
    }
  }

  /// Stop listening to real-time updates
  void stopListening() {
    _notesSubscription?.cancel();
    _foldersSubscription?.cancel();
    _calendarSubscription?.cancel();
    _homeworkSubscription?.cancel();
    _timetableSubscription?.cancel();
    _settingsSubscription?.cancel();

    _fdNotesSubscription?.cancel();
    _fdFoldersSubscription?.cancel();
    _fdCalendarSubscription?.cancel();
    _fdHomeworkSubscription?.cancel();
    _fdTimetableSubscription?.cancel();
    _fdSettingsSubscription?.cancel();
  }

  /// Trigger a sync operation (debounced)
  void triggerSync() {
    if (!_isOnline || !_syncEnabled) return;
    _syncSubject.add(null);
  }

  /// Sync a single note to Firebase
  Future<bool> syncNote(Note note) async {
    if (!_isOnline || !_syncEnabled) return false;

    try {
      _setStatus(SyncStatus.syncing);

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        final fdFirestore = _firedartFirestore;
        if (fdFirestore == null) return false;
        await fdFirestore.collection('notes').document(note.id).update(
              note.toJson(),
            ); // Firedart doesn't have set with merge = true out of the box easily.
        // A safer approach in firedart:
        // Since note.toJson() contains all fields, set is fine.
        await fdFirestore
            .collection('notes')
            .document(note.id)
            .set(note.toJson());
      } else {
        final firestore = _firebaseFirestore;
        if (firestore == null) return false;
        await firestore
            .collection('notes')
            .doc(note.id)
            .set(note.toJson(), SetOptions(merge: true));
      }

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
    if (!_isOnline || !_syncEnabled) return false;

    try {
      _setStatus(SyncStatus.syncing);

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        final fdFirestore = _firedartFirestore;
        if (fdFirestore == null) return false;
        await fdFirestore
            .collection('folders')
            .document(folder.id)
            .set(folder.toJson());
      } else {
        final firestore = _firebaseFirestore;
        if (firestore == null) return false;
        await firestore
            .collection('folders')
            .doc(folder.id)
            .set(folder.toJson(), SetOptions(merge: true));
      }

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
      final updates = {
        'isDeleted': true,
        'updatedAt': DateTime.now().toIso8601String(),
      };
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        final fdFirestore = _firedartFirestore;
        if (fdFirestore == null) return false;
        await fdFirestore.collection('notes').document(noteId).update(updates);
      } else {
        final firestore = _firebaseFirestore;
        if (firestore == null) return false;
        await firestore.collection('notes').doc(noteId).update(updates);
      }
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
      final updates = {
        'isDeleted': true,
        'updatedAt': DateTime.now().toIso8601String(),
      };
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        final fdFirestore = _firedartFirestore;
        if (fdFirestore == null) return false;
        await fdFirestore
            .collection('folders')
            .document(folderId)
            .update(updates);
      } else {
        final firestore = _firebaseFirestore;
        if (firestore == null) return false;
        await firestore.collection('folders').doc(folderId).update(updates);
      }
      return true;
    } catch (e) {
      _setError('Failed to delete folder: $e');
      return false;
    }
  }

  /// Sync a timetable entry to Firebase
  Future<bool> syncTimetableEntry(Map<String, dynamic> entryData) async {
    if (!_isOnline || !_syncEnabled) return false;

    try {
      _setStatus(SyncStatus.syncing);

      final entryId = entryData['id'] as String;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        final fdFirestore = _firedartFirestore;
        if (fdFirestore == null) return false;
        await fdFirestore
            .collection('timetable_entries')
            .document(entryId)
            .set(entryData);
      } else {
        final firestore = _firebaseFirestore;
        if (firestore == null) return false;
        await firestore
            .collection('timetable_entries')
            .doc(entryId)
            .set(entryData, SetOptions(merge: true));
      }

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
    if (!_isOnline || !_syncEnabled) return false;

    try {
      _setStatus(SyncStatus.syncing);

      final homeworkId = homeworkData['id'] as String;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        final fdFirestore = _firedartFirestore;
        if (fdFirestore == null) return false;
        await fdFirestore
            .collection('homework')
            .document(homeworkId)
            .set(homeworkData);
      } else {
        final firestore = _firebaseFirestore;
        if (firestore == null) return false;
        await firestore
            .collection('homework')
            .doc(homeworkId)
            .set(homeworkData, SetOptions(merge: true));
      }

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
      final updates = {
        'isDeleted': true,
        'updatedAt': DateTime.now().toIso8601String(),
      };
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        final fdFirestore = _firedartFirestore;
        if (fdFirestore == null) return false;
        await fdFirestore
            .collection('homework')
            .document(homeworkId)
            .update(updates);
      } else {
        final firestore = _firebaseFirestore;
        if (firestore == null) return false;
        await firestore.collection('homework').doc(homeworkId).update(updates);
      }
      return true;
    } catch (e) {
      _setError('Failed to delete homework: $e');
      return false;
    }
  }

  /// Sync a calendar event to Firebase
  Future<bool> syncCalendarEvent(Map<String, dynamic> eventData) async {
    if (!_isOnline || !_syncEnabled) return false;

    try {
      _setStatus(SyncStatus.syncing);

      final eventId = eventData['id'] as String;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        final fdFirestore = _firedartFirestore;
        if (fdFirestore == null) return false;
        await fdFirestore
            .collection('calendar_events')
            .document(eventId)
            .set(eventData);
      } else {
        final firestore = _firebaseFirestore;
        if (firestore == null) return false;
        await firestore
            .collection('calendar_events')
            .doc(eventId)
            .set(eventData, SetOptions(merge: true));
      }

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
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        final fdFirestore = _firedartFirestore;
        if (fdFirestore == null) return false;
        await fdFirestore
            .collection('calendar_events')
            .document(eventId)
            .update({'isDeleted': true});
      } else {
        final firestore = _firebaseFirestore;
        if (firestore == null) return false;
        await firestore
            .collection('calendar_events')
            .doc(eventId)
            .update({'isDeleted': true});
      }
      return true;
    } catch (e) {
      _setError('Failed to delete calendar event: $e');
      return false;
    }
  }

  /// Sync user settings to Firestore
  Future<bool> syncSettings(Map<String, dynamic> settingsData) async {
    if (!_isOnline || !_syncEnabled || _currentUserId == null) return false;

    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        final fdFirestore = _firedartFirestore;
        if (fdFirestore == null) return false;
        await fdFirestore
            .collection('users')
            .document(_currentUserId!)
            .collection('settings')
            .document('app_settings')
            .set(settingsData);
      } else {
        final firestore = _firebaseFirestore;
        if (firestore == null) return false;
        await firestore
            .collection('users')
            .doc(_currentUserId)
            .collection('settings')
            .doc('app_settings')
            .set(settingsData, SetOptions(merge: true));
      }
      return true;
    } catch (e) {
      debugPrint('SyncService: Failed to sync settings: $e');
      return false;
    }
  }

  /// Sync all dirty (unsynced) items
  Future<bool> syncDirtyItems({
    List<Note>? dirtyNotes,
    List<Folder>? dirtyFolders,
    List<CalendarEvent>? dirtyEvents,
    List<Homework>? dirtyHomework,
    List<TimetableEntry>? dirtyEntries,
  }) async {
    if (!_isOnline || !_syncEnabled) {
      return true;
    }

    final hasNotes = dirtyNotes != null && dirtyNotes.isNotEmpty;
    final hasFolders = dirtyFolders != null && dirtyFolders.isNotEmpty;
    final hasEvents = dirtyEvents != null && dirtyEvents.isNotEmpty;
    final hasHomework = dirtyHomework != null && dirtyHomework.isNotEmpty;
    final hasEntries = dirtyEntries != null && dirtyEntries.isNotEmpty;

    if (!hasNotes && !hasFolders && !hasEvents && !hasHomework && !hasEntries) {
      return true;
    }

    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        final fdFirestore = _firedartFirestore;
        if (fdFirestore == null) return false;

        debugPrint(
          'SyncService [Linux]: Committing batch sync for ${dirtyNotes?.length ?? 0} notes, ${dirtyFolders?.length ?? 0} folders, ${dirtyEvents?.length ?? 0} events, ${dirtyHomework?.length ?? 0} homework, ${dirtyEntries?.length ?? 0} entries',
        );

        // Firedart doesn't natively expose batch operations in the same way,
        // so we can execute them concurrently as standard updates.
        final futures = <Future<void>>[];

        if (hasNotes) {
          for (final note in dirtyNotes) {
            futures.add(
              fdFirestore.collection('notes').document(note.id).set(
                    note
                        .copyWith(isDirty: false, syncedAt: DateTime.now())
                        .toJson(),
                  ),
            );
          }
        }

        if (hasFolders) {
          for (final folder in dirtyFolders) {
            futures.add(
              fdFirestore.collection('folders').document(folder.id).set(
                    folder
                        .copyWith(isDirty: false, syncedAt: DateTime.now())
                        .toJson(),
                  ),
            );
          }
        }

        if (hasEvents) {
          for (final event in dirtyEvents) {
            futures.add(
              fdFirestore.collection('calendar_events').document(event.id).set(
                    event.copyWith(isDirty: false).toJson(),
                  ),
            );
          }
        }

        if (hasHomework) {
          for (final homework in dirtyHomework) {
            futures.add(
              fdFirestore.collection('homework').document(homework.id).set(
                    homework.copyWith(isDirty: false).toJson(),
                  ),
            );
          }
        }

        if (hasEntries) {
          for (final entry in dirtyEntries) {
            futures.add(
              fdFirestore
                  .collection('timetable_entries')
                  .document(entry.id)
                  .set(
                    entry.copyWith(isDirty: false).toJson(),
                  ),
            );
          }
        }

        await Future.wait(futures);
      } else {
        final firestore = _firebaseFirestore;
        if (firestore == null) {
          _setError('Sync failed: Firebase not available');
          return false;
        }

        final batch = firestore.batch();

        debugPrint(
          'SyncService: Committing batch sync for ${dirtyNotes?.length ?? 0} notes, ${dirtyFolders?.length ?? 0} folders, ${dirtyEvents?.length ?? 0} events, ${dirtyHomework?.length ?? 0} homework, ${dirtyEntries?.length ?? 0} entries',
        );

        if (hasNotes) {
          for (final note in dirtyNotes) {
            final ref = firestore.collection('notes').doc(note.id);
            batch.set(
              ref,
              note.copyWith(isDirty: false, syncedAt: DateTime.now()).toJson(),
              SetOptions(merge: true),
            );
          }
        }

        if (hasFolders) {
          for (final folder in dirtyFolders) {
            final ref = firestore.collection('folders').doc(folder.id);
            batch.set(
              ref,
              folder
                  .copyWith(isDirty: false, syncedAt: DateTime.now())
                  .toJson(),
              SetOptions(merge: true),
            );
          }
        }

        if (hasEvents) {
          for (final event in dirtyEvents) {
            final ref = firestore.collection('calendar_events').doc(event.id);
            batch.set(
              ref,
              event.copyWith(isDirty: false).toJson(),
              SetOptions(merge: true),
            );
          }
        }

        if (hasHomework) {
          for (final homework in dirtyHomework) {
            final ref = firestore.collection('homework').doc(homework.id);
            batch.set(
              ref,
              homework.copyWith(isDirty: false).toJson(),
              SetOptions(merge: true),
            );
          }
        }

        if (hasEntries) {
          for (final entry in dirtyEntries) {
            final ref = firestore.collection('timetable_entries').doc(entry.id);
            batch.set(
              ref,
              entry.copyWith(isDirty: false).toJson(),
              SetOptions(merge: true),
            );
          }
        }

        await batch.commit();
      }

      _setStatus(SyncStatus.synced);
      _lastSyncTime = DateTime.now();
      return true;
    } catch (e) {
      debugPrint('SyncService: Sync failed: $e');
      _setError('Sync failed: $e');
      return false;
    }
  }

  // ===========================================
  // PRIVATE METHODS
  // ===========================================

  /// Perform background sync
  Future<void> _performSync() async {
    if (!_isOnline || !_syncEnabled) return;

    // Notify listeners/providers that it's time to sync dirty items
    _syncTriggerController.add(null);

    _lastSyncTime = DateTime.now();
    if (_status == SyncStatus.syncing) {
      _setStatus(SyncStatus.synced);
    } else {
      notifyListeners();
    }
  }

  /// Force a refresh of the sync connection
  void refresh() {
    _setStatus(SyncStatus.syncing);

    // Trigger immediate sync attempt
    if (_syncEnabled && _isOnline) {
      // Reset error status
      _errorMessage = null;

      // If we assume the issue might be a broken stream, let's restart listeners if we can
      if (_currentUserId != null) {
        debugPrint('Restarting sync listeners for user: $_currentUserId');
        startListening(_currentUserId!);
      } else {
        debugPrint(
          'Cannot restart listeners: userId unknown. Just triggering push sync.',
        );
        triggerSync();
      }

      notifyListeners();
    } else {
      // If offline, just show offline status
      if (!_isOnline) {
        _status = SyncStatus.offline;
      } else {
        _status = SyncStatus.idle;
      }
      notifyListeners();
    }
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
    // Use microtask to avoid setState during build
    Future.microtask(() => notifyListeners());
    // Auto-recovery removed to allow user to see error and retry manually
  }

  @override
  void dispose() {
    stopListening();
    _connectivitySubscription?.cancel();
    _syncSubject.close();
    _syncTriggerController.close();
    super.dispose();
  }
}
