/// Settings Screen
/// 
/// App settings including theme, sync, and account options.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/theme_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/services/local_folder_sync_service.dart';
import '../../../core/providers/notes_provider.dart';
import '../../../core/providers/folders_provider.dart';
import '../../../core/routes/app_router.dart';

/// Settings screen with app preferences
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();
    final authService = context.watch<AuthService>();
    final syncService = context.watch<SyncService>();
    final localSyncService = context.watch<LocalFolderSyncService>();

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
          
          // Only show sync toggle for logged-in users (not guests)
          if (authService.isLoggedIn)
            _SettingsTile(
              icon: Icons.sync,
              title: 'Cloud Sync',
              subtitle: authService.syncEnabled 
                  ? 'Syncing with cloud enabled' 
                  : 'Syncing with cloud disabled',
              trailing: Switch(
                value: authService.syncEnabled,
                onChanged: (value) async {
                  await authService.setSyncEnabled(value);
                  syncService.setSyncEnabled(value);
                  if (value && authService.userId != null) {
                    // Restart sync if enabled
                    syncService.startListening(authService.userId!);
                  }
                },
              ),
            ),
          
          if (authService.isGuestMode)
            _SettingsTile(
              icon: Icons.cloud_off_outlined,
              title: 'Guest Mode',
              subtitle: 'Using app locally without sync',
              trailing: const Icon(Icons.info_outline, color: Colors.grey),
            ),
          
          _SettingsTile(
            icon: Icons.wifi_off_outlined,
            title: 'Offline Mode',
            subtitle: 'Save data when offline',
            trailing: const Icon(Icons.check, color: Colors.green),
          ),
          
          _SettingsTile(
            icon: Icons.sync,
            title: 'Local Folder Sync',
            subtitle: localSyncService.syncFolder != null 
                ? localSyncService.syncFolder!.path 
                : 'Not configured',
            onTap: () => _showLocalFolderSync(context),
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

  void _showLocalFolderSync(BuildContext context) {
    final syncService = context.read<LocalFolderSyncService>();
    final notesProvider = context.read<NotesProvider>();
    final foldersProvider = context.read<FoldersProvider>();
    final authService = context.read<AuthService>();
    final userId = authService.userId;

    if (userId == null) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Local Folder Sync'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (syncService.syncFolder != null) ...[
                Text('Sync folder: ${syncService.syncFolder!.path}'),
                const SizedBox(height: 16),
              ],
              ElevatedButton.icon(
                onPressed: () async {
                  final success = await syncService.chooseSyncFolder();
                  if (success && dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                    _showLocalFolderSync(context); // Refresh
                  }
                },
                icon: const Icon(Icons.folder_open),
                label: Text(syncService.syncFolder != null 
                    ? 'Change Folder' 
                    : 'Choose Folder'),
              ),
              if (syncService.syncFolder != null) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: syncService.isSyncing ? null : () async {
                    // Set up conflict handler
                    syncService.onConflictsDetected = (conflicts) {
                      Navigator.pop(dialogContext);
                      _showConflictResolution(
                        context,
                        conflicts,
                        syncService,
                        notesProvider,
                        foldersProvider,
                        userId,
                      );
                    };
                    
                    await syncService.sync(
                      notesProvider: notesProvider,
                      foldersProvider: foldersProvider,
                      userId: userId,
                    );
                    
                    if (dialogContext.mounted && syncService.conflicts.isEmpty) {
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Sync completed')),
                      );
                    }
                  },
                  icon: const Icon(Icons.sync),
                  label: const Text('Sync Now'),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showConflictResolution(
    BuildContext context,
    List<ConflictInfo> conflicts,
    LocalFolderSyncService syncService,
    NotesProvider notesProvider,
    FoldersProvider foldersProvider,
    String userId,
  ) {
    if (conflicts.isEmpty) return;

    int currentIndex = 0;

    void showNextConflict() {
      if (currentIndex >= conflicts.length) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All conflicts resolved')),
        );
        return;
      }

      final conflict = conflicts[currentIndex];
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text('Conflict: ${conflict.itemName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This ${conflict.isNote ? "note" : "folder"} has been modified in both locations.'),
                const SizedBox(height: 16),
                Text('Local modified: ${_formatDateTime(conflict.localModified)}'),
                Text('Cloud modified: ${_formatDateTime(conflict.cloudModified)}'),
                const SizedBox(height: 16),
                const Text('Choose which version to keep:'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await syncService.resolveConflict(
                  conflict,
                  ConflictResolution.useLocal,
                  notesProvider: notesProvider,
                  foldersProvider: foldersProvider,
                  userId: userId,
                );
                Navigator.pop(dialogContext);
                currentIndex++;
                showNextConflict();
              },
              child: const Text('Use Local'),
            ),
            TextButton(
              onPressed: () async {
                await syncService.resolveConflict(
                  conflict,
                  ConflictResolution.useCloud,
                  notesProvider: notesProvider,
                  foldersProvider: foldersProvider,
                  userId: userId,
                );
                Navigator.pop(dialogContext);
                currentIndex++;
                showNextConflict();
              },
              child: const Text('Use Cloud'),
            ),
            TextButton(
              onPressed: () async {
                await syncService.resolveConflict(
                  conflict,
                  ConflictResolution.keepBoth,
                  notesProvider: notesProvider,
                  foldersProvider: foldersProvider,
                  userId: userId,
                );
                Navigator.pop(dialogContext);
                currentIndex++;
                showNextConflict();
              },
              child: const Text('Keep Both'),
            ),
            TextButton(
              onPressed: () async {
                await syncService.resolveConflict(
                  conflict,
                  ConflictResolution.skip,
                  notesProvider: notesProvider,
                  foldersProvider: foldersProvider,
                  userId: userId,
                );
                Navigator.pop(dialogContext);
                currentIndex++;
                showNextConflict();
              },
              child: const Text('Skip'),
            ),
          ],
        ),
      );
    }

    showNextConflict();
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
           '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
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



