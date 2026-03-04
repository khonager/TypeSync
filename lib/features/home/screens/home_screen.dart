/// Home Screen
///
/// Main screen showing folders and files in a grid view.
/// Based on the design mockup with dark theme.
library;

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../../core/models/folder.dart';
import '../../../core/models/note.dart';
import '../../../core/providers/calendar_provider.dart';
import '../../../core/providers/folders_provider.dart';
import '../../../core/providers/homework_provider.dart';
import '../../../core/providers/notes_provider.dart';
import '../../../core/providers/timetable_provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/local_file_service.dart';
import '../../../core/services/migration_service.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/services/theme_service.dart';
import '../../../core/routes/app_router.dart';
import '../../../core/utils/color_utils.dart';
import '../../../core/utils/file_picker_helper.dart';
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

  // Drag and drop state
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    // Defer initialization until after the first frame to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  Future<void> _initializeData() async {
    debugPrint('HomeScreen: _initializeData IS CALLED!');
    final authService = context.read<AuthService>();
    final userId = authService.userId;

    // Use 'guest' ID if not logged in (Guest Mode)
    final effectiveUserId = userId ?? 'guest';

    // Initialize local file service
    await LocalFileService.instance.initialize(effectiveUserId);

    if (!mounted) return;

    // Initialize providers with user ID
    // Note: Guests use 'guest' as ID, so their data is stored in 'notes_guest' box
    await context.read<NotesProvider>().initialize(effectiveUserId);
    if (!mounted) return;
    await context.read<FoldersProvider>().initialize(effectiveUserId);
    if (!mounted) return;

    // Sync the sync service with auth preferences
    final syncService = context.read<SyncService>();
    syncService.setSyncEnabled(authService.syncEnabled);

    // Only start sync if user is logged in (not guest) and sync is enabled
    // We check actual userId (not effective) to determine if we can sync
    if (userId != null && authService.isLoggedIn && authService.syncEnabled) {
      syncService.startListening(userId);

      // Connect providers to sync service
      context.read<NotesProvider>().setSyncService(syncService);
      context.read<FoldersProvider>().setSyncService(syncService);
      context.read<CalendarProvider>().setSyncService(syncService);
      context.read<HomeworkProvider>().setSyncService(syncService);
      context.read<TimetableProvider>().setSyncService(syncService);
      context.read<ThemeService>().setSyncService(syncService);

      // Set up sync callbacks
      syncService.onNotesUpdated = (notes) {
        context.read<NotesProvider>().handleCloudUpdate(notes);
      };
      syncService.onFoldersUpdated = (folders) {
        context.read<FoldersProvider>().handleCloudUpdate(folders);
      };
      syncService.onCalendarUpdated = (events) {
        context.read<CalendarProvider>().handleCloudUpdate(events);
      };
      syncService.onHomeworkUpdated = (tasks) {
        context.read<HomeworkProvider>().handleCloudUpdate(tasks);
      };
      syncService.onTimetableUpdated = (entries) {
        context.read<TimetableProvider>().handleCloudUpdate(entries);
      };
      syncService.onSettingsUpdated = (settings) {
        context.read<ThemeService>().handleCloudSettings(settings);
      };

      // Check for data migration (Guest/Local -> User)
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _checkDataMigration(userId);
        });
      }
    } else {
      // For guests or when sync is disabled, don't set up sync service
      context.read<NotesProvider>().setSyncService(null);
      context.read<FoldersProvider>().setSyncService(null);
      context.read<CalendarProvider>().setSyncService(null);
      context.read<HomeworkProvider>().setSyncService(null);
      context.read<TimetableProvider>().setSyncService(null);
      context.read<ThemeService>().setSyncService(null);
    }
  }

  Future<void> _checkDataMigration(String userId) async {
    final notesProvider = context.read<NotesProvider>();
    final foldersProvider = context.read<FoldersProvider>();
    final migrationService = MigrationService();

    if (migrationService.needsMigration(
      currentUserId: userId,
      notesProvider: notesProvider,
    )) {
      // Ask user to migrate
      final shouldMigrate = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Sync Local Notes?'),
          content: const Text(
            'We found notes created locally. Do you want to add them to your account account?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true), // Yes, migrate
              child: const Text('Merge'),
            ),
          ],
        ),
      );

      if (shouldMigrate == true && mounted) {
        final count = await migrationService.migrateData(
          newUserId: userId,
          notesProvider: notesProvider,
          foldersProvider: foldersProvider,
          keepLocal: false,
        );

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Migrated $count items to your account')),
        );

        // Trigger sync immediately
        context.read<SyncService>().triggerSync();
      }
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
    final folders = (_currentFolderId == null
            ? foldersProvider.rootFolders
            : foldersProvider.getSubfolders(_currentFolderId!))
        .cast<Folder>();
    final notes = notesProvider.getNotesInFolder(_currentFolderId).cast<Note>();

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
        onNewNote: _showCreateOptions,
        onNewFolder: _showCreateOptions,
      ),

      // FAB for quick note creation
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateOptions,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(
    List<Folder> folders,
    List<Note> notes,
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
                            onNoteDropped: _handleNoteDroppedOnFolder,
                            onFolderDropped: _handleFolderDroppedOnFolder,
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _currentFolderId == null ? 'No notes yet' : 'This folder is empty',
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

  void _showCreateOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
          ],
        ),
      ),
    );
  }

  Future<void> _createNewNote() async {
    final authService = context.read<AuthService>();
    final userId = authService.userId;
    if (userId == null) return;

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

      await context.read<FoldersProvider>().createFolder(
            userId: userId,
            name: name,
            parentId: _currentFolderId,
          );
    }
  }

  Future<void> _addDocumentFromStorage() async {
    try {
      final filePath = await FilePickerHelper.pickFile(
        context: context,
        dialogTitle: 'Select Document',
      );

      if (filePath != null) {
        final file = File(filePath);
        final fileName = file.path.split(Platform.pathSeparator).last;
        await _importFile(filePath, fileName);
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
      String noteType = 'text';

      // Read file content based on type
      if (fileExtension == 'txt' ||
          fileExtension == 'md' ||
          fileExtension == 'markdown') {
        // Text files - read content
        content = await file.readAsString();
        noteType = fileExtension == 'md' || fileExtension == 'markdown'
            ? 'markdown'
            : 'text';
      } else if (fileExtension == 'pdf') {
        // PDF files - copy to app storage and create PDF note
        final storedPath = await LocalFileService.instance.copyFileToStorage(
          filePath,
          fileName: fileName,
        );

        if (storedPath != null) {
          content = ''; // Empty content for PDFs
          noteType = 'pdf';
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to import PDF: $fileName')),
            );
          }
          return;
        }
      } else if (['jpg', 'jpeg', 'png', 'gif', 'webp']
          .contains(fileExtension)) {
        // Image files - create note with image reference
        content = '[Image file: $fileName]';
        noteType = 'text';
      } else {
        // Other files - create note with file reference
        content = '[File: $fileName]';
        noteType = 'text';
      }

      if (!mounted) return;
      final notesProvider = context.read<NotesProvider>();
      final note = await notesProvider.createNote(
        userId: userId,
        folderId: _currentFolderId,
        title: fileName,
        content: content,
        type: noteType == 'pdf'
            ? NoteType.pdf
            : (noteType == 'markdown' ? NoteType.markdown : NoteType.text),
      );

      // Store PDF path if it's a PDF (use stored path, not original)
      if (noteType == 'pdf' && note != null) {
        final storedPath = await LocalFileService.instance.copyFileToStorage(
          filePath,
          fileName: fileName,
        );
        if (storedPath != null) {
          final updatedNote = note.copyWith(pdfPath: storedPath);
          await notesProvider.updateNote(updatedNote);
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
                // TODO: Show color picker
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
            final pdfFile = File(note.pdfPath!);
            if (await pdfFile.exists()) {
              await pdfFile.copy('${exportDir.path}/$fileName.pdf');
              exportedCount++;
            }
            continue;
          } else if (note.type == NoteType.markdown) {
            extension = '.md';
            content = note.content;
          } else {
            extension = '.txt';
            try {
              final jsonData = jsonDecode(note.content) as List<dynamic>;
              final document = Document.fromJson(jsonData);
              content = document.toPlainText();
            } catch (e) {
              content = note.content;
            }
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
          final pdfFile = File(note.pdfPath!);
          if (await pdfFile.exists()) {
            await pdfFile.copy('${folderDir.path}/$fileName.pdf');
          }
          continue;
        } else if (note.type == NoteType.markdown) {
          extension = '.md';
          content = note.content;
        } else {
          extension = '.txt';
          try {
            final jsonData = jsonDecode(note.content) as List<dynamic>;
            final document = Document.fromJson(jsonData);
            content = document.toPlainText();
          } catch (e) {
            content = note.content;
          }
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
        // Export PDF file
        final pdfFile = File(note.pdfPath!);
        if (!await pdfFile.exists()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('PDF file not found')),
            );
          }
          return;
        }

        if (!mounted) return;

        // Use file picker to choose export location (with Linux fallback)
        final savePath = await FilePickerHelper.saveFile(
          context: context,
          dialogTitle: 'Export PDF',
          fileName: '$fileName.pdf',
          fileExtension: 'pdf',
        );

        if (savePath != null) {
          await pdfFile.copy(savePath);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('PDF exported successfully')),
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
        // Convert Quill Delta to plain text
        try {
          final jsonData = jsonDecode(note.content) as List<dynamic>;
          final document = Document.fromJson(jsonData);
          content = document.toPlainText();
        } catch (e) {
          // If not JSON, use content as-is
          content = note.content;
        }
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
