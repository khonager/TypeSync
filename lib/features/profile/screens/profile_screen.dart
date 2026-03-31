/// Profile Screen
///
/// User profile management screen.
library;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import '../../../core/models/user.dart';
import '../../../core/providers/calendar_provider.dart';
import '../../../core/providers/folders_provider.dart';
import '../../../core/providers/homework_provider.dart';
import '../../../core/providers/notes_provider.dart';
import '../../../core/providers/timetable_provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/local_file_service.dart';
import '../../../core/services/local_folder_sync_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/services/theme_service.dart';
import '../../../core/routes/app_router.dart';

/// User profile screen
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
  int _localStorageBytes = 0;
  bool _isLoadingLocalStorage = false;
  String? _lastObservedLocalSyncPath;

  Future<void> _refreshStorageInfo() async {
    final authService = context.read<AuthService>();
    if (authService.isGuestMode) {
      return;
    }

    await authService.refreshCurrentUser();
    if (!mounted) return;

    final cloudUserId = authService.userId;
    final workspaceId = authService.storageUserId;
    if (cloudUserId == null || workspaceId == null) return;

    final storageService = context.read<StorageService>();
    final localFileService = LocalFileService.instance;
    final localFolderSyncService = context.read<LocalFolderSyncService>();

    setState(() {
      _isLoadingLocalStorage = true;
    });

    try {
      await Future.wait([
        storageService.loadStorageInfo(cloudUserId),
        () async {
          await localFileService.initialize(workspaceId);
          final localAppStorageBytes =
              await localFileService.getTotalStorageBytes();
          final localFolderSyncBytes =
              await localFolderSyncService.getTotalStorageBytes();
          final localStorageBytes =
              localAppStorageBytes + localFolderSyncBytes;
          if (!mounted) return;
          setState(() {
            _localStorageBytes = localStorageBytes;
          });
        }(),
      ]);
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocalStorage = false;
        });
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1000) return '$bytes B';
    if (bytes < 1000 * 1000) return '${(bytes / 1000).toStringAsFixed(1)} KB';
    if (bytes < 1000 * 1000 * 1000) {
      return '${(bytes / (1000 * 1000)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1000 * 1000 * 1000)).toStringAsFixed(2)} GB';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Load storage info when screen opens and refresh auth state in case the
    // user just verified their email in the browser.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refreshStorageInfo();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final localSyncPath = context.watch<LocalFolderSyncService>().syncFolder?.path;
    if (localSyncPath != _lastObservedLocalSyncPath) {
      _lastObservedLocalSyncPath = localSyncPath;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _refreshStorageInfo();
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !context.read<AuthService>().isGuestMode) {
      _refreshStorageInfo();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final storageService = context.watch<StorageService>();
    final user = authService.currentUser;

    if (authService.isGuestMode) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Sign In'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.login, size: 56),
                const SizedBox(height: 16),
                Text(
                  'Sign in to use cloud sync and account features.',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () =>
                      AppRouter.navigateAndClearStack(context, AppRouter.login),
                  child: const Text('Go to Sign In'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Profile'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile header
          Center(
            child: Column(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  backgroundImage: user?.photoUrl != null
                      ? NetworkImage(user!.photoUrl!)
                      : null,
                  child: user?.photoUrl == null
                      ? Text(
                          user?.displayName?.isNotEmpty == true
                              ? user!.displayName![0].toUpperCase()
                              : user?.email[0].toUpperCase() ?? '?',
                          style: const TextStyle(fontSize: 32),
                        )
                      : null,
                ),
                const SizedBox(height: 16),
                // Name
                Text(
                  user?.displayName ?? 'No name',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                // Email
                Text(
                  user?.email ?? '',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey,
                      ),
                ),
                const SizedBox(height: 8),
                // Email verification status
                if (user != null && !user.emailVerified)
                  TextButton.icon(
                    onPressed: () {
                      authService.resendVerificationEmail();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Verification email sent'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.warning, size: 16),
                    label: const Text('Verify email'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.orange,
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Storage usage
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Cloud Storage',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        storageService.usageFormatted,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: storageService.usagePercent,
                      backgroundColor: Colors.grey.withValues(alpha: 0.3),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Subscription tier
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Plan: ${storageService.currentTier.displayName}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      TextButton(
                        onPressed: () {
                          AppRouter.navigateTo(context, AppRouter.subscription);
                        },
                        child: const Text('Upgrade'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Local Files',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        _isLoadingLocalStorage
                            ? 'Calculating...'
                            : _formatBytes(_localStorageBytes),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Stored on this device only. Includes app-local files and the configured Local Folder Sync directory, while cloud files are tracked separately.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),

                  // 95% capacity warning
                  if (storageService.usagePercent >= 0.95) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              storageService.isStorageFull
                                  ? 'Storage is full! Please upgrade your plan.'
                                  : 'Storage is almost full (${(storageService.usagePercent * 100).toInt()}%).',
                              style: const TextStyle(color: Colors.orange),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Edit profile
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit Profile'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showEditProfile(context, authService),
          ),

          // Change password
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Change Password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showChangePassword(context),
          ),

          const Divider(height: 32),

          // Danger zone
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text(
              'Delete Account',
              style: TextStyle(color: Colors.red),
            ),
            onTap: () => _confirmDeleteAccount(context),
          ),
        ],
      ),
    );
  }

  void _showEditProfile(BuildContext context, AuthService authService) {
    final nameController = TextEditingController(
      text: authService.currentUser?.displayName,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Profile'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Display Name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              authService.updateProfile(displayName: nameController.text);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showChangePassword(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Password'),
        content: const Text(
          'We\'ll send you an email with a link to reset your password.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final authService = context.read<AuthService>();
              final email = authService.currentUser?.email;
              if (email != null) {
                authService.resetPassword(email);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Password reset email sent'),
                  ),
                );
              }
            },
            child: const Text('Send Email'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'Are you sure you want to delete your account? '
          'This action cannot be undone and all your data will be permanently lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    await _deleteAccount(context);
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final authService = context.read<AuthService>();
    final syncService = context.read<SyncService>();
    final notesProvider = context.read<NotesProvider>();
    final foldersProvider = context.read<FoldersProvider>();
    final calendarProvider = context.read<CalendarProvider>();
    final homeworkProvider = context.read<HomeworkProvider>();
    final timetableProvider = context.read<TimetableProvider>();
    final themeService = context.read<ThemeService>();
    final workspaceId = authService.storageUserId;

    final deleted = await authService.deleteAccount();

    if (!deleted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              authService.errorMessage ?? 'Failed to delete account.',
            ),
          ),
        );
      }
      return;
    }

    await _detachWorkspaceServices(
      syncService: syncService,
      notesProvider: notesProvider,
      foldersProvider: foldersProvider,
      calendarProvider: calendarProvider,
      homeworkProvider: homeworkProvider,
      timetableProvider: timetableProvider,
      themeService: themeService,
    );
    if (workspaceId != null) {
      await _deleteWorkspaceData(workspaceId);
    }

    if (!context.mounted) return;
    AppRouter.navigateAndClearStack(context, AppRouter.login);
  }

  Future<void> _detachWorkspaceServices({
    required SyncService syncService,
    required NotesProvider notesProvider,
    required FoldersProvider foldersProvider,
    required CalendarProvider calendarProvider,
    required HomeworkProvider homeworkProvider,
    required TimetableProvider timetableProvider,
    required ThemeService themeService,
  }) async {
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
