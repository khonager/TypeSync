/// Editor Screen
/// 
/// Note editing screen with rich text support, line/character count,
/// and real-time sync. Based on the bottom-right design mockup.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/models/note.dart';
import '../../../core/providers/notes_provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/local_file_service.dart';
import '../../../core/utils/color_utils.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/editor_stats.dart';

/// Note editor with markdown-like rich text editing
/// 
/// Features:
/// - Rich text formatting (bold, italic, headers, lists)
/// - Line and character counter
/// - Real-time sync while typing
/// - PDF insert support
class EditorScreen extends StatefulWidget {
  final String? noteId;
  final String? folderId;

  const EditorScreen({
    super.key,
    this.noteId,
    this.folderId,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  // Quill editor controller
  late QuillController _quillController;
  
  // Focus node for the editor
  final FocusNode _focusNode = FocusNode();
  
  // Scroll controller
  final ScrollController _scrollController = ScrollController();
  
  // Current note being edited
  Note? _note;
  
  // Title controller
  final TextEditingController _titleController = TextEditingController();
  
  // Auto-save timer
  Timer? _saveTimer;
  
  // Stats
  int _characterCount = 0;
  int _lineCount = 0;
  
  // Loading state
  bool _isLoading = true;
  
  // Drag and drop state
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _initializeEditor();
  }

  Future<void> _initializeEditor() async {
    final notesProvider = context.read<NotesProvider>();
    
    if (widget.noteId != null) {
      // Load existing note
      _note = notesProvider.getNoteById(widget.noteId!);
      
      if (_note != null) {
        _titleController.text = _note!.title;
        
        // Parse content as Delta if it's JSON, otherwise treat as plain text
        try {
          if (_note!.content.isNotEmpty && _note!.content.startsWith('[')) {
            final jsonData = jsonDecode(_note!.content) as List<dynamic>;
            final document = Document.fromJson(jsonData);
            _quillController = QuillController(
              document: document,
              selection: const TextSelection.collapsed(offset: 0),
            );
          } else {
            // Plain text content
            final document = Document()..insert(0, _note!.content);
            _quillController = QuillController(
              document: document,
              selection: const TextSelection.collapsed(offset: 0),
            );
          }
        } catch (e) {
          // If parsing fails, create empty document with content as plain text
          final document = Document()..insert(0, _note!.content);
          _quillController = QuillController(
            document: document,
            selection: const TextSelection.collapsed(offset: 0),
          );
        }
        
        _characterCount = _note!.characterCount;
        _lineCount = _note!.lineCount;
      }
    }
    
    // Create new note if none exists
    if (_note == null) {
      _quillController = QuillController.basic();
      _titleController.text = 'No name';
      
      final authService = context.read<AuthService>();
      if (authService.userId != null) {
        _note = await notesProvider.createNote(
          userId: authService.userId!,
          folderId: widget.folderId,
        );
      }
    }
    
    // Listen for content changes
    _quillController.addListener(_onContentChanged);
    
    setState(() {
      _isLoading = false;
    });
    
    // Calculate initial stats
    _updateStats();
  }

  void _onContentChanged() {
    _updateStats();
    _scheduleSave();
  }

  void _updateStats() {
    final plainText = _quillController.document.toPlainText();
    setState(() {
      _characterCount = plainText.length;
      _lineCount = '\n'.allMatches(plainText).length + 1;
    });
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _saveNote);
  }

  Future<void> _saveNote() async {
    if (_note == null) return;
    
    final notesProvider = context.read<NotesProvider>();
    
    // Get content as JSON string
    final content = jsonEncode(_quillController.document.toDelta().toJson());
    
    await notesProvider.updateNoteContent(
      noteId: _note!.id,
      content: content,
      characterCount: _characterCount,
      lineCount: _lineCount,
    );
  }

  Future<void> _updateTitle(String title) async {
    if (_note == null) return;
    
    final notesProvider = context.read<NotesProvider>();
    await notesProvider.updateNote(_note!.copyWith(title: title));
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _quillController.removeListener(_onContentChanged);
    _quillController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final bgColor = _note?.backgroundColor != null
        ? Color(int.parse(_note!.backgroundColor!.replaceFirst('#', '0xFF')))
        : null;

    return Scaffold(
      backgroundColor: bgColor ?? Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: bgColor ?? Theme.of(context).appBarTheme.backgroundColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        title: Center(
          child: TextField(
            controller: _titleController,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Title',
              contentPadding: EdgeInsets.zero,
              filled: false,
            ),
            onChanged: _updateTitle,
          ),
        ),
        actions: [
          // Stats display (Lines/Char counter)
          EditorStats(
            lineCount: _lineCount,
            characterCount: _characterCount,
          ),
          // More options
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showMoreOptions,
          ),
        ],
      ),
      body: _note?.type == NoteType.pdf && _note?.pdfPath != null
          ? _buildPdfViewer()
          : DropTarget(
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
                clipBehavior: Clip.none,
                children: [
                  // Editor area
                  Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: bgColor ?? Theme.of(context).scaffoldBackgroundColor,
                    padding: const EdgeInsets.all(16),
                    child: QuillEditor(
                      controller: _quillController,
                      focusNode: _focusNode,
                      scrollController: _scrollController,
                    ),
                  ),
                  
                  // Floating toolbar
                  EditorToolbar(
                    controller: _quillController,
                    onInsertPdf: _insertPdf,
                  ),
            // Drag overlay
            if (_isDragging)
              Container(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
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
      ),
    );
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('Insert PDF'),
              onTap: () {
                Navigator.pop(context);
                _insertPdf();
              },
            ),
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: const Text('Add tags'),
              onTap: () {
                Navigator.pop(context);
                _showTagDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Background color'),
              onTap: () {
                Navigator.pop(context);
                _showColorPicker();
              },
            ),
            ListTile(
              leading: Icon(
                _note?.isFavorite == true ? Icons.star : Icons.star_outline,
                color: _note?.isFavorite == true ? Colors.amber : null,
              ),
              title: Text(
                _note?.isFavorite == true 
                    ? 'Remove from favorites' 
                    : 'Add to favorites',
              ),
              onTap: () {
                Navigator.pop(context);
                _toggleFavorite();
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Export'),
              onTap: () {
                Navigator.pop(context);
                _exportNote();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _insertPdf() async {
    try {
      final filePicker = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );
      
      if (filePicker != null && filePicker.files.single.path != null) {
        final filePath = filePicker.files.single.path!;
        final fileName = filePicker.files.single.name;
        
        // Copy PDF to app storage
        final authService = context.read<AuthService>();
        final userId = authService.userId;
        if (userId == null) return;
        
        await LocalFileService.instance.initialize(userId);
        final storedPath = await LocalFileService.instance.copyFileToStorage(
          filePath,
          fileName: fileName,
        );
        
        if (storedPath != null && _note != null) {
          // Update note to be a PDF type
          final notesProvider = context.read<NotesProvider>();
          final updatedNote = _note!.copyWith(
            type: NoteType.pdf,
            pdfPath: storedPath,
            title: fileName.replaceAll('.pdf', ''),
          );
          await notesProvider.updateNote(updatedNote);
          
          // Refresh the note
          setState(() {
            _note = updatedNote;
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('PDF imported: $fileName')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to import PDF')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error importing PDF: $e')),
        );
      }
    }
  }

  void _showTagDialog() {
    // TODO: Implement tag dialog
  }

  void _showColorPicker() {
    if (_note == null) return;
    
    final currentColor = _note?.backgroundColor;
    
    // Use Future.delayed to ensure bottom sheet is closed before showing dialog
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      
      showDialog(
        context: context,
        barrierDismissible: true,
        useRootNavigator: true,
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
                    onTap: () => _setNoteBackgroundColor(null, dialogContext),
                    isSelected: currentColor == null,
                    label: 'None',
                  ),
                  ...AppColorPalette.noteBackgroundColors.map((colorOption) => 
                    _ColorOption(
                      color: colorOption.color,
                      onTap: () => _setNoteBackgroundColor(colorOption.hex, dialogContext),
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
    });
  }

  void _setNoteBackgroundColor(String? color, BuildContext dialogContext) async {
    if (_note == null) return;
    
    Navigator.pop(dialogContext);
    await context.read<NotesProvider>().setBackgroundColor(_note!.id, color);
    
    // Refresh note from provider to ensure we have the latest state
    final updatedNote = context.read<NotesProvider>().getNoteById(_note!.id);
    if (updatedNote != null) {
      setState(() {
        _note = updatedNote;
      });
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(color == null 
              ? 'Background color removed' 
              : 'Background color set'),
        ),
      );
    }
  }

  void _toggleFavorite() {
    if (_note != null) {
      context.read<NotesProvider>().toggleFavorite(_note!.id);
      setState(() {
        _note = _note!.copyWith(isFavorite: !_note!.isFavorite);
      });
    }
  }

  Future<void> _exportNote() async {
    if (_note == null) return;
    
    try {
      // Determine export file name and extension
      String fileName = _note!.title;
      String extension = '.txt';
      String content = '';
      
      if (_note!.type == NoteType.pdf && _note!.pdfPath != null) {
        // Export PDF file
        final pdfFile = File(_note!.pdfPath!);
        if (!await pdfFile.exists()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('PDF file not found')),
            );
          }
          return;
        }
        
        // Use file picker to choose export location
        final savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Export PDF',
          fileName: '$fileName.pdf',
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );
        
        if (savePath != null) {
          await pdfFile.copy(savePath);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('PDF exported to $savePath')),
            );
          }
        }
        return;
      } else if (_note!.type == NoteType.markdown) {
        extension = '.md';
        content = _note!.content;
      } else {
        // Text note - export as plain text
        extension = '.txt';
        // Convert Quill Delta to plain text
        try {
          final jsonData = jsonDecode(_note!.content) as List<dynamic>;
          final document = Document.fromJson(jsonData);
          content = document.toPlainText();
        } catch (e) {
          // If not JSON, use content as-is
          content = _note!.content;
        }
      }
      
      // Use file picker to choose export location
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Note',
        fileName: '$fileName$extension',
        type: FileType.custom,
        allowedExtensions: [extension.substring(1)],
      );
      
      if (savePath != null) {
        final file = File(savePath);
        await file.writeAsString(content);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Note exported to $savePath')),
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

  Widget _buildPdfViewer() {
    if (_note?.pdfPath == null) {
      return const Center(
        child: Text('PDF file not found'),
      );
    }

    final pdfPath = _note!.pdfPath!;
    final pdfFile = File(pdfPath);
    
    return FutureBuilder<bool>(
      future: Future(() => pdfFile.existsSync()),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (!snapshot.hasData || !snapshot.data!) {
          return _buildPdfErrorView(pdfFile);
        }

        // Try to use Syncfusion PDF viewer, fallback to external viewer if it fails
        try {
          return SfPdfViewer.file(pdfFile);
        } catch (e) {
          debugPrint('PDF viewer error: $e');
          return _buildPdfErrorView(pdfFile);
        }
      },
    );
  }

  Widget _buildPdfErrorView(File pdfFile) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.picture_as_pdf, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'PDF Viewer',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            pdfFile.path,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              // Try to open PDF in external viewer
              final uri = Uri.file(pdfFile.absolute.path);
              try {
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else {
                  // Try using xdg-open on Linux
                  if (Platform.isLinux) {
                    await Process.run('xdg-open', [pdfFile.absolute.path]);
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Unable to open PDF in external viewer')),
                      );
                    }
                  }
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error opening PDF: $e')),
                  );
                }
              }
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open in external viewer'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDroppedFiles(List<XFile> files) async {
    for (final file in files) {
      try {
        final filePath = file.path;
        final fileName = file.name;
        final fileExtension = fileName.split('.').last.toLowerCase();
        
        // Read file content
        final fileData = File(filePath);
        if (!await fileData.exists()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('File not found: $fileName')),
            );
          }
          continue;
        }
        
        // Handle different file types
        if (fileExtension == 'txt' || fileExtension == 'md' || fileExtension == 'markdown') {
          // Text files - insert content into current note
          final content = await fileData.readAsString();
          final selection = _quillController.selection;
          final offset = selection.isCollapsed ? selection.start : selection.start;
          
          // Insert file content
          _quillController.document.insert(offset, '\n\n--- Imported from $fileName ---\n\n');
          _quillController.document.insert(offset + 35 + fileName.length, content);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Imported $fileName into note')),
            );
          }
        } else if (fileExtension == 'pdf') {
          // PDF files - import as PDF note
          final authService = context.read<AuthService>();
          final userId = authService.userId;
          if (userId == null) return;
          
          await LocalFileService.instance.initialize(userId);
          final storedPath = await LocalFileService.instance.copyFileToStorage(
            filePath,
            fileName: fileName,
          );
          
          if (storedPath != null) {
            // Create a new PDF note
            final notesProvider = context.read<NotesProvider>();
            final pdfNote = await notesProvider.createNote(
              userId: userId,
              folderId: _note?.folderId,
              title: fileName.replaceAll('.pdf', ''),
              content: '',
              type: NoteType.pdf,
            );
            
            if (pdfNote != null) {
              final updatedNote = pdfNote.copyWith(pdfPath: storedPath);
              await notesProvider.updateNote(updatedNote);
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('PDF imported: $fileName')),
                );
                // Optionally open the PDF note
                // AppRouter.openEditor(context, noteId: pdfNote.id);
              }
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to import PDF: $fileName')),
              );
            }
          }
        } else if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(fileExtension)) {
          // Image files - insert reference
          final selection = _quillController.selection;
          final offset = selection.isCollapsed ? selection.start : selection.start;
          _quillController.document.insert(offset, '\n\n[Image: $fileName]\n\n');
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Image reference added: $fileName')),
            );
          }
        } else {
          // Other files - insert reference
          final selection = _quillController.selection;
          final offset = selection.isCollapsed ? selection.start : selection.start;
          _quillController.document.insert(offset, '\n\n[File: $fileName]\n\n');
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('File reference added: $fileName')),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to import ${file.name}: $e')),
          );
        }
      }
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
                ? Icon(Icons.close, color: Colors.grey[700])
                : null,
          ),
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                label!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
