import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/services/auth_service.dart';
import '../core/services/sync_service.dart';
import '../core/services/local_file_service.dart';

/// Orchestrates services based on application state changes
class ServiceOrchestrator extends StatefulWidget {
  final Widget child;

  const ServiceOrchestrator({
    required this.child,
    super.key,
  });

  @override
  State<ServiceOrchestrator> createState() => _ServiceOrchestratorState();
}

class _ServiceOrchestratorState extends State<ServiceOrchestrator> {
  String? _lastWorkspaceId;
  bool? _lastSyncEnabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkAuthState();
  }

  void _checkAuthState() {
    final authService = context.read<AuthService>();
    final syncService = context.read<SyncService>();
    final workspaceId = authService.storageUserId;
    final cloudUserId = authService.userId;
    final syncEnabled =
        authService.isLoggedIn && authService.effectiveSyncEnabled;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      syncService.setSyncEnabled(authService.effectiveSyncEnabled);
    });

    // Check if workspace ID or sync mode changed
    if (workspaceId != _lastWorkspaceId || syncEnabled != _lastSyncEnabled) {
      _lastWorkspaceId = workspaceId;
      _lastSyncEnabled = syncEnabled;

      if (workspaceId != null) {
        // User logged in
        debugPrint(
          'ServiceOrchestrator: Workspace active ($workspaceId), initializing services',
        );

        // Initialize LocalFileService
        LocalFileService.instance.initialize(workspaceId).catchError((e) {
          debugPrint(
            'ServiceOrchestrator: Failed to initialize LocalFileService: $e',
          );
        });

        // HomeScreen owns sync startup once provider callbacks are attached.
        // We only stop listeners here when sync becomes unavailable.
        if (!syncEnabled || cloudUserId == null) {
          syncService.stopListening();
        }
      } else {
        // User logged out
        debugPrint('ServiceOrchestrator: User logged out, stopping services');

        // Stop SyncService listening
        syncService.stopListening();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
