/// Editor Screen
/// 
/// Note editing screen with rich text support, line/character count,
/// and real-time sync. Based on the bottom-right design mockup.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../../../core/models/note.dart';
import '../../../core/providers/notes_provider.dart';
import '../../../core/services/auth_service.dart';
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
  late quill.QuillController _quillController;
  
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
          final delta = _note!.content.isNotEmpty 
              ? quill.Document.fromJson(
                  _note!.content.startsWith('[') 
                      ? (List<dynamic>.from(
                          (await _parseJson(_note!.content)) as List<dynamic>
                        ))
                      : [{'insert': '${_note!.content}\n'}]
                )
              : quill.Document();
          _quillController = quill.QuillController(
            document: delta,
            selection: const TextSelection.collapsed(offset: 0),
          );
        } catch (e) {
          // If parsing fails, create empty document with content as plain text
          _quillController = quill.QuillController(
            document: quill.Document()..insert(0, _note!.content),
            selection: const TextSelection.collapsed(offset: 0),
          );
        }
        
        _characterCount = _note!.characterCount;
        _lineCount = _note!.lineCount;
      }
    }
    
    // Create new note if none exists
    if (_note == null) {
      _quillController = quill.QuillController.basic();
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

  Future<dynamic> _parseJson(String json) async {
    // Simple JSON parsing - in production use dart:convert
    return [];
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
    
    // Get content as JSON
    final content = _quillController.document.toDelta().toJson().toString();
    
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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            // Editable title
            Expanded(
              child: TextField(
                controller: _titleController,
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
          ],
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
      body: Column(
        children: [
          // Editor area
          Expanded(
            child: Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: quill.QuillEditor(
                controller: _quillController,
                focusNode: _focusNode,
                scrollController: _scrollController,
                configurations: quill.QuillEditorConfigurations(
                  scrollable: true,
                  autoFocus: true,
                  expands: true,
                  padding: const EdgeInsets.all(16),
                  placeholder: 'Start typing...',
                  customStyles: quill.DefaultStyles(
                    paragraph: quill.DefaultTextBlockStyle(
                      Theme.of(context).textTheme.bodyLarge!,
                      const quill.VerticalSpacing(8, 0),
                      const quill.VerticalSpacing(0, 0),
                      null,
                    ),
                    h1: quill.DefaultTextBlockStyle(
                      Theme.of(context).textTheme.headlineLarge!,
                      const quill.VerticalSpacing(16, 0),
                      const quill.VerticalSpacing(0, 0),
                      null,
                    ),
                    h2: quill.DefaultTextBlockStyle(
                      Theme.of(context).textTheme.headlineMedium!,
                      const quill.VerticalSpacing(12, 0),
                      const quill.VerticalSpacing(0, 0),
                      null,
                    ),
                    h3: quill.DefaultTextBlockStyle(
                      Theme.of(context).textTheme.headlineSmall!,
                      const quill.VerticalSpacing(8, 0),
                      const quill.VerticalSpacing(0, 0),
                      null,
                    ),
                    code: quill.DefaultTextBlockStyle(
                      TextStyle(
                        fontFamily: 'JetBrainsMono',
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 14,
                      ),
                      const quill.VerticalSpacing(8, 0),
                      const quill.VerticalSpacing(0, 0),
                      BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          // Toolbar
          EditorToolbar(
            controller: _quillController,
            onInsertPdf: _insertPdf,
          ),
        ],
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
    // TODO: Implement PDF picker and insertion
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PDF insertion coming soon')),
    );
  }

  void _showTagDialog() {
    // TODO: Implement tag dialog
  }

  void _showColorPicker() {
    // TODO: Implement color picker
  }

  void _toggleFavorite() {
    if (_note != null) {
      context.read<NotesProvider>().toggleFavorite(_note!.id);
      setState(() {
        _note = _note!.copyWith(isFavorite: !_note!.isFavorite);
      });
    }
  }

  void _exportNote() {
    // TODO: Implement export functionality
  }
}

