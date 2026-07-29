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
import '../models/tag.dart';
import '../models/timetable_entry.dart';
import 'diagnostics_service.dart';

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
  Timer? _refreshTimeoutTimer;
  Timer? _linuxWorkspaceRefreshTimer;
  bool _awaitingRefreshResult = false;

  static const Duration _linuxWorkspaceRefreshInterval = Duration(seconds: 15);

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
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _activeNoteSubscription;

  // Stream subscriptions for real-time updates (firedart)
  StreamSubscription<List<fd.Document>>? _fdNotesSubscription;
  StreamSubscription<List<fd.Document>>? _fdFoldersSubscription;
  StreamSubscription<List<fd.Document>>? _fdCalendarSubscription;
  StreamSubscription<List<fd.Document>>? _fdHomeworkSubscription;
  StreamSubscription<List<fd.Document>>? _fdTimetableSubscription;
  StreamSubscription<fd.Document?>? _fdSettingsSubscription;
  StreamSubscription<fd.Document?>? _fdActiveNoteSubscription;

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
  void Function(Note)? onNoteUpdated;

  // Stream for triggering sync across providers
  final _syncTriggerController = StreamController<void>.broadcast();
  Stream<void> get syncTriggerStream => _syncTriggerController.stream;

  // Sync enabled flag (set by AuthService)
  bool _syncEnabled = true;

  /// Set whether sync is enabled
  void setSyncEnabled(bool enabled) {
    if (_syncEnabled == enabled) {
      return;
    }
    if (!enabled) {
      stopListening(reason: 'sync disabled');
    }
    _syncEnabled = enabled;
    _diagnostics.info(
      'SyncService',
      'SYNC_LIFECYCLE syncEnabled=$_syncEnabled currentUser=$_currentUserId',
    );
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

  final DiagnosticsService _diagnostics = DiagnosticsService.instance;

  /// Initialize connectivity listener
  void _initConnectivityListener() {
    // Check initial connectivity
    _connectivity.checkConnectivity().then((results) {
      _updateConnectivity(results);
    }).catchError((e) {
      if (kDebugMode) {
        debugPrint('Failed to check initial connectivity: $e');
      }
    });

    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (results) {
        _updateConnectivity(results);
      },
    );
  }

  void _updateConnectivity(List<ConnectivityResult> results) {
    final wasOffline = !_isOnline;
    _isOnline = results.any((r) => r != ConnectivityResult.none);

    if (_isOnline && wasOffline) {
      // Came back online, trigger sync and restart listeners if we have a user
      _status = SyncStatus.idle;
      if (_currentUserId != null && _syncEnabled) {
        startCoreListening(_currentUserId!);
        unawaited(fetchWorkspaceSnapshot(_currentUserId!));
      }
      triggerSync();
    } else if (!_isOnline) {
      _status = SyncStatus.offline;
    }

    notifyListeners();
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
  String? _activeNoteId;
  bool _listenersActive = false;
  int _listenerGeneration = 0;
  int _snapshotGeneration = 0;

  /// Start listening to real-time updates for a user
  void startListening(String userId) {
    startCoreListening(userId);
    unawaited(fetchWorkspaceSnapshot(userId));
  }

  void startCoreListening(String userId) {
    if (_currentUserId == userId &&
        _listenersActive &&
        (_settingsSubscription != null || _fdSettingsSubscription != null) &&
        (_calendarSubscription != null ||
            _linuxWorkspaceRefreshTimer != null)) {
      _diagnostics.info(
        'SyncService',
        'SYNC_LIFECYCLE reused core listeners for user=$userId generation=$_listenerGeneration',
      );
      return;
    }

    if (_currentUserId != userId) {
      stopListening(reason: 'startCoreListening($userId)');
    } else {
      _cancelCoreListeners();
    }

    _currentUserId = userId;

    if (!_isOnline) {
      _diagnostics.info(
        'SyncService',
        'SYNC_LIFECYCLE offline; listeners deferred for user=$userId',
      );
      _status = SyncStatus.offline;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        _listenersActive = false;
        notifyListeners();
        return;
      }
    }

    final generation = ++_listenerGeneration;
    _listenersActive = true;
    _setStatus(SyncStatus.syncing);
    _diagnostics.info(
      'SyncService',
      'SYNC_SCOPE starting core listeners scope=core:settings user=$userId generation=$generation platform=${defaultTargetPlatform.name}',
    );

    if (!_syncEnabled) {
      _diagnostics.warning(
        'SyncService',
        'SYNC_LIFECYCLE sync is disabled; listeners not started for user=$userId',
      );
      _listenersActive = false;
      return;
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      _startLinuxWorkspaceRefreshTimer(userId);
      _startCoreListeningFiredart(userId, generation);
      return;
    }

    final firestore = _firebaseFirestore;
    if (firestore == null) {
      _setError('Sync unavailable: Firebase not initialized');
      return;
    }

    try {
      _settingsSubscription = firestore
          .collection('users')
          .doc(userId)
          .collection('settings')
          .doc('app_settings')
          .snapshots()
          .listen(
        (snapshot) {
          if (generation != _listenerGeneration) {
            return;
          }
          if (snapshot.exists && snapshot.data() != null) {
            debugPrint('SyncService: Received settings update from Firestore');
            onSettingsUpdated?.call(snapshot.data()!);
            _lastSyncTime = DateTime.now();
            _markRefreshSucceeded('Received settings update');
            if (_status == SyncStatus.syncing) {
              _setStatus(SyncStatus.synced);
            }
          }
        },
        onError: (Object error) => _setError('Failed to sync settings: $error'),
      );

      // Calendar events need a collection listener because, unlike an open
      // note, there is no single active document to subscribe to.
      _calendarSubscription = firestore
          .collection('calendar_events')
          .where('userId', isEqualTo: userId)
          .snapshots()
          .listen(
        (snapshot) {
          if (generation != _listenerGeneration) {
            return;
          }

          final events = <CalendarEvent>[];
          for (final doc in snapshot.docs) {
            try {
              events.add(CalendarEvent.fromJson(doc.data()));
            } catch (e) {
              _diagnostics.warning(
                'SyncService',
                'Skipped malformed calendar event ${doc.id} during live update: $e',
              );
            }
          }

          onCalendarUpdated?.call(events);
          _lastSyncTime = DateTime.now();
          _markRefreshSucceeded('Received calendar update');
          if (_status == SyncStatus.syncing) {
            _setStatus(SyncStatus.synced);
          }
        },
        onError: (Object error) =>
            _setError('Failed to sync calendar events: $error'),
      );
    } catch (e) {
      // Firebase not initialized or unavailable
      debugPrint('Cannot start listening: Firebase not available - $e');
      _listenersActive = false;
      _setError('Sync unavailable: Firebase not initialized');
    }
  }

  Future<bool> fetchWorkspaceSnapshot(String userId) async {
    // Ensure we have correct connectivity status
    try {
      final results = await _connectivity.checkConnectivity();
      _isOnline = results.any((r) => r != ConnectivityResult.none);
      if (!_isOnline) {
        _status = SyncStatus.offline;
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'Failed to check connectivity in fetchWorkspaceSnapshot: $e',
        );
      }
    }

    if (!_isOnline || !_syncEnabled) {
      return true;
    }

    _currentUserId ??= userId;
    final generation = ++_snapshotGeneration;
    _setStatus(SyncStatus.syncing);
    _diagnostics.info(
      'SyncService',
      'SYNC_SCOPE fetching workspace snapshot scope=snapshot:workspace user=$userId generation=$generation platform=${defaultTargetPlatform.name}',
    );

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      return _fetchWorkspaceSnapshotFiredart(userId, generation);
    }

    final firestore = _firebaseFirestore;
    if (firestore == null) {
      _setError('Sync unavailable: Firebase not initialized');
      return false;
    }

    try {
      final notesDocs = await firestore
          .collection('notes')
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .get();
      final notes = <Note>[];
      for (final doc in notesDocs.docs) {
        try {
          notes.add(Note.fromJson(doc.data()));
        } catch (e) {
          _diagnostics.warning(
            'SyncService',
            'Skipped malformed note ${doc.id} during snapshot fetch: $e',
          );
        }
      }
      if (generation != _snapshotGeneration) return false;
      onNotesUpdated?.call(notes);

      final folderDocs = await firestore
          .collection('folders')
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .get();
      final folders =
          folderDocs.docs.map((doc) => Folder.fromJson(doc.data())).toList();
      if (generation != _snapshotGeneration) return false;
      onFoldersUpdated?.call(folders);

      final eventDocs = await firestore
          .collection('calendar_events')
          .where('userId', isEqualTo: userId)
          .get();
      final events = eventDocs.docs
          .map((doc) => CalendarEvent.fromJson(doc.data()))
          .toList();
      if (generation != _snapshotGeneration) return false;
      onCalendarUpdated?.call(events);

      final homeworkDocs = await firestore
          .collection('homework')
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .get();
      final homework = homeworkDocs.docs
          .map((doc) => Homework.fromJson(doc.data()))
          .toList();
      if (generation != _snapshotGeneration) return false;
      onHomeworkUpdated?.call(homework);

      final timetableDocs = await firestore
          .collection('timetable_entries')
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .get();
      final timetable = timetableDocs.docs
          .map((doc) => TimetableEntry.fromJson(doc.data()))
          .toList();
      if (generation != _snapshotGeneration) return false;
      onTimetableUpdated?.call(timetable);

      _diagnostics.info(
        'SyncService',
        'SYNC_SCOPE workspace snapshot loaded user=$userId generation=$generation notes=${notes.length} folders=${folders.length} events=${events.length} homework=${homework.length} timetable=${timetable.length}',
      );
      _lastSyncTime = DateTime.now();
      _markRefreshSucceeded('Workspace snapshot loaded');
      _setStatus(SyncStatus.synced);
      return true;
    } catch (e) {
      _setError('Workspace snapshot fetch failed: $e');
      return false;
    }
  }

  Future<bool> _fetchCalendarSnapshot(String userId) async {
    if (!_isOnline || !_syncEnabled || _currentUserId != userId) {
      return true;
    }

    final generation = _listenerGeneration;
    try {
      final events = <CalendarEvent>[];
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        final firestore = _firedartFirestore;
        if (firestore == null) {
          return false;
        }
        final docs = await firestore
            .collection('calendar_events')
            .where('userId', isEqualTo: userId)
            .get();
        for (final doc in docs) {
          try {
            final data = Map<String, dynamic>.from(doc.map);
            data['id'] = doc.id;
            events.add(CalendarEvent.fromJson(data));
          } catch (e) {
            _diagnostics.warning(
              'SyncService',
              'Skipped malformed Linux calendar event ${doc.id} during foreground refresh: $e',
            );
          }
        }
      } else {
        final firestore = _firebaseFirestore;
        if (firestore == null) {
          return false;
        }
        final snapshot = await firestore
            .collection('calendar_events')
            .where('userId', isEqualTo: userId)
            .get();
        for (final doc in snapshot.docs) {
          try {
            events.add(CalendarEvent.fromJson(doc.data()));
          } catch (e) {
            _diagnostics.warning(
              'SyncService',
              'Skipped malformed calendar event ${doc.id} during foreground refresh: $e',
            );
          }
        }
      }

      if (generation != _listenerGeneration || _currentUserId != userId) {
        return false;
      }
      onCalendarUpdated?.call(events);
      _lastSyncTime = DateTime.now();
      return true;
    } catch (e) {
      _diagnostics.warning(
        'SyncService',
        'Calendar foreground refresh failed for user=$userId: $e',
      );
      return false;
    }
  }

  void startNoteListening(String noteId) {
    final userId = _currentUserId;
    if (userId == null || !_isOnline || !_syncEnabled) {
      return;
    }
    if (_activeNoteId == noteId &&
        (_activeNoteSubscription != null ||
            _fdActiveNoteSubscription != null)) {
      return;
    }

    stopNoteListening();
    _activeNoteId = noteId;
    final generation = _listenerGeneration;
    _diagnostics.info(
      'SyncService',
      'SYNC_SCOPE starting active note listener scope=note:$noteId user=$userId generation=$generation',
    );

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      final firestore = _firedartFirestore;
      if (firestore == null) {
        _setError('Sync unavailable: Firedart Firestore not initialized');
        return;
      }
      _fdActiveNoteSubscription =
          firestore.collection('notes').document(noteId).stream.listen(
        (doc) {
          if (_activeNoteId != noteId || generation != _listenerGeneration) {
            return;
          }
          if (doc == null) return;
          final data = Map<String, dynamic>.from(doc.map);
          data['id'] = doc.id;
          final note = Note.fromJson(data);
          if (note.userId == userId) {
            onNoteUpdated?.call(note);
            _lastSyncTime = DateTime.now();
          }
        },
        onError: (Object error) => _setError('Failed to sync note: $error'),
      );
      return;
    }

    final firestore = _firebaseFirestore;
    if (firestore == null) {
      _setError('Sync unavailable: Firebase not initialized');
      return;
    }
    _activeNoteSubscription =
        firestore.collection('notes').doc(noteId).snapshots().listen(
      (snapshot) {
        if (_activeNoteId != noteId || generation != _listenerGeneration) {
          return;
        }
        final data = snapshot.data();
        if (!snapshot.exists || data == null) return;
        final note = Note.fromJson(data);
        if (note.userId == userId) {
          onNoteUpdated?.call(note);
          _lastSyncTime = DateTime.now();
        }
      },
      onError: (Object error) => _setError('Failed to sync note: $error'),
    );
  }

  void stopNoteListening([String? noteId]) {
    if (noteId != null && _activeNoteId != noteId) {
      return;
    }
    final hadListener =
        _activeNoteSubscription != null || _fdActiveNoteSubscription != null;
    if (hadListener) {
      _diagnostics.info(
        'SyncService',
        'SYNC_SCOPE stopping active note listener scope=note:${_activeNoteId ?? 'none'}',
      );
    }
    _activeNoteSubscription?.cancel();
    _fdActiveNoteSubscription?.cancel();
    _activeNoteSubscription = null;
    _fdActiveNoteSubscription = null;
    _activeNoteId = null;
  }

  /// Start listening to Firedart (Linux) real-time updates
  void _startCoreListeningFiredart(String userId, int generation) {
    final firestore = _firedartFirestore;
    if (firestore == null) {
      debugPrint('Cannot start listening: Firedart Firestore not available');
      _listenersActive = false;
      _setError('Sync unavailable: Firedart Firestore not initialized');
      return;
    }

    try {
      _fdSettingsSubscription = firestore
          .collection('users')
          .document(userId)
          .collection('settings')
          .document('app_settings')
          .stream
          .listen(
        (doc) {
          if (generation != _listenerGeneration) {
            return;
          }
          if (doc != null) {
            debugPrint(
              'SyncService [Linux]: Received settings update from Firestore',
            );
            final data = doc.map;
            data['id'] = doc.id;
            onSettingsUpdated?.call(data);
            _lastSyncTime = DateTime.now();
            _markRefreshSucceeded('Received Linux settings update');
            if (_status == SyncStatus.syncing) {
              _setStatus(SyncStatus.synced);
            }
          }
        },
        onError: (Object error) => _setError('Failed to sync settings: $error'),
      );
    } catch (e) {
      _listenersActive = false;
      _setError('Sync unavailable: Firedart error');
    }
  }

  Future<bool> _fetchWorkspaceSnapshotFiredart(
    String userId,
    int generation,
  ) async {
    final firestore = _firedartFirestore;
    if (firestore == null) {
      _setError('Sync unavailable: Firedart Firestore not initialized');
      return false;
    }

    try {
      _diagnostics.info(
        'SyncService',
        'SYNC_SCOPE fetching Linux workspace snapshot user=$userId generation=$generation',
      );

      final notesDocs = await firestore
          .collection('notes')
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .get();
      final notes = <Note>[];
      for (final doc in notesDocs) {
        try {
          final data = Map<String, dynamic>.from(doc.map);
          data['id'] = doc.id;
          notes.add(Note.fromJson(data));
        } catch (e) {
          _diagnostics.warning(
            'SyncService',
            'Skipped malformed Linux note ${doc.id} during initial fetch: $e',
          );
        }
      }
      if (generation != _snapshotGeneration) {
        _diagnostics.info(
          'SyncService',
          'SYNC_SCOPE discarded stale Linux notes snapshot user=$userId generation=$generation currentGeneration=$_snapshotGeneration',
        );
        return false;
      }
      onNotesUpdated?.call(notes);

      final folderDocs = await firestore
          .collection('folders')
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .get();
      final folders = <Folder>[];
      for (final doc in folderDocs) {
        try {
          final data = Map<String, dynamic>.from(doc.map);
          data['id'] = doc.id;
          folders.add(Folder.fromJson(data));
        } catch (e) {
          _diagnostics.warning(
            'SyncService',
            'Skipped malformed Linux folder ${doc.id} during initial fetch: $e',
          );
        }
      }
      if (generation != _snapshotGeneration) {
        _diagnostics.info(
          'SyncService',
          'SYNC_SCOPE discarded stale Linux folder snapshot user=$userId generation=$generation currentGeneration=$_snapshotGeneration',
        );
        return false;
      }
      onFoldersUpdated?.call(folders);

      final eventDocs = await firestore
          .collection('calendar_events')
          .where('userId', isEqualTo: userId)
          .get();
      final events = eventDocs.map((doc) {
        final data = Map<String, dynamic>.from(doc.map);
        data['id'] = doc.id;
        return CalendarEvent.fromJson(data);
      }).toList();
      if (generation != _snapshotGeneration) {
        return false;
      }
      onCalendarUpdated?.call(events);

      final homeworkDocs = await firestore
          .collection('homework')
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .get();
      final homework = homeworkDocs.map((doc) {
        final data = Map<String, dynamic>.from(doc.map);
        data['id'] = doc.id;
        return Homework.fromJson(data);
      }).toList();
      if (generation != _snapshotGeneration) {
        return false;
      }
      onHomeworkUpdated?.call(homework);

      final timetableDocs = await firestore
          .collection('timetable_entries')
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .get();
      final timetable = timetableDocs.map((doc) {
        final data = Map<String, dynamic>.from(doc.map);
        data['id'] = doc.id;
        return TimetableEntry.fromJson(data);
      }).toList();
      if (generation != _snapshotGeneration) {
        return false;
      }
      onTimetableUpdated?.call(timetable);

      _diagnostics.info(
        'SyncService',
        'SYNC_SCOPE Linux workspace snapshot loaded user=$userId generation=$generation notes=${notes.length} folders=${folders.length} events=${events.length} homework=${homework.length} timetable=${timetable.length}',
      );
      _lastSyncTime = DateTime.now();
      _markRefreshSucceeded('Initial Linux cloud snapshot loaded');
      _setStatus(SyncStatus.synced);
      return true;
    } catch (e) {
      _setError('Linux workspace snapshot fetch failed: $e');
      return false;
    }
  }

  /// Stop listening to real-time updates
  void stopListening({String reason = 'manual'}) {
    final hadListeners = _listenersActive ||
        _notesSubscription != null ||
        _foldersSubscription != null ||
        _calendarSubscription != null ||
        _homeworkSubscription != null ||
        _timetableSubscription != null ||
        _settingsSubscription != null ||
        _activeNoteSubscription != null ||
        _fdNotesSubscription != null ||
        _fdFoldersSubscription != null ||
        _fdCalendarSubscription != null ||
        _fdHomeworkSubscription != null ||
        _fdTimetableSubscription != null ||
        _fdSettingsSubscription != null ||
        _fdActiveNoteSubscription != null;
    _diagnostics.info(
      'SyncService',
      'SYNC_LIFECYCLE stopping listeners user=$_currentUserId generation=$_listenerGeneration reason=$reason hadListeners=$hadListeners',
    );
    _cancelRefreshTimeout();
    _linuxWorkspaceRefreshTimer?.cancel();
    _linuxWorkspaceRefreshTimer = null;
    _notesSubscription?.cancel();
    _foldersSubscription?.cancel();
    _calendarSubscription?.cancel();
    _homeworkSubscription?.cancel();
    _timetableSubscription?.cancel();
    _settingsSubscription?.cancel();
    _activeNoteSubscription?.cancel();

    _fdNotesSubscription?.cancel();
    _fdFoldersSubscription?.cancel();
    _fdCalendarSubscription?.cancel();
    _fdHomeworkSubscription?.cancel();
    _fdTimetableSubscription?.cancel();
    _fdSettingsSubscription?.cancel();
    _fdActiveNoteSubscription?.cancel();

    _notesSubscription = null;
    _foldersSubscription = null;
    _calendarSubscription = null;
    _homeworkSubscription = null;
    _timetableSubscription = null;
    _settingsSubscription = null;
    _activeNoteSubscription = null;
    _fdNotesSubscription = null;
    _fdFoldersSubscription = null;
    _fdCalendarSubscription = null;
    _fdHomeworkSubscription = null;
    _fdTimetableSubscription = null;
    _fdSettingsSubscription = null;
    _fdActiveNoteSubscription = null;
    _activeNoteId = null;
    _listenersActive = false;
  }

  void _cancelCoreListeners() {
    _settingsSubscription?.cancel();
    _calendarSubscription?.cancel();
    _fdSettingsSubscription?.cancel();
    _settingsSubscription = null;
    _calendarSubscription = null;
    _fdSettingsSubscription = null;
    _linuxWorkspaceRefreshTimer?.cancel();
    _linuxWorkspaceRefreshTimer = null;
    _listenersActive = false;
  }

  void _startLinuxWorkspaceRefreshTimer(String userId) {
    _linuxWorkspaceRefreshTimer?.cancel();
    // Firedart cannot stream a user-filtered query. Polling the scoped
    // snapshot keeps Linux clients current without attempting an unfiltered
    // collection listener that Firestore security rules would reject.
    _linuxWorkspaceRefreshTimer = Timer.periodic(
      _linuxWorkspaceRefreshInterval,
      (_) {
        if (_currentUserId == userId &&
            _listenersActive &&
            _syncEnabled &&
            _isOnline) {
          unawaited(_fetchCalendarSnapshot(userId));
        }
      },
    );
  }

  /// Trigger a sync operation (debounced)
  void triggerSync() {
    if (!_isOnline || !_syncEnabled) return;
    _syncSubject.add(null);
  }

  /// Sync a single note to Firebase
  Future<bool> syncNote(Note note) async {
    if (!_isOnline || !_syncEnabled) return false;
    if (note.localOnly) return true;

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

  /// Sync a single tag to Firebase
  Future<bool> syncTag(Tag tag) async {
    if (!_isOnline || !_syncEnabled) return false;

    try {
      _setStatus(SyncStatus.syncing);

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        final fdFirestore = _firedartFirestore;
        if (fdFirestore == null) return false;
        await fdFirestore.collection('tags').document(tag.id).set(tag.toJson());
      } else {
        final firestore = _firebaseFirestore;
        if (firestore == null) return false;
        await firestore
            .collection('tags')
            .doc(tag.id)
            .set(tag.toJson(), SetOptions(merge: true));
      }

      _setStatus(SyncStatus.synced);
      _lastSyncTime = DateTime.now();
      return true;
    } catch (e) {
      _setError('Failed to sync tag: $e');
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
            .update(settingsData);
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
    List<Tag>? dirtyTags,
    List<CalendarEvent>? dirtyEvents,
    List<Homework>? dirtyHomework,
    List<TimetableEntry>? dirtyEntries,
  }) async {
    if (!_isOnline || !_syncEnabled) {
      return true;
    }

    final syncableNotes =
        dirtyNotes?.where((note) => !note.localOnly).toList() ?? const <Note>[];

    final hasNotes = syncableNotes.isNotEmpty;
    final hasFolders = dirtyFolders != null && dirtyFolders.isNotEmpty;
    final hasTags = dirtyTags != null && dirtyTags.isNotEmpty;
    final hasEvents = dirtyEvents != null && dirtyEvents.isNotEmpty;
    final hasHomework = dirtyHomework != null && dirtyHomework.isNotEmpty;
    final hasEntries = dirtyEntries != null && dirtyEntries.isNotEmpty;

    if (!hasNotes &&
        !hasFolders &&
        !hasTags &&
        !hasEvents &&
        !hasHomework &&
        !hasEntries) {
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
          for (final note in syncableNotes) {
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

        if (hasTags) {
          for (final tag in dirtyTags) {
            futures.add(
              fdFirestore.collection('tags').document(tag.id).set(
                    tag.copyWith(isDirty: false).toJson(),
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
          for (final note in syncableNotes) {
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

        if (hasTags) {
          for (final tag in dirtyTags) {
            final ref = firestore.collection('tags').doc(tag.id);
            batch.set(
              ref,
              tag.copyWith(isDirty: false).toJson(),
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
    _awaitingRefreshResult = true;
    _startRefreshTimeout();
    _diagnostics.info(
      'SyncService',
      'Manual sync refresh requested on ${defaultTargetPlatform.name}',
    );

    // Trigger immediate sync attempt
    if (_syncEnabled && _isOnline) {
      // Reset error status
      _errorMessage = null;

      if (_currentUserId != null) {
        _diagnostics.info(
          'SyncService',
          'Refreshing workspace snapshot for user $_currentUserId',
        );
        triggerSync();
        unawaited(fetchWorkspaceSnapshot(_currentUserId!));
      } else {
        _diagnostics.warning(
          'SyncService',
          'Cannot restart listeners because userId is unknown; triggering local sync only',
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
      _cancelRefreshTimeout();
      notifyListeners();
    }
  }

  void _setStatus(SyncStatus newStatus) {
    _status = newStatus;
    if (newStatus != SyncStatus.error) {
      _errorMessage = null;
    }
    if (newStatus == SyncStatus.synced || newStatus == SyncStatus.idle) {
      _cancelRefreshTimeout();
      _awaitingRefreshResult = false;
    }
    notifyListeners();
  }

  void _setError(String message) {
    _cancelRefreshTimeout();
    _awaitingRefreshResult = false;
    _status = SyncStatus.error;
    _errorMessage = message;
    _diagnostics.error('SyncService', message);
    // Use microtask to avoid setState during build
    Future.microtask(() => notifyListeners());
    // Auto-recovery removed to allow user to see error and retry manually
  }

  void _startRefreshTimeout() {
    _refreshTimeoutTimer?.cancel();
    _refreshTimeoutTimer = Timer(const Duration(seconds: 8), () {
      if (_awaitingRefreshResult && _status == SyncStatus.syncing) {
        _setError(
          'Sync refresh timed out. Open Settings > Diagnostics Log for details.',
        );
      }
    });
  }

  void _cancelRefreshTimeout() {
    _refreshTimeoutTimer?.cancel();
    _refreshTimeoutTimer = null;
  }

  void _markRefreshSucceeded(String detail) {
    if (_awaitingRefreshResult) {
      _diagnostics.info('SyncService', detail);
      _awaitingRefreshResult = false;
      _cancelRefreshTimeout();
    }
  }

  @override
  void dispose() {
    stopListening();
    _connectivitySubscription?.cancel();
    _refreshTimeoutTimer?.cancel();
    _syncSubject.close();
    _syncTriggerController.close();
    super.dispose();
  }
}
