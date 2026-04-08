/// Settings Screen
///
/// App settings including theme, sync, and account options.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/models/folder.dart';
import '../../../core/models/note.dart';
import '../../../core/services/theme_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/local_folder_sync_service.dart';
import '../../../core/services/local_file_service.dart';
import '../../../core/services/diagnostics_service.dart';
import '../../../core/services/anytype_import_service.dart';
import '../../../core/services/rich_text_plain_text_service.dart';
import '../../../core/providers/notes_provider.dart';
import '../../../core/providers/folders_provider.dart';
import '../../../core/providers/calendar_provider.dart';
import '../../../core/providers/homework_provider.dart';
import '../../../core/providers/timetable_provider.dart';
import '../../../core/routes/app_router.dart';
import '../../../core/utils/file_picker_helper.dart';

/// Settings screen with app preferences
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();
    final authService = context.watch<AuthService>();
    final syncService = context.watch<SyncService>();
    final localSyncService = context.watch<LocalFolderSyncService>();
    final diagnosticsService = context.watch<DiagnosticsService>();

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
          const _SectionHeader(title: 'Appearance'),

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
          const _SectionHeader(title: 'Account'),

          if (authService.isGuestMode)
            _SettingsTile(
              icon: Icons.login,
              title: 'Sign In to Sync',
              subtitle: 'Create an account to backup your notes',
              onTap: () {
                // Navigate to login screen
                // We use push because we want to come back to settings if they cancel
                // But actually, successful login will likely redirect to home.
                AppRouter.navigateTo(context, AppRouter.login);
              },
            )
          else ...[
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
              onTap: () =>
                  AppRouter.navigateTo(context, AppRouter.subscription),
            ),
          ],

          const Divider(),

          // Sync Section
          const _SectionHeader(title: 'Sync'),

          // Only show sync toggle for logged-in users (not guests)
          if (authService.isLoggedIn)
            _SettingsTile(
              icon: Icons.sync,
              title: 'Cloud Sync',
              subtitle: authService.localOnlyMode
                  ? 'Disabled while Local Workspace is active'
                  : authService.syncEnabled
                      ? 'Syncing with cloud enabled'
                      : 'Syncing with cloud disabled',
              trailing: Switch(
                value: authService.effectiveSyncEnabled,
                onChanged: (value) async {
                  if (authService.localOnlyMode) return;
                  await authService.setSyncEnabled(value);
                  syncService.setSyncEnabled(authService.effectiveSyncEnabled);
                  if (authService.effectiveSyncEnabled &&
                      authService.userId != null) {
                    // Restart sync if enabled
                    syncService.startListening(authService.userId!);
                  } else {
                    syncService.stopListening();
                  }
                },
              ),
            ),

          if (authService.isLoggedIn)
            _SettingsTile(
              icon: Icons.laptop_mac_outlined,
              title: 'Local Workspace Mode',
              subtitle: authService.localOnlyMode
                  ? 'Using isolated local clone (no cloud writes)'
                  : 'Use synced cloud workspace',
              trailing: Switch(
                value: authService.localOnlyMode,
                onChanged: (value) async {
                  await _toggleLocalWorkspaceMode(context, value);
                },
              ),
            ),

          if (authService.isGuestMode)
            const _SettingsTile(
              icon: Icons.cloud_off_outlined,
              title: 'Guest Mode',
              subtitle: 'Using app locally without sync',
              trailing: Icon(Icons.info_outline, color: Colors.grey),
            ),

          const _SettingsTile(
            icon: Icons.wifi_off_outlined,
            title: 'Offline Mode',
            subtitle: 'Save data when offline',
            trailing: Icon(Icons.check, color: Colors.green),
          ),

          _SettingsTile(
            icon: Icons.sync,
            title: 'Local Folder Sync',
            subtitle: localSyncService.syncFolder != null
                ? localSyncService.syncFolder!.path
                : 'Not configured',
            onTap: () => _showLocalFolderSync(context),
          ),

          _SettingsTile(
            icon: Icons.bug_report_outlined,
            title: 'Diagnostics Log',
            subtitle: diagnosticsService.hasEntries
                ? '${diagnosticsService.entries.length} entries available'
                : 'No warnings or errors recorded',
            onTap: () => _showDiagnosticsLog(context),
          ),

          if (authService.isLoggedIn)
            _SettingsTile(
              icon: Icons.cleaning_services_outlined,
              title: 'Reset Local Sync Cache',
              subtitle: 'Clear only this device workspace cache and redownload',
              titleColor: Colors.orange,
              onTap: () => _confirmResetLocalCache(context),
            ),

          const Divider(),

          const _SectionHeader(title: 'Import'),

          _SettingsTile(
            icon: Icons.download_for_offline_outlined,
            title: 'Import from Anytype',
            subtitle: 'Choose a Markdown export folder',
            onTap: () => _importFromAnytype(context),
          ),

          const Divider(),

          // About Section
          const _SectionHeader(title: 'About'),

          const _SettingsTile(
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

          if (authService.isLoggedIn)
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

  Future<void> _toggleLocalWorkspaceMode(
    BuildContext context,
    bool enabled,
  ) async {
    final authService = context.read<AuthService>();
    final syncService = context.read<SyncService>();
    final notesProvider = context.read<NotesProvider>();
    final foldersProvider = context.read<FoldersProvider>();
    final calendarProvider = context.read<CalendarProvider>();
    final homeworkProvider = context.read<HomeworkProvider>();
    final timetableProvider = context.read<TimetableProvider>();
    final themeService = context.read<ThemeService>();

    if (!authService.isLoggedIn || authService.userId == null) {
      return;
    }

    final sourceWorkspace = authService.storageUserId ?? authService.userId!;
    await authService.setLocalOnlyMode(enabled);
    final targetWorkspace = authService.storageUserId ?? authService.userId!;

    if (enabled && sourceWorkspace != targetWorkspace) {
      final clonedFiles = await LocalFileService.instance.cloneWorkspaceFiles(
        sourceWorkspace,
        targetWorkspace,
      );
      final clonedNotes = await notesProvider.cloneWorkspace(
        sourceUserId: sourceWorkspace,
        targetUserId: targetWorkspace,
        overwriteTarget: false,
        stripRemoteAssetPaths: true,
      );
      final clonedFolders = await foldersProvider.cloneWorkspace(
        sourceUserId: sourceWorkspace,
        targetUserId: targetWorkspace,
        overwriteTarget: false,
      );

      if (context.mounted &&
          (clonedFiles > 0 || clonedNotes > 0 || clonedFolders > 0)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Cloned $clonedFiles local files, $clonedNotes notes, and $clonedFolders folders to local workspace',
            ),
          ),
        );
      }
    }

    await LocalFileService.instance.initialize(targetWorkspace);
    await notesProvider.initialize(targetWorkspace);
    await foldersProvider.initialize(targetWorkspace);
    await calendarProvider.initialize(targetWorkspace);
    await homeworkProvider.initialize(targetWorkspace);
    await timetableProvider.initialize(targetWorkspace);
    final strippedRemoteAssets = enabled
        ? await notesProvider.stripRemoteAssetPathsFromActiveWorkspace()
        : 0;

    syncService.setSyncEnabled(authService.effectiveSyncEnabled);
    if (authService.effectiveSyncEnabled && authService.userId != null) {
      syncService.startListening(authService.userId!);
      notesProvider.setSyncService(syncService);
      foldersProvider.setSyncService(syncService);
      calendarProvider.setSyncService(syncService);
      homeworkProvider.setSyncService(syncService);
      timetableProvider.setSyncService(syncService);
      themeService.setSyncService(syncService);
    } else {
      syncService.stopListening();
      notesProvider.setSyncService(null);
      foldersProvider.setSyncService(null);
      calendarProvider.setSyncService(null);
      homeworkProvider.setSyncService(null);
      timetableProvider.setSyncService(null);
      themeService.setSyncService(null);
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? strippedRemoteAssets > 0
                    ? 'Local workspace enabled. Removed $strippedRemoteAssets cloud-backed file links.'
                    : 'Local workspace enabled'
                : 'Returned to cloud workspace',
          ),
        ),
      );
    }
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
            final isSelected = color == themeService.accentColor;
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

  Future<void> _importFromAnytype(BuildContext context) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Anytype import currently needs a local export folder, so web is not supported yet.',
          ),
        ),
      );
      return;
    }

    final shouldContinue = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import from Anytype'),
        content: const Text(
          'Export from Anytype as Markdown, not any-block. TypeSync will import the folder structure, Markdown notes, and linked local files it can find in that export.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Choose Folder'),
          ),
        ],
      ),
    );

    if (shouldContinue != true || !context.mounted) {
      return;
    }

    final folderPath = await FilePickerHelper.pickDirectory(
      context: context,
      dialogTitle: 'Choose Anytype Markdown export folder',
    );

    if (folderPath == null || !context.mounted) {
      return;
    }

    final authService = context.read<AuthService>();
    final notesProvider = context.read<NotesProvider>();
    final foldersProvider = context.read<FoldersProvider>();
    final storageService = context.read<StorageService>();
    final workspaceId = authService.storageUserId;
    final noteUserId = authService.userId ?? workspaceId;

    if (workspaceId == null || noteUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active workspace is available')),
      );
      return;
    }

    await LocalFileService.instance.initialize(workspaceId);

    if (!context.mounted) {
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('Importing Anytype Markdown export...')),
          ],
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    late final AnytypeImportResult result;
    try {
      result = await AnytypeImportService.instance.importMarkdownExport(
        exportDirectory: Directory(folderPath),
        noteUserId: noteUserId,
        notesProvider: notesProvider,
        foldersProvider: foldersProvider,
        useCloudStorage:
            authService.isLoggedIn && authService.effectiveSyncEnabled,
        cloudUserId: authService.userId,
        storageService: storageService,
      );
    } finally {
      if (context.mounted) {
        final navigator = Navigator.of(context, rootNavigator: true);
        if (navigator.canPop()) {
          navigator.pop();
        }
      }
    }

    if (!context.mounted) {
      return;
    }

    final summary = StringBuffer(
      'Imported ${result.importedNotes} notes',
    );
    if (result.importedFolders > 0) {
      summary.write(' across ${result.importedFolders} folders');
    }
    if (result.importedAttachments > 0) {
      summary.write(' with ${result.importedAttachments} attachments');
    }
    if (result.failedEntries.isNotEmpty) {
      summary.write('. ${result.failedEntries.length} items failed');
    } else if (result.skippedEntries.isNotEmpty) {
      summary.write('. ${result.skippedEntries.length} items were skipped');
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(summary.toString())),
    );

    if (result.hasWarnings) {
      _showImportWarnings(context, result);
    }
  }

  void _showImportWarnings(
    BuildContext context,
    AnytypeImportResult result,
  ) {
    final lines = <String>[
      if (result.failedEntries.isNotEmpty) 'Failed:',
      ...result.failedEntries,
      if (result.failedEntries.isNotEmpty && result.skippedEntries.isNotEmpty)
        '',
      if (result.skippedEntries.isNotEmpty) 'Skipped:',
      ...result.skippedEntries,
    ];

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Anytype Import Notes'),
        content: SizedBox(
          width: 640,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: SingleChildScrollView(
              child: SelectableText(lines.join('\n')),
            ),
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

  void _showDiagnosticsLog(BuildContext context) {
    final diagnosticsService = context.read<DiagnosticsService>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Diagnostics Log'),
        content: SizedBox(
          width: 640,
          child: Consumer<DiagnosticsService>(
            builder: (context, diagnostics, _) {
              if (!diagnostics.hasEntries) {
                return const Text('No diagnostics have been recorded yet.');
              }

              final lines = diagnostics.entries.reversed
                  .map((entry) => entry.toDisplayLine())
                  .toList();

              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: SingleChildScrollView(
                  child: SelectableText(lines.join('\n\n')),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              diagnosticsService.clear();
            },
            child: const Text('Clear'),
          ),
          ElevatedButton(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: diagnosticsService.exportText()),
              );
              if (dialogContext.mounted && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Diagnostics copied')),
                );
              }
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmResetLocalCache(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset local cache?'),
        content: const Text(
          'This clears the current workspace cache on this device only and then reloads it from cloud sync. Cloud data will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await _resetLocalCache(context);
    }
  }

  Future<void> _resetLocalCache(BuildContext context) async {
    final authService = context.read<AuthService>();
    final syncService = context.read<SyncService>();
    final diagnosticsService = context.read<DiagnosticsService>();
    final notesProvider = context.read<NotesProvider>();
    final foldersProvider = context.read<FoldersProvider>();
    final calendarProvider = context.read<CalendarProvider>();
    final homeworkProvider = context.read<HomeworkProvider>();
    final timetableProvider = context.read<TimetableProvider>();
    final themeService = context.read<ThemeService>();

    final workspaceId = authService.storageUserId;
    final cloudUserId = authService.userId;
    if (workspaceId == null || cloudUserId == null) {
      diagnosticsService.warning(
        'LocalCacheReset',
        'Skipped local cache reset because no logged-in workspace was active',
      );
      return;
    }

    diagnosticsService.info(
      'LocalCacheReset',
      'Clearing local cache for workspace $workspaceId',
    );

    syncService.stopListening();
    notesProvider.setSyncService(null);
    foldersProvider.setSyncService(null);
    calendarProvider.setSyncService(null);
    homeworkProvider.setSyncService(null);
    timetableProvider.setSyncService(null);
    themeService.setSyncService(null);

    await notesProvider.closeWorkspace();
    await foldersProvider.closeWorkspace();
    await calendarProvider.closeWorkspace();
    await homeworkProvider.closeWorkspace();
    await timetableProvider.closeWorkspace();

    final boxNames = [
      'notes_$workspaceId',
      'folders_$workspaceId',
      'calendar_events_$workspaceId',
      'homework_$workspaceId',
      'timetable_$workspaceId',
    ];

    try {
      for (final boxName in boxNames) {
        if (Hive.isBoxOpen(boxName)) {
          await Hive.box(boxName).close();
        }
        await Hive.deleteBoxFromDisk(boxName);
      }

      await LocalFileService.instance.clearAllFiles();

      await notesProvider.initialize(workspaceId);
      await foldersProvider.initialize(workspaceId);
      await calendarProvider.initialize(workspaceId);
      await homeworkProvider.initialize(workspaceId);
      await timetableProvider.initialize(workspaceId);

      syncService.setSyncEnabled(authService.effectiveSyncEnabled);
      if (authService.effectiveSyncEnabled) {
        syncService.startListening(cloudUserId);
        notesProvider.setSyncService(syncService);
        foldersProvider.setSyncService(syncService);
        calendarProvider.setSyncService(syncService);
        homeworkProvider.setSyncService(syncService);
        timetableProvider.setSyncService(syncService);
        themeService.setSyncService(syncService);
        syncService.refresh();
      }

      diagnosticsService.info(
        'LocalCacheReset',
        'Local cache reset complete for workspace $workspaceId',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Local cache cleared. Sync is reloading from cloud.'),
          ),
        );
      }
    } catch (e) {
      diagnosticsService.error(
        'LocalCacheReset',
        'Failed to reset local cache: $e',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reset local cache: $e')),
        );
      }
    }
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
                  final success =
                      await syncService.chooseSyncFolder(context: context);
                  if (success && dialogContext.mounted && context.mounted) {
                    Navigator.pop(dialogContext);
                    _showLocalFolderSync(context); // Refresh
                  } else if (!success &&
                      dialogContext.mounted &&
                      context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          syncService.errorMessage ?? 'Failed to choose folder',
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.folder_open),
                label: Text(
                  syncService.syncFolder != null
                      ? 'Change Folder'
                      : 'Choose Folder',
                ),
              ),
              if (syncService.syncFolder != null) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: syncService.isSyncing
                      ? null
                      : () async {
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

                          if (dialogContext.mounted &&
                              context.mounted &&
                              syncService.conflicts.isEmpty) {
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
    bool applyToAllRemaining = false;
    late void Function() showNextConflict;

    Future<void> resolveConflicts(
      ConflictResolution resolution, {
      required BuildContext dialogContext,
    }) async {
      final conflictsToResolve = applyToAllRemaining
          ? conflicts.skip(currentIndex).toList()
          : [conflicts[currentIndex]];

      for (final conflict in conflictsToResolve) {
        await syncService.resolveConflict(
          conflict,
          resolution,
          notesProvider: notesProvider,
          foldersProvider: foldersProvider,
          userId: userId,
        );
      }

      if (!dialogContext.mounted) {
        return;
      }

      Navigator.pop(dialogContext);
      currentIndex += conflictsToResolve.length;
      if (currentIndex >= conflicts.length) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                applyToAllRemaining
                    ? 'Applied ${_resolutionLabel(resolution)} to ${conflictsToResolve.length} conflicts.'
                    : 'All conflicts resolved',
              ),
            ),
          );
        }
        return;
      }

      showNextConflict();
    }

    showNextConflict = () {
      if (currentIndex >= conflicts.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All conflicts resolved')),
        );
        return;
      }

      final conflict = conflicts[currentIndex];
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('Conflict: ${conflict.itemName}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This ${conflict.isNote ? "note" : "folder"} has been modified in both locations.',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Local modified: ${_formatDateTime(conflict.localModified)}',
                  ),
                  Text(
                    'Cloud modified: ${_formatDateTime(conflict.cloudModified)}',
                  ),
                  const SizedBox(height: 16),
                  FutureBuilder<_ConflictPreviewData>(
                    future: _loadConflictPreview(
                      conflict: conflict,
                      syncService: syncService,
                      notesProvider: notesProvider,
                      foldersProvider: foldersProvider,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final preview = snapshot.data;
                      if (preview == null) {
                        return const SizedBox.shrink();
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _buildConflictPreview(preview),
                      );
                    },
                  ),
                  const Text('Choose which version to keep:'),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: applyToAllRemaining,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      'Apply to all remaining conflicts (${conflicts.length - currentIndex})',
                    ),
                    onChanged: (value) {
                      setDialogState(() {
                        applyToAllRemaining = value ?? false;
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => resolveConflicts(
                  ConflictResolution.useLocal,
                  dialogContext: dialogContext,
                ),
                child: Text(
                  applyToAllRemaining ? 'Use Local for All' : 'Use Local',
                ),
              ),
              TextButton(
                onPressed: () => resolveConflicts(
                  ConflictResolution.useCloud,
                  dialogContext: dialogContext,
                ),
                child: Text(
                  applyToAllRemaining ? 'Use Cloud for All' : 'Use Cloud',
                ),
              ),
              TextButton(
                onPressed: () => resolveConflicts(
                  ConflictResolution.keepBoth,
                  dialogContext: dialogContext,
                ),
                child: Text(
                  applyToAllRemaining ? 'Keep Both for All' : 'Keep Both',
                ),
              ),
              TextButton(
                onPressed: () => resolveConflicts(
                  ConflictResolution.skip,
                  dialogContext: dialogContext,
                ),
                child: Text(applyToAllRemaining ? 'Skip All' : 'Skip'),
              ),
            ],
          ),
        ),
      );
    };

    showNextConflict();
  }

  String _resolutionLabel(ConflictResolution resolution) {
    switch (resolution) {
      case ConflictResolution.useLocal:
        return 'Use Local';
      case ConflictResolution.useCloud:
        return 'Use Cloud';
      case ConflictResolution.keepBoth:
        return 'Keep Both';
      case ConflictResolution.skip:
        return 'Skip';
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1000) return '$bytes B';
    if (bytes < 1000 * 1000) return '${(bytes / 1000).toStringAsFixed(1)} KB';
    if (bytes < 1000 * 1000 * 1000) {
      return '${(bytes / (1000 * 1000)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1000 * 1000 * 1000)).toStringAsFixed(2)} GB';
  }

  Future<_ConflictPreviewData> _loadConflictPreview({
    required ConflictInfo conflict,
    required LocalFolderSyncService syncService,
    required NotesProvider notesProvider,
    required FoldersProvider foldersProvider,
  }) async {
    if (conflict.isNote) {
      return _loadNoteConflictPreview(
        conflict: conflict,
        syncService: syncService,
        notesProvider: notesProvider,
      );
    }

    return _loadFolderConflictPreview(
      conflict: conflict,
      syncService: syncService,
      foldersProvider: foldersProvider,
    );
  }

  Future<_ConflictPreviewData> _loadNoteConflictPreview({
    required ConflictInfo conflict,
    required LocalFolderSyncService syncService,
    required NotesProvider notesProvider,
  }) async {
    final note = notesProvider.getNoteById(conflict.itemId);
    final syncFolder = syncService.syncFolder;
    if (note == null || syncFolder == null) {
      return const _ConflictPreviewData.empty();
    }

    final localPath = p.join(syncFolder.path, _localPathForNote(note));
    final localFile = File(localPath);
    final localExists = await localFile.exists();
    final localSize = localExists ? await localFile.length() : 0;
    final localPreview = localExists
        ? await _readLocalPreview(localFile, note.type)
        : 'Local file not found.';
    final cloudPreview = _cloudPreviewForNote(note);

    final differences = <String>[
      if (localExists && localSize != note.size)
        'Size differs: local ${_formatBytes(localSize)} vs cloud ${_formatBytes(note.size)}',
      if (_normalizePreview(localPreview) != _normalizePreview(cloudPreview))
        'Content preview differs',
      if (localExists) 'Local file path: ${localFile.path}',
      if (note.pdfPath?.isNotEmpty == true && note.type == NoteType.pdf)
        'Cloud PDF reference: ${note.pdfPath}',
    ];

    return _ConflictPreviewData(
      differences: differences,
      local: _ConflictSideData(
        label: 'Local',
        meta: localExists
            ? '${_noteTypeLabel(note.type)} • ${_formatBytes(localSize)}'
            : 'Missing local file',
        preview: localPreview,
      ),
      cloud: _ConflictSideData(
        label: 'Cloud',
        meta: '${_noteTypeLabel(note.type)} • ${_formatBytes(note.size)}',
        preview: cloudPreview,
      ),
    );
  }

  Future<_ConflictPreviewData> _loadFolderConflictPreview({
    required ConflictInfo conflict,
    required LocalFolderSyncService syncService,
    required FoldersProvider foldersProvider,
  }) async {
    final folder = foldersProvider.getFolderById(conflict.itemId);
    final syncFolder = syncService.syncFolder;
    if (folder == null || syncFolder == null) {
      return const _ConflictPreviewData.empty();
    }

    final localDir =
        Directory(p.join(syncFolder.path, _localPathForFolder(folder)));
    final localExists = await localDir.exists();
    var localItems = 0;
    if (localExists) {
      await for (final _ in localDir.list()) {
        localItems++;
      }
    }

    final differences = <String>[
      if (localExists)
        'Local directory contains $localItems item${localItems == 1 ? '' : 's'}',
      if ((folder.subtitle ?? '').trim().isNotEmpty)
        'Cloud subtitle: ${folder.subtitle}',
      if (folder.parentId != null) 'Cloud folder has a parent folder',
    ];

    return _ConflictPreviewData(
      differences: differences,
      local: _ConflictSideData(
        label: 'Local',
        meta: localExists ? 'Directory on disk' : 'Missing local directory',
        preview: localExists ? localDir.path : 'Local folder not found.',
      ),
      cloud: _ConflictSideData(
        label: 'Cloud',
        meta: 'Folder in app workspace',
        preview: [
          folder.name,
          if ((folder.subtitle ?? '').trim().isNotEmpty) folder.subtitle!,
        ].join('\n'),
      ),
    );
  }

  Future<String> _readLocalPreview(File file, NoteType type) async {
    try {
      if (type == NoteType.pdf ||
          p.extension(file.path).toLowerCase() == '.pdf') {
        return 'PDF file on disk';
      }

      final raw = await file.readAsString();
      return _truncatePreview(raw);
    } catch (e) {
      return 'Unable to read local file: $e';
    }
  }

  String _cloudPreviewForNote(Note note) {
    if (note.type == NoteType.pdf) {
      return note.pdfPath?.isNotEmpty == true
          ? 'PDF note\n${note.pdfPath}'
          : 'PDF note';
    }

    final content = note.type == NoteType.markdown
        ? note.content
        : _extractPlainText(note.content);
    return _truncatePreview(content);
  }

  String _extractPlainText(String content) {
    return RichTextPlainTextService.extractPlainText(content);
  }

  String _truncatePreview(String value) {
    final normalized = value.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) {
      return 'No text content';
    }
    if (normalized.length <= 400) {
      return normalized;
    }
    return '${normalized.substring(0, 400)}...';
  }

  String _normalizePreview(String value) {
    final buffer = StringBuffer();
    var wroteWhitespace = false;

    for (final codeUnit in value.trim().codeUnits) {
      final isWhitespace =
          codeUnit == 32 || codeUnit == 9 || codeUnit == 10 || codeUnit == 13;
      if (isWhitespace) {
        if (!wroteWhitespace) {
          buffer.write(' ');
          wroteWhitespace = true;
        }
        continue;
      }

      buffer.writeCharCode(codeUnit);
      wroteWhitespace = false;
    }

    return buffer.toString();
  }

  String _localPathForNote(Note note) {
    switch (note.type) {
      case NoteType.pdf:
        return '${note.title}.pdf';
      case NoteType.markdown:
        return '${note.title}.md';
      case NoteType.text:
        return '${note.title}.txt';
    }
  }

  String _localPathForFolder(Folder folder) => folder.name;

  String _noteTypeLabel(NoteType type) {
    switch (type) {
      case NoteType.text:
        return 'Text';
      case NoteType.markdown:
        return 'Markdown';
      case NoteType.pdf:
        return 'PDF';
    }
  }

  Widget _buildConflictPreview(_ConflictPreviewData preview) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (preview.differences.isNotEmpty) ...[
          const Text(
            'Differences',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ...preview.differences.map(
            (difference) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• $difference'),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _buildConflictSideCard(preview.local),
        const SizedBox(height: 8),
        _buildConflictSideCard(preview.cloud),
      ],
    );
  }

  Widget _buildConflictSideCard(_ConflictSideData side) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            side.label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            side.meta,
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 8),
          SelectableText(side.preview),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(
    BuildContext context,
    AuthService authService,
  ) async {
    final action = await showDialog<_SignOutAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text(
          'Choose whether to keep your files on this device and continue as a guest, or remove all local files and return to the login screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _SignOutAction.continueAsGuest),
            child: const Text('Keep Files'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(context, _SignOutAction.deleteLocalAndSignOut),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete Files & Sign Out'),
          ),
        ],
      ),
    );

    if (!context.mounted || action == null) {
      return;
    }

    switch (action) {
      case _SignOutAction.continueAsGuest:
        await _continueAsGuest(context);
        break;
      case _SignOutAction.deleteLocalAndSignOut:
        await _deleteLocalFilesAndSignOut(context);
        break;
    }
  }

  Future<void> _continueAsGuest(BuildContext context) async {
    final authService = context.read<AuthService>();
    final notesProvider = context.read<NotesProvider>();
    final foldersProvider = context.read<FoldersProvider>();
    final calendarProvider = context.read<CalendarProvider>();
    final homeworkProvider = context.read<HomeworkProvider>();
    final timetableProvider = context.read<TimetableProvider>();
    final workspaceId = authService.storageUserId ?? authService.userId;
    await _detachWorkspaceServices(context);
    await authService.continueAsGuest(workspaceId: workspaceId);

    if (!authService.isGuestMode) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              authService.errorMessage ?? 'Failed to continue as guest.',
            ),
          ),
        );
      }
      return;
    }

    final guestWorkspaceId = authService.storageUserId;
    if (guestWorkspaceId != null) {
      await LocalFileService.instance.initialize(guestWorkspaceId);
      await notesProvider.initialize(guestWorkspaceId);
      await foldersProvider.initialize(guestWorkspaceId);
      await calendarProvider.initialize(guestWorkspaceId);
      await homeworkProvider.initialize(guestWorkspaceId);
      await timetableProvider.initialize(guestWorkspaceId);
    }

    if (!context.mounted) return;
    AppRouter.navigateAndClearStack(context, AppRouter.home);
  }

  Future<void> _deleteLocalFilesAndSignOut(BuildContext context) async {
    final authService = context.read<AuthService>();
    final workspaceId = authService.storageUserId;

    await _detachWorkspaceServices(context);
    if (workspaceId != null) {
      await _deleteWorkspaceData(workspaceId);
    }
    await authService.signOut();

    if (!context.mounted) return;
    AppRouter.navigateAndClearStack(context, AppRouter.login);
  }

  Future<void> _detachWorkspaceServices(BuildContext context) async {
    final syncService = context.read<SyncService>();
    final notesProvider = context.read<NotesProvider>();
    final foldersProvider = context.read<FoldersProvider>();
    final calendarProvider = context.read<CalendarProvider>();
    final homeworkProvider = context.read<HomeworkProvider>();
    final timetableProvider = context.read<TimetableProvider>();
    final themeService = context.read<ThemeService>();

    syncService.stopListening();
    notesProvider.setSyncService(null);
    foldersProvider.setSyncService(null);
    calendarProvider.setSyncService(null);
    homeworkProvider.setSyncService(null);
    timetableProvider.setSyncService(null);
    themeService.setSyncService(null);

    await notesProvider.closeWorkspace();
    await foldersProvider.closeWorkspace();
    await calendarProvider.closeWorkspace();
    await homeworkProvider.closeWorkspace();
    await timetableProvider.closeWorkspace();
  }

  Future<void> _deleteWorkspaceData(String workspaceId) async {
    final boxNames = [
      'notes_$workspaceId',
      'folders_$workspaceId',
      'calendar_events_$workspaceId',
      'homework_$workspaceId',
      'timetable_$workspaceId',
    ];

    for (final boxName in boxNames) {
      if (Hive.isBoxOpen(boxName)) {
        await Hive.box(boxName).close();
      }
      await Hive.deleteBoxFromDisk(boxName);
    }

    await LocalFileService.instance.deleteWorkspaceFiles(workspaceId);
  }
}

enum _SignOutAction {
  continueAsGuest,
  deleteLocalAndSignOut,
}

class _ConflictPreviewData {
  final List<String> differences;
  final _ConflictSideData local;
  final _ConflictSideData cloud;

  const _ConflictPreviewData({
    required this.differences,
    required this.local,
    required this.cloud,
  });

  const _ConflictPreviewData.empty()
      : differences = const [],
        local = const _ConflictSideData(
          label: 'Local',
          meta: 'Unavailable',
          preview: 'No preview available.',
        ),
        cloud = const _ConflictSideData(
          label: 'Cloud',
          meta: 'Unavailable',
          preview: 'No preview available.',
        );
}

class _ConflictSideData {
  final String label;
  final String meta;
  final String preview;

  const _ConflictSideData({
    required this.label,
    required this.meta,
    required this.preview,
  });
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
      trailing:
          trailing ?? (onTap != null ? const Icon(Icons.chevron_right) : null),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
