/// Settings Screen
/// 
/// App settings including theme, sync, and account options.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/theme_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/routes/app_router.dart';

/// Settings screen with app preferences
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();
    final authService = context.watch<AuthService>();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // Appearance Section
          _SectionHeader(title: 'Appearance'),
          
          // Dark mode toggle with long press for system sync
          _SettingsTile(
            icon: Icons.dark_mode_outlined,
            title: 'Dark Mode',
            subtitle: themeService.syncWithSystem 
                ? 'Synced with system' 
                : (themeService.isDarkMode ? 'On' : 'Off'),
            trailing: Switch(
              value: themeService.isDarkMode,
              onChanged: (_) => themeService.toggleTheme(),
            ),
            onTap: () => themeService.toggleTheme(),
            onLongPress: () {
              themeService.toggleSystemSync();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    themeService.syncWithSystem 
                        ? 'Theme synced with system' 
                        : 'Manual theme mode',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
          
          // Accent color
          _SettingsTile(
            icon: Icons.palette_outlined,
            title: 'Accent Color',
            subtitle: 'Customize app theme color',
            trailing: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: themeService.accentColor,
                shape: BoxShape.circle,
              ),
            ),
            onTap: () => _showColorPicker(context, themeService),
          ),
          
          const Divider(),
          
          // Account Section
          _SectionHeader(title: 'Account'),
          
          _SettingsTile(
            icon: Icons.person_outline,
            title: 'Profile',
            subtitle: authService.currentUser?.email ?? 'Not signed in',
            onTap: () => AppRouter.navigateTo(context, AppRouter.profile),
          ),
          
          _SettingsTile(
            icon: Icons.cloud_outlined,
            title: 'Storage & Subscription',
            subtitle: 'Manage your cloud storage',
            onTap: () => AppRouter.navigateTo(context, AppRouter.subscription),
          ),
          
          const Divider(),
          
          // Sync Section
          _SectionHeader(title: 'Sync'),
          
          _SettingsTile(
            icon: Icons.sync,
            title: 'Background Sync',
            subtitle: 'Keep notes synced automatically',
            trailing: Switch(
              value: true, // TODO: Connect to actual setting
              onChanged: (value) {
                // TODO: Implement background sync toggle
              },
            ),
          ),
          
          _SettingsTile(
            icon: Icons.wifi_off_outlined,
            title: 'Offline Mode',
            subtitle: 'Save data when offline',
            trailing: const Icon(Icons.check, color: Colors.green),
          ),
          
          const Divider(),
          
          // About Section
          _SectionHeader(title: 'About'),
          
          _SettingsTile(
            icon: Icons.info_outline,
            title: 'Version',
            subtitle: '1.0.0',
          ),
          
          _SettingsTile(
            icon: Icons.description_outlined,
            title: 'Licenses',
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: 'TypeSync',
                applicationVersion: '1.0.0',
              );
            },
          ),
          
          const Divider(),
          
          // Sign out
          _SettingsTile(
            icon: Icons.logout,
            title: 'Sign Out',
            titleColor: Colors.red,
            onTap: () => _confirmSignOut(context, authService),
          ),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showColorPicker(BuildContext context, ThemeService themeService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Accent Color'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: ThemeService.accentColors.map((color) {
            final isSelected = color.value == themeService.accentColor.value;
            return GestureDetector(
              onTap: () {
                themeService.setAccentColor(color);
                Navigator.pop(context);
              },
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: isSelected 
                      ? Border.all(color: Colors.white, width: 3)
                      : null,
                ),
                child: isSelected 
                    ? const Icon(Icons.check, color: Colors.white)
                    : null,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _confirmSignOut(BuildContext context, AuthService authService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              authService.signOut();
              AppRouter.navigateAndClearStack(context, AppRouter.login);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.grey,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? titleColor;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: titleColor),
      title: Text(
        title,
        style: TextStyle(color: titleColor),
      ),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right) : null),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

