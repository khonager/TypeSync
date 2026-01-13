/// Home Screen
/// 
/// Main screen showing folders and files in a grid view.
/// Based on the design mockup with dark theme.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/folders_provider.dart';
import '../../../core/providers/notes_provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/routes/app_router.dart';
import '../widgets/folder_grid.dart';
import '../widgets/file_grid.dart';
import '../widgets/home_bottom_bar.dart';
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
  // Current folder being viewed (null = root)
  String? _currentFolderId;
  
  // View mode (grid or list)
  bool _isGridView = true;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    final authService = context.read<AuthService>();
    if (authService.userId != null) {
      // Initialize providers with user ID
      await context.read<NotesProvider>().initialize(authService.userId!);
      await context.read<FoldersProvider>().initialize(authService.userId!);
      
      // Start real-time sync
      final syncService = context.read<SyncService>();
      syncService.startListening(authService.userId!);
      
      // Connect providers to sync service
      context.read<NotesProvider>().setSyncService(syncService);
      context.read<FoldersProvider>().setSyncService(syncService);
      
      // Set up sync callbacks
      syncService.onNotesUpdated = (notes) {
        context.read<NotesProvider>().handleCloudUpdate(notes);
      };
      syncService.onFoldersUpdated = (folders) {
        context.read<FoldersProvider>().handleCloudUpdate(folders);
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final foldersProvider = context.watch<FoldersProvider>();
    final notesProvider = context.watch<NotesProvider>();
    
    // Get current folder for title
    final currentFolder = _currentFolderId != null 
        ? foldersProvider.getFolderById(_currentFolderId!)
        : null;
    
    // Get folders and notes for current view
    final folders = _currentFolderId == null
        ? foldersProvider.rootFolders
        : foldersProvider.getSubfolders(_currentFolderId!);
    final notes = notesProvider.getNotesInFolder(_currentFolderId);

    return Scaffold(
      // Custom app bar matching the design
      appBar: AppBar(
        // Show back button when in a folder
        leading: _currentFolderId != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios),
                onPressed: _navigateBack,
              )
            : null,
        title: Text(currentFolder?.name ?? 'TypeSync'),
        actions: [
          // Sync status indicator
          const SyncStatusIndicator(),
          
          // View toggle
          IconButton(
            icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
            onPressed: () => setState(() => _isGridView = !_isGridView),
            tooltip: _isGridView ? 'List view' : 'Grid view',
          ),
          
          // Settings
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => AppRouter.navigateTo(context, AppRouter.settings),
          ),
        ],
      ),
      
      body: _buildBody(folders, notes, foldersProvider, notesProvider),
      
      // Bottom navigation bar matching the design
      bottomNavigationBar: HomeBottomBar(
        currentFolderId: _currentFolderId,
        onNewNote: _createNewNote,
        onNewFolder: _createNewFolder,
      ),
      
      // FAB for quick note creation
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewNote,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(
    List folders,
    List notes,
    FoldersProvider foldersProvider,
    NotesProvider notesProvider,
  ) {
    if (foldersProvider.isLoading || notesProvider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (folders.isEmpty && notes.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _initializeData,
      child: CustomScrollView(
        slivers: [
          // Breadcrumb navigation
          if (_currentFolderId != null)
            SliverToBoxAdapter(
              child: _buildBreadcrumb(foldersProvider),
            ),
          
          // Folders section
          if (folders.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Folders',
                  style: TextStyle(
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
                      onFolderTap: _navigateToFolder,
                      onFolderLongPress: _showFolderOptions,
                    )
                  : FolderList(
                      folders: folders,
                      onFolderTap: _navigateToFolder,
                      onFolderLongPress: _showFolderOptions,
                    ),
            ),
          ],
          
          // Files section
          if (notes.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Files',
                  style: TextStyle(
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
                      onNoteTap: _openNote,
                      onNoteLongPress: _showNoteOptions,
                    )
                  : FileList(
                      notes: notes,
                      onNoteTap: _openNote,
                      onNoteLongPress: _showNoteOptions,
                    ),
            ),
          ],
          
          // Bottom padding
          const SliverToBoxAdapter(
            child: SizedBox(height: 100),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _currentFolderId == null 
                ? 'No notes yet' 
                : 'This folder is empty',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to create a new note',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
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

  void _navigateBack() {
    if (_currentFolderId != null) {
      final foldersProvider = context.read<FoldersProvider>();
      final currentFolder = foldersProvider.getFolderById(_currentFolderId!);
      setState(() {
        _currentFolderId = currentFolder?.parentId;
      });
    }
  }

  void _openNote(String noteId) {
    AppRouter.openEditor(context, noteId: noteId, folderId: _currentFolderId);
  }

  Future<void> _createNewNote() async {
    final authService = context.read<AuthService>();
    if (authService.userId == null) return;
    
    final notesProvider = context.read<NotesProvider>();
    final note = await notesProvider.createNote(
      userId: authService.userId!,
      folderId: _currentFolderId,
    );
    
    if (note != null && mounted) {
      AppRouter.openEditor(context, noteId: note.id, folderId: _currentFolderId);
    }
  }

  Future<void> _createNewFolder() async {
    final name = await _showTextInputDialog(
      title: 'New Folder',
      hint: 'Folder name',
    );
    
    if (name != null && name.isNotEmpty) {
      final authService = context.read<AuthService>();
      if (authService.userId == null) return;
      
      await context.read<FoldersProvider>().createFolder(
        userId: authService.userId!,
        name: name,
        parentId: _currentFolderId,
      );
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
                final folder = this.context.read<FoldersProvider>().getFolderById(folderId);
                final newName = await _showTextInputDialog(
                  title: 'Rename Folder',
                  hint: 'New name',
                  initialValue: folder?.name,
                );
                if (newName != null && newName.isNotEmpty) {
                  await this.context.read<FoldersProvider>().renameFolder(folderId, newName);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Change color'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Show color picker
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

  void _showNoteOptions(String noteId) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: const Text('Add to favorites'),
              onTap: () {
                Navigator.pop(context);
                this.context.read<NotesProvider>().toggleFavorite(noteId);
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
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                this.context.read<NotesProvider>().deleteNote(noteId);
              },
            ),
          ],
        ),
      ),
    );
  }
}

