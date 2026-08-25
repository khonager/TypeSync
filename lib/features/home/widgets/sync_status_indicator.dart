/// Sync Status Indicator Widget
///
/// Shows the current sync status with a visual indicator.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/sync_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/providers/notes_provider.dart';

enum SyncIndicatorState {
  waiting,
  syncing,
  verified,
  conflict,
  error,
  offline,
}

SyncIndicatorState resolveSyncIndicatorState({
  required SyncStatus globalStatus,
  bool noteScoped = false,
  bool noteIsDirty = false,
  bool noteHasConflict = false,
  bool noteVersionVerified = false,
  bool hasUnsavedChanges = false,
}) {
  if (globalStatus == SyncStatus.offline) return SyncIndicatorState.offline;
  if (globalStatus == SyncStatus.error) return SyncIndicatorState.error;
  if (noteScoped) {
    if (noteHasConflict) return SyncIndicatorState.conflict;
    if (noteIsDirty || hasUnsavedChanges) {
      return globalStatus == SyncStatus.syncing
          ? SyncIndicatorState.syncing
          : SyncIndicatorState.waiting;
    }
    if (!noteVersionVerified) {
      return globalStatus == SyncStatus.syncing
          ? SyncIndicatorState.syncing
          : SyncIndicatorState.waiting;
    }
    return SyncIndicatorState.verified;
  }
  if (globalStatus == SyncStatus.syncing) return SyncIndicatorState.syncing;
  if (globalStatus == SyncStatus.synced) return SyncIndicatorState.verified;
  return SyncIndicatorState.waiting;
}

/// Visual indicator for sync status
class SyncStatusIndicator extends StatelessWidget {
  final String? noteId;
  final bool hasUnsavedChanges;

  const SyncStatusIndicator({
    super.key,
    this.noteId,
    this.hasUnsavedChanges = false,
  });

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();

    // Don't show sync indicator in guest mode or local-only workspace mode
    if (authService.isGuestMode || authService.localOnlyMode) {
      return const SizedBox.shrink();
    }

    final syncService = context.watch<SyncService>();
    final note = noteId == null
        ? null
        : context.watch<NotesProvider>().getNoteById(noteId!);
    final indicatorState = resolveSyncIndicatorState(
      globalStatus: syncService.status,
      noteScoped: noteId != null,
      noteIsDirty: note?.isDirty ?? false,
      noteHasConflict: note?.hasConflict ?? false,
      noteVersionVerified:
          note != null && syncService.isNoteVersionVerified(note),
      hasUnsavedChanges: hasUnsavedChanges,
    );

    IconData icon;
    Color color;
    String tooltip;

    switch (indicatorState) {
      case SyncIndicatorState.waiting:
        icon = Icons.cloud_queue_outlined;
        color = Theme.of(context).colorScheme.outline;
        tooltip = noteId == null
            ? 'Waiting for sync'
            : 'This note is not yet verified with cloud';
        break;
      case SyncIndicatorState.syncing:
        icon = Icons.sync;
        color = Theme.of(context).colorScheme.primary;
        tooltip = noteId == null ? 'Syncing...' : 'Verifying this note...';
        break;
      case SyncIndicatorState.verified:
        icon = Icons.cloud_done;
        color = Colors.green;
        tooltip = noteId == null
            ? 'All changes saved'
            : 'This exact note version is verified with cloud';
        break;
      case SyncIndicatorState.conflict:
        icon = Icons.cloud_off;
        color = Colors.red;
        tooltip = 'This note differs from the cloud version';
        break;
      case SyncIndicatorState.error:
        icon = Icons.cloud_off;
        color = Colors.red;
        tooltip = syncService.errorMessage ?? 'Sync error';
        break;
      case SyncIndicatorState.offline:
        icon = Icons.cloud_off_outlined;
        color = Colors.orange;
        tooltip = 'Offline - changes saved locally';
        break;
    }

    return Tooltip(
      message:
          '$tooltip${syncService.status == SyncStatus.error ? '\nTap to retry' : '\nTap to refresh'}',
      child: InkWell(
        onTap: () {
          syncService.refresh();
        },
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: indicatorState == SyncIndicatorState.syncing
              ? _SyncingAnimation(color: color)
              : Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}

/// Animated sync icon
class _SyncingAnimation extends StatefulWidget {
  final Color color;

  const _SyncingAnimation({required this.color});

  @override
  State<_SyncingAnimation> createState() => _SyncingAnimationState();
}

class _SyncingAnimationState extends State<_SyncingAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: _controller.value * 2 * 3.14159,
          child: Icon(Icons.sync, color: widget.color, size: 20),
        );
      },
    );
  }
}
