/// Home Bottom Bar Widget
///
/// Bottom navigation bar matching the design mockup.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/auth_service.dart';

enum HomeBottomBarTab { files, profile }

const double _kAddButtonSize = 72;
const double _kAddButtonGap = 6;
const double _kAddButtonTopOffset = -22;
const double _kBarTopPadding = 8.0;
const double _kBarContentHeight = 64.0;
const double _kBarMinBottomPadding = 12.0;
const double _kScrollPaddingBuffer = 16.0;

double homeBottomBarHeightFor(BuildContext context) {
  final bottomInset = MediaQuery.paddingOf(context).bottom;
  final barBottomPadding =
      bottomInset > 0 ? bottomInset : _kBarMinBottomPadding;
  return _kBarContentHeight + _kBarTopPadding + barBottomPadding;
}

double homeBottomBarScrollPaddingFor(BuildContext context) {
  return homeBottomBarHeightFor(context) +
      _kAddButtonTopOffset.abs() +
      _kScrollPaddingBuffer;
}

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
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final barBottomPadding =
        bottomInset > 0 ? bottomInset : _kBarMinBottomPadding;
    final barHeight = homeBottomBarHeightFor(context);

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
            child: CustomPaint(
              painter: _BottomBarBackgroundPainter(
                color: colorScheme.surface,
                borderColor: Colors.white.withValues(alpha: 0.1),
              ),
              child: SizedBox(
                height: barHeight,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    _kBarTopPadding,
                    24,
                    barBottomPadding,
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
            ),
          ),
          Positioned(
            top: _kAddButtonTopOffset,
            child: _CenterAddButton(
              color: colorScheme.surface,
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
  final Color iconColor;
  final VoidCallback onTap;

  const _CenterAddButton({
    required this.color,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: _kAddButtonSize,
          height: _kAddButtonSize,
          child: Icon(
            Icons.add,
            color: iconColor,
            size: 36,
          ),
        ),
      ),
    );
  }
}

class _BottomBarBackgroundPainter extends CustomPainter {
  final Color color;
  final Color borderColor;

  const _BottomBarBackgroundPainter({
    required this.color,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const cutoutRadius = (_kAddButtonSize / 2) + _kAddButtonGap;
    const cutoutCenterY = _kAddButtonTopOffset + (_kAddButtonSize / 2);
    final cutoutCenter = Offset(size.width / 2, cutoutCenterY);
    final fullRectPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutoutPath = Path()
      ..addOval(Rect.fromCircle(center: cutoutCenter, radius: cutoutRadius));
    final visiblePath = Path.combine(
      PathOperation.difference,
      fullRectPath,
      cutoutPath,
    );

    canvas.drawPath(
      visiblePath,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      visiblePath,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
  }

  @override
  bool shouldRepaint(covariant _BottomBarBackgroundPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.borderColor != borderColor;
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
