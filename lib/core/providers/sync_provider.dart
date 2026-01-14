/// Sync Provider
///
/// Tracks synchronization state across the app for UI feedback.
library;

import 'package:flutter/foundation.dart';

import '../services/sync_service.dart';

/// Provider for sync status display
class SyncProvider extends ChangeNotifier {
  SyncStatus _status = SyncStatus.idle;
  DateTime? _lastSyncTime;
  int _pendingChanges = 0;
  bool _isOnline = true;

  SyncStatus get status => _status;
  DateTime? get lastSyncTime => _lastSyncTime;
  int get pendingChanges => _pendingChanges;
  bool get isOnline => _isOnline;
  bool get hasPendingChanges => _pendingChanges > 0;

  String get statusText {
    switch (_status) {
      case SyncStatus.idle:
        return 'Synced';
      case SyncStatus.syncing:
        return 'Syncing...';
      case SyncStatus.synced:
        return 'All changes saved';
      case SyncStatus.error:
        return 'Sync error';
      case SyncStatus.offline:
        return 'Offline';
    }
  }

  void updateStatus(SyncStatus status) {
    _status = status;
    if (status == SyncStatus.synced) {
      _lastSyncTime = DateTime.now();
      _pendingChanges = 0;
    }
    notifyListeners();
  }

  void setOnline(bool online) {
    _isOnline = online;
    if (!online) {
      _status = SyncStatus.offline;
    }
    notifyListeners();
  }

  void incrementPendingChanges() {
    _pendingChanges++;
    notifyListeners();
  }

  void resetPendingChanges() {
    _pendingChanges = 0;
    notifyListeners();
  }
}
