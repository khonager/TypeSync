library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/folder.dart';
import '../../../core/models/note.dart';
import '../../../core/providers/folders_provider.dart';
import '../../../core/providers/notes_provider.dart';
import '../../../core/providers/tags_provider.dart';
import '../../../core/routes/app_router.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/utils/search_query.dart';
import '../../../core/widgets/desktop_window_frame.dart';
import '../../home/widgets/file_grid.dart';
import '../../home/widgets/folder_grid.dart';
import '../../home/widgets/home_bottom_bar.dart';
import '../../profile/screens/profile_screen.dart';
import 'editor_screen.dart';

class SplitEditorScreen extends StatefulWidget {
  const SplitEditorScreen({
    required this.primaryNoteId,
    this.secondaryNoteId,
    this.initialSecondaryFolderId,
    super.key,
  });

  final String primaryNoteId;
  final String? secondaryNoteId;
  final String? initialSecondaryFolderId;

  @override
  State<SplitEditorScreen> createState() => _SplitEditorScreenState();
}

class _SplitEditorScreenState extends State<SplitEditorScreen>
    with SingleTickerProviderStateMixin {
  late String _primaryNoteId;
  String? _secondaryNoteId;
  final ValueNotifier<double> _primaryPaneFraction = ValueNotifier<double>(0.5);
  late final AnimationController _collapseController;
  Animation<double>? _collapseAnimation;
  bool _isClosingSplit = false;

  @override
  void initState() {
    super.initState();
    _primaryNoteId = widget.primaryNoteId;
    _secondaryNoteId = widget.secondaryNoteId;
    _collapseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _collapseController.dispose();
    _primaryPaneFraction.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notesProvider = context.watch<NotesProvider>();
    final primaryNote = notesProvider.getNoteById(_primaryNoteId);
    final secondaryNote = _secondaryNoteId == null
        ? null
        : notesProvider.getNoteById(_secondaryNoteId!);

    if (primaryNote == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Side by Side')),
        body: const Center(
          child: Text('The selected note is no longer available.'),
        ),
      );
    }

    final primaryPane = EditorScreen(
      key: ValueKey('split-primary-${primaryNote.id}'),
      noteId: primaryNote.id,
      embedded: true,
      onClose: () => _closeSplitClosing(closingPrimary: true),
      onSideBySideAction: () => _closeSplitClosing(closingPrimary: true),
      isSideBySideOpen: true,
    );

    final secondaryPane = secondaryNote == null
        ? _SecondaryBrowserPane(
            initialFolderId: widget.initialSecondaryFolderId,
            onNoteSelected: (noteId) {
              setState(() {
                _secondaryNoteId = noteId;
              });
            },
          )
        : EditorScreen(
            key: ValueKey(
              'split-secondary-${secondaryNote.id}-$_secondaryNoteId',
            ),
            noteId: secondaryNote.id,
            embedded: true,
            onClose: () => _closeSplitClosing(closingPrimary: false),
            onSideBySideAction: () => _closeSplitClosing(closingPrimary: false),
            isSideBySideOpen: true,
          );

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: desktopWindowDragArea(),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          tooltip: 'Back to home',
          onPressed: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
        ),
        title: const Text('Side by Side'),
        actions: withDesktopWindowControls([
          if (secondaryNote != null)
            IconButton(
              tooltip: 'Swap panes',
              onPressed: _isClosingSplit ? null : _swapPanes,
              icon: const Icon(Icons.swap_horiz),
            ),
          IconButton(
            tooltip:
                secondaryNote == null ? 'Show browser' : 'Close right note',
            onPressed: _isClosingSplit ? null : _showSecondaryBrowser,
            icon: const Icon(Icons.folder_copy_outlined),
          ),
        ]),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isStacked = constraints.maxWidth < 980;
          if (isStacked) {
            return Column(
              children: [
                Expanded(child: primaryPane),
                const Divider(height: 1),
                Expanded(child: secondaryPane),
              ],
            );
          }

          return ValueListenableBuilder<double>(
            valueListenable: _primaryPaneFraction,
            builder: (context, fraction, _) {
              const handleWidth = 18.0;
              final dividerWidth = _isClosingSplit ? 0.0 : handleWidth;
              final availableWidth =
                  (constraints.maxWidth - dividerWidth).clamp(
                0.0,
                double.infinity,
              );
              final primaryWidth = _isClosingSplit
                  ? (availableWidth * fraction).clamp(0.0, availableWidth)
                  : (availableWidth * fraction).clamp(
                      320.0,
                      availableWidth - 320.0,
                    );
              final secondaryWidth = availableWidth - primaryWidth;

              return Row(
                children: [
                  if (primaryWidth > 0)
                    SizedBox(
                      width: primaryWidth,
                      child: _TrackpadResizeRegion(
                        onDelta: (delta) =>
                            _updatePrimaryPaneFraction(availableWidth, delta),
                        child: primaryPane,
                      ),
                    ),
                  if (!_isClosingSplit)
                    _ResizeHandle(
                      onDrag: (delta) =>
                          _updatePrimaryPaneFraction(availableWidth, delta),
                    ),
                  if (secondaryWidth > 0)
                    SizedBox(
                      width: secondaryWidth,
                      child: _TrackpadResizeRegion(
                        onDelta: (delta) =>
                            _updatePrimaryPaneFraction(availableWidth, delta),
                        child: secondaryPane,
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _swapPanes() {
    if (_secondaryNoteId == null) return;
    setState(() {
      final currentPrimary = _primaryNoteId;
      _primaryNoteId = _secondaryNoteId!;
      _secondaryNoteId = currentPrimary;
    });
  }

  void _showSecondaryBrowser() {
    if (_secondaryNoteId == null) return;
    setState(() {
      _secondaryNoteId = null;
    });
  }

  void _closeSplitClosing({required bool closingPrimary}) {
    if (_isClosingSplit) return;
    final notesProvider = context.read<NotesProvider>();
    final primaryNote = notesProvider.getNoteById(_primaryNoteId);
    final secondaryNote = _secondaryNoteId == null
        ? null
        : notesProvider.getNoteById(_secondaryNoteId!);
    final resolvedNote = closingPrimary
        ? (secondaryNote ?? primaryNote)
        : (primaryNote ?? secondaryNote);
    if (resolvedNote == null) {
      Navigator.of(context).maybePop();
      return;
    }
    final targetFraction = closingPrimary ? 0.0 : 1.0;

    setState(() {
      _isClosingSplit = true;
    });

    _collapseAnimation?.removeListener(_handleCollapseTick);
    _collapseController.stop();
    _collapseController.reset();
    _collapseAnimation = Tween<double>(
      begin: _primaryPaneFraction.value,
      end: targetFraction,
    ).animate(
      CurvedAnimation(
        parent: _collapseController,
        curve: Curves.easeInOutCubic,
      ),
    )..addListener(_handleCollapseTick);

    _collapseController.forward().whenComplete(() {
      if (!mounted) return;
      _collapseAnimation?.removeListener(_handleCollapseTick);
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, __, ___) => EditorScreen(
            noteId: resolvedNote.id,
            folderId: resolvedNote.folderId,
          ),
        ),
      );
    });
  }

  void _handleCollapseTick() {
    final value = _collapseAnimation?.value;
    if (value == null) return;
    _primaryPaneFraction.value = value;
  }

  void _updatePrimaryPaneFraction(double availableWidth, double delta) {
    if (_isClosingSplit || availableWidth <= 0 || delta == 0) return;
    final nextWidth = (availableWidth * _primaryPaneFraction.value) + delta;
    _primaryPaneFraction.value = (nextWidth / availableWidth).clamp(0.28, 0.72);
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({
    required this.onDrag,
  });

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: SizedBox(
          width: 18,
          child: Center(
            child: Container(
              width: 4,
              height: 72,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackpadResizeRegion extends StatelessWidget {
  const _TrackpadResizeRegion({
    required this.onDelta,
    required this.child,
  });

  final ValueChanged<double> onDelta;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerPanZoomUpdate: (event) {
        final delta = event.panDelta;
        if (delta.dx == 0 || delta.dx.abs() < delta.dy.abs()) return;
        onDelta(delta.dx);
      },
      child: child,
    );
  }
}

class _SecondaryBrowserPane extends StatefulWidget {
  const _SecondaryBrowserPane({
    required this.onNoteSelected,
    this.initialFolderId,
  });

  final ValueChanged<String> onNoteSelected;
  final String? initialFolderId;

  @override
  State<_SecondaryBrowserPane> createState() => _SecondaryBrowserPaneState();
}

class _SecondaryBrowserPaneState extends State<_SecondaryBrowserPane> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _currentFolderId;
  bool _isGridView = true;
  HomeBottomBarTab _selectedTab = HomeBottomBarTab.files;

  @override
  void initState() {
    super.initState();
    _currentFolderId = widget.initialFolderId;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedTab == HomeBottomBarTab.profile) {
      return Scaffold(
        body: Column(
          children: [
            _buildTopBar(
              title: _profileTitle(context.read<AuthService>()),
              actions: [
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
                  tooltip: 'Settings',
                ),
              ],
            ),
            const Expanded(child: ProfileScreen(embedded: true)),
          ],
        ),
        bottomNavigationBar: HomeBottomBar(
          currentFolderId: _currentFolderId,
          onAddTap: _showCreateOptions,
          selectedTab: _selectedTab,
          onFilesTap: () {
            setState(() {
              _selectedTab = HomeBottomBarTab.files;
            });
          },
          onProfileTap: () {},
        ),
      );
    }

    final foldersProvider = context.watch<FoldersProvider>();
    final notesProvider = context.watch<NotesProvider>();
    final tagsProvider = context.watch<TagsProvider>();
    final parsedSearchQuery = SearchQuery.parse(_searchQuery);
    final isSearchActive = parsedSearchQuery.isActive;
    final currentFolder = _currentFolderId == null
        ? null
        : foldersProvider.getFolderById(_currentFolderId!);

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
          ? notesProvider
              .searchNotesWithQuery(
                parsedSearchQuery,
                tagNameResolver: (id) => tagsProvider.getTagById(id)?.name,
              )
              .toList()
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
    final noteLocationLabels = isSearchActive
        ? _buildNoteLocationLabels(
            notes: notes,
            foldersProvider: foldersProvider,
          )
        : const <String, String>{};
    final noteOpenSearchQuery = parsedSearchQuery.textTokens.isNotEmpty
        ? parsedSearchQuery.plainTextQuery
        : null;

    return Scaffold(
      body: Column(
        children: [
          _buildPaneHeader(
            currentFolderName: currentFolder?.name,
            isSearchActive: isSearchActive,
          ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
              ),
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildSearchBar()),
                  if (_currentFolderId != null && !isSearchActive)
                    SliverToBoxAdapter(
                      child: _buildBreadcrumb(foldersProvider),
                    ),
                  if (showFolderResults && folders.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: _SectionLabel(
                        label: isSearchActive
                            ? 'Folders (${folders.length})'
                            : 'Folders',
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: _isGridView
                          ? FolderGrid(
                              folders: folders,
                              folderStats: folderStats,
                              onFolderTap: (folderId) {
                                if (isSearchActive) {
                                  _clearSearchQuery();
                                }
                                setState(() {
                                  _currentFolderId = folderId;
                                });
                              },
                              onFolderLongPress: (_) {},
                            )
                          : FolderList(
                              folders: folders,
                              folderStats: folderStats,
                              onFolderTap: (folderId) {
                                if (isSearchActive) {
                                  _clearSearchQuery();
                                }
                                setState(() {
                                  _currentFolderId = folderId;
                                });
                              },
                              onFolderLongPress: (_) {},
                            ),
                    ),
                  ],
                  if (showFileResults && notes.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: _SectionLabel(
                        label: isSearchActive
                            ? 'Files (${notes.length})'
                            : 'Files',
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: _isGridView
                          ? FileGrid(
                              notes: notes,
                              noteLocationLabels: noteLocationLabels,
                              onNoteTap: (noteId) =>
                                  widget.onNoteSelected(noteId),
                              onNoteLongPress: (_) {},
                            )
                          : FileList(
                              notes: notes,
                              noteLocationLabels: noteLocationLabels,
                              onNoteTap: (noteId) =>
                                  widget.onNoteSelected(noteId),
                              onNoteLongPress: (_) {},
                            ),
                    ),
                  ],
                  if (folders.isEmpty && notes.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyBrowserState(isSearchActive: isSearchActive),
                    )
                  else
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 24),
                    ),
                  if (noteOpenSearchQuery != null)
                    const SliverToBoxAdapter(child: SizedBox.shrink()),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: HomeBottomBar(
        currentFolderId: _currentFolderId,
        onAddTap: _showCreateOptions,
        selectedTab: _selectedTab,
        onFilesTap: () {},
        onProfileTap: () {
          setState(() {
            _selectedTab = HomeBottomBarTab.profile;
          });
        },
      ),
    );
  }

  Widget _buildPaneHeader({
    required String? currentFolderName,
    required bool isSearchActive,
  }) {
    final title = isSearchActive
        ? 'Search results'
        : (currentFolderName ?? 'Browse notes');
    return _buildTopBar(
      title: title,
      leading: _currentFolderId != null && !isSearchActive
          ? IconButton(
              tooltip: 'Back to parent folder',
              onPressed: _navigateBack,
              icon: const Icon(Icons.arrow_back_ios),
            )
          : null,
      actions: [
        IconButton(
          tooltip: _isGridView ? 'List view' : 'Grid view',
          onPressed: () {
            setState(() {
              _isGridView = !_isGridView;
            });
          },
          icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
        ),
        IconButton(
          icon: const Icon(Icons.schedule_outlined),
          onPressed: () => AppRouter.navigateTo(context, AppRouter.timetable),
          tooltip: 'Timetable',
        ),
        IconButton(
          icon: const Icon(Icons.calendar_today_outlined),
          onPressed: () => AppRouter.navigateTo(context, AppRouter.calendar),
          tooltip: 'Calendar',
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => AppRouter.navigateTo(context, AppRouter.settings),
          tooltip: 'Settings',
        ),
      ],
    );
  }

  Widget _buildTopBar({
    required String title,
    Widget? leading,
    List<Widget> actions = const <Widget>[],
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).appBarTheme.backgroundColor,
        border: Border(
          bottom: BorderSide(
            color: colors.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          if (leading != null) leading,
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ...actions,
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText:
              'Search... (type in: / has: / is: / tag:, press Tab to accept)',
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
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
      ),
    );
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
              onTap: () {
                setState(() {
                  _currentFolderId = null;
                });
              },
              child: Text(
                'Files',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final folder in path) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.chevron_right, size: 16),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _currentFolderId = folder.id;
                  });
                },
                child: Text(
                  folder.name,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _navigateBack() {
    if (_currentFolderId == null) return;
    final foldersProvider = context.read<FoldersProvider>();
    final currentFolder = foldersProvider.getFolderById(_currentFolderId!);
    setState(() {
      _currentFolderId = currentFolder?.parentId;
    });
  }

  void _clearSearchQuery() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
    });
  }

  String _profileTitle(AuthService authService) {
    return authService.isGuestMode ? 'Sign In' : 'Profile';
  }

  void _showCreateOptions() {
    if (_selectedTab != HomeBottomBarTab.files) {
      setState(() {
        _selectedTab = HomeBottomBarTab.files;
      });
    }

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
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
            const SizedBox(height: 8),
          ],
        ),
      ),
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
    if (note == null || !mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onNoteSelected(note.id);
      }
    });
  }

  Future<void> _createNewFolder() async {
    final controller = TextEditingController();
    final folderName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Folder name',
          ),
          onSubmitted: (value) {
            Navigator.of(context).pop(value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (folderName == null || folderName.isEmpty || !mounted) {
      return;
    }

    final authService = context.read<AuthService>();
    final userId = authService.userId;
    if (userId == null) return;

    final folder = await context.read<FoldersProvider>().createFolder(
          userId: userId,
          name: folderName,
          parentId: _currentFolderId,
        );

    if (folder != null && mounted) {
      setState(() {
        _currentFolderId = folder.id;
      });
    }
  }

  Map<String, String> _buildNoteLocationLabels({
    required List<Note> notes,
    required FoldersProvider foldersProvider,
  }) {
    final labels = <String, String>{};

    for (final note in notes) {
      final path = foldersProvider.getFolderPath(note.folderId);
      if (path.isEmpty) {
        labels[note.id] = 'Files';
      } else {
        labels[note.id] = path.map((folder) => folder.name).join(' / ');
      }
    }

    return labels;
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
      if (cached != null) return cached;

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
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey,
        ),
      ),
    );
  }
}

class _EmptyBrowserState extends StatelessWidget {
  const _EmptyBrowserState({
    required this.isSearchActive,
  });

  final bool isSearchActive;

  @override
  Widget build(BuildContext context) {
    final icon =
        isSearchActive ? Icons.search_off_outlined : Icons.folder_open_outlined;
    final title = isSearchActive ? 'No matching notes' : 'Nothing here yet';
    final subtitle = isSearchActive
        ? 'Try a different search or browse your folders.'
        : 'Pick another folder or use search to open a note here.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
