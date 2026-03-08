/// Sync Status Indicator Widget
///
/// Shows the current sync status with a visual indicator.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/sync_service.dart';
import '../../../core/services/auth_service.dart';

/// Visual indicator for sync status
class SyncStatusIndicator extends StatelessWidget {
  const SyncStatusIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();

    // Don't show sync indicator in guest mode or local-only workspace mode
    if (authService.isGuestMode || authService.localOnlyMode) {
      return const SizedBox.shrink();
    }

    final syncService = context.watch<SyncService>();

    IconData icon;
    Color color;
    String tooltip;

    switch (syncService.status) {
      case SyncStatus.idle:
        icon = Icons.cloud_done_outlined;
        color = Colors.green;
        tooltip = 'Synced';
        break;
      case SyncStatus.syncing:
        icon = Icons.sync;
        color = Theme.of(context).colorScheme.primary;
        tooltip = 'Syncing...';
        break;
      case SyncStatus.synced:
        icon = Icons.cloud_done;
        color = Colors.green;
        tooltip = 'All changes saved';
        break;
      case SyncStatus.error:
        icon = Icons.cloud_off;
        color = Colors.red;
        tooltip = syncService.errorMessage ?? 'Sync error';
        break;
      case SyncStatus.offline:
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
          child: syncService.status == SyncStatus.syncing
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
