/// Editor Screen
///
/// Note editing screen with rich text support, line/character count,
/// and real-time sync. Based on the bottom-right design mockup.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';

import '../../../core/utils/web_download_stub.dart'
    if (dart.library.html) '../../../core/utils/web_download_web.dart'
    as web_download;

import '../../../core/models/note.dart';
import '../../../core/providers/notes_provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/local_file_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/utils/color_utils.dart';
import '../../../core/utils/file_picker_helper.dart';
import '../../../core/widgets/pdf_viewer_widget.dart';
import '../../home/widgets/sync_status_indicator.dart';
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

  // Title controller
  final TextEditingController _titleController = TextEditingController();

  // Last saved content to prevent unnecessary reloads from provider
  String? _lastSavedContent;

  // Current note being edited
  Note? _note;

  // Auto-save timer
  Timer? _saveTimer;

  // Stats
  int _characterCount = 0;
  int _lineCount = 0;

  // Loading state
  bool _isLoading = true;

  // Drag and drop state
  bool _isDragging = false;
  bool _isUpdatingFromExternal = false;
  String? _activeAttachmentId;
  bool _sideBySideAttachments = false;

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
    if (_isUpdatingFromExternal) return;
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
    if (_note?.hasConflict == true) return; // Don't auto-save during a conflict
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 200), _saveNote);
  }

  Future<void> _saveNote() async {
    if (_note == null || _note!.hasConflict) return;

    final notesProvider = context.read<NotesProvider>();

    // Get content as JSON string
    final content = jsonEncode(_quillController.document.toDelta().toJson());
    _lastSavedContent = content;

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
    return _buildEditor(context);
  }

  Widget _buildEditor(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    // React to external changes from provider
    final notesProvider = context.watch<NotesProvider>();
    final providerNote = widget.noteId != null
        ? notesProvider.getNoteById(widget.noteId!)
        : (_note != null ? notesProvider.getNoteById(_note!.id) : null);

    if (providerNote != null && _note != null) {
      if (providerNote.updatedAt.isAfter(_note!.updatedAt) ||
          providerNote.isDirty != _note!.isDirty ||
          providerNote.hasConflict != _note!.hasConflict) {
        final providerContent = providerNote.content;
        final localContent =
            jsonEncode(_quillController.document.toDelta().toJson());

        // We only reload Quill if the content actually differs from what we currently have
        // AND it wasn't a change we just pushed ourselves.
        if (providerContent != localContent &&
            providerContent != _lastSavedContent) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _updateContentFromProvider(providerNote);
          });
        } else {
          // Content matches or is our own save. Just sync metadata silently.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _note = providerNote;
                _lastSavedContent = providerContent;
              });
            }
          });
        }
      }
    }

    final bgColor = _note?.backgroundColor != null
        ? Color(int.parse(_note!.backgroundColor!.replaceFirst('#', '0xFF')))
        : null;

    return Scaffold(
      backgroundColor: bgColor ?? Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor:
            bgColor ?? Theme.of(context).appBarTheme.backgroundColor,
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
          // Sync status indicator
          const SyncStatusIndicator(),
          // More options
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showMoreOptions,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_note?.hasConflict == true) _buildConflictBanner(),
          Expanded(
            child: DropTarget(
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
                  _buildEditorWithAttachments(bgColor),
                  EditorToolbar(
                    controller: _quillController,
                    onInsertPdf: _insertPdf,
                  ),
                  if (_isDragging)
                    Container(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.2),
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
                                'Drop files here to attach',
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
          ),
        ],
      ),
    );
  }

  Widget _buildConflictBanner() {
    return Container(
      width: double.infinity,
      color: Colors.red.shade800,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Conflicting changes detected!',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            onPressed: _showConflictDialog,
            style: TextButton.styleFrom(
              foregroundColor: Colors.red.shade800,
              backgroundColor: Colors.white,
            ),
            child: const Text('RESOLVE'),
          ),
        ],
      ),
    );
  }

  List<NoteAttachment> _effectiveAttachments() {
    if (_note == null) return const <NoteAttachment>[];

    final attachments = List<NoteAttachment>.from(_note!.attachments);
    if (_note!.pdfPath != null &&
        _note!.pdfPath!.isNotEmpty &&
        !attachments.any((attachment) => attachment.path == _note!.pdfPath)) {
      attachments.insert(
        0,
        NoteAttachment(
          id: 'legacy-pdf-${_note!.id}',
          name: '${_note!.title}.pdf',
          path: _note!.pdfPath!,
          mimeType: 'application/pdf',
          size: _note!.size,
          addedAt: _note!.updatedAt,
        ),
      );
    }

    return attachments;
  }

  NoteAttachment? _activeAttachment(List<NoteAttachment> attachments) {
    if (attachments.isEmpty) return null;
    if (_activeAttachmentId == null) return attachments.first;

    for (final attachment in attachments) {
      if (attachment.id == _activeAttachmentId) {
        return attachment;
      }
    }
    return attachments.first;
  }

  bool _isDesktopLayout() {
    if (kIsWeb) return true;
    return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  }

  Widget _buildEditorWithAttachments(Color? bgColor) {
    final attachments = _effectiveAttachments();
    final activeAttachment = _activeAttachment(attachments);
    final isDesktop = _isDesktopLayout();
    final canSideBySide =
        isDesktop && MediaQuery.of(context).size.width >= 1100;
    final showSideBySide =
        canSideBySide && _sideBySideAttachments && activeAttachment != null;

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: bgColor ?? Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildAttachmentsSection(
              attachments, activeAttachment, canSideBySide),
          const SizedBox(height: 12),
          Expanded(
            child: showSideBySide
                ? Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: _buildAttachmentPreview(activeAttachment),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 6,
                        child: _buildEditorSurface(bgColor),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      if (activeAttachment != null)
                        Container(
                          height: 260,
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            child: _buildAttachmentPreview(activeAttachment),
                          ),
                        ),
                      Expanded(child: _buildEditorSurface(bgColor)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorSurface(Color? bgColor) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: bgColor ?? Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: QuillEditor(
        controller: _quillController,
        focusNode: _focusNode,
        scrollController: _scrollController,
      ),
    );
  }

  Widget _buildAttachmentsSection(
    List<NoteAttachment> attachments,
    NoteAttachment? activeAttachment,
    bool canSideBySide,
  ) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.attach_file),
                const SizedBox(width: 8),
                Text(
                  'Attachments (${attachments.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                if (canSideBySide)
                  IconButton(
                    tooltip: _sideBySideAttachments
                        ? 'Switch to stacked view'
                        : 'Switch to side-by-side view',
                    onPressed: () {
                      setState(() {
                        _sideBySideAttachments = !_sideBySideAttachments;
                      });
                    },
                    icon: Icon(
                      _sideBySideAttachments
                          ? Icons.splitscreen
                          : Icons.view_agenda,
                    ),
                  ),
                TextButton.icon(
                  onPressed: _insertPdf,
                  icon: const Icon(Icons.add),
                  label: const Text('Attach'),
                ),
              ],
            ),
            if (attachments.isNotEmpty) const SizedBox(height: 8),
            if (attachments.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: attachments
                    .map(
                      (attachment) => ChoiceChip(
                        selected: activeAttachment?.id == attachment.id,
                        label: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: Text(
                            attachment.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        onSelected: (selected) {
                          setState(() {
                            _activeAttachmentId =
                                selected ? attachment.id : null;
                          });
                        },
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentPreview(NoteAttachment attachment) {
    final extension = p.extension(attachment.name).toLowerCase();
    if (attachment.path.startsWith('data:')) {
      final separatorIndex = attachment.path.indexOf(',');
      if (separatorIndex <= 0) {
        return _buildAttachmentUnavailable(attachment);
      }
      final bytes = base64Decode(attachment.path.substring(separatorIndex + 1));

      if (extension == '.pdf') {
        return PdfPreview(
          build: (_) => bytes,
          allowPrinting: true,
          allowSharing: true,
          canChangeOrientation: false,
          canChangePageFormat: false,
          canDebug: false,
        );
      }

      if (['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp']
          .contains(extension)) {
        return Container(
          color: Colors.black12,
          child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
        );
      }

      if (['.txt', '.md', '.markdown', '.json', '.yaml', '.yml', '.csv', '.log']
          .contains(extension)) {
        final text = utf8.decode(bytes, allowMalformed: true);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        );
      }

      return _buildAttachmentInfo(attachment);
    }

    final file = File(attachment.path);

    if (!file.existsSync()) {
      return _buildAttachmentUnavailable(attachment);
    }

    if (extension == '.pdf') {
      return PdfViewerWidget(pdfFile: file);
    }

    if (['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp']
        .contains(extension)) {
      return Container(
        color: Colors.black12,
        child: Center(child: Image.file(file, fit: BoxFit.contain)),
      );
    }

    if (['.txt', '.md', '.markdown', '.json', '.yaml', '.yml', '.csv', '.log']
        .contains(extension)) {
      return FutureBuilder<String>(
        future: file.readAsString(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData) {
            return _buildAttachmentUnavailable(attachment);
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Text(snapshot.data!,
                style: Theme.of(context).textTheme.bodyMedium),
          );
        },
      );
    }

    return _buildAttachmentInfo(attachment);
  }

  Widget _buildAttachmentUnavailable(NoteAttachment attachment) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 40),
            const SizedBox(height: 8),
            Text('Attachment unavailable: ${attachment.name}'),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentInfo(NoteAttachment attachment) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file_outlined, size: 52),
            const SizedBox(height: 12),
            Text(attachment.name, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              '${(attachment.size / 1024).toStringAsFixed(1)} KB',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _openAttachmentExternally(attachment),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open externally'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAttachmentExternally(NoteAttachment attachment) async {
    try {
      if (attachment.path.startsWith('data:')) {
        final uri = Uri.parse(attachment.path);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        return;
      }

      final file = File(attachment.path);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('File not found: ${attachment.name}')),
          );
        }
        return;
      }

      final uri = Uri.file(file.absolute.path);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }

      if (Platform.isLinux) {
        await Process.run('xdg-open', [file.absolute.path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [file.absolute.path]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', file.absolute.path]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to open file: $e')),
        );
      }
    }
  }

  void _showConflictDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Resolve Conflict'),
        content: const Text(
          'This note was modified on another device at the same time. '
          'How would you like to resolve this?\n\n'
          '• Keep Local: Retain your current changes and overwrite the cloud.\n'
          '• Keep Cloud: Discard your current changes and load the cloud version.\n'
          '• Merge: Append the cloud version to the bottom of your local version.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<NotesProvider>().resolveConflict(_note!.id, 'local');
            },
            child: const Text('Keep Local'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<NotesProvider>().resolveConflict(_note!.id, 'cloud');
            },
            child: const Text('Keep Cloud'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<NotesProvider>().resolveConflict(_note!.id, 'merge');
            },
            child: const Text('Merge'),
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
              leading: const Icon(Icons.attach_file),
              title: const Text('Attach file'),
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
              leading: Icon(
                _note?.localOnly == true
                    ? Icons.cloud_off_outlined
                    : Icons.cloud_done_outlined,
              ),
              title: Text(
                _note?.localOnly == true
                    ? 'Stored locally only'
                    : 'Synced with cloud',
              ),
              subtitle: const Text('Toggle note-level cloud sync'),
              onTap: () {
                Navigator.pop(context);
                _toggleLocalOnlyForCurrentNote();
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
    final storageService = context.read<StorageService>();
    if (storageService.isStorageFull) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Storage is full. Please upgrade to add attachments.'),
          ),
        );
      }
      return;
    }

    try {
      final pickedFile = await FilePickerHelper.pickPlatformFile(
        context: context,
        dialogTitle: 'Select attachment',
      );

      if (pickedFile != null) {
        if (kIsWeb) {
          final bytes = pickedFile.bytes;
          if (bytes == null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Unable to read file bytes on web')),
              );
            }
            return;
          }
          await _attachFileToCurrentNote(
              fileName: pickedFile.name, bytes: bytes);
          return;
        }

        final filePath = pickedFile.path;
        if (filePath == null || filePath.isEmpty) {
          return;
        }
        await _attachFileToCurrentNote(
            filePath: filePath, fileName: pickedFile.name);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error attaching file: $e')),
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
                  ...AppColorPalette.noteBackgroundColors.map(
                    (colorOption) => _ColorOption(
                      color: colorOption.color,
                      onTap: () => _setNoteBackgroundColor(
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
    });
  }

  Future<void> _setNoteBackgroundColor(
    String? color,
    BuildContext dialogContext,
  ) async {
    if (_note == null) return;

    Navigator.pop(dialogContext);
    await context.read<NotesProvider>().setBackgroundColor(_note!.id, color);

    // Refresh note from provider to ensure we have the latest state
    if (!mounted) return;
    final updatedNote = context.read<NotesProvider>().getNoteById(_note!.id);
    if (updatedNote != null) {
      setState(() {
        _note = updatedNote;
      });
    }

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

  void _toggleFavorite() {
    if (_note != null) {
      context.read<NotesProvider>().toggleFavorite(_note!.id);
      setState(() {
        _note = _note!.copyWith(isFavorite: !_note!.isFavorite);
      });
    }
  }

  Future<void> _toggleLocalOnlyForCurrentNote() async {
    if (_note == null) return;
    final updated = _note!.copyWith(localOnly: !_note!.localOnly);
    final success = await context.read<NotesProvider>().updateNote(updated);
    if (!mounted) return;
    if (success) {
      setState(() {
        _note = updated;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updated.localOnly
                ? 'Note set to local-only'
                : 'Note set to cloud-sync',
          ),
        ),
      );
    }
  }

  Future<void> _exportNote() async {
    if (_note == null) return;

    try {
      // Determine export file name and extension
      final String fileName = _note!.title;
      String extension = '.txt';
      String content = '';
      Uint8List? fileBytes;

      if (_note!.type == NoteType.pdf && _note!.pdfPath != null) {
        // Export PDF file
        if (kIsWeb) {
          // On Web, we'd typicaly use the URL or bytes.
          // Assuming pdfPath is a URL or we need to fetch it.
          // For now, if it's a local path representation, it might not work on Web directly
          // unless stored in Firebase.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('PDF export on Web is not yet implemented')),
          );
          return;
        }

        final pdfFile = File(_note!.pdfPath!);
        if (!await pdfFile.exists()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('PDF file not found')),
            );
          }
          return;
        }
        fileBytes = await pdfFile.readAsBytes();
        extension = '.pdf';
      } else {
        if (_note!.type == NoteType.markdown) {
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
        fileBytes = utf8.encode(content);
      }

      final fullName = '$fileName$extension';

      // Platform-specific export logic
      if (kIsWeb) {
        // Web: Trigger native browser download
        await _exportWeb(fileBytes, fullName);
      } else if (Platform.isAndroid || Platform.isIOS) {
        // Mobile: Use system Share sheet
        await _exportMobile(fileBytes, fullName);
      } else {
        // Desktop: Use native file save dialog
        await _exportDesktop(content, fileBytes, fullName, extension);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export: $e')),
        );
      }
    }
  }

  Future<void> _exportWeb(Uint8List bytes, String fileName) async {
    try {
      web_download.downloadFile(bytes, fileName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download started')),
        );
      }
    } catch (e) {
      throw 'Could not trigger download: $e';
    }
  }

  Future<void> _exportMobile(Uint8List bytes, String fileName) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/$fileName');
    await tempFile.writeAsBytes(bytes);

    final xFile = XFile(tempFile.path, name: fileName);
    await Share.shareXFiles([xFile], text: 'Exported Note: $fileName');
  }

  Future<void> _exportDesktop(String textContent, Uint8List? bytes,
      String fileName, String extension) async {
    final savePath = await FilePickerHelper.saveFile(
      context: context,
      dialogTitle: 'Export Note',
      fileName: fileName,
      fileExtension:
          extension.startsWith('.') ? extension.substring(1) : extension,
    );

    if (savePath != null) {
      final file = File(savePath);
      if (bytes != null) {
        await file.writeAsBytes(bytes);
      } else {
        await file.writeAsString(textContent);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported to $savePath')),
        );
      }
    }
  }

  Future<void> _handleDroppedFiles(List<XFile> files) async {
    final storageService = context.read<StorageService>();
    if (storageService.isStorageFull) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Storage is full. Please upgrade to import files.'),
          ),
        );
      }
      return;
    }

    for (final file in files) {
      try {
        final filePath = file.path;
        final fileName = file.name;

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

        await _attachFileToCurrentNote(filePath: filePath, fileName: fileName);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to attach ${file.name}: $e')),
          );
        }
      }
    }
  }

  Future<void> _attachFileToCurrentNote({
    required String fileName,
    String? filePath,
    Uint8List? bytes,
  }) async {
    if (_note == null) return;
    if (!mounted) return;

    final notesProvider = context.read<NotesProvider>();
    final authService = context.read<AuthService>();
    final userId = authService.userId;
    if (userId == null) return;

    final ext = p.extension(fileName).toLowerCase();
    final mimeType = _mimeTypeForExtension(ext);
    String storedPath;
    int size;

    if (bytes != null) {
      final mime = mimeType ?? 'application/octet-stream';
      storedPath = 'data:$mime;base64,${base64Encode(bytes)}';
      size = bytes.length;
    } else {
      if (filePath == null || filePath.isEmpty) return;
      final sourceFile = File(filePath);
      if (!await sourceFile.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('File not found: $fileName')),
          );
        }
        return;
      }

      await LocalFileService.instance.initialize(userId);
      final copiedPath = await LocalFileService.instance.copyFileToStorage(
        filePath,
        fileName: fileName,
      );

      if (copiedPath == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to attach $fileName')),
          );
        }
        return;
      }

      storedPath = copiedPath;
      size = await sourceFile.length();
    }

    final attachment = NoteAttachment.create(
      name: fileName,
      path: storedPath,
      mimeType: mimeType,
      size: size,
    );

    final alreadyExists = _note!.attachments.any(
      (existing) =>
          existing.path == storedPath || existing.name == attachment.name,
    );
    if (alreadyExists) {
      return;
    }

    final updatedNote = _note!.copyWith(
      attachments: [..._note!.attachments, attachment],
      type: _note!.type == NoteType.pdf ? NoteType.text : _note!.type,
      pdfPath: _note!.pdfPath,
    );

    final success = await notesProvider.updateNote(updatedNote);
    if (!success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update note with $fileName')),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _note = updatedNote;
      _activeAttachmentId = attachment.id;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Attached: $fileName')),
    );
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
      case '.txt':
        return 'text/plain';
      case '.md':
      case '.markdown':
        return 'text/markdown';
      case '.json':
        return 'application/json';
      case '.csv':
        return 'text/csv';
      default:
        return null;
    }
  }

  void _updateContentFromProvider(Note providerNote) {
    if (!mounted) return;

    try {
      final delta =
          Delta.fromJson(jsonDecode(providerNote.content) as List<dynamic>);

      setState(() {
        _isUpdatingFromExternal = true;

        // Preserve selection if possible
        final selection = _quillController.selection;

        _quillController.document = Document.fromDelta(delta);

        // Try to restore selection
        if (selection.end <= _quillController.document.length) {
          _quillController.updateSelection(selection, ChangeSource.local);
        }

        _note = providerNote;
        _lastSavedContent = providerNote.content;
        _characterCount = providerNote.characterCount;
        _lineCount = providerNote.lineCount;
        _titleController.text = providerNote.title;

        _isUpdatingFromExternal = false;
      });
    } catch (e) {
      debugPrint('Error updating from external source: $e');
      _isUpdatingFromExternal = false;
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
