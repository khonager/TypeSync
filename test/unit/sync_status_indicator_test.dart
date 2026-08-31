import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/core/services/sync_service.dart';
import 'package:typesync/features/home/widgets/sync_status_indicator.dart';

void main() {
  group('note-scoped sync indicator', () {
    test('does not show verified for a dirty note', () {
      expect(
        resolveSyncIndicatorState(
          globalStatus: SyncStatus.synced,
          noteScoped: true,
          noteIsDirty: true,
          noteVersionVerified: true,
        ),
        SyncIndicatorState.waiting,
      );
    });

    test('does not show verified before this revision is acknowledged', () {
      expect(
        resolveSyncIndicatorState(
          globalStatus: SyncStatus.synced,
          noteScoped: true,
        ),
        SyncIndicatorState.waiting,
      );
    });

    test('shows verified only for the acknowledged clean revision', () {
      expect(
        resolveSyncIndicatorState(
          globalStatus: SyncStatus.synced,
          noteScoped: true,
          noteVersionVerified: true,
        ),
        SyncIndicatorState.verified,
      );
    });

    test('does not show verified while editor changes are unsaved', () {
      expect(
        resolveSyncIndicatorState(
          globalStatus: SyncStatus.synced,
          noteScoped: true,
          noteVersionVerified: true,
          hasUnsavedChanges: true,
        ),
        SyncIndicatorState.waiting,
      );
    });

    test('shows a conflict even when global sync reports success', () {
      expect(
        resolveSyncIndicatorState(
          globalStatus: SyncStatus.synced,
          noteScoped: true,
          noteHasConflict: true,
        ),
        SyncIndicatorState.conflict,
      );
    });
  });
}
