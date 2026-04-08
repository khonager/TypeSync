/// Home Screen
///
/// Main screen showing folders and files in a grid view.
/// Based on the design mockup with dark theme.
library;

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../core/models/folder.dart';
import '../../../core/models/note.dart';
import '../../../core/providers/calendar_provider.dart';
import '../../../core/providers/folders_provider.dart';
import '../../../core/providers/homework_provider.dart';
import '../../../core/providers/notes_provider.dart';
import '../../../core/providers/timetable_provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/data_repair_service.dart';
import '../../../core/services/local_file_service.dart';
import '../../../core/services/migration_service.dart';
import '../../../core/services/rich_text_plain_text_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/services/theme_service.dart';
import '../../../core/services/diagnostics_service.dart';
import '../../../core/routes/app_router.dart';
import '../../../core/utils/color_utils.dart';
import '../../../core/utils/file_picker_helper.dart';
import '../../../core/utils/search_query.dart';
import '../../profile/screens/profile_screen.dart';
import '../widgets/folder_grid.dart';
import '../widgets/file_grid.dart';
import '../widgets/home_bottom_bar.dart';
import '../widgets/home_upcoming_section.dart';
import '../widgets/sync_status_indicator.dart';

/// Home screen with folder/file browser
///
/// Displays a grid of folders and files matching the design.
/// Supports navigation into folders and creating new items.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const List<String> _inSearchSuggestions = [
    'in:text',
    'in:title',
    'in:attachment',
    'in:pdf',
    'in:txt',
    'in:markdown',
  ];
  static const List<String> _hasSearchSuggestions = [
    'has:attachment',
    'has:image',
    'has:pdf',
  ];
  static const List<String> _isSearchSuggestions = [
    'is:file',
    'is:folder',
  ];

  // Current folder being viewed (null = root)
  String? _currentFolderId;
  HomeBottomBarTab _selectedTab = HomeBottomBarTab.files;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  List<String> _searchSuggestions = const <String>[];
  int _selectedSearchSuggestionIndex = 0;

  // View mode (grid or list)
  bool _isGridView = true;

  // Drag and drop state
  bool _isDragging = false;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _scrollViewKey = GlobalKey();
  Timer? _autoScrollTimer;
  double _autoScrollDelta = 0;

  Timer? _repairAuditTimer;
  String? _lastRepairPromptSignature;
  bool _isRepairDialogOpen = false;
  bool _isHandlingGuestImport = false;
  final DiagnosticsService _diagnostics = DiagnosticsService.instance;
  String? _activeWorkspaceId;
  String? _activeCloudUserId;
  bool? _activeSyncEnabled;
  AuthService? _authService;
  String? _initializingWorkspaceId;

  @override
  void initState() {
    super.initState();
    // Defer initialization until after the first frame to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _attachAuthListener();
      _initializeData();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachAuthListener();
  }

  Future<void> _initializeData({bool force = false}) async {
    final authService = context.read<AuthService>();
    final cloudUserId = authService.userId;
    final effectiveUserId = authService.storageUserId;

    _diagnostics.info(
      'HomeScreen',
      'WORKSPACE_FLOW initialize requested force=$force routeCurrent=${ModalRoute.of(context)?.isCurrent} cloudUser=$cloudUserId workspace=$effectiveUserId guestMode=${authService.isGuestMode} pendingGuestImport=${authService.pendingGuestImportWorkspaceId}',
    );

    if (effectiveUserId == null) {
      _diagnostics.warning(
        'HomeScreen',
        'WORKSPACE_FLOW skipped initialize because there is no active workspace',
      );
      return;
    }

    if (_initializingWorkspaceId == effectiveUserId) {
      _diagnostics.info(
        'HomeScreen',
        'WORKSPACE_FLOW skipped initialize because workspace=$effectiveUserId is already initializing',
      );
      return;
    }

    final syncEnabled =
        authService.isLoggedIn && authService.effectiveSyncEnabled;
    if (!force &&
        _activeWorkspaceId == effectiveUserId &&
        _activeCloudUserId == cloudUserId &&
        _activeSyncEnabled == syncEnabled) {
      _diagnostics.info(
        'HomeScreen',
        'WORKSPACE_FLOW skipped initialize because workspace=$effectiveUserId syncEnabled=$syncEnabled is unchanged',
      );
      return;
    }

    final workspaceChanged = _activeWorkspaceId != effectiveUserId;
    final previousWorkspaceId = _activeWorkspaceId;
    _activeWorkspaceId = effectiveUserId;
    _activeCloudUserId = cloudUserId;
    _activeSyncEnabled = syncEnabled;
    _initializingWorkspaceId = effectiveUserId;

    _diagnostics.info(
      'HomeScreen',
      'WORKSPACE_FLOW active workspace changed previous=$previousWorkspaceId next=$effectiveUserId cloudUser=$cloudUserId syncEnabled=$syncEnabled',
    );

    if (workspaceChanged && mounted) {
      setState(() {
        _currentFolderId = null;
      });
    }

    final notesProvider = context.read<NotesProvider>();
    final foldersProvider = context.read<FoldersProvider>();
    final calendarProvider = context.read<CalendarProvider>();
    final homeworkProvider = context.read<HomeworkProvider>();
    final timetableProvider = context.read<TimetableProvider>();
    final themeService = context.read<ThemeService>();
    final syncService = context.read<SyncService>();

    try {
      // Initialize local file service
      await LocalFileService.instance.initialize(effectiveUserId);

      if (!mounted) return;

      // Initialize providers with the active workspace ID.
      await notesProvider.initialize(effectiveUserId);
      if (!mounted) return;
      await foldersProvider.initialize(effectiveUserId);
      if (!mounted) return;

      _diagnostics.info(
        'HomeScreen',
        'WORKSPACE_FLOW workspace initialized workspace=$effectiveUserId notes=${notesProvider.notes.length} folders=${foldersProvider.folders.length}',
      );

      _scheduleRepairAudit();

      // Sync the sync service with auth preferences
      syncService.setSyncEnabled(authService.effectiveSyncEnabled);

      // Only start sync if user is logged in (not guest) and sync is enabled
      // We check actual userId (not effective) to determine if we can sync
      if (cloudUserId != null && syncEnabled) {
        // Connect providers to sync service
        notesProvider.setSyncService(syncService);
        foldersProvider.setSyncService(syncService);
        calendarProvider.setSyncService(syncService);
        homeworkProvider.setSyncService(syncService);
        timetableProvider.setSyncService(syncService);
        themeService.setSyncService(syncService);

        // Set up sync callbacks without touching BuildContext after init.
        syncService.onNotesUpdated = (notes) {
          notesProvider.handleCloudUpdate(notes);
          if (mounted) {
            _scheduleRepairAudit();
          }
        };
        syncService.onFoldersUpdated = (folders) {
          foldersProvider.handleCloudUpdate(folders);
          if (mounted) {
            _scheduleRepairAudit();
          }
        };
        syncService.onCalendarUpdated = calendarProvider.handleCloudUpdate;
        syncService.onHomeworkUpdated = homeworkProvider.handleCloudUpdate;
        syncService.onTimetableUpdated = timetableProvider.handleCloudUpdate;
        syncService.onSettingsUpdated = themeService.handleCloudSettings;

        _diagnostics.info(
          'HomeScreen',
          'SYNC_LIFECYCLE callbacks attached workspace=$effectiveUserId cloudUser=$cloudUserId',
        );

        syncService.startListening(cloudUserId);

        // Check for guest workspace import after sign-in
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            _checkGuestWorkspaceImport(cloudUserId);
          });
        }
      } else {
        // For guests or when sync is disabled, don't set up sync service
        syncService.stopListening(
          reason: 'workspace unavailable or sync disabled',
        );
        notesProvider.setSyncService(null);
        foldersProvider.setSyncService(null);
        calendarProvider.setSyncService(null);
        homeworkProvider.setSyncService(null);
        timetableProvider.setSyncService(null);
        themeService.setSyncService(null);
        _diagnostics.info(
          'HomeScreen',
          'SYNC_LIFECYCLE sync detached workspace=$effectiveUserId cloudUser=$cloudUserId syncEnabled=$syncEnabled guestMode=${authService.isGuestMode}',
        );
      }
    } finally {
      if (_initializingWorkspaceId == effectiveUserId) {
        _initializingWorkspaceId = null;
      }
      _diagnostics.info(
        'HomeScreen',
        'WORKSPACE_FLOW initialize finished workspace=$effectiveUserId activeFolder=$_currentFolderId',
      );
    }
  }

  void _scheduleRepairAudit() {
    _repairAuditTimer?.cancel();
    _repairAuditTimer = Timer(const Duration(milliseconds: 800), () {
      _maybePromptRepairPlan();
    });
  }

  Future<void> _maybePromptRepairPlan() async {
    if (!mounted || _isRepairDialogOpen) {
      return;
    }

    final authService = context.read<AuthService>();
    final currentUserId = authService.storageUserId;
    if (currentUserId == null) {
      _diagnostics.warning(
        'RepairAudit',
        'Skipped repair audit because there is no active workspace user id',
      );
      return;
    }

    final repairService = DataRepairService();
    final plan = repairService.buildRepairPlan(
      currentUserId: currentUserId,
      foldersProvider: context.read<FoldersProvider>(),
      notesProvider: context.read<NotesProvider>(),
    );

    if (!plan.hasChanges || plan.signature == _lastRepairPromptSignature) {
      if (!plan.hasChanges) {
        _diagnostics.info('RepairAudit', 'No repairable legacy items found');
      }
      return;
    }

    _diagnostics.info(
      'RepairAudit',
      'Found ${plan.totalItems} repairable legacy item${plan.totalItems == 1 ? '' : 's'}',
    );

    _isRepairDialogOpen = true;
    final shouldRepair = await _showRepairDialog(plan);
    _isRepairDialogOpen = false;
    _lastRepairPromptSignature = plan.signature;

    if (shouldRepair != true || !mounted) {
      _diagnostics.info('RepairAudit', 'User declined legacy item repair');
      return;
    }

    final repairedCount = await repairService.applyRepairPlan(
      plan: plan,
      foldersProvider: context.read<FoldersProvider>(),
      notesProvider: context.read<NotesProvider>(),
    );

    if (!mounted) {
      return;
    }

    _diagnostics.info(
      'RepairAudit',
      'Applied repairs to $repairedCount item${repairedCount == 1 ? '' : 's'}',
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Repaired $repairedCount item${repairedCount == 1 ? '' : 's'}',
        ),
      ),
    );
  }

  Future<bool?> _showRepairDialog(RepairPlan plan) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Repair legacy items?'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TypeSync found ${plan.totalItems} item${plan.totalItems == 1 ? '' : 's'} that can be repaired safely.',
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: plan.allItems.map((candidate) {
                      final typeLabel = candidate.type == RepairItemType.folder
                          ? 'Folder'
                          : 'Note';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          '$typeLabel: ${candidate.name}\nWill change: ${candidate.changes.join(', ')}',
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkGuestWorkspaceImport(String userId) async {
    if (!mounted) {
      return;
    }

    if (_isHandlingGuestImport) {
      _diagnostics.info(
        'HomeScreen',
        'GUEST_IMPORT skipped because an import flow is already running',
      );
      return;
    }

    _isHandlingGuestImport = true;
    final authService = context.read<AuthService>();
    final notesProvider = context.read<NotesProvider>();
    final foldersProvider = context.read<FoldersProvider>();
    final migrationService = MigrationService();
    final guestWorkspaceId = authService.pendingGuestImportWorkspaceId;

    try {
      _diagnostics.info(
        'HomeScreen',
        'GUEST_IMPORT pending workspace=$guestWorkspaceId targetUser=$userId activeWorkspace=${authService.storageUserId}',
      );

      if (guestWorkspaceId == null || guestWorkspaceId == userId) {
        _diagnostics.info(
          'HomeScreen',
          'GUEST_IMPORT skipped because there is no distinct guest workspace to import',
        );
        return;
      }

      final hasGuestData = await migrationService.workspaceHasData(
        guestWorkspaceId,
      );
      _diagnostics.info(
        'HomeScreen',
        'GUEST_IMPORT source workspace=$guestWorkspaceId hasData=$hasGuestData',
      );
      if (!hasGuestData || !mounted) {
        await authService.clearPendingGuestImportWorkspace();
        return;
      }

      final action = await showDialog<_GuestImportAction>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Import Guest Files?'),
          content: const Text(
            'We found files from your guest workspace. Do you want to add them to this signed-in account?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, _GuestImportAction.keep),
              child: const Text('Keep Guest Files'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, _GuestImportAction.deleteGuestFiles),
              child: const Text('Delete Guest Files'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(context, _GuestImportAction.import),
              child: const Text('Import'),
            ),
          ],
        ),
      );

      if (!mounted || action == null) {
        _diagnostics.info(
          'HomeScreen',
          'GUEST_IMPORT prompt dismissed without action',
        );
        return;
      }

      _diagnostics.info(
        'HomeScreen',
        'GUEST_IMPORT prompt action=${action.name} sourceWorkspace=$guestWorkspaceId targetUser=$userId',
      );

      switch (action) {
        case _GuestImportAction.import:
          final count = await migrationService.importWorkspace(
            sourceWorkspaceId: guestWorkspaceId,
            targetUserId: userId,
            notesProvider: notesProvider,
            foldersProvider: foldersProvider,
          );
          await notesProvider.initialize(userId);
          await foldersProvider.initialize(userId);
          _diagnostics.info(
            'HomeScreen',
            'GUEST_IMPORT import finished targetUser=$userId importedItems=$count notes=${notesProvider.notes.length} folders=${foldersProvider.folders.length}',
          );
          await authService.clearPendingGuestImportWorkspace();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                count > 0
                    ? 'Imported $count guest items to your account. Guest files were kept locally as a backup.'
                    : 'No new guest items were imported',
              ),
            ),
          );
          context.read<SyncService>().triggerSync();
          break;
        case _GuestImportAction.deleteGuestFiles:
          await migrationService.deleteWorkspace(guestWorkspaceId);
          await authService.clearPendingGuestImportWorkspace();
          await authService.clearGuestWorkspaceId();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Deleted guest files')),
          );
          break;
        case _GuestImportAction.keep:
          await authService.clearPendingGuestImportWorkspace();
          break;
      }
    } finally {
      _isHandlingGuestImport = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final foldersProvider = context.watch<FoldersProvider>();
    final notesProvider = context.watch<NotesProvider>();
    final authService = context.watch<AuthService>();
    final parsedSearchQuery = SearchQuery.parse(_searchQuery);
    final isSearchActive = parsedSearchQuery.isActive;
    final isProfileTab = _selectedTab == HomeBottomBarTab.profile;
    final noteOpenSearchQuery = parsedSearchQuery.textTokens.isNotEmpty
        ? parsedSearchQuery.plainTextQuery
        : null;

    // Get current folder for title
    final currentFolder = _currentFolderId != null
        ? foldersProvider.getFolderById(_currentFolderId!)
        : null;

    // Get folders and notes for current view / global search mode.
    late final List<Folder> folders;
    late final List<Note> notes;
    late final bool showFolderResults;
    late final bool showFileResults;

    if (isSearchActive) {
      showFolderResults = parsedSearchQuery.includeFolders;
      showFileResults = parsedSearchQuery.includeFiles;
      folders = showFolderResults
          ? foldersProvider.searchFolders(parsedSearchQuery.plainTextQuery)
          : <Folder>[];
      notes = showFileResults
          ? notesProvider.searchNotesWithQuery(parsedSearchQuery)
          : <Note>[];
    } else {
      showFolderResults = true;
      showFileResults = true;
      folders = _currentFolderId == null
          ? foldersProvider.rootFolders
          : foldersProvider.getSubfolders(_currentFolderId!);
      notes = notesProvider.getNotesInFolder(_currentFolderId);
    }

    final folderStats = _buildFolderStats(
      allFolders: foldersProvider.folders,
      allNotes: notesProvider.notes,
    );

    return Scaffold(
      extendBody: true,
      // Custom app bar matching the design
      appBar: AppBar(
        // Show back button when in a folder
        leading: !isProfileTab && _currentFolderId != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios),
                onPressed: _navigateBack,
              )
            : null,
        title: Text(
          isProfileTab
              ? (authService.isGuestMode ? 'Sign In' : 'Profile')
              : isSearchActive
                  ? 'Search results'
                  : (currentFolder?.name ?? 'TypeSync'),
        ),
        actions: isProfileTab
            ? [
                IconButton(
                  icon: const Icon(Icons.schedule_outlined),
                  onPressed: () =>
                      AppRouter.navigateTo(context, AppRouter.timetable),
                  tooltip: 'Timetable',
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () =>
                      AppRouter.navigateTo(context, AppRouter.settings),
                ),
              ]
            : [
                // Sync status indicator
                const SyncStatusIndicator(),

                // View toggle
                IconButton(
                  icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
                  onPressed: () => setState(() => _isGridView = !_isGridView),
                  tooltip: _isGridView ? 'List view' : 'Grid view',
                ),

                IconButton(
                  icon: const Icon(Icons.schedule_outlined),
                  onPressed: () =>
                      AppRouter.navigateTo(context, AppRouter.timetable),
                  tooltip: 'Timetable',
                ),

                // Settings
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () =>
                      AppRouter.navigateTo(context, AppRouter.settings),
                ),
              ],
      ),

      body: isProfileTab
          ? const ProfileScreen(embedded: true)
          : _buildBody(
              folders,
              notes,
              foldersProvider,
              notesProvider,
              folderStats: folderStats,
              isSearchActive: isSearchActive,
              showFolderResults: showFolderResults,
              showFileResults: showFileResults,
              noteOpenSearchQuery: noteOpenSearchQuery,
            ),

      // Bottom navigation bar matching the design
      bottomNavigationBar: HomeBottomBar(
        currentFolderId: _currentFolderId,
        onAddTap: _showCreateOptions,
        selectedTab: _selectedTab,
        onFilesTap: () {
          if (_selectedTab == HomeBottomBarTab.files) {
            return;
          }
          setState(() {
            _selectedTab = HomeBottomBarTab.files;
          });
        },
        onProfileTap: () {
          if (_selectedTab == HomeBottomBarTab.profile) {
            return;
          }
          setState(() {
            _selectedTab = HomeBottomBarTab.profile;
          });
        },
      ),
    );
  }

  @override
  void dispose() {
    _authService?.removeListener(_handleAuthStateChanged);
    _repairAuditTimer?.cancel();
    _autoScrollTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _attachAuthListener() {
    final authService = context.read<AuthService>();
    if (identical(_authService, authService)) {
      return;
    }

    _authService?.removeListener(_handleAuthStateChanged);
    _authService = authService;
    _authService?.addListener(_handleAuthStateChanged);
    _diagnostics.info(
      'HomeScreen',
      'AUTH_FLOW attached auth listener workspace=${authService.storageUserId} cloudUser=${authService.userId}',
    );
  }

  void _handleAuthStateChanged() {
    if (!mounted) return;
    final isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? true;
    _diagnostics.info(
      'HomeScreen',
      'AUTH_FLOW home observed auth change routeCurrent=$isCurrentRoute workspace=${context.read<AuthService>().storageUserId} cloudUser=${context.read<AuthService>().userId}',
    );
    if (!isCurrentRoute) {
      _diagnostics.info(
        'HomeScreen',
        'AUTH_FLOW skipped hidden HomeScreen auth reaction',
      );
      return;
    }
    _initializeData();
  }

  bool get _useLongPressGridDrag {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  void _handleGridDragStarted() {
    _updateAutoScroll(0);
  }

  void _handleGridDragPositionChanged(Offset globalPosition) {
    final scrollContext = _scrollViewKey.currentContext;
    if (scrollContext == null || !_scrollController.hasClients) {
      return;
    }

    final renderBox = scrollContext.findRenderObject();
    if (renderBox is! RenderBox || !renderBox.hasSize) {
      return;
    }

    final localPosition = renderBox.globalToLocal(globalPosition);
    const edgeZone = 96.0;
    const maxDelta = 22.0;
    final height = renderBox.size.height;

    double nextDelta = 0;
    if (localPosition.dy < edgeZone) {
      final intensity =
          ((edgeZone - localPosition.dy) / edgeZone).clamp(0.0, 1.0);
      nextDelta = -maxDelta * intensity;
    } else if (localPosition.dy > height - edgeZone) {
      final intensity =
          ((localPosition.dy - (height - edgeZone)) / edgeZone).clamp(0.0, 1.0);
      nextDelta = maxDelta * intensity;
    }

    _updateAutoScroll(nextDelta);
  }

  void _handleGridDragEnded() {
    _updateAutoScroll(0);
  }

  Map<String, FolderVisualStats> _buildFolderStats({
    required List<Folder> allFolders,
    required List<Note> allNotes,
  }) {
    final notesByFolder = <String?, List<Note>>{};
    for (final note in allNotes) {
      notesByFolder.putIfAbsent(note.folderId, () => <Note>[]).add(note);
    }

    final childFoldersByParent = <String?, List<Folder>>{};
    for (final folder in allFolders) {
      childFoldersByParent
          .putIfAbsent(folder.parentId, () => <Folder>[])
          .add(folder);
    }

    final statsByFolder = <String, FolderVisualStats>{};

    FolderVisualStats computeStats(Folder folder) {
      final cached = statsByFolder[folder.id];
      if (cached != null) {
        return cached;
      }

      final directNotes = notesByFolder[folder.id] ?? const <Note>[];
      final childFolders = childFoldersByParent[folder.id] ?? const <Folder>[];
      final directFileCount = directNotes.length;
      final directSubfolderCount = childFolders.length;

      var recursiveFileCount = directFileCount;
      var totalBytes = 0;
      for (final note in directNotes) {
        totalBytes += _noteTotalBytes(note);
      }

      for (final child in childFolders) {
        final childStats = computeStats(child);
        recursiveFileCount += childStats.recursiveFileCount;
        totalBytes += childStats.totalBytes;
      }

      final stats = FolderVisualStats(
        recursiveFileCount: recursiveFileCount,
        directFileCount: directFileCount,
        directSubfolderCount: directSubfolderCount,
        totalBytes: totalBytes,
      );
      statsByFolder[folder.id] = stats;
      return stats;
    }

    for (final folder in allFolders) {
      computeStats(folder);
    }

    return statsByFolder;
  }

  int _noteTotalBytes(Note note) {
    var total = note.size;
    for (final attachment in note.attachments) {
      total += attachment.size;
    }
    return total;
  }

  void _updateAutoScroll(double delta) {
    _autoScrollDelta = delta;
    if (delta == 0) {
      _autoScrollTimer?.cancel();
      _autoScrollTimer = null;
      return;
    }

    _autoScrollTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_scrollController.hasClients) {
        return;
      }

      final position = _scrollController.position;
      final nextOffset = (_scrollController.offset + _autoScrollDelta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );

      if (nextOffset == _scrollController.offset) {
        _updateAutoScroll(0);
        return;
      }

      _scrollController.jumpTo(nextOffset);
    });
  }

  Widget _buildBody(
    List<Folder> folders,
    List<Note> notes,
    FoldersProvider foldersProvider,
    NotesProvider notesProvider, {
    required Map<String, FolderVisualStats> folderStats,
    required bool isSearchActive,
    required bool showFolderResults,
    required bool showFileResults,
    required String? noteOpenSearchQuery,
  }) {
    if (foldersProvider.isLoading || notesProvider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final hasVisibleItems = folders.isNotEmpty || notes.isNotEmpty;
    final bottomScrollPadding = homeBottomBarScrollPaddingFor(context);

    return DropTarget(
      onDragEntered: (details) {
        setState(() {
          _isDragging = true;
        });
      },
      onDragExited: (details) {
        setState(() {
          _isDragging = false;
        });
      },
      onDragDone: (details) {
        _handleDroppedFiles(details.files);
        setState(() {
          _isDragging = false;
        });
      },
      child: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _initializeData,
            child: CustomScrollView(
              key: _scrollViewKey,
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: _buildSearchBar(),
                ),

                if (_currentFolderId == null && !isSearchActive)
                  const SliverToBoxAdapter(
                    child: HomeUpcomingSection(),
                  ),

                // Breadcrumb navigation
                if (_currentFolderId != null && !isSearchActive)
                  SliverToBoxAdapter(
                    child: _buildBreadcrumb(foldersProvider),
                  ),

                // Folders section
                if (showFolderResults && folders.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        isSearchActive
                            ? 'Folders (${folders.length})'
                            : 'Folders',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: _isGridView
                        ? FolderGrid(
                            folders: folders,
                            folderStats: folderStats,
                            onFolderTap: (folderId) => _handleFolderTap(
                              folderId,
                              isSearchActive: isSearchActive,
                            ),
                            onFolderLongPress: _showFolderOptions,
                            onNoteDropped: _handleNoteDroppedOnFolder,
                            onFolderDropped: _handleFolderDroppedOnFolder,
                            useLongPressDrag: _useLongPressGridDrag,
                            onDragStarted: _handleGridDragStarted,
                            onDragPositionChanged:
                                _handleGridDragPositionChanged,
                            onDragEnded: _handleGridDragEnded,
                          )
                        : FolderList(
                            folders: folders,
                            folderStats: folderStats,
                            onFolderTap: (folderId) => _handleFolderTap(
                              folderId,
                              isSearchActive: isSearchActive,
                            ),
                            onFolderLongPress: _showFolderOptions,
                          ),
                  ),
                ],

                // Files section
                if (showFileResults && notes.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        isSearchActive ? 'Files (${notes.length})' : 'Files',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: _isGridView
                        ? FileGrid(
                            notes: notes,
                            onNoteTap: (noteId) => _openNote(
                              noteId,
                              searchQuery: noteOpenSearchQuery,
                            ),
                            onNoteLongPress: _showNoteOptions,
                            useLongPressDrag: _useLongPressGridDrag,
                            onDragStarted: _handleGridDragStarted,
                            onDragPositionChanged:
                                _handleGridDragPositionChanged,
                            onDragEnded: _handleGridDragEnded,
                          )
                        : FileList(
                            notes: notes,
                            onNoteTap: (noteId) => _openNote(
                              noteId,
                              searchQuery: noteOpenSearchQuery,
                            ),
                            onNoteLongPress: _showNoteOptions,
                          ),
                  ),
                ],

                if (!hasVisibleItems)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: bottomScrollPadding),
                      child: _buildEmptyState(isSearchActive: isSearchActive),
                    ),
                  ),

                if (hasVisibleItems)
                  SliverToBoxAdapter(
                    child: SizedBox(height: bottomScrollPadding),
                  ),
              ],
            ),
          ),
          // Drag overlay
          if (_isDragging)
            Container(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_upload,
                        size: 64,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Drop files here to import',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({required bool isSearchActive}) {
    final icon =
        isSearchActive ? Icons.search_off_outlined : Icons.folder_open_outlined;
    final title = isSearchActive
        ? 'No results found'
        : (_currentFolderId == null ? 'No notes yet' : 'This folder is empty');
    final subtitle = isSearchActive
        ? 'Try another keyword or filter like is:file / in:text'
        : 'Tap + to create a new note';

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final activeSuggestion = _activeSearchSuggestion();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          Focus(
            onKeyEvent: (_, event) => _handleSearchKeyEvent(event),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText:
                    'Search... (type in: / has: / is:, press Tab to accept)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Clear search',
                        onPressed: _clearSearchQuery,
                      ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface.withValues(
                      alpha: 0.9,
                    ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: _handleSearchChanged,
            ),
          ),
          if (_searchSuggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < _searchSuggestions.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(_searchSuggestions[i]),
                        selected: i == _selectedSearchSuggestionIndex,
                        onSelected: (_) => _applySearchSuggestion(
                          _searchSuggestions[i],
                        ),
                      ),
                    ),
                  if (activeSuggestion != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        'Tab',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  KeyEventResult _handleSearchKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent || _searchSuggestions.isEmpty) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.tab) {
      final suggestion = _activeSearchSuggestion();
      if (suggestion == null) return KeyEventResult.ignored;
      _applySearchSuggestion(suggestion);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedSearchSuggestionIndex =
            (_selectedSearchSuggestionIndex + 1) % _searchSuggestions.length;
      });
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedSearchSuggestionIndex =
            (_selectedSearchSuggestionIndex - 1 + _searchSuggestions.length) %
                _searchSuggestions.length;
      });
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _clearSearchQuery() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _searchSuggestions = const <String>[];
      _selectedSearchSuggestionIndex = 0;
    });
  }

  void _handleSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
      _searchSuggestions = _buildSearchSuggestions(value);
      _selectedSearchSuggestionIndex = 0;
    });
  }

  String? _activeSearchSuggestion() {
    if (_searchSuggestions.isEmpty) return null;
    final index = _selectedSearchSuggestionIndex.clamp(
      0,
      _searchSuggestions.length - 1,
    );
    return _searchSuggestions[index];
  }

  List<String> _buildSearchSuggestions(String query) {
    final token = _activeSearchToken(query);
    if (token == null || token.isEmpty) return const <String>[];

    final lowerToken = token.toLowerCase();

    if (lowerToken == 'in' || lowerToken == 'in:') {
      return _inSearchSuggestions;
    }
    if (lowerToken == 'has' || lowerToken == 'has:') {
      return _hasSearchSuggestions;
    }
    if (lowerToken == 'is' || lowerToken == 'is:') {
      return _isSearchSuggestions;
    }
    if (lowerToken.startsWith('in:')) {
      return _inSearchSuggestions
          .where((option) => option.startsWith(lowerToken))
          .toList();
    }
    if (lowerToken.startsWith('has:')) {
      return _hasSearchSuggestions
          .where((option) => option.startsWith(lowerToken))
          .toList();
    }
    if (lowerToken.startsWith('is:')) {
      return _isSearchSuggestions
          .where((option) => option.startsWith(lowerToken))
          .toList();
    }

    return const <String>[];
  }

  String? _activeSearchToken(String query) {
    if (query.isEmpty || query.endsWith(' ')) {
      return null;
    }

    final parts = query.split(RegExp(r'\s+'));
    if (parts.isEmpty) return null;
    return parts.last;
  }

  void _applySearchSuggestion(String suggestion) {
    final currentText = _searchController.text;
    final lastWhitespace = currentText.lastIndexOf(RegExp(r'\s'));
    final tokenStart = lastWhitespace >= 0 ? lastWhitespace + 1 : 0;
    final prefix = currentText.substring(0, tokenStart);
    final updatedText = '$prefix$suggestion ';

    _searchController.value = TextEditingValue(
      text: updatedText,
      selection: TextSelection.collapsed(offset: updatedText.length),
    );

    setState(() {
      _searchQuery = updatedText;
      _searchSuggestions = const <String>[];
      _selectedSearchSuggestionIndex = 0;
    });

    _searchFocusNode.requestFocus();
  }

  Widget _buildBreadcrumb(FoldersProvider foldersProvider) {
    final path = foldersProvider.getFolderPath(_currentFolderId);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            GestureDetector(
              onTap: () => _navigateToFolder(null),
              child: const Text(
                'Home',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            for (final folder in path) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.chevron_right, size: 16, color: Colors.grey),
              ),
              GestureDetector(
                onTap: () => _navigateToFolder(folder.id),
                child: Text(
                  folder.name,
                  style: TextStyle(
                    color: folder.id == _currentFolderId
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _navigateToFolder(String? folderId) {
    setState(() {
      _currentFolderId = folderId;
    });
  }

  void _handleFolderTap(
    String folderId, {
    required bool isSearchActive,
  }) {
    if (isSearchActive) {
      _clearSearchQuery();
      setState(() {
        _currentFolderId = folderId;
      });
      return;
    }

    _navigateToFolder(folderId);
  }

  void _navigateBack() {
    if (_currentFolderId != null) {
      final foldersProvider = context.read<FoldersProvider>();
      final currentFolder = foldersProvider.getFolderById(_currentFolderId!);
      setState(() {
        _currentFolderId = currentFolder?.parentId;
      });
    }
  }

  void _openNote(
    String noteId, {
    String? searchQuery,
  }) {
    FocusManager.instance.primaryFocus?.unfocus();
    _searchFocusNode.unfocus();

    final note = context.read<NotesProvider>().getNoteById(noteId);
    AppRouter.openEditor(
      context,
      noteId: noteId,
      folderId: note?.folderId ?? _currentFolderId,
      searchQuery: searchQuery,
    );
  }

  void _showCreateOptions() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.85;

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxSheetHeight),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Add',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.note_add),
                    title: const Text('Create File'),
                    subtitle: const Text('Create a new note/document'),
                    onTap: () {
                      Navigator.pop(context);
                      _createNewNote();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.folder),
                    title: const Text('Create Folder'),
                    subtitle: const Text('Create a new folder'),
                    onTap: () {
                      Navigator.pop(context);
                      _createNewFolder();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.upload_file),
                    title: const Text('Add Document from Storage'),
                    subtitle: const Text('Import a file from your device'),
                    onTap: () {
                      Navigator.pop(context);
                      _addDocumentFromStorage();
                    },
                  ),
                  const Divider(height: 24),
                  ListTile(
                    leading: const Icon(Icons.calendar_today),
                    title: const Text('Calendar'),
                    subtitle: const Text('Open reminders and events'),
                    onTap: () {
                      Navigator.pop(context);
                      AppRouter.navigateTo(context, AppRouter.calendar);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.checklist),
                    title: const Text('Homework'),
                    subtitle: const Text('Open assignments and tasks'),
                    onTap: () {
                      Navigator.pop(context);
                      AppRouter.navigateTo(context, AppRouter.homework);
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _createNewNote() async {
    final authService = context.read<AuthService>();
    final userId = authService.userId;
    if (userId == null) return;

    final storageService = context.read<StorageService>();
    if (storageService.isStorageFull) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Storage is full. Please upgrade to create notes.'),
          ),
        );
      }
      return;
    }

    final notesProvider = context.read<NotesProvider>();
    final note = await notesProvider.createNote(
      userId: userId,
      folderId: _currentFolderId,
    );

    if (note != null && mounted) {
      AppRouter.openEditor(
        context,
        noteId: note.id,
        folderId: _currentFolderId,
      );
    }
  }

  Future<void> _createNewFolder() async {
    final name = await _showTextInputDialog(
      title: 'New Folder',
      hint: 'Folder name',
    );

    if (name != null && name.isNotEmpty) {
      // FIX: Check mounted before using context
      if (!mounted) return;
      final authService = context.read<AuthService>();
      final userId = authService.userId;
      if (userId == null) return;

      final storageService = context.read<StorageService>();
      if (storageService.isStorageFull) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Storage is full. Please upgrade to create folders.'),
            ),
          );
        }
        return;
      }

      await context.read<FoldersProvider>().createFolder(
            userId: userId,
            name: name,
            parentId: _currentFolderId,
          );
    }
  }

  Future<void> _addDocumentFromStorage() async {
    final storageService = context.read<StorageService>();
    if (storageService.isStorageFull) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Storage is full. Please upgrade to add documents.'),
          ),
        );
      }
      return;
    }

    try {
      final pickedFile = await FilePickerHelper.pickPlatformFile(
        context: context,
        dialogTitle: 'Select Document',
      );

      if (pickedFile != null) {
        if (kIsWeb) {
          await _importBrowserFile(pickedFile);
          return;
        }

        final filePath = pickedFile.path;
        if (filePath == null || filePath.isEmpty) return;
        await _importFile(filePath, pickedFile.name);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import file: $e')),
        );
      }
    }
  }

  Future<void> _handleDroppedFiles(List<XFile> files) async {
    for (final file in files) {
      try {
        final filePath = file.path;
        final fileName = file.name;
        await _importFile(filePath, fileName);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to import ${file.name}: $e')),
          );
        }
      }
    }
  }

  Future<void> _importFile(String filePath, String fileName) async {
    final authService = context.read<AuthService>();
    final storageService = context.read<StorageService>();
    final userId = authService.userId;
    if (userId == null) return;

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('File not found: $fileName')),
          );
        }
        return;
      }

      final fileExtension = fileName.split('.').last.toLowerCase();
      String content = '';
      NoteType noteType = NoteType.text;

      // Read file content based on type
      if (_isTextImportExtension(fileExtension)) {
        // Text files - read content
        content = await file.readAsString();
        noteType = fileExtension == 'md' || fileExtension == 'markdown'
            ? NoteType.markdown
            : NoteType.text;
      } else if (fileExtension == 'pdf') {
        content = '';
        noteType = NoteType.pdf;
      } else {
        final note = await _createAttachmentBackedImportedNote(
          userId: userId,
          fileName: fileName,
          filePath: filePath,
        );
        if (note != null && mounted) {
          AppRouter.openEditor(
            context,
            noteId: note.id,
            folderId: _currentFolderId,
          );

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Imported $fileName')));
        }
        return;
      }

      if (!mounted) return;
      final notesProvider = context.read<NotesProvider>();
      final note = await notesProvider.createNote(
        userId: userId,
        folderId: _currentFolderId,
        title: fileName,
        content: content,
        type: noteType,
      );

      // Store cloud-backed PDF path so the note is readable on every device.
      if (noteType == NoteType.pdf && note != null) {
        final sanitizedName = _sanitizeFileName(fileName);
        final storedPath = await storageService.uploadFile(
          userId: userId,
          filePath: filePath,
          destinationPath: 'pdf_notes/${note.id}/$sanitizedName',
          contentType: 'application/pdf',
        );
        if (storedPath != null) {
          final updatedNote = note.copyWith(
            pdfPath: storedPath,
            size: await File(filePath).length(),
          );
          await notesProvider.updateNote(updatedNote);
        } else {
          await notesProvider.deleteNote(note.id);
          if (mounted) {
            final errorMessage = storageService.errorMessage;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text(errorMessage ?? 'Failed to import PDF: $fileName'),
              ),
            );
          }
          return;
        }
      }

      if (note != null && mounted) {
        // Open the note with the imported content
        AppRouter.openEditor(
          context,
          noteId: note.id,
          folderId: _currentFolderId,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported $fileName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import file: $e')),
        );
      }
    }
  }

  Future<void> _importBrowserFile(PlatformFile pickedFile) async {
    final authService = context.read<AuthService>();
    final storageService = context.read<StorageService>();
    final notesProvider = context.read<NotesProvider>();
    final userId = authService.userId;
    if (userId == null) return;

    final bytes = pickedFile.bytes;
    final fileName = pickedFile.name;
    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to read file bytes: $fileName')),
        );
      }
      return;
    }

    try {
      final fileExtension = fileName.split('.').last.toLowerCase();
      String content = '';
      NoteType noteType = NoteType.text;

      if (_isTextImportExtension(fileExtension)) {
        content = utf8.decode(bytes, allowMalformed: true);
        noteType = fileExtension == 'md' || fileExtension == 'markdown'
            ? NoteType.markdown
            : NoteType.text;
      } else if (fileExtension == 'pdf') {
        content = '';
        noteType = NoteType.pdf;
      } else {
        final note = await _createAttachmentBackedImportedNote(
          userId: userId,
          fileName: fileName,
          bytes: bytes,
        );
        if (note != null && mounted) {
          AppRouter.openEditor(
            context,
            noteId: note.id,
            folderId: _currentFolderId,
          );

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Imported $fileName')));
        }
        return;
      }

      final note = await notesProvider.createNote(
        userId: userId,
        folderId: _currentFolderId,
        title: fileName,
        content: content,
        type: noteType,
      );

      if (noteType == NoteType.pdf && note != null) {
        final sanitizedName = _sanitizeFileName(fileName);
        final storedPath = await storageService.uploadData(
          userId: userId,
          data: bytes,
          destinationPath: 'pdf_notes/${note.id}/$sanitizedName',
          contentType: 'application/pdf',
        );
        if (storedPath != null) {
          final updatedNote = note.copyWith(
            pdfPath: storedPath,
            size: bytes.length,
          );
          await notesProvider.updateNote(updatedNote);
        } else {
          await notesProvider.deleteNote(note.id);
          if (mounted) {
            final errorMessage = storageService.errorMessage;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text(errorMessage ?? 'Failed to import PDF: $fileName'),
              ),
            );
          }
          return;
        }
      }

      if (note != null && mounted) {
        AppRouter.openEditor(
          context,
          noteId: note.id,
          folderId: _currentFolderId,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported $fileName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import file: $e')),
        );
      }
    }
  }

  Future<Note?> _createAttachmentBackedImportedNote({
    required String userId,
    required String fileName,
    String? filePath,
    Uint8List? bytes,
  }) async {
    final notesProvider = context.read<NotesProvider>();
    final storageService = context.read<StorageService>();

    final note = await notesProvider.createNote(
      userId: userId,
      folderId: _currentFolderId,
      title: fileName,
      content: '',
      type: NoteType.text,
    );
    if (note == null) return null;

    final attachmentId = const Uuid().v4();
    final extension = _fileExtension(fileName);
    final mimeType = _mimeTypeForExtension(extension);
    final destinationPath =
        'attachments/${note.id}/${attachmentId}_${_sanitizeFileName(fileName)}';

    String? storedPath;
    int size;

    if (bytes != null) {
      storedPath = await storageService.uploadData(
        userId: userId,
        data: bytes,
        destinationPath: destinationPath,
        contentType: mimeType,
      );
      size = bytes.length;
    } else {
      if (filePath == null || filePath.isEmpty) {
        await notesProvider.deleteNote(note.id);
        return null;
      }
      final file = File(filePath);
      if (!await file.exists()) {
        await notesProvider.deleteNote(note.id);
        return null;
      }
      storedPath = await storageService.uploadFile(
        userId: userId,
        filePath: filePath,
        destinationPath: destinationPath,
        contentType: mimeType,
      );
      size = await file.length();
    }

    if (storedPath == null) {
      await notesProvider.deleteNote(note.id);
      if (mounted) {
        final errorMessage = storageService.errorMessage;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage ?? 'Failed to import attachment'),
          ),
        );
      }
      return null;
    }

    final updatedNote = note.copyWith(
      attachments: [
        ...note.attachments,
        NoteAttachment(
          id: attachmentId,
          name: fileName,
          path: storedPath,
          mimeType: mimeType,
          size: size,
          addedAt: DateTime.now(),
        ),
      ],
    );

    final success = await notesProvider.updateNote(updatedNote);
    if (!success) {
      await notesProvider.deleteNote(note.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import attachment: $fileName')),
        );
      }
      return null;
    }

    return updatedNote;
  }

  bool _isTextImportExtension(String fileExtension) {
    return fileExtension == 'txt' ||
        fileExtension == 'md' ||
        fileExtension == 'markdown';
  }

  String _fileExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == fileName.length - 1) {
      return '';
    }
    return fileName.substring(dotIndex).toLowerCase();
  }

  String? _mimeTypeForExtension(String extension) {
    switch (extension) {
      case '.pdf':
        return 'application/pdf';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.svg':
        return 'image/svg+xml';
      case '.bmp':
        return 'image/bmp';
      case '.ico':
        return 'image/x-icon';
      case '.tif':
      case '.tiff':
        return 'image/tiff';
      case '.txt':
        return 'text/plain';
      case '.md':
      case '.markdown':
        return 'text/markdown';
      case '.json':
        return 'application/json';
      case '.csv':
        return 'text/csv';
      case '.yaml':
      case '.yml':
        return 'application/yaml';
      case '.xml':
        return 'application/xml';
      case '.html':
      case '.htm':
        return 'text/html';
      case '.css':
        return 'text/css';
      case '.js':
        return 'text/javascript';
      case '.dart':
        return 'text/x-dart';
      case '.py':
        return 'text/x-python';
      default:
        return null;
    }
  }

  Future<String?> _showTextInputDialog({
    required String title,
    required String hint,
    String? initialValue,
  }) async {
    final controller = TextEditingController(text: initialValue);

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (value) {
            if (value.isNotEmpty) {
              Navigator.pop(context, value);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showFolderOptions(String folderId) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () async {
                Navigator.pop(context);
                final folder = this
                    .context
                    .read<FoldersProvider>()
                    .getFolderById(folderId);
                final newName = await _showTextInputDialog(
                  title: 'Rename Folder',
                  hint: 'New name',
                  initialValue: folder?.name,
                );
                if (newName != null && newName.isNotEmpty) {
                  if (!mounted) return;
                  await this
                      .context
                      .read<FoldersProvider>()
                      .renameFolder(folderId, newName);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Change color'),
              onTap: () {
                Navigator.pop(context);
                _showFolderColorPicker(folderId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Export folder'),
              onTap: () {
                Navigator.pop(context);
                _exportFolder(folderId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                this.context.read<FoldersProvider>().deleteFolder(folderId);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportFolder(String folderId) async {
    final foldersProvider = context.read<FoldersProvider>();
    final notesProvider = context.read<NotesProvider>();
    final folder = foldersProvider.getFolderById(folderId);
    if (folder == null) return;

    try {
      // Use file picker to choose export directory (with Linux fallback)
      final directory = await FilePickerHelper.pickDirectory(
        context: context,
        dialogTitle: 'Export folder to',
      );

      if (directory == null) return;

      final exportDir = Directory('$directory/${folder.name}');
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }

      // Export all notes in this folder
      final notes = notesProvider.getNotesInFolder(folderId);
      int exportedCount = 0;

      for (final note in notes) {
        try {
          final String fileName = note.title;
          String extension = '.txt';
          String content = '';

          if (note.type == NoteType.pdf && note.pdfPath != null) {
            final exported = await _writePdfToDestination(
              note.pdfPath!,
              '${exportDir.path}/$fileName.pdf',
            );
            if (exported) {
              exportedCount++;
            }
            continue;
          } else if (note.type == NoteType.markdown) {
            extension = '.md';
            content = note.content;
          } else {
            extension = '.txt';
            content = RichTextPlainTextService.extractPlainText(note.content);
          }

          final file = File('${exportDir.path}/$fileName$extension');
          await file.writeAsString(content);
          exportedCount++;
        } catch (e) {
          debugPrint('Failed to export note ${note.id}: $e');
        }
      }

      // Export subfolders recursively
      final subfolders = foldersProvider.getSubfolders(folderId);
      for (final subfolder in subfolders) {
        await _exportFolderRecursive(subfolder.id, exportDir.path);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported $exportedCount items from folder')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export folder: $e')),
        );
      }
    }
  }

  Future<void> _exportFolderRecursive(String folderId, String basePath) async {
    final foldersProvider = context.read<FoldersProvider>();
    final notesProvider = context.read<NotesProvider>();
    final folder = foldersProvider.getFolderById(folderId);
    if (folder == null) return;

    final folderDir = Directory('$basePath/${folder.name}');
    if (!await folderDir.exists()) {
      await folderDir.create(recursive: true);
    }

    // Export notes in this folder
    final notes = notesProvider.getNotesInFolder(folderId);
    for (final note in notes) {
      try {
        final String fileName = note.title;
        String extension = '.txt';
        String content = '';

        if (note.type == NoteType.pdf && note.pdfPath != null) {
          await _writePdfToDestination(
            note.pdfPath!,
            '${folderDir.path}/$fileName.pdf',
          );
          continue;
        } else if (note.type == NoteType.markdown) {
          extension = '.md';
          content = note.content;
        } else {
          extension = '.txt';
          content = RichTextPlainTextService.extractPlainText(note.content);
        }

        final file = File('${folderDir.path}/$fileName$extension');
        await file.writeAsString(content);
      } catch (e) {
        debugPrint('Failed to export note ${note.id}: $e');
      }
    }

    // Export subfolders
    final subfolders = foldersProvider.getSubfolders(folderId);
    for (final subfolder in subfolders) {
      await _exportFolderRecursive(subfolder.id, folderDir.path);
    }
  }

  void _showNoteOptions(String noteId) {
    final note = context.read<NotesProvider>().getNoteById(noteId);

    showModalBottomSheet(
      context: context,
      builder: (bottomSheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                note?.isFavorite == true ? Icons.star : Icons.star_outline,
              ),
              title: Text(
                note?.isFavorite == true
                    ? 'Remove from favorites'
                    : 'Add to favorites',
              ),
              onTap: () {
                Navigator.pop(bottomSheetContext);
                context.read<NotesProvider>().toggleFavorite(noteId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Set background color'),
              onTap: () async {
                Navigator.pop(bottomSheetContext);
                // Wait a bit for bottom sheet to close, then show dialog
                await Future.delayed(const Duration(milliseconds: 200));
                if (mounted) {
                  _showNoteColorPicker(noteId);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: const Text('Move to folder'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Show folder picker
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Export'),
              onTap: () {
                Navigator.pop(bottomSheetContext);
                _exportNote(noteId);
              },
            ),
            ListTile(
              leading: Icon(
                note?.localOnly == true
                    ? Icons.cloud_off_outlined
                    : Icons.cloud_done_outlined,
              ),
              title: Text(
                note?.localOnly == true
                    ? 'Stored locally only'
                    : 'Synced with cloud',
              ),
              onTap: () async {
                Navigator.pop(bottomSheetContext);
                final current =
                    context.read<NotesProvider>().getNoteById(noteId);
                if (current == null) return;
                await context.read<NotesProvider>().updateNote(
                      current.copyWith(localOnly: !current.localOnly),
                    );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                context.read<NotesProvider>().deleteNote(noteId);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportNote(String noteId) async {
    final note = context.read<NotesProvider>().getNoteById(noteId);
    if (note == null) return;

    try {
      final String fileName = note.title;
      String extension = '.txt';
      String content = '';

      if (note.type == NoteType.pdf && note.pdfPath != null) {
        if (!mounted) return;

        // Use file picker to choose export location (with Linux fallback)
        final savePath = await FilePickerHelper.saveFile(
          context: context,
          dialogTitle: 'Export PDF',
          fileName: '$fileName.pdf',
          fileExtension: 'pdf',
        );

        if (savePath != null) {
          final exported =
              await _writePdfToDestination(note.pdfPath!, savePath);
          if (mounted && exported) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('PDF exported successfully')),
            );
          } else if (mounted && !exported) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('PDF file not found')),
            );
          }
        }
        return;
      } else if (note.type == NoteType.markdown) {
        extension = '.md';
        content = note.content;
      } else {
        // Text note - export as plain text
        extension = '.txt';
        content = RichTextPlainTextService.extractPlainText(note.content);
      }

      // Use file picker to choose export location (with Linux fallback)
      final savePath = await FilePickerHelper.saveFile(
        context: context,
        dialogTitle: 'Export Note',
        fileName: '$fileName$extension',
        fileExtension: extension.substring(1),
      );

      if (savePath != null) {
        final file = File(savePath);
        await file.writeAsString(content);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Note exported successfully')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export: $e')),
        );
      }
    }
  }

  void _showNoteColorPicker(String noteId) {
    if (!mounted) return;

    final note = context.read<NotesProvider>().getNoteById(noteId);
    final currentColor = note?.backgroundColor;

    // Use root navigator to ensure dialog appears above bottom sheet
    showDialog(
      context: context,
      barrierDismissible: true,
      useRootNavigator: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Background Color'),
          content: SingleChildScrollView(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ColorOption(
                  color: Colors.transparent,
                  onTap: () =>
                      _setNoteBackgroundColor(noteId, null, dialogContext),
                  isSelected: currentColor == null,
                  label: 'None',
                ),
                ...AppColorPalette.noteBackgroundColors.map(
                  (colorOption) => _ColorOption(
                    color: colorOption.color,
                    onTap: () => _setNoteBackgroundColor(
                      noteId,
                      colorOption.hex,
                      dialogContext,
                    ),
                    isSelected: currentColor == colorOption.hex,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _showFolderColorPicker(String folderId) {
    if (!mounted) return;

    final folder = context.read<FoldersProvider>().getFolderById(folderId);
    final currentColor = folder?.backgroundColor;

    showDialog(
      context: context,
      barrierDismissible: true,
      useRootNavigator: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Folder Color'),
          content: SingleChildScrollView(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ColorOption(
                  color: Colors.transparent,
                  onTap: () =>
                      _setFolderBackgroundColor(folderId, null, dialogContext),
                  isSelected: currentColor == null || currentColor.isEmpty,
                  label: 'None',
                ),
                ...AppColorPalette.noteBackgroundColors.map(
                  (colorOption) => _ColorOption(
                    color: colorOption.color,
                    onTap: () => _setFolderBackgroundColor(
                      folderId,
                      colorOption.hex,
                      dialogContext,
                    ),
                    isSelected: currentColor == colorOption.hex,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _setFolderBackgroundColor(
    String folderId,
    String? color,
    BuildContext dialogContext,
  ) {
    Navigator.pop(dialogContext);
    context.read<FoldersProvider>().setFolderColor(folderId, color);
  }

  void _setNoteBackgroundColor(
    String noteId,
    String? color,
    BuildContext dialogContext,
  ) {
    Navigator.pop(dialogContext);
    context.read<NotesProvider>().setBackgroundColor(noteId, color);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            color == null ? 'Background color removed' : 'Background color set',
          ),
        ),
      );
    }
  }

  void _handleNoteDroppedOnFolder(String noteId, String folderId) {
    context.read<NotesProvider>().moveToFolder(noteId, folderId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note moved to folder')),
      );
    }
  }

  void _handleFolderDroppedOnFolder(String folderId, String? newParentId) {
    context.read<FoldersProvider>().moveFolder(folderId, newParentId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newParentId == null ? 'Folder moved to root' : 'Folder moved',
          ),
        ),
      );
    }
  }

  bool _isRemoteFilePath(String path) =>
      path.startsWith('http://') || path.startsWith('https://');

  Future<bool> _writePdfToDestination(
    String sourcePath,
    String destinationPath,
  ) async {
    try {
      if (_isRemoteFilePath(sourcePath)) {
        final response = await http.get(Uri.parse(sourcePath));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          return false;
        }
        await File(destinationPath).writeAsBytes(response.bodyBytes);
        return true;
      }

      final pdfFile = File(sourcePath);
      if (!await pdfFile.exists()) {
        return false;
      }

      await pdfFile.copy(destinationPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  String _sanitizeFileName(String value) {
    final buffer = StringBuffer();
    for (final codeUnit in value.codeUnits) {
      final isUpper = codeUnit >= 65 && codeUnit <= 90;
      final isLower = codeUnit >= 97 && codeUnit <= 122;
      final isDigit = codeUnit >= 48 && codeUnit <= 57;
      final isAllowed = isUpper ||
          isLower ||
          isDigit ||
          codeUnit == 46 ||
          codeUnit == 95 ||
          codeUnit == 45;
      buffer.writeCharCode(isAllowed ? codeUnit : 95);
    }
    return buffer.toString();
  }
}

enum _GuestImportAction {
  import,
  keep,
  deleteGuestFiles,
}

/// Color option widget for note background color picker
class _ColorOption extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;
  final bool isSelected;
  final String? label;

  const _ColorOption({
    required this.color,
    required this.onTap,
    this.isSelected = false,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
                width: isSelected ? 3 : 1,
              ),
            ),
            child: color == Colors.transparent
                ? const Icon(Icons.clear, size: 20)
                : null,
          ),
          if (label != null) ...[
            const SizedBox(height: 4),
            Text(
              label!,
              style: TextStyle(
                fontSize: 10,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
