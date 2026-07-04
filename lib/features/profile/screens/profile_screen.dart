/// Profile Screen
///
/// User profile management screen.
library;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import '../../../core/widgets/desktop_window_frame.dart';
import '../../home/widgets/home_bottom_bar.dart';

/// User profile screen
class ProfileScreen extends StatefulWidget {
  final bool embedded;

  const ProfileScreen({
    this.embedded = false,
    super.key,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
  static const String _localStorageTotalPrefsPrefix =
      'profile_local_storage_total_';
  static const String _localStorageAppPrefsPrefix =
      'profile_local_storage_app_';
  static const String _localStorageFolderSyncPrefsPrefix =
      'profile_local_storage_folder_sync_';

  int _localStorageBytes = 0;
  int _localAppStorageBytes = 0;
  int _localFolderSyncBytes = 0;
  bool _isLoadingLocalStorage = false;
  bool _hasCachedLocalStorage = false;
  bool _hasObservedLocalSyncPath = false;
  String? _lastObservedLocalSyncPath;

  String _localStoragePrefsKey(String prefix, String workspaceId) {
    return '$prefix$workspaceId';
  }

  Future<void> _loadCachedLocalStorageInfo() async {
    final authService = context.read<AuthService>();
    if (authService.isGuestMode) {
      return;
    }

    final workspaceId = authService.storageUserId;
    if (workspaceId == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAppStorageBytes = prefs.getInt(
        _localStoragePrefsKey(_localStorageAppPrefsPrefix, workspaceId),
      );
      final savedFolderSyncBytes = prefs.getInt(
        _localStoragePrefsKey(_localStorageFolderSyncPrefsPrefix, workspaceId),
      );
      final savedTotalStorageBytes = prefs.getInt(
        _localStoragePrefsKey(_localStorageTotalPrefsPrefix, workspaceId),
      );
      final hasCachedValue = savedAppStorageBytes != null ||
          savedFolderSyncBytes != null ||
          savedTotalStorageBytes != null;

      if (!mounted || !hasCachedValue) {
        return;
      }

      final nextAppStorageBytes = savedAppStorageBytes ?? 0;
      final nextFolderSyncBytes = savedFolderSyncBytes ?? 0;
      final nextTotalStorageBytes =
          savedTotalStorageBytes ?? nextAppStorageBytes + nextFolderSyncBytes;

      setState(() {
        _hasCachedLocalStorage = true;
        _localAppStorageBytes = nextAppStorageBytes;
        _localFolderSyncBytes = nextFolderSyncBytes;
        _localStorageBytes = nextTotalStorageBytes;
      });
    } catch (_) {
      // Keep rendering with in-memory values if the cache is unavailable.
    }
  }

  Future<void> _persistLocalStorageInfo({
    required String workspaceId,
    required int localAppStorageBytes,
    required int localFolderSyncBytes,
    required int localStorageBytes,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _localStoragePrefsKey(_localStorageAppPrefsPrefix, workspaceId),
        localAppStorageBytes,
      );
      await prefs.setInt(
        _localStoragePrefsKey(_localStorageFolderSyncPrefsPrefix, workspaceId),
        localFolderSyncBytes,
      );
      await prefs.setInt(
        _localStoragePrefsKey(_localStorageTotalPrefsPrefix, workspaceId),
        localStorageBytes,
      );
    } catch (_) {
      // A missed cache write should not interrupt profile rendering.
    }
  }

  Future<void> _refreshCloudStorageInfo({bool runAudit = false}) async {
    final authService = context.read<AuthService>();
    if (authService.isGuestMode) {
      return;
    }

    await authService.refreshCurrentUser();
    if (!mounted) return;

    final cloudUserId = authService.userId;
    if (cloudUserId == null) return;

    final storageService = context.read<StorageService>();

    await storageService.loadStorageInfo(
      cloudUserId,
      fallbackUser: authService.currentUser,
      runAudit: runAudit,
    );
  }

  Future<void> _refreshLocalStorageInfo({bool showLoadingState = false}) async {
    final authService = context.read<AuthService>();
    if (authService.isGuestMode) {
      return;
    }

    final workspaceId = authService.storageUserId;
    if (workspaceId == null) return;

    final localFileService = LocalFileService.instance;
    final localFolderSyncService = context.read<LocalFolderSyncService>();

    if (showLoadingState && mounted) {
      setState(() {
        _isLoadingLocalStorage = true;
      });
    }

    try {
      await localFileService.initialize(workspaceId);
      final localAppStorageBytes =
          await localFileService.getTotalStorageBytes();
      final localFolderSyncBytes =
          await localFolderSyncService.getTotalStorageBytes();
      final localStorageBytes = localAppStorageBytes + localFolderSyncBytes;

      await _persistLocalStorageInfo(
        workspaceId: workspaceId,
        localAppStorageBytes: localAppStorageBytes,
        localFolderSyncBytes: localFolderSyncBytes,
        localStorageBytes: localStorageBytes,
      );

      if (!mounted) return;

      final hasChanged = _localAppStorageBytes != localAppStorageBytes ||
          _localFolderSyncBytes != localFolderSyncBytes ||
          _localStorageBytes != localStorageBytes ||
          !_hasCachedLocalStorage;

      if (hasChanged || _isLoadingLocalStorage) {
        setState(() {
          _hasCachedLocalStorage = true;
          _localAppStorageBytes = localAppStorageBytes;
          _localFolderSyncBytes = localFolderSyncBytes;
          _localStorageBytes = localStorageBytes;
        });
      }
    } finally {
      if (showLoadingState && mounted && _isLoadingLocalStorage) {
        setState(() {
          _isLoadingLocalStorage = false;
        });
      }
    }
  }

  Future<void> _refreshStorageInfo({
    bool refreshCloud = true,
    bool refreshLocal = true,
    bool showLocalLoadingState = false,
    bool runCloudAudit = false,
  }) async {
    if (refreshCloud) {
      await _refreshCloudStorageInfo(runAudit: runCloudAudit);
    }
    if (refreshLocal && mounted) {
      await _refreshLocalStorageInfo(showLoadingState: showLocalLoadingState);
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

  String _formatExactBytes(int bytes) {
    final digits = bytes.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      final remaining = digits.length - index;
      buffer.write(digits[index]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(',');
      }
    }
    return '${buffer.toString()} bytes';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Restore the most recent local storage figures immediately, then refresh
    // only the cloud-backed values when the screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadCachedLocalStorageInfo();
      if (!mounted) return;
      await _refreshStorageInfo(refreshLocal: false);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final localSyncPath =
        context.watch<LocalFolderSyncService>().syncFolder?.path;
    if (!_hasObservedLocalSyncPath) {
      _hasObservedLocalSyncPath = true;
      _lastObservedLocalSyncPath = localSyncPath;
      return;
    }

    if (localSyncPath != _lastObservedLocalSyncPath) {
      _lastObservedLocalSyncPath = localSyncPath;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _refreshLocalStorageInfo(showLoadingState: !_hasCachedLocalStorage);
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
      _refreshStorageInfo(showLocalLoadingState: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final storageService = context.watch<StorageService>();
    final user = authService.currentUser;
    final bottomScrollPadding =
        widget.embedded ? homeBottomBarScrollPaddingFor(context) : 16.0;

    if (authService.isGuestMode) {
      final body = _buildGuestBody(
        context,
        bottomPadding: bottomScrollPadding,
      );
      if (widget.embedded) {
        return body;
      }

      return Scaffold(
        appBar: AppBar(
          flexibleSpace: desktopWindowDragArea(),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Sign In'),
          actions: withDesktopWindowControls(const []),
        ),
        body: body,
      );
    }

    final body = ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomScrollPadding),
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
                  onPressed:
                      authService.isLoading ? null : _resendVerificationEmail,
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
                    if (storageService.isLoading &&
                        !storageService.hasLoadedStorageInfo)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Loading...',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      )
                    else
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
                    value: storageService.isLoading &&
                            !storageService.hasLoadedStorageInfo
                        ? null
                        : storageService.usagePercent.clamp(0, 1),
                    backgroundColor: Colors.grey.withValues(alpha: 0.3),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 12),
                if (storageService.isLoading &&
                    !storageService.hasLoadedStorageInfo)
                  Text(
                    'Checking cloud usage...',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                  )
                else
                  Text(
                    _formatExactBytes(storageService.storageUsedBytes),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey),
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton.icon(
                          onPressed: storageService.isLoading
                              ? null
                              : () => _refreshStorageInfo(
                                    refreshLocal: false,
                                    runCloudAudit: true,
                                  ),
                          icon: const Icon(Icons.manage_search, size: 18),
                          label: const Text('Audit'),
                        ),
                        TextButton(
                          onPressed: () {
                            AppRouter.navigateTo(
                              context,
                              AppRouter.subscription,
                            );
                          },
                          child: const Text('Upgrade'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  storageService.hasAuditedStorageInfo
                      ? 'Quota checks use the saved account total. The breakdown below is from the latest audit.'
                      : 'Quota checks use this saved account total. Run an audit to recalculate the detailed breakdown.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                ),
                if (storageService.hasAuditedStorageInfo) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Notes content',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        _formatBytes(storageService.cloudContentBytes),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Note attachments',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        _formatBytes(storageService.cloudAttachmentBytes),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Cloud files',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        '${storageService.cloudFileCount}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Cloud notes',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        '${storageService.cloudNoteCount}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
                if (storageService.hasAuditedStorageInfo &&
                    storageService.cloudRecordedBytes >
                        [
                          storageService.cloudContentBytes +
                              storageService.cloudAttachmentBytes,
                          storageService.cloudStoredFileBytes,
                        ].reduce((a, b) => a > b ? a : b)) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recorded account total',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        _formatBytes(storageService.cloudRecordedBytes),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
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
                  'Stored on this device only. Total = app-local cache + Local Folder Sync directory.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatExactBytes(_localStorageBytes),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'App-local cache',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      _formatBytes(_localAppStorageBytes),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Local Folder Sync',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      _formatBytes(_localFolderSyncBytes),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
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
    );

    if (widget.embedded) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: desktopWindowDragArea(),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Profile'),
        actions: withDesktopWindowControls(const []),
      ),
      body: body,
    );
  }

  Widget _buildGuestBody(
    BuildContext context, {
    required double bottomPadding,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPadding),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.maxHeight - bottomPadding,
          ),
          child: Center(
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
            onPressed: () async {
              final navigator = Navigator.of(context);
              final authService = context.read<AuthService>();
              final email = authService.currentUser?.email;
              if (email == null) {
                if (!mounted) return;
                navigator.pop();
                _showMessage('No email address is available for this account.');
                return;
              }

              final success = await authService.resetPassword(email);
              if (!mounted) return;

              navigator.pop();
              _showMessage(
                success
                    ? 'Password reset email sent.'
                    : authService.errorMessage ??
                        'We could not send the password reset email. Please try again.',
              );
            },
            child: const Text('Send Email'),
          ),
        ],
      ),
    );
  }

  Future<void> _resendVerificationEmail() async {
    final authService = context.read<AuthService>();
    final success = await authService.resendVerificationEmail();

    if (!mounted) return;

    _showMessage(
      success
          ? 'Verification email sent.'
          : authService.errorMessage ??
              'We could not send the verification email. Please try again.',
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
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
