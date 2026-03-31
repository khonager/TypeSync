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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    const barTopPadding = 8.0;
    const barContentHeight = 64.0;
    final barBottomPadding = bottomInset > 0 ? bottomInset : 12.0;
    final barHeight = barContentHeight + barTopPadding + barBottomPadding;

    return SizedBox(
      height: barHeight,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: barHeight,
              padding: EdgeInsets.fromLTRB(
                24,
                barTopPadding,
                24,
                barBottomPadding,
              ),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.center,
                      child: _BottomBarButton(
                        icon: Icons.folder_copy_outlined,
                        label: 'Files',
                        onTap: onFilesTap,
                        isSelected: selectedTab == HomeBottomBarTab.files,
                      ),
                    ),
                  ),
                  const SizedBox(width: 104),
                  Expanded(
                    child: Align(
                      alignment: Alignment.center,
                      child: _BottomBarButton(
                        icon: isGuest ? Icons.login : Icons.person_outline,
                        label: isGuest ? 'Sign In' : 'Profile',
                        onTap: onProfileTap,
                        isSelected: selectedTab == HomeBottomBarTab.profile,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: -22,
            child: _CenterAddButton(
              color: colorScheme.surface,
              gapColor: theme.scaffoldBackgroundColor,
              iconColor: Colors.grey,
              onTap: onAddTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterAddButton extends StatelessWidget {
  final Color color;
  final Color gapColor;
  final Color iconColor;
  final VoidCallback onTap;

  const _CenterAddButton({
    required this.color,
    required this.gapColor,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: gapColor,
        shape: BoxShape.circle,
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Material(
          color: color,
          shape: const CircleBorder(),
          elevation: 2,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 72,
              height: 72,
              child: Icon(
                Icons.add,
                color: iconColor,
                size: 36,
              ),
            ),
          ),
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
