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
import 'package:http/http.dart' as http;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/web_download_stub.dart'
    if (dart.library.html) '../../../core/utils/web_download_web.dart'
    as web_download;

import '../../../core/models/note.dart';
import '../../../core/providers/notes_provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/local_file_service.dart';
import '../../../core/routes/app_router.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/utils/color_utils.dart';
import '../../../core/utils/file_picker_helper.dart';
import '../../../core/widgets/pdf_viewer_widget.dart';
import '../../../core/widgets/remote_pdf_embed_stub.dart'
    if (dart.library.html) '../../../core/widgets/remote_pdf_embed_web.dart';
import '../../home/widgets/sync_status_indicator.dart';
import '../widgets/markdown_table_embed_builder.dart';
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
  bool _hasStartedCloudMigration = false;
  bool _hideAttachmentPreview = false;
  double _sideBySideAttachmentFraction = 0.46;
  double _stackedAttachmentHeight = 320;
  bool _attachmentsExpanded = false;

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

    if (_note != null && !_hasStartedCloudMigration) {
      _hasStartedCloudMigration = true;
      unawaited(_ensureCloudBackedFiles());
    }
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
    final showAttachmentPreview =
        activeAttachment != null && !_hideAttachmentPreview;

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: bgColor ?? Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (attachments.isNotEmpty) ...[
            _buildAttachmentsSection(
              attachments,
              activeAttachment,
              canSideBySide,
              showAttachmentPreview,
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: showSideBySide
                ? _buildSideBySideEditorLayout(
                    activeAttachment,
                    bgColor,
                    showAttachmentPreview,
                  )
                : _buildStackedEditorLayout(
                    activeAttachment,
                    bgColor,
                    showAttachmentPreview,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideBySideEditorLayout(
    NoteAttachment? activeAttachment,
    Color? bgColor,
    bool showAttachmentPreview,
  ) {
    if (!showAttachmentPreview || activeAttachment == null) {
      return _buildEditorSurface(bgColor);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const dividerWidth = 18.0;
        final availableWidth = constraints.maxWidth - dividerWidth;
        final attachmentWidth =
            (availableWidth * _sideBySideAttachmentFraction).clamp(
          280.0,
          availableWidth - 320.0,
        );
        final editorWidth = availableWidth - attachmentWidth;

        return Row(
          children: [
            SizedBox(
              width: attachmentWidth,
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: _buildAttachmentPreview(activeAttachment),
              ),
            ),
            _buildHorizontalResizeHandle(availableWidth),
            SizedBox(
              width: editorWidth,
              child: _buildEditorSurface(bgColor),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStackedEditorLayout(
    NoteAttachment? activeAttachment,
    Color? bgColor,
    bool showAttachmentPreview,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!showAttachmentPreview || activeAttachment == null) {
          return _buildEditorSurface(bgColor);
        }

        const dividerHeight = 18.0;
        final availableHeight = constraints.maxHeight - dividerHeight;
        final attachmentHeight = _stackedAttachmentHeight.clamp(
          180.0,
          availableHeight - 180.0,
        );
        final editorHeight = availableHeight - attachmentHeight;

        return Column(
          children: [
            SizedBox(
              height: attachmentHeight,
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: _buildAttachmentPreview(activeAttachment),
              ),
            ),
            _buildVerticalResizeHandle(availableHeight),
            SizedBox(
              height: editorHeight,
              child: _buildEditorSurface(bgColor),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHorizontalResizeHandle(double availableWidth) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          setState(() {
            final nextWidth = availableWidth * _sideBySideAttachmentFraction +
                details.delta.dx;
            _sideBySideAttachmentFraction =
                (nextWidth / availableWidth).clamp(0.25, 0.72);
          });
        },
        child: SizedBox(
          width: 18,
          child: Center(
            child: Container(
              width: 4,
              height: 72,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerticalResizeHandle(double availableHeight) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) {
          setState(() {
            _stackedAttachmentHeight =
                (_stackedAttachmentHeight + details.delta.dy)
                    .clamp(180.0, availableHeight - 180.0);
          });
        },
        child: SizedBox(
          height: 18,
          child: Center(
            child: Container(
              width: 72,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
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
        configurations: const QuillEditorConfigurations(
          embedBuilders: [MarkdownTableEmbedBuilder()],
        ),
      ),
    );
  }

  Widget _buildAttachmentsSection(
    List<NoteAttachment> attachments,
    NoteAttachment? activeAttachment,
    bool canSideBySide,
    bool showAttachmentPreview,
  ) {
    if (attachments.length == 1 && activeAttachment != null) {
      return _buildSingleAttachmentBar(
        activeAttachment,
        canSideBySide,
        showAttachmentPreview,
      );
    }

    return _buildMultiAttachmentBar(
      attachments,
      activeAttachment,
      canSideBySide,
      showAttachmentPreview,
    );
  }

  Widget _buildSingleAttachmentBar(
    NoteAttachment attachment,
    bool canSideBySide,
    bool showAttachmentPreview,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            Icons.attach_file,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              attachment.name,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '1 attachment',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(width: 8),
          if (canSideBySide)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: _sideBySideAttachments
                  ? 'Switch to stacked view'
                  : 'Switch to side-by-side view',
              onPressed: () {
                setState(() {
                  _sideBySideAttachments = !_sideBySideAttachments;
                });
              },
              icon: Icon(
                _sideBySideAttachments ? Icons.splitscreen : Icons.view_agenda,
              ),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: showAttachmentPreview
                ? 'Hide attachment preview'
                : 'Show attachment preview',
            onPressed: () {
              setState(() {
                _hideAttachmentPreview = !_hideAttachmentPreview;
              });
            },
            icon: Icon(
              showAttachmentPreview
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
          TextButton.icon(
            onPressed: _insertPdf,
            icon: const Icon(Icons.add),
            label: const Text('Attach'),
          ),
        ],
      ),
    );
  }

  Widget _buildMultiAttachmentBar(
    List<NoteAttachment> attachments,
    NoteAttachment? activeAttachment,
    bool canSideBySide,
    bool showAttachmentPreview,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.attach_file,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${attachments.length} attachments'
                  '${activeAttachment != null ? ' • ${activeAttachment.name}' : ''}',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _attachmentsExpanded = !_attachmentsExpanded;
                  });
                },
                child: Text(_attachmentsExpanded ? 'Collapse' : 'Expand'),
              ),
              if (canSideBySide)
                IconButton(
                  visualDensity: VisualDensity.compact,
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
              if (activeAttachment != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: showAttachmentPreview
                      ? 'Hide attachment preview'
                      : 'Show attachment preview',
                  onPressed: () {
                    setState(() {
                      _hideAttachmentPreview = !_hideAttachmentPreview;
                    });
                  },
                  icon: Icon(
                    showAttachmentPreview
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              TextButton.icon(
                onPressed: _insertPdf,
                icon: const Icon(Icons.add),
                label: const Text('Attach'),
              ),
            ],
          ),
          if (_attachmentsExpanded) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: attachments
                    .map(
                      (attachment) => ChoiceChip(
                        selected: activeAttachment?.id == attachment.id,
                        label: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: Text(
                            attachment.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        onSelected: (selected) {
                          setState(() {
                            _activeAttachmentId =
                                selected ? attachment.id : null;
                            if (selected) {
                              _hideAttachmentPreview = false;
                            }
                          });
                        },
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAttachmentPreview(NoteAttachment attachment) {
    final extension = p.extension(attachment.name).toLowerCase();
    final mimeType = attachment.mimeType?.toLowerCase();
    if (attachment.path.startsWith('data:')) {
      Uint8List bytes;
      String? dataMimeType;
      try {
        final separatorIndex = attachment.path.indexOf(',');
        if (separatorIndex <= 0) {
          return _buildAttachmentUnavailable(attachment);
        }
        dataMimeType = _mimeTypeFromDataUri(attachment.path);
        bytes = base64Decode(attachment.path.substring(separatorIndex + 1));
      } catch (_) {
        return _buildAttachmentUnavailable(attachment);
      }

      if (_isPdfAttachment(extension, mimeType ?? dataMimeType)) {
        return PdfPreview(
          build: (_) => bytes,
          allowPrinting: true,
          allowSharing: true,
          canChangeOrientation: false,
          canChangePageFormat: false,
          canDebug: false,
        );
      }

      if (_isSvgAttachment(extension, mimeType ?? dataMimeType)) {
        return _buildSvgMemoryPreview(attachment, bytes);
      }

      if (_isRasterImageAttachment(extension, mimeType ?? dataMimeType)) {
        return Container(
          color: Colors.black12,
          child: Center(
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _buildAttachmentInfo(attachment),
            ),
          ),
        );
      }

      if (_isTextAttachment(extension, mimeType ?? dataMimeType)) {
        final text = utf8.decode(bytes, allowMalformed: true);
        return _buildTextAttachmentPreview(text);
      }

      return _buildAttachmentInfo(attachment);
    }

    if (_isRemoteAttachmentPath(attachment.path)) {
      if (_isPdfAttachment(extension, mimeType)) {
        if (kIsWeb) {
          return RemotePdfEmbed(url: attachment.path);
        }
        return FutureBuilder<Uint8List?>(
          future: _fetchAttachmentBytes(attachment.path),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData) {
              return _buildAttachmentUnavailable(attachment);
            }
            return PdfPreview(
              build: (_) => snapshot.data!,
              allowPrinting: true,
              allowSharing: true,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
            );
          },
        );
      }

      if (_isSvgAttachment(extension, mimeType)) {
        return FutureBuilder<Uint8List?>(
          future: _fetchAttachmentBytes(attachment.path),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final bytes = snapshot.data;
            if (bytes == null) {
              return _buildAttachmentInfo(attachment);
            }
            return _buildSvgMemoryPreview(attachment, bytes);
          },
        );
      }

      if (_isRasterImageAttachment(extension, mimeType)) {
        return Container(
          color: Colors.black12,
          child: Center(
            child: Image.network(
              attachment.path,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => FutureBuilder<Uint8List?>(
                future: _fetchAttachmentBytes(attachment.path),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final bytes = snapshot.data;
                  if (bytes == null) {
                    return _buildAttachmentInfo(attachment);
                  }
                  return Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        _buildAttachmentInfo(attachment),
                  );
                },
              ),
            ),
          ),
        );
      }

      if (_isTextAttachment(extension, mimeType)) {
        return FutureBuilder<String?>(
          future: _fetchAttachmentText(attachment.path),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData) {
              return _buildAttachmentInfo(attachment);
            }
            return _buildTextAttachmentPreview(snapshot.data!);
          },
        );
      }

      return _buildAttachmentInfo(attachment);
    }

    if (kIsWeb) {
      // Web cannot access device-local absolute file paths from other platforms.
      return _buildAttachmentUnavailable(attachment);
    }

    final file = File(attachment.path);

    if (!file.existsSync()) {
      return _buildAttachmentUnavailable(attachment);
    }

    if (_isPdfAttachment(extension, mimeType)) {
      return PdfViewerWidget(pdfFile: file);
    }

    if (_isSvgAttachment(extension, mimeType)) {
      return _buildSvgFilePreview(attachment, file);
    }

    if (_isRasterImageAttachment(extension, mimeType)) {
      return Container(
        color: Colors.black12,
        child: Center(
          child: Image.file(
            file,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _buildAttachmentInfo(attachment),
          ),
        ),
      );
    }

    if (_isTextAttachment(extension, mimeType)) {
      return FutureBuilder<String>(
        future: file.readAsString(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData) {
            return _buildAttachmentInfo(attachment);
          }
          return _buildTextAttachmentPreview(snapshot.data!);
        },
      );
    }

    return _buildAttachmentInfo(attachment);
  }

  Widget _buildTextAttachmentPreview(String text) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: SelectableText(
        text,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }

  Widget _buildSvgMemoryPreview(NoteAttachment attachment, Uint8List bytes) {
    return Container(
      color: Colors.black12,
      child: Center(
        child: SvgPicture.memory(
          bytes,
          fit: BoxFit.contain,
          placeholderBuilder: (_) =>
              const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  Widget _buildSvgFilePreview(NoteAttachment attachment, File file) {
    return Container(
      color: Colors.black12,
      child: FutureBuilder<Uint8List>(
        future: file.readAsBytes(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final bytes = snapshot.data;
          if (bytes == null) {
            return _buildAttachmentInfo(attachment);
          }

          return Center(
            child: SvgPicture.memory(
              bytes,
              fit: BoxFit.contain,
              placeholderBuilder: (_) =>
                  const Center(child: CircularProgressIndicator()),
            ),
          );
        },
      ),
    );
  }

  bool _isPdfAttachment(String extension, String? mimeType) {
    return extension == '.pdf' || mimeType == 'application/pdf';
  }

  bool _isSvgAttachment(String extension, String? mimeType) {
    return extension == '.svg' || mimeType == 'image/svg+xml';
  }

  bool _isRasterImageAttachment(String extension, String? mimeType) {
    return const {
          '.jpg',
          '.jpeg',
          '.png',
          '.gif',
          '.webp',
          '.bmp',
          '.ico',
          '.tif',
          '.tiff',
          '.avif',
        }.contains(extension) ||
        (mimeType?.startsWith('image/') == true && mimeType != 'image/svg+xml');
  }

  bool _isTextAttachment(String extension, String? mimeType) {
    return const {
          '.txt',
          '.md',
          '.markdown',
          '.json',
          '.yaml',
          '.yml',
          '.csv',
          '.log',
          '.xml',
          '.html',
          '.htm',
          '.css',
          '.js',
          '.ts',
          '.dart',
          '.py',
          '.java',
          '.c',
          '.cc',
          '.cpp',
          '.h',
          '.hpp',
          '.sh',
          '.sql',
          '.ini',
          '.toml',
          '.env',
        }.contains(extension) ||
        mimeType == 'application/json' ||
        mimeType == 'application/xml' ||
        mimeType == 'image/svg+xml' ||
        mimeType?.startsWith('text/') == true;
  }

  String? _mimeTypeFromDataUri(String path) {
    if (!path.startsWith('data:')) return null;
    final separatorIndex = path.indexOf(',');
    if (separatorIndex <= 5) return null;
    final metadata = path.substring(5, separatorIndex);
    final semicolonIndex = metadata.indexOf(';');
    final mimeType =
        semicolonIndex >= 0 ? metadata.substring(0, semicolonIndex) : metadata;
    if (mimeType.isEmpty) return null;
    return mimeType.toLowerCase();
  }

  Widget _buildAttachmentUnavailable(NoteAttachment attachment) {
    final isProbablyLocalPath = !attachment.path.startsWith('data:') &&
        !attachment.path.startsWith('http://') &&
        !attachment.path.startsWith('https://');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 40),
            const SizedBox(height: 8),
            Text('Attachment unavailable: ${attachment.name}'),
            if (kIsWeb && isProbablyLocalPath) ...[
              const SizedBox(height: 6),
              const Text(
                'This file was attached using a device-local path and is not readable in web.',
                textAlign: TextAlign.center,
              ),
            ],
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

      if (_isRemoteAttachmentPath(attachment.path)) {
        final uri = Uri.parse(attachment.path);
        await launchUrl(
          uri,
          mode: kIsWeb
              ? LaunchMode.platformDefault
              : LaunchMode.externalApplication,
        );
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

  bool _isRemoteAttachmentPath(String path) =>
      path.startsWith('http://') || path.startsWith('https://');

  bool _isLocalAttachmentPath(String path) =>
      !path.startsWith('data:') && !_isRemoteAttachmentPath(path);

  Future<Uint8List?> _fetchAttachmentBytes(String path) async {
    try {
      final response = await http.get(Uri.parse(path));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      return response.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _fetchAttachmentText(String path) async {
    final bytes = await _fetchAttachmentBytes(path);
    if (bytes == null) return null;
    return utf8.decode(bytes, allowMalformed: true);
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
    final authService = context.read<AuthService>();

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
            if (authService.isGuestMode)
              ListTile(
                leading: const Icon(Icons.login),
                title: const Text('Sign in to sync'),
                subtitle: const Text('Sync this note across your devices'),
                onTap: () {
                  Navigator.pop(context);
                  AppRouter.navigateTo(context, AppRouter.login);
                },
              )
            else
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
    final authService = context.read<AuthService>();
    final shouldUseLocalAttachments =
        authService.isGuestMode || _note?.localOnly == true;

    if (!shouldUseLocalAttachments && storageService.isStorageFull) {
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
                  content: Text('Unable to read file bytes on web'),
                ),
              );
            }
            return;
          }
          await _attachFileToCurrentNote(
            fileName: pickedFile.name,
            bytes: bytes,
          );
          return;
        }

        final filePath = pickedFile.path;
        if (filePath == null || filePath.isEmpty) {
          return;
        }
        await _attachFileToCurrentNote(
          filePath: filePath,
          fileName: pickedFile.name,
        );
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
        if (_isRemoteAttachmentPath(_note!.pdfPath!)) {
          fileBytes = await _fetchAttachmentBytes(_note!.pdfPath!);
        } else {
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
        }
        if (fileBytes == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('PDF file not found')),
            );
          }
          return;
        }
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

  Future<void> _exportDesktop(
    String textContent,
    Uint8List? bytes,
    String fileName,
    String extension,
  ) async {
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
    final authService = context.read<AuthService>();
    final shouldUseLocalAttachments =
        authService.isGuestMode || _note?.localOnly == true;

    if (!shouldUseLocalAttachments && storageService.isStorageFull) {
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
    final storageService = context.read<StorageService>();
    final localFileService = LocalFileService.instance;
    final shouldUseLocalStorage = authService.isGuestMode || _note!.localOnly;
    String? storedPath;
    int size;
    final attachmentId = const Uuid().v4();
    final storagePath = shouldUseLocalStorage
        ? null
        : _buildCloudFilePath(
            noteId: _note!.id,
            itemId: attachmentId,
            fileName: fileName,
            bucket: 'attachments',
          );

    if (bytes != null) {
      if (shouldUseLocalStorage) {
        storedPath = await localFileService.writeBytesToStorage(
          bytes,
          fileName: fileName,
        );
      } else {
        storedPath = await storageService.uploadData(
          userId: userId,
          data: bytes,
          destinationPath: storagePath!,
          contentType: mimeType,
        );
      }
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

      if (shouldUseLocalStorage) {
        storedPath = await localFileService.copyFileToStorage(
          filePath,
          fileName: fileName,
        );
      } else {
        storedPath = await storageService.uploadFile(
          userId: userId,
          filePath: filePath,
          destinationPath: storagePath!,
          contentType: mimeType,
        );
      }
      size = await sourceFile.length();
    }

    if (storedPath == null) {
      if (mounted) {
        final errorMessage = shouldUseLocalStorage
            ? 'Failed to save $fileName locally'
            : storageService.errorMessage;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage ?? 'Failed to attach $fileName')),
        );
      }
      return;
    }

    final attachment = NoteAttachment(
      id: attachmentId,
      name: fileName,
      path: storedPath,
      mimeType: mimeType,
      size: size,
      addedAt: DateTime.now(),
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

  Future<void> _ensureCloudBackedFiles() async {
    if (_note == null || _note!.localOnly) return;

    final authService = context.read<AuthService>();
    final notesProvider = context.read<NotesProvider>();
    final storageService = context.read<StorageService>();
    final userId = authService.userId;
    if (userId == null) return;

    var note = _note!;
    var changed = false;

    final migratedAttachments = <NoteAttachment>[];
    for (final attachment in note.attachments) {
      if (!_isLocalAttachmentPath(attachment.path)) {
        migratedAttachments.add(attachment);
        continue;
      }

      final file = File(attachment.path);
      if (!await file.exists()) {
        migratedAttachments.add(attachment);
        continue;
      }

      final remotePath = await storageService.uploadFile(
        userId: userId,
        filePath: attachment.path,
        destinationPath: _buildCloudFilePath(
          noteId: note.id,
          itemId: attachment.id,
          fileName: attachment.name,
          bucket: 'attachments',
        ),
        contentType: attachment.mimeType,
      );

      if (remotePath == null) {
        migratedAttachments.add(attachment);
        continue;
      }

      migratedAttachments.add(attachment.copyWith(path: remotePath));
      changed = true;
    }

    note = note.copyWith(attachments: migratedAttachments);

    if (note.type == NoteType.pdf &&
        note.pdfPath != null &&
        _isLocalAttachmentPath(note.pdfPath!)) {
      final file = File(note.pdfPath!);
      if (await file.exists()) {
        final remotePath = await storageService.uploadFile(
          userId: userId,
          filePath: note.pdfPath!,
          destinationPath: _buildCloudFilePath(
            noteId: note.id,
            itemId: 'pdf',
            fileName: '${note.title}.pdf',
            bucket: 'pdf_notes',
          ),
          contentType: 'application/pdf',
        );
        if (remotePath != null) {
          note = note.copyWith(pdfPath: remotePath);
          changed = true;
        }
      }
    }

    if (!changed) return;

    final success = await notesProvider.updateNote(note);
    if (!success || !mounted) return;

    setState(() {
      _note = notesProvider.getNoteById(note.id) ?? note;
    });
  }

  String _buildCloudFilePath({
    required String noteId,
    required String itemId,
    required String fileName,
    required String bucket,
  }) {
    final sanitizedName = _sanitizeFileName(fileName);
    return '$bucket/$noteId/${itemId}_$sanitizedName';
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
      case '.ts':
        return 'text/plain';
      case '.dart':
        return 'text/x-dart';
      case '.py':
        return 'text/x-python';
      case '.java':
        return 'text/x-java-source';
      case '.c':
      case '.cc':
      case '.cpp':
      case '.h':
      case '.hpp':
        return 'text/plain';
      case '.sh':
        return 'application/x-sh';
      case '.sql':
        return 'application/sql';
      case '.toml':
        return 'application/toml';
      case '.ini':
      case '.log':
      case '.env':
        return 'text/plain';
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
      final document = Document()..insert(0, providerNote.content);
      setState(() {
        _isUpdatingFromExternal = true;
        _quillController.document = document;
        _quillController.updateSelection(
          const TextSelection.collapsed(offset: 0),
          ChangeSource.local,
        );
        _note = providerNote;
        _lastSavedContent = providerNote.content;
        _characterCount = providerNote.characterCount;
        _lineCount = providerNote.lineCount;
        _titleController.text = providerNote.title;
        _isUpdatingFromExternal = false;
      });
      debugPrint('Error updating from external source: $e');
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
