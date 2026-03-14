/// Home Bottom Bar Widget
///
/// Bottom navigation bar matching the design mockup.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/routes/app_router.dart';
import '../../../core/services/auth_service.dart';

/// Bottom navigation bar for home screen
///
/// Contains navigation to files, sync, and profile sections.
class HomeBottomBar extends StatelessWidget {
  final String? currentFolderId;
  final VoidCallback onNewNote;
  final VoidCallback onNewFolder;

  const HomeBottomBar({
    required this.onNewNote,
    required this.onNewFolder,
    super.key,
    this.currentFolderId,
  });

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final isGuest = authService.isGuestMode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            // Files button
            _BottomBarButton(
              icon: Icons.folder_copy_outlined,
              label: 'Files',
              onTap: () {
                // Already on files
              },
              isSelected: true,
            ),

            // Sync button - navigates to sync status/settings
            _BottomBarButton(
              icon: Icons.sync,
              label: 'Sync',
              onTap: () {
                // Show sync options
                _showSyncOptions(context);
              },
            ),

            // Profile button
            _BottomBarButton(
              icon: isGuest ? Icons.login : Icons.person_outline,
              label: isGuest ? 'Sign In' : 'Profile',
              onTap: () => AppRouter.navigateTo(
                context,
                isGuest ? AppRouter.login : AppRouter.profile,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSyncOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Productivity',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('Calendar'),
              subtitle: const Text('Test reminders & events'),
              onTap: () {
                Navigator.pop(context);
                AppRouter.navigateTo(context, AppRouter.calendar);
              },
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Timetable'),
              subtitle: const Text('Weekly class schedule'),
              onTap: () {
                Navigator.pop(context);
                AppRouter.navigateTo(context, AppRouter.timetable);
              },
            ),
            ListTile(
              leading: const Icon(Icons.checklist),
              title: const Text('Homework'),
              subtitle: const Text('Todo list for assignments'),
              onTap: () {
                Navigator.pop(context);
                AppRouter.navigateTo(context, AppRouter.homework);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Individual button in the bottom bar
class _BottomBarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isSelected;

  const _BottomBarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        isSelected ? Theme.of(context).colorScheme.primary : Colors.grey;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
