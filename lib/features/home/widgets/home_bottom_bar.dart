/// Home Bottom Bar Widget
///
/// Bottom navigation bar matching the design mockup.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/auth_service.dart';

enum HomeBottomBarTab { files, profile }

/// Bottom navigation bar for home screen
///
/// Contains navigation to files, sync, and profile sections.
class HomeBottomBar extends StatelessWidget {
  final String? currentFolderId;
  final VoidCallback onAddTap;
  final HomeBottomBarTab selectedTab;
  final VoidCallback onFilesTap;
  final VoidCallback onProfileTap;

  const HomeBottomBar({
    required this.onAddTap,
    required this.selectedTab,
    required this.onFilesTap,
    required this.onProfileTap,
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
              onTap: onFilesTap,
              isSelected: selectedTab == HomeBottomBarTab.files,
            ),

            // Add button
            _BottomBarButton(
              icon: Icons.add_circle_outline,
              label: 'Add',
              onTap: onAddTap,
            ),

            // Profile button
            _BottomBarButton(
              icon: isGuest ? Icons.login : Icons.person_outline,
              label: isGuest ? 'Sign In' : 'Profile',
              onTap: onProfileTap,
              isSelected: selectedTab == HomeBottomBarTab.profile,
            ),
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
