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
  String? _lastUserId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkAuthState();
  }

  void _checkAuthState() {
    final authService = context.read<AuthService>();
    final syncService = context.read<SyncService>();
    final userId = authService.userId;

    // Check if user ID changed
    if (userId != _lastUserId) {
      _lastUserId = userId;

      if (userId != null) {
        // User logged in
        debugPrint(
          'ServiceOrchestrator: User logged in ($userId), initializing services',
        );

        // Initialize LocalFileService
        LocalFileService.instance.initialize(userId).catchError((e) {
          debugPrint(
            'ServiceOrchestrator: Failed to initialize LocalFileService: $e',
          );
        });

        // Start SyncService listening
        syncService.startListening(userId);
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
