/// Editor Screen
///
/// Note editing screen with rich text support, line/character count,
/// and real-time sync. Based on the bottom-right design mockup.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/web_download_stub.dart'
    if (dart.library.html) '../../../core/utils/web_download_web.dart'
    as web_download;

import '../../../core/models/note.dart';
import '../../../core/models/typesync_kanban_embed.dart';
import '../../../core/providers/notes_provider.dart';
import '../../../core/providers/tags_provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/diagnostics_service.dart';
import '../../../core/services/local_file_service.dart';
import '../../../core/services/rich_text_plain_text_service.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/routes/app_router.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/utils/color_utils.dart';
import '../../../core/utils/file_picker_helper.dart';
import '../../../core/utils/version_compatibility.dart';
import '../../../core/widgets/inline_pdf_preview.dart';
import '../../../core/widgets/pdf_viewer_widget.dart';
import '../../../core/widgets/desktop_window_frame.dart';
import '../../../core/widgets/remote_pdf_embed_stub.dart'
    if (dart.library.html) '../../../core/widgets/remote_pdf_embed_web.dart';
import '../../home/widgets/sync_status_indicator.dart';
import '../../../core/models/typesync_table_embed.dart';
import '../widgets/markdown_table_embed_builder.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/editor_stats.dart';
import '../widgets/typesync_kanban_embed_builder.dart';
import '../widgets/typesync_table_embed_builder.dart';

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
  final String? searchQuery;
  final bool embedded;
  final VoidCallback? onClose;
  final VoidCallback? onSideBySideAction;
  final bool isSideBySideOpen;

  const EditorScreen({
    super.key,
    this.noteId,
    this.folderId,
    this.searchQuery,
    this.embedded = false,
    this.onClose,
    this.onSideBySideAction,
    this.isSideBySideOpen = false,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorSearchMatch {
  const _EditorSearchMatch({
    required this.startOffset,
    required this.endOffset,
  });

  final int startOffset;
  final int endOffset;

  int get length => endOffset - startOffset;
}

class _ChecklistLineState {
  const _ChecklistLineState({
    required this.startOffset,
    required this.endOffset,
    required this.listType,
  });

  final int startOffset;
  final int endOffset;
  final String? listType;

  bool get isChecklist =>
      listType == Attribute.checked.value ||
      listType == Attribute.unchecked.value;

  bool get isChecked => listType == Attribute.checked.value;

  Attribute<String?> get toggledAttribute =>
      isChecked ? Attribute.unchecked : Attribute.checked;
}

class _ChecklistLeading extends StatelessWidget {
  const _ChecklistLeading({
    required this.size,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final double size;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final railColor = value
        ? theme.colorScheme.primary.withValues(alpha: 0.18)
        : Colors.transparent;
    final fillColor = value
        ? (enabled
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface.withValues(alpha: 0.5))
        : theme.colorScheme.surface;
    final borderColor = value
        ? (enabled
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface.withValues(alpha: 0))
        : (enabled
            ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
            : theme.colorScheme.onSurface.withValues(alpha: 0.3));

    return SizedBox.expand(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? () => onChanged(!value) : null,
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll<Color>(
            Colors.transparent,
          ),
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          hoverColor: Colors.transparent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 3,
                  margin: const EdgeInsetsDirectional.only(top: 2, bottom: 2),
                  decoration: BoxDecoration(
                    color: railColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.topEnd,
                child: Container(
                  width: size,
                  height: size,
                  margin: EdgeInsetsDirectional.only(
                    top: 1,
                    end: size * 0.35,
                  ),
                  decoration: BoxDecoration(
                    color: fillColor,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: borderColor),
                  ),
                  child: value
                      ? Icon(
                          Icons.check,
                          size: size * 0.82,
                          color: theme.colorScheme.onPrimary,
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorScreenState extends State<EditorScreen>
    with SingleTickerProviderStateMixin {
  final DiagnosticsService _diagnostics = DiagnosticsService.instance;
  static const String _caretOffsetPreferencePrefix = 'typesync_editor_caret_';
  static const String _checklistCreatedAtAttributeKey =
      'typesync-checklist-created-at';
  static const String _checklistCheckedAtAttributeKey =
      'typesync-checklist-checked-at';
  static const String _toolbarPlacementPreferenceKey =
      'typesync_editor_toolbar_placement_v1';
  static const String _toolbarOffsetXPreferenceKey =
      'typesync_editor_offset_x_v1';
  static const String _toolbarOffsetYPreferenceKey =
      'typesync_editor_offset_y_v1';
  static const String _attachmentsExpandedPreferencePrefix =
      'typesync_editor_attachments_expanded_';
  static const String _attachmentsPreviewHiddenPreferencePrefix =
      'typesync_editor_attachments_preview_hidden_';

  // Quill editor controller
  late QuillController _quillController;

  // Focus node for the editor
  final FocusNode _focusNode = FocusNode();
  final FocusNode _titleFocusNode = FocusNode();

  // Scroll controller
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<EditorState> _editorKey = GlobalKey<EditorState>();
  final GlobalKey _editorSurfaceKey = GlobalKey();

  // Title controller
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _findController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();
  final FocusNode _findFocusNode = FocusNode();
  final FocusNode _replaceFocusNode = FocusNode();

  // Last saved content to prevent unnecessary reloads from provider
  String? _lastSavedContent;

  // Current note being edited
  Note? _note;
  Note? _pendingExternalNote;
  String? _activeNoteSyncId;
  SyncService? _syncService;

  // Auto-save timer
  Timer? _saveTimer;
  Timer? _caretPersistTimer;
  Timer? _toolbarPersistTimer;
  bool _didUserFocusEditor = false;

  // Stats
  int _characterCount = 0;
  int _lineCount = 0;

  // Loading state
  bool _isLoading = true;

  // Drag and drop state
  bool _isDragging = false;
  bool _isUpdatingFromExternal = false;
  bool _isApplyingChecklistMetadata = false;
  String? _activeAttachmentId;
  bool _sideBySideAttachments = false;
  bool _hasStartedCloudMigration = false;
  bool _hideAttachmentPreview = false;
  double _sideBySideAttachmentFraction = 0.46;
  double _stackedAttachmentHeight = 320;
  bool _attachmentsExpanded = false;
  EditorToolbarPlacement _toolbarPlacement = EditorToolbarPlacement.floating;
  Offset _toolbarPosition = const Offset(16, 100);
  late final AnimationController _matchGlowController;
  Timer? _matchGlowStopTimer;
  Rect? _matchGlowRect;
  bool _showMatchGlow = false;
  bool _didAttemptInitialSearchJump = false;
  bool _isSearchPanelVisible = false;
  bool _matchCase = false;
  List<_EditorSearchMatch> _searchMatches = const <_EditorSearchMatch>[];
  int _currentSearchMatchIndex = -1;
  final Map<String, Future<Uint8List?>> _attachmentBytesFutures = {};
  final Map<String, Future<String?>> _attachmentTextFutures = {};
  String? _autoGeneratedTitleHint;

  bool get _openedFromSearch {
    final query = widget.searchQuery?.trim();
    return query != null && query.isNotEmpty;
  }

  String? get _initialRouteSearchQuery {
    final query = widget.searchQuery?.trim();
    if (query == null || query.isEmpty) return null;
    return query;
  }

  String? get _caretOffsetPreferenceKey {
    final noteId = _note?.id;
    if (noteId == null || noteId.isEmpty) return null;
    return '$_caretOffsetPreferencePrefix$noteId';
  }

  String? get _attachmentsExpandedPreferenceKey {
    final noteId = _note?.id;
    if (noteId == null || noteId.isEmpty) return null;
    return '$_attachmentsExpandedPreferencePrefix$noteId';
  }

  String? get _attachmentsPreviewHiddenPreferenceKey {
    final noteId = _note?.id;
    if (noteId == null || noteId.isEmpty) return null;
    return '$_attachmentsPreviewHiddenPreferencePrefix$noteId';
  }

  bool _isAutoGeneratedTitle(String title) {
    return RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$').hasMatch(title);
  }

  void _syncTitleField(String title) {
    if (_isAutoGeneratedTitle(title)) {
      _autoGeneratedTitleHint = title;
      _titleController.text = '';
      return;
    }

    _autoGeneratedTitleHint = null;
    _titleController.text = title;
  }

  @override
  void initState() {
    super.initState();
    _syncService = context.read<SyncService>();
    _findController.addListener(_handleSearchQueryChanged);
    _focusNode.addListener(_onEditorFocusChanged);
    _matchGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _initializeEditor();
  }

  Future<void> _initializeEditor() async {
    final notesProvider = context.read<NotesProvider>();

    if (widget.noteId != null) {
      // Load existing note
      _note = notesProvider.getNoteById(widget.noteId!);

      if (_note != null) {
        _syncTitleField(_note!.title);

        // Parse content as Delta if it's JSON, otherwise treat as plain text
        try {
          if (_note!.content.isNotEmpty && _note!.content.startsWith('[')) {
            final loadResult = _loadDocumentFromStoredContent(_note!.content);
            final document = loadResult.document;
            _lastSavedContent = loadResult.normalizedContent;
            _quillController = QuillController(
              document: document,
              selection: const TextSelection.collapsed(offset: 0),
            );
          } else {
            // Plain text content
            final document = Document()..insert(0, _note!.content);
            _lastSavedContent = _note!.content;
            _quillController = QuillController(
              document: document,
              selection: const TextSelection.collapsed(offset: 0),
            );
          }
        } catch (e) {
          // If parsing fails, create empty document with content as plain text
          final document = Document()..insert(0, _note!.content);
          _lastSavedContent = _note!.content;
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

      final authService = context.read<AuthService>();
      if (authService.userId != null) {
        _note = await notesProvider.createNote(
          userId: authService.userId!,
          folderId: widget.folderId,
        );
        if (_note != null) {
          _syncTitleField(_note!.title);
        }
      }
    }

    if (!_openedFromSearch) {
      final restoredCaretOffset = await _loadPersistedCaretOffset();
      if (restoredCaretOffset != null) {
        _setEditorSelection(restoredCaretOffset);
      }
    }

    await _loadToolbarPreferences();
    await _loadAttachmentPreferences();

    // Listen for content changes
    _quillController.addListener(_onContentChanged);

    setState(() {
      _isLoading = false;
    });

    // Calculate initial stats
    _updateStats();
    if (_isCurrentAppVersionCompatibleWithNote()) {
      if (_openedFromSearch) {
        _maybeNavigateToInitialSearchMatch();
        _requestInitialEditorFocus(force: true);
      } else {
        _requestInitialEditorFocus();
      }
    }

    if (_note != null && !_hasStartedCloudMigration) {
      _attachActiveNoteSync();
      _hasStartedCloudMigration = true;
      unawaited(_ensureCloudBackedFiles());
    }
  }

  void _attachActiveNoteSync() {
    final note = _note;
    if (note == null || note.localOnly || note.id == _activeNoteSyncId) {
      return;
    }

    final authService = context.read<AuthService>();
    if (!authService.effectiveSyncEnabled || authService.userId == null) {
      return;
    }

    _syncService?.startNoteListening(note.id);
    _activeNoteSyncId = note.id;
  }

  void _onContentChanged() {
    if (_isUpdatingFromExternal) return;
    _ensureChecklistMetadata();
    _updateStats();
    _refreshSearchMatches();
    _scheduleSave();
    _scheduleCaretOffsetPersist();
  }

  void _ensureChecklistMetadata() {
    if (_isApplyingChecklistMetadata) return;

    final updates = <({int offset, Attribute<String?> attribute})>[];
    final operations = _quillController.document.toDelta().toJson();
    var documentOffset = 0;
    var lineStartOffset = 0;

    for (final operation in operations) {
      final insert = operation['insert'];
      final attributes = operation['attributes'] is Map
          ? Map<String, dynamic>.from(operation['attributes'] as Map)
          : const <String, dynamic>{};

      if (insert is String) {
        for (final rune in insert.runes) {
          final character = String.fromCharCode(rune);
          if (character == '\n') {
            final listType = attributes[Attribute.list.key];
            final isChecklist = listType == Attribute.checked.value ||
                listType == Attribute.unchecked.value;

            if (isChecklist) {
              final createdAt =
                  attributes[_checklistCreatedAtAttributeKey] as String?;
              final checkedAt =
                  attributes[_checklistCheckedAtAttributeKey] as String?;
              final isChecked = listType == Attribute.checked.value;
              final now = DateTime.now().toIso8601String();

              if (createdAt == null || createdAt.isEmpty) {
                updates.add(
                  (
                    offset: lineStartOffset,
                    attribute: _checklistMetadataAttribute(
                      _checklistCreatedAtAttributeKey,
                      now,
                    ),
                  ),
                );
              }

              if (isChecked && (checkedAt == null || checkedAt.isEmpty)) {
                updates.add(
                  (
                    offset: lineStartOffset,
                    attribute: _checklistMetadataAttribute(
                      _checklistCheckedAtAttributeKey,
                      now,
                    ),
                  ),
                );
              } else if (!isChecked &&
                  checkedAt != null &&
                  checkedAt.isNotEmpty) {
                updates.add(
                  (
                    offset: lineStartOffset,
                    attribute: _checklistMetadataAttribute(
                      _checklistCheckedAtAttributeKey,
                      null,
                    ),
                  ),
                );
              }
            }

            lineStartOffset = documentOffset + 1;
          }

          documentOffset++;
        }
        continue;
      }

      documentOffset++;
    }

    if (updates.isEmpty) return;

    final selection = _quillController.selection;
    _isApplyingChecklistMetadata = true;
    _quillController
      ..ignoreFocusOnTextChange = true
      ..skipRequestKeyboard = true;

    try {
      for (final update in updates) {
        _quillController.formatText(update.offset, 0, update.attribute);
      }
      if (selection.isValid) {
        _quillController.updateSelection(selection, ChangeSource.local);
      }
    } finally {
      _quillController
        ..ignoreFocusOnTextChange = false
        ..skipRequestKeyboard = false;
      _isApplyingChecklistMetadata = false;
    }
  }

  Attribute<String?> _checklistMetadataAttribute(String key, String? value) {
    return Attribute<String?>(key, AttributeScope.block, value);
  }

  List<_ChecklistLineState> _selectedChecklistLineStates() {
    final selection = _quillController.selection;
    if (!selection.isValid) {
      return const <_ChecklistLineState>[];
    }

    final operations = _quillController.document.toDelta().toJson();
    final selectedLines = <_ChecklistLineState>[];
    final selectionStart = selection.start;
    final selectionEnd = selection.end;
    var documentOffset = 0;
    var lineStartOffset = 0;

    for (final operation in operations) {
      final insert = operation['insert'];
      final attributes = operation['attributes'] is Map
          ? Map<String, dynamic>.from(operation['attributes'] as Map)
          : const <String, dynamic>{};

      if (insert is String) {
        for (final rune in insert.runes) {
          final character = String.fromCharCode(rune);
          if (character == '\n') {
            final lineEndOffset = documentOffset;
            final lineSelectionEnd = lineEndOffset + 1;
            final isSelected = selection.isCollapsed
                ? selectionStart >= lineStartOffset &&
                    selectionStart <= lineEndOffset
                : selectionStart < lineSelectionEnd &&
                    selectionEnd > lineStartOffset;

            if (isSelected) {
              selectedLines.add(
                _ChecklistLineState(
                  startOffset: lineStartOffset,
                  endOffset: lineEndOffset,
                  listType: attributes[Attribute.list.key] as String?,
                ),
              );
            }

            lineStartOffset = documentOffset + 1;
          }

          documentOffset++;
        }
        continue;
      }

      documentOffset++;
    }

    return selectedLines;
  }

  _ChecklistLineState? _currentChecklistLineState() {
    final selection = _quillController.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      return null;
    }

    final selectedLines = _selectedChecklistLineStates();
    if (selectedLines.length != 1) {
      return null;
    }

    final line = selectedLines.first;
    return line.isChecklist ? line : null;
  }

  void _insertEditorNewline() {
    final selection = _quillController.selection;
    if (!selection.isValid) return;

    final replacementLength = selection.end - selection.start;
    _quillController.replaceText(
      selection.start,
      replacementLength,
      '\n',
      null,
    );
    _quillController.updateSelection(
      TextSelection.collapsed(offset: selection.start + 1),
      ChangeSource.local,
    );
  }

  void _handleChecklistContinuationShortcut() {
    if (!_focusNode.hasFocus) return;

    final checklistLine = _currentChecklistLineState();
    _insertEditorNewline();

    if (checklistLine == null) {
      return;
    }

    final continuationOffset = _quillController.selection.baseOffset;
    _isApplyingChecklistMetadata = true;
    _quillController
      ..ignoreFocusOnTextChange = true
      ..skipRequestKeyboard = true;

    try {
      _quillController.formatText(
        continuationOffset,
        0,
        Attribute.clone(
          checklistLine.isChecked ? Attribute.checked : Attribute.unchecked,
          null,
        ),
      );
      _quillController.formatText(
        continuationOffset,
        0,
        _checklistMetadataAttribute(_checklistCreatedAtAttributeKey, null),
      );
      _quillController.formatText(
        continuationOffset,
        0,
        _checklistMetadataAttribute(_checklistCheckedAtAttributeKey, null),
      );
    } finally {
      _quillController
        ..ignoreFocusOnTextChange = false
        ..skipRequestKeyboard = false;
      _isApplyingChecklistMetadata = false;
    }

    _ensureChecklistMetadata();
    _updateStats();
    _refreshSearchMatches();
    _scheduleSave();
    _scheduleCaretOffsetPersist();
  }

  void _handleChecklistOppositeStateShortcut() {
    if (!_focusNode.hasFocus) return;

    final checklistLine = _currentChecklistLineState();
    _insertEditorNewline();

    if (checklistLine == null) {
      return;
    }

    final newLineOffset = _quillController.selection.baseOffset;
    final now = DateTime.now().toIso8601String();
    final targetAttribute = checklistLine.toggledAttribute;
    final targetCheckedAt =
        targetAttribute.value == Attribute.checked.value ? now : null;

    _isApplyingChecklistMetadata = true;
    _quillController
      ..ignoreFocusOnTextChange = true
      ..skipRequestKeyboard = true;

    try {
      _quillController.formatText(newLineOffset, 0, targetAttribute);
      _quillController.formatText(
        newLineOffset,
        0,
        _checklistMetadataAttribute(_checklistCreatedAtAttributeKey, now),
      );
      _quillController.formatText(
        newLineOffset,
        0,
        _checklistMetadataAttribute(
          _checklistCheckedAtAttributeKey,
          targetCheckedAt,
        ),
      );
    } finally {
      _quillController
        ..ignoreFocusOnTextChange = false
        ..skipRequestKeyboard = false;
      _isApplyingChecklistMetadata = false;
    }

    _ensureChecklistMetadata();
    _updateStats();
    _refreshSearchMatches();
    _scheduleSave();
    _scheduleCaretOffsetPersist();
  }

  void _toggleChecklistCycle() {
    final selection = _quillController.selection;
    if (!selection.isValid) return;

    final selectedLines = _selectedChecklistLineStates();
    if (selectedLines.isEmpty) return;

    final hasNonChecklist = selectedLines.any((line) => !line.isChecklist);
    final allChecklist = !hasNonChecklist;
    final allChecked =
        allChecklist && selectedLines.every((line) => line.isChecked);
    final targetOffsets = hasNonChecklist
        ? selectedLines
            .where((line) => !line.isChecklist)
            .map((line) => line.startOffset)
            .toList(growable: false)
        : selectedLines.map((line) => line.startOffset).toList(growable: false);

    if (targetOffsets.isEmpty) return;

    _isApplyingChecklistMetadata = true;
    _quillController
      ..ignoreFocusOnTextChange = true
      ..skipRequestKeyboard = true;

    try {
      if (hasNonChecklist) {
        for (final offset in targetOffsets) {
          _quillController.formatText(offset, 0, Attribute.unchecked);
        }
      } else if (allChecked) {
        for (final offset in targetOffsets) {
          _quillController.formatText(
            offset,
            0,
            Attribute.clone(Attribute.unchecked, null),
          );
          _quillController.formatText(
            offset,
            0,
            _checklistMetadataAttribute(_checklistCreatedAtAttributeKey, null),
          );
          _quillController.formatText(
            offset,
            0,
            _checklistMetadataAttribute(_checklistCheckedAtAttributeKey, null),
          );
        }
      } else {
        for (final offset in targetOffsets) {
          _quillController.formatText(offset, 0, Attribute.checked);
        }
      }

      _quillController.updateSelection(selection, ChangeSource.local);
    } finally {
      _quillController
        ..ignoreFocusOnTextChange = false
        ..skipRequestKeyboard = false;
      _isApplyingChecklistMetadata = false;
    }

    _ensureChecklistMetadata();
    _updateStats();
    _refreshSearchMatches();
    _scheduleSave();
    _scheduleCaretOffsetPersist();
  }

  DateTime? _parseChecklistMetadataTimestamp(Object? rawValue) {
    if (rawValue is! String || rawValue.trim().isEmpty) {
      return null;
    }

    return DateTime.tryParse(rawValue)?.toLocal();
  }

  String _formatChecklistMetadataTimestamp(DateTime timestamp) {
    return DateFormat.yMMMd().add_jm().format(timestamp);
  }

  String _buildChecklistTooltipMessage(Line line, bool isChecked) {
    final attributes = line.style.attributes;
    final createdAt = _parseChecklistMetadataTimestamp(
      attributes[_checklistCreatedAtAttributeKey]?.value,
    );
    final checkedAt = isChecked
        ? _parseChecklistMetadataTimestamp(
            attributes[_checklistCheckedAtAttributeKey]?.value,
          )
        : null;

    final lines = <String>[
      if (createdAt != null)
        'Created: ${_formatChecklistMetadataTimestamp(createdAt)}',
      if (checkedAt != null)
        'Checked: ${_formatChecklistMetadataTimestamp(checkedAt)}',
    ];

    if (lines.isEmpty) {
      return 'Checklist item';
    }

    return lines.join('\n');
  }

  void _handleChecklistCheckboxTap(
    int offset,
    bool value,
    ValueChanged<bool> onCheckboxTap,
  ) {
    onCheckboxTap(value);

    final selection = _quillController.selection;
    _isApplyingChecklistMetadata = true;
    _quillController
      ..ignoreFocusOnTextChange = true
      ..skipRequestKeyboard = true;

    try {
      final lineNode = _quillController.document.queryChild(offset).node;
      if (lineNode is! Line) return;

      final createdAt = lineNode
          .style.attributes[_checklistCreatedAtAttributeKey]?.value as String?;
      if (createdAt == null || createdAt.isEmpty) {
        _quillController.formatText(
          offset,
          0,
          _checklistMetadataAttribute(
            _checklistCreatedAtAttributeKey,
            DateTime.now().toIso8601String(),
          ),
        );
      }

      _quillController.formatText(
        offset,
        0,
        _checklistMetadataAttribute(
          _checklistCheckedAtAttributeKey,
          value ? DateTime.now().toIso8601String() : null,
        ),
      );

      if (selection.isValid) {
        _quillController.updateSelection(selection, ChangeSource.local);
      }
    } finally {
      _quillController
        ..ignoreFocusOnTextChange = false
        ..skipRequestKeyboard = false;
      _isApplyingChecklistMetadata = false;
    }
  }

  Widget? _buildChecklistHoverLeading(Node node, LeadingConfigurations config) {
    final isChecklist = config.attribute == Attribute.checked ||
        config.attribute == Attribute.unchecked;
    if (!isChecklist || node is! Line || config.lineSize == null) {
      return null;
    }

    return Tooltip(
      message: _buildChecklistTooltipMessage(node, config.value),
      waitDuration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppTheme.darkTertiary,
        ),
      ),
      textStyle: const TextStyle(
        color: AppTheme.darkTextPrimary,
        fontSize: 14,
        height: 1.35,
      ),
      child: _ChecklistLeading(
        size: config.lineSize!,
        value: config.value,
        enabled: config.enabled ?? false,
        onChanged: (value) {
          _handleChecklistCheckboxTap(
            node.documentOffset,
            value,
            config.onCheckboxTap,
          );
        },
      ),
    );
  }

  void _handleSearchQueryChanged() {
    _refreshSearchMatches(navigateToCurrentMatch: _openedFromSearch);
  }

  void _onEditorFocusChanged() {
    if (_focusNode.hasFocus) {
      final pendingExternalNote = _pendingExternalNote;
      if (pendingExternalNote != null) {
        _pendingExternalNote = null;
        _updateContentFromProvider(pendingExternalNote);
      }
      _didUserFocusEditor = true;
      _scheduleCaretOffsetPersist();
      return;
    }

    if (_didUserFocusEditor) {
      _caretPersistTimer?.cancel();
      unawaited(_persistCaretOffset(force: true));
    }
  }

  void _requestInitialEditorFocus({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || (!force && _openedFromSearch)) return;
      _focusNode.requestFocus();
    });
  }

  void _scheduleCaretOffsetPersist() {
    if (!_focusNode.hasFocus) return;
    _caretPersistTimer?.cancel();
    _caretPersistTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(_persistCaretOffset());
    });
  }

  Future<int?> _loadPersistedCaretOffset() async {
    final key = _caretOffsetPreferenceKey;
    if (key == null) return null;

    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistCaretOffset({bool force = false}) async {
    final key = _caretOffsetPreferenceKey;
    if (key == null) return;
    if (!_didUserFocusEditor && !force) return;
    if (!_focusNode.hasFocus && !force) return;

    final selection = _quillController.selection;
    if (!selection.isValid) return;

    final rawOffset = selection.extentOffset >= 0
        ? selection.extentOffset
        : selection.baseOffset;
    if (rawOffset < 0) return;

    final safeOffset = _safeDocumentOffset(rawOffset);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(key, safeOffset);
    } catch (_) {
      // Best-effort persistence; ignore local preference write failures.
    }
  }

  Future<void> _loadToolbarPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final placementRaw = prefs.getString(_toolbarPlacementPreferenceKey);
      if (placementRaw != null) {
        _toolbarPlacement = switch (placementRaw) {
          'top' => EditorToolbarPlacement.top,
          'bottom' => EditorToolbarPlacement.bottom,
          'left' => EditorToolbarPlacement.left,
          'right' => EditorToolbarPlacement.right,
          _ => EditorToolbarPlacement.floating,
        };
      }

      final offsetX = prefs.getDouble(_toolbarOffsetXPreferenceKey);
      final offsetY = prefs.getDouble(_toolbarOffsetYPreferenceKey);
      if (offsetX != null && offsetY != null) {
        _toolbarPosition = Offset(offsetX, offsetY);
      }
    } catch (_) {
      // Best-effort preference loading.
    }
  }

  Future<void> _loadAttachmentPreferences() async {
    final expandedKey = _attachmentsExpandedPreferenceKey;
    final previewHiddenKey = _attachmentsPreviewHiddenPreferenceKey;
    if (expandedKey == null && previewHiddenKey == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final expanded = expandedKey == null ? null : prefs.getBool(expandedKey);
      final previewHidden =
          previewHiddenKey == null ? null : prefs.getBool(previewHiddenKey);

      if (!mounted) return;
      setState(() {
        if (expanded != null) {
          _attachmentsExpanded = expanded;
        }
        if (previewHidden != null) {
          _hideAttachmentPreview = previewHidden;
        }
      });
    } catch (_) {
      // Best-effort preference loading.
    }
  }

  Future<void> _persistAttachmentPreferences() async {
    final expandedKey = _attachmentsExpandedPreferenceKey;
    final previewHiddenKey = _attachmentsPreviewHiddenPreferenceKey;
    if (expandedKey == null && previewHiddenKey == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (expandedKey != null) {
        await prefs.setBool(expandedKey, _attachmentsExpanded);
      }
      if (previewHiddenKey != null) {
        await prefs.setBool(previewHiddenKey, _hideAttachmentPreview);
      }
    } catch (_) {
      // Best-effort preference persistence.
    }
  }

  void _scheduleToolbarPreferencesPersist() {
    _toolbarPersistTimer?.cancel();
    _toolbarPersistTimer = Timer(const Duration(milliseconds: 200), () {
      unawaited(_persistToolbarPreferences());
    });
  }

  Future<void> _persistToolbarPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final placementRaw = switch (_toolbarPlacement) {
        EditorToolbarPlacement.top => 'top',
        EditorToolbarPlacement.bottom => 'bottom',
        EditorToolbarPlacement.left => 'left',
        EditorToolbarPlacement.right => 'right',
        EditorToolbarPlacement.floating => 'floating',
      };

      await prefs.setString(_toolbarPlacementPreferenceKey, placementRaw);
      await prefs.setDouble(_toolbarOffsetXPreferenceKey, _toolbarPosition.dx);
      await prefs.setDouble(_toolbarOffsetYPreferenceKey, _toolbarPosition.dy);
    } catch (_) {
      // Best-effort preference persistence.
    }
  }

  void _setEditorSelection(int offset) {
    _quillController.updateSelection(
      TextSelection.collapsed(offset: _safeDocumentOffset(offset)),
      ChangeSource.local,
    );
  }

  int _safeDocumentOffset(int offset) {
    final maxOffset = _quillController.document.length > 0
        ? _quillController.document.length - 1
        : 0;
    return offset.clamp(0, maxOffset).toInt();
  }

  ({Document document, String normalizedContent})
      _loadDocumentFromStoredContent(
    String content,
  ) {
    final normalizedContent = _normalizedStoredContent(content);
    final document = Document.fromJson(
      jsonDecode(normalizedContent) as List<dynamic>,
    );
    return (document: document, normalizedContent: normalizedContent);
  }

  String _normalizedStoredContent(String content) {
    if (content.isEmpty || !content.trimLeft().startsWith('[')) {
      return content;
    }

    try {
      final decoded = jsonDecode(content);
      if (decoded is! List<dynamic>) {
        return content;
      }
      final normalized = _sanitizeDeltaOperations(decoded);
      return jsonEncode(normalized);
    } catch (_) {
      return content;
    }
  }

  List<dynamic> _sanitizeDeltaOperations(List<dynamic> operations) {
    final sanitized = <Map<String, dynamic>>[];

    for (final rawOperation in operations) {
      if (rawOperation is! Map) {
        continue;
      }

      final operation = Map<String, dynamic>.from(rawOperation);
      final insert = operation['insert'];
      if (insert is! Map) {
        final normalizedStringOperations =
            _normalizeStringOperationForQuill(operation);
        if (normalizedStringOperations != null) {
          sanitized.addAll(normalizedStringOperations);
          continue;
        }
        sanitized.add(operation);
        continue;
      }

      final replacement = _unsupportedEmbedReplacement(insert);
      if (replacement != null) {
        sanitized.addAll(replacement);
        continue;
      }

      sanitized.add(operation);
    }

    if (sanitized.isEmpty) {
      return const [
        {'insert': '\n'},
      ];
    }

    final lastInsert = sanitized.last['insert'];
    if (lastInsert is! String || !lastInsert.endsWith('\n')) {
      sanitized.add(const {'insert': '\n'});
    }

    return sanitized;
  }

  List<Map<String, dynamic>>? _normalizeStringOperationForQuill(
    Map<String, dynamic> operation,
  ) {
    final insert = operation['insert'];
    if (insert is! String || !insert.contains('\n')) {
      return null;
    }

    final rawAttributes = operation['attributes'];
    if (rawAttributes is! Map || rawAttributes.isEmpty) {
      return null;
    }

    final attributes = Map<String, dynamic>.from(rawAttributes);
    final lineAttributes = <String, dynamic>{};
    for (final entry in attributes.entries) {
      final attribute = Attribute.fromKeyValue(entry.key, entry.value);
      if (attribute?.scope == AttributeScope.block ||
          attribute?.scope == AttributeScope.ignore ||
          entry.key == _checklistCreatedAtAttributeKey ||
          entry.key == _checklistCheckedAtAttributeKey) {
        lineAttributes[entry.key] = entry.value;
      }
    }

    final segments = insert.split('\n');
    final normalized = <Map<String, dynamic>>[];
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      if (segment.isNotEmpty) {
        normalized.add({
          'insert': segment,
          'attributes': attributes,
        });
      }

      if (index < segments.length - 1) {
        normalized.add({
          'insert': '\n',
          if (lineAttributes.isNotEmpty) 'attributes': lineAttributes,
        });
      }
    }

    return normalized;
  }

  List<Map<String, dynamic>>? _unsupportedEmbedReplacement(
    Map<dynamic, dynamic> insert,
  ) {
    final resolved = _resolveEmbed(insert);
    if (resolved == null) {
      return const [
        {'insert': '[Unsupported content]\n'},
      ];
    }

    if (_isSupportedEmbedType(resolved.type)) {
      return null;
    }

    return [
      {'insert': _unsupportedEmbedText(resolved.type, resolved.value)},
    ];
  }

  ({String type, Object? value})? _resolveEmbed(Map<dynamic, dynamic> insert) {
    final keys = insert.keys.toList(growable: false);
    if (keys.isEmpty) {
      return null;
    }

    final embedType = '${keys.first}';
    final embedValue = insert[keys.first];
    if (embedType != BlockEmbed.customType || embedValue is! String) {
      return (type: embedType, value: embedValue);
    }

    try {
      final decoded = jsonDecode(embedValue);
      if (decoded is! Map) {
        return (type: embedType, value: embedValue);
      }
      final customKeys = decoded.keys.toList(growable: false);
      if (customKeys.isEmpty) {
        return (type: embedType, value: embedValue);
      }
      final customType = '${customKeys.first}';
      return (type: customType, value: decoded[customKeys.first]);
    } catch (_) {
      return (type: embedType, value: embedValue);
    }
  }

  bool _isSupportedEmbedType(String embedType) {
    return embedType == TypeSyncKanbanEmbed.kanbanType ||
        embedType == TypeSyncTableEmbed.tableType ||
        embedType == 'x-embed-table';
  }

  String _unsupportedEmbedText(String embedType, Object? embedValue) {
    final rawValue = embedValue?.toString().trim() ?? '';
    final uri = Uri.tryParse(rawValue);
    final uriPath = uri?.path;
    final label = rawValue.isEmpty
        ? ''
        : p
            .basename((uriPath?.isNotEmpty ?? false) ? uriPath! : rawValue)
            .trim();

    return switch (embedType) {
      BlockEmbed.imageType =>
        label.isEmpty ? '[Image attachment]\n' : '[Image attachment: $label]\n',
      BlockEmbed.videoType =>
        label.isEmpty ? '[Video attachment]\n' : '[Video attachment: $label]\n',
      BlockEmbed.formulaType =>
        rawValue.isEmpty ? '[Formula]\n' : '$rawValue\n',
      _ => '[Unsupported content]\n',
    };
  }

  String? _minimumVersionRequiredByCurrentDocument() {
    final operations = _quillController.document.toDelta().toJson();
    for (final operation in operations) {
      final insert = operation['insert'];
      if (insert is! Map) continue;
      final resolved = _resolveEmbed(insert);
      if (resolved?.type == TypeSyncKanbanEmbed.kanbanType) {
        return TypeSyncKanbanEmbed.minimumSupportedAppVersion;
      }
    }
    return null;
  }

  String? _requiredAppVersionForCurrentNote() {
    final raw = _note?.minSupportedAppVersion?.trim();
    if (raw == null || raw.isEmpty) return null;
    return VersionCompatibility.normalize(raw);
  }

  bool _isCurrentAppVersionCompatibleWithNote() {
    final minimumVersion = _requiredAppVersionForCurrentNote();
    if (minimumVersion == null) return true;
    return VersionCompatibility.isAtLeast(
      current: kCurrentAppVersion,
      minimum: minimumVersion,
    );
  }

  Future<void> _markCurrentNoteRequiresVersion(String minimumVersion) async {
    final noteId = _note?.id;
    if (noteId == null || noteId.isEmpty) return;

    final notesProvider = context.read<NotesProvider>();
    final updatedNote = await notesProvider.setMinimumSupportedAppVersion(
      noteId: noteId,
      minimumVersion: minimumVersion,
    );
    if (!mounted || updatedNote == null) return;

    setState(() {
      _note = updatedNote;
    });
  }

  void _updateStats() {
    final plainText = RichTextPlainTextService.extractPlainTextFromDelta(
      _quillController.document.toDelta().toJson(),
    );
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

  Future<void> _saveNoteFromShortcut() async {
    _saveTimer?.cancel();
    await _saveNote();
  }

  Future<void> _saveNote() async {
    if (_note == null || _note!.hasConflict) return;

    final notesProvider = context.read<NotesProvider>();

    // Get content as JSON string
    final content = jsonEncode(
      _sanitizeDeltaOperations(_quillController.document.toDelta().toJson()),
    );

    final result = await notesProvider.saveNoteContentFromEditor(
      noteId: _note!.id,
      baseUpdatedAt: _note!.updatedAt,
      baseContent: _normalizedStoredContent(_note!.content),
      content: content,
      characterCount: _characterCount,
      lineCount: _lineCount,
    );

    if (!mounted) return;

    switch (result.status) {
      case NoteWriteStatus.saved:
        setState(() {
          _note = result.note;
          _lastSavedContent = content;
        });
        break;
      case NoteWriteStatus.skippedRemoteNewer:
        if (result.note != null) {
          _showEditorSyncMessage(result.message ?? 'Loaded a newer version.');
          _updateContentFromProvider(result.note!);
        }
        return;
      case NoteWriteStatus.conflict:
        setState(() {
          _note = result.note;
        });
        _showEditorSyncMessage(
          result.message ?? 'Conflicting changes were detected.',
        );
        return;
      case NoteWriteStatus.missing:
        _showEditorSyncMessage('This note could not be found anymore.');
        return;
    }

    final minimumVersion = _minimumVersionRequiredByCurrentDocument();
    if (minimumVersion != null) {
      unawaited(_markCurrentNoteRequiresVersion(minimumVersion));
    }
  }

  Future<void> _updateTitle(String title) async {
    if (_note == null) return;

    final nextTitle =
        title.isEmpty ? (_autoGeneratedTitleHint ?? _note!.title) : title;
    final notesProvider = context.read<NotesProvider>();
    final result = await notesProvider.saveNoteTitleFromEditor(
      noteId: _note!.id,
      baseUpdatedAt: _note!.updatedAt,
      baseTitle: _note!.title,
      title: nextTitle,
    );
    if (!mounted) return;

    switch (result.status) {
      case NoteWriteStatus.saved:
        setState(() {
          _note = result.note;
        });
        break;
      case NoteWriteStatus.skippedRemoteNewer:
        if (result.note != null) {
          _showEditorSyncMessage(result.message ?? 'Loaded a newer title.');
          setState(() {
            _note = result.note;
            _syncTitleField(result.note!.title);
            _titleController.selection = TextSelection.collapsed(
              offset: _titleController.text.length,
            );
          });
        }
        break;
      case NoteWriteStatus.conflict:
        if (result.note != null) {
          setState(() {
            _note = result.note;
          });
        }
        _showEditorSyncMessage(
          result.message ?? 'This note has unresolved conflicting changes.',
        );
        break;
      case NoteWriteStatus.missing:
        _showEditorSyncMessage('This note could not be found anymore.');
        break;
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _caretPersistTimer?.cancel();
    _toolbarPersistTimer?.cancel();
    if (_didUserFocusEditor) {
      unawaited(_persistCaretOffset(force: true));
    }
    unawaited(_persistToolbarPreferences());
    _matchGlowStopTimer?.cancel();
    _matchGlowController.dispose();
    _findController.removeListener(_handleSearchQueryChanged);
    _findController.dispose();
    _replaceController.dispose();
    _findFocusNode.dispose();
    _replaceFocusNode.dispose();
    _titleFocusNode.dispose();
    _quillController.removeListener(_onContentChanged);
    _quillController.dispose();
    _focusNode.removeListener(_onEditorFocusChanged);
    _focusNode.dispose();
    _scrollController.dispose();
    _titleController.dispose();
    if (_activeNoteSyncId != null) {
      _syncService?.stopNoteListening(_activeNoteSyncId);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildEditor(context);
  }

  bool get _isToolbarDockedInColumn =>
      _toolbarPlacement == EditorToolbarPlacement.top ||
      _toolbarPlacement == EditorToolbarPlacement.bottom;

  void _setToolbarPlacement(EditorToolbarPlacement placement) {
    if (_toolbarPlacement == placement) return;
    setState(() {
      _toolbarPlacement = placement;
    });
    _scheduleToolbarPreferencesPersist();
  }

  void _setToolbarPosition(Offset position) {
    if ((_toolbarPosition - position).distance < 0.5) return;
    _toolbarPosition = position;
    _scheduleToolbarPreferencesPersist();
  }

  Widget _buildEditor(BuildContext context) {
    if (_isLoading) {
      if (widget.embedded) {
        return const Center(child: CircularProgressIndicator());
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
        final providerContent = _normalizedStoredContent(providerNote.content);
        final localContent = _currentEditorContent();
        final localHasUnsavedEdits = _hasUnsavedLocalEditorChanges();

        // We only reload Quill if the content actually differs from what we currently have
        // AND it wasn't a change we just pushed ourselves.
        if (providerContent != localContent &&
            providerContent != _lastSavedContent) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (!localHasUnsavedEdits) {
              _pendingExternalNote = null;
              _updateContentFromProvider(providerNote);
              return;
            }

            setState(() {
              _pendingExternalNote = providerNote;
              _note = providerNote;
              _characterCount = providerNote.characterCount;
              _lineCount = providerNote.lineCount;
              _syncTitleField(providerNote.title);
            });
          });
        } else {
          // Content matches or is our own save. Just sync metadata silently.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _pendingExternalNote = null;
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
    final requiredVersion = _requiredAppVersionForCurrentNote();
    final currentVersion = VersionCompatibility.normalize(kCurrentAppVersion);
    final isUnsupportedVersion = requiredVersion != null &&
        !VersionCompatibility.isAtLeast(
          current: currentVersion,
          minimum: requiredVersion,
        );

    final editorBody = Column(
      children: isUnsupportedVersion
          ? [
              Expanded(
                child: _buildUnsupportedVersionNotice(
                  requiredVersion: requiredVersion,
                  currentVersion: currentVersion,
                ),
              ),
            ]
          : [
              if (_note?.hasConflict == true) _buildConflictBanner(),
              if (_toolbarPlacement == EditorToolbarPlacement.top)
                _buildToolbar(),
              if (_isSearchPanelVisible) _buildSearchPanel(),
              _buildEditorWorkspace(bgColor),
              if (_toolbarPlacement == EditorToolbarPlacement.bottom)
                _buildToolbar(),
            ],
    );

    final content = widget.embedded
        ? DecoratedBox(
            decoration: BoxDecoration(
              color: bgColor ?? Theme.of(context).scaffoldBackgroundColor,
            ),
            child: Column(
              children: [
                _buildEmbeddedHeader(bgColor),
                Expanded(child: editorBody),
              ],
            ),
          )
        : Scaffold(
            backgroundColor:
                bgColor ?? Theme.of(context).scaffoldBackgroundColor,
            appBar: _buildAppBar(bgColor),
            body: editorBody,
          );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          _openSearchPanel();
        },
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () {
          _openSearchPanel();
        },
        const SingleActivator(LogicalKeyboardKey.keyH, control: true): () {
          _openSearchPanel(focusReplace: true);
        },
        const SingleActivator(LogicalKeyboardKey.keyH, meta: true): () {
          _openSearchPanel(focusReplace: true);
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_isSearchPanelVisible) {
            _closeSearchPanel();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          unawaited(_saveNoteFromShortcut());
        },
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
          unawaited(_saveNoteFromShortcut());
        },
      },
      child: content,
    );
  }

  PreferredSizeWidget _buildAppBar(Color? bgColor) {
    return AppBar(
      backgroundColor: bgColor ?? Theme.of(context).appBarTheme.backgroundColor,
      flexibleSpace: desktopWindowDragArea(),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios),
        onPressed: () => Navigator.pop(context),
      ),
      title: Center(
        child: _buildTitleField(),
      ),
      actions: withDesktopWindowControls(
        _buildHeaderActions(),
        enabled: !widget.embedded,
      ),
    );
  }

  Widget _buildEmbeddedHeader(Color? bgColor) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final showTitle = maxWidth >= 220;
        final showSideBySide = maxWidth >= 260;
        final showStats = maxWidth >= 360;
        final showSync = maxWidth >= 420;

        return ClipRect(
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: bgColor ?? Theme.of(context).appBarTheme.backgroundColor,
              border: Border(
                bottom: BorderSide(
                  color: colors.outline.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                if (widget.onClose != null)
                  IconButton(
                    tooltip: 'Back to browser',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.arrow_back_ios),
                  ),
                if (showTitle)
                  Expanded(child: _buildTitleField())
                else
                  const Spacer(),
                ..._buildHeaderActions(
                  showSideBySide: showSideBySide,
                  showStats: showStats,
                  showSync: showSync,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTitleField() {
    return TextField(
      controller: _titleController,
      focusNode: _titleFocusNode,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleMedium,
      decoration: InputDecoration(
        border: InputBorder.none,
        hintText: _autoGeneratedTitleHint ?? 'Title',
        contentPadding: EdgeInsets.zero,
        filled: false,
      ),
      onChanged: _updateTitle,
    );
  }

  List<Widget> _buildHeaderActions({
    bool showSideBySide = true,
    bool showStats = true,
    bool showSync = true,
  }) {
    final sideBySideLabel =
        widget.isSideBySideOpen ? 'Close side by side' : 'Open side by side';
    final sideBySideIcon =
        widget.isSideBySideOpen ? Icons.close : Icons.splitscreen_outlined;

    return [
      if (showSideBySide && widget.onSideBySideAction != null)
        IconButton(
          tooltip: sideBySideLabel,
          onPressed: widget.onSideBySideAction,
          icon: Icon(sideBySideIcon),
        ),
      if (showStats)
        EditorStats(
          lineCount: _lineCount,
          characterCount: _characterCount,
        ),
      if (showSync) const SyncStatusIndicator(),
      IconButton(
        icon: const Icon(Icons.search),
        tooltip: 'Search and replace',
        onPressed: _openSearchPanel,
      ),
      IconButton(
        icon: const Icon(Icons.more_vert),
        onPressed: _showMoreOptions,
      ),
    ];
  }

  Widget _buildSearchPanel() {
    final colors = Theme.of(context).colorScheme;
    final hasMatches = _searchMatches.isNotEmpty;
    final matchCountText = _findController.text.trim().isEmpty
        ? 'Enter text to search'
        : hasMatches
            ? 'Match ${_currentSearchMatchIndex + 1} of ${_searchMatches.length}'
            : 'No matches found';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.outline.withValues(alpha: 0.22)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _findController,
                    focusNode: _findFocusNode,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Find',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _goToNextSearchMatch(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _replaceController,
                    focusNode: _replaceFocusNode,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Replace with',
                      prefixIcon: Icon(Icons.find_replace),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _replaceCurrentMatch(),
                  ),
                ),
                const SizedBox(width: 12),
                FilterChip(
                  label: const Text('Match case'),
                  selected: _matchCase,
                  onSelected: (selected) {
                    setState(() {
                      _matchCase = selected;
                    });
                    _refreshSearchMatches();
                  },
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Previous match',
                  onPressed: hasMatches ? _goToPreviousSearchMatch : null,
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
                IconButton(
                  tooltip: 'Next match',
                  onPressed: hasMatches ? _goToNextSearchMatch : null,
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
                IconButton(
                  tooltip: 'Close search',
                  onPressed: _closeSearchPanel,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  matchCountText,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: hasMatches
                            ? colors.onSurface
                            : colors.onSurfaceVariant,
                      ),
                ),
                FilledButton.tonalIcon(
                  onPressed: hasMatches ? _replaceCurrentMatch : null,
                  icon: const Icon(Icons.find_replace),
                  label: const Text('Replace'),
                ),
                FilledButton.tonal(
                  onPressed: hasMatches ? _replaceAllMatches : null,
                  child: const Text('Replace all'),
                ),
                FilledButton.tonal(
                  onPressed: hasMatches
                      ? () => _formatAllMatches(Attribute.bold)
                      : null,
                  child: const Text('Bold all'),
                ),
                FilledButton.tonal(
                  onPressed: hasMatches
                      ? () => _formatAllMatches(Attribute.underline)
                      : null,
                  child: const Text('Underline all'),
                ),
                FilledButton.tonal(
                  onPressed: hasMatches
                      ? () => _formatAllMatches(
                            const BackgroundAttribute('#FFF59D'),
                          )
                      : null,
                  child: const Text('Highlight all'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return EditorToolbar(
      controller: _quillController,
      onInsertPdf: _insertPdf,
      onInsertTable: _insertTable,
      onInsertKanban: _insertKanban,
      onToggleChecklist: _toggleChecklistCycle,
      placement: _toolbarPlacement,
      onPlacementChanged: _setToolbarPlacement,
      initialPosition: _toolbarPosition,
      onPositionChanged: _setToolbarPosition,
    );
  }

  Widget _buildEditorWorkspace(Color? bgColor) {
    final routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;

    return Expanded(
      child: DropTarget(
        onDragEntered: (details) {
          if (!routeIsCurrent) return;
          setState(() {
            _isDragging = true;
          });
        },
        onDragExited: (details) {
          if (!routeIsCurrent) return;
          setState(() {
            _isDragging = false;
          });
        },
        onDragDone: (details) {
          if (!routeIsCurrent) return;
          _handleDroppedFiles(details.files);
          setState(() {
            _isDragging = false;
          });
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            _buildEditorWithAttachments(bgColor),
            if (!_isToolbarDockedInColumn)
              Positioned.fill(child: _buildToolbar()),
            if (_isDragging)
              Container(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.2),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.upload_file,
                        size: 48,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Drop files to attach',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnsupportedVersionNotice({
    required String requiredVersion,
    required String currentVersion,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          margin: const EdgeInsets.all(24),
          color: colors.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.system_update_alt,
                      color: colors.onErrorContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Unsupported TypeSync Version',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: colors.onErrorContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'This file uses features that require TypeSync '
                  '$requiredVersion or newer.',
                  style: Theme.of(
                    context,
                  )
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: colors.onErrorContainer),
                ),
                const SizedBox(height: 8),
                Text(
                  'Current version: $currentVersion',
                  style: Theme.of(
                    context,
                  )
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: colors.onErrorContainer),
                ),
                const SizedBox(height: 12),
                Text(
                  'Update TypeSync to continue editing this file.',
                  style: Theme.of(
                    context,
                  )
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: colors.onErrorContainer),
                ),
              ],
            ),
          ),
        ),
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
        final availableWidth = (constraints.maxWidth - dividerWidth).clamp(
          0.0,
          double.infinity,
        );
        if (availableWidth <= 0) {
          return const SizedBox.shrink();
        }

        final maxAttachmentWidth = availableWidth > 320
            ? availableWidth - 320.0
            : availableWidth * 0.5;
        final resolvedMaxAttachmentWidth = maxAttachmentWidth.clamp(
          0.0,
          availableWidth,
        );
        final resolvedMinAttachmentWidth =
            (availableWidth >= 600 ? 280.0 : availableWidth * 0.35).clamp(
          0.0,
          resolvedMaxAttachmentWidth,
        );
        final attachmentWidth =
            (availableWidth * _sideBySideAttachmentFraction).clamp(
          resolvedMinAttachmentWidth,
          resolvedMaxAttachmentWidth,
        );
        final editorWidth = availableWidth - attachmentWidth;

        return Row(
          children: [
            SizedBox(
              width: attachmentWidth,
              child: _wrapTrackpadResizeRegion(
                axis: Axis.horizontal,
                onDelta: (delta) =>
                    _updateSideBySideAttachmentFraction(availableWidth, delta),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: _buildAttachmentPreview(activeAttachment),
                ),
              ),
            ),
            _buildHorizontalResizeHandle(availableWidth),
            SizedBox(
              width: editorWidth,
              child: _wrapTrackpadResizeRegion(
                axis: Axis.horizontal,
                onDelta: (delta) =>
                    _updateSideBySideAttachmentFraction(availableWidth, delta),
                child: _buildEditorSurface(bgColor),
              ),
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
        final availableHeight = (constraints.maxHeight - dividerHeight).clamp(
          0.0,
          double.infinity,
        );
        if (availableHeight <= 0) {
          return const SizedBox.shrink();
        }

        final maxAttachmentHeight = availableHeight > 180
            ? availableHeight - 180.0
            : availableHeight * 0.5;
        final resolvedMaxAttachmentHeight = maxAttachmentHeight.clamp(
          0.0,
          availableHeight,
        );
        final resolvedMinAttachmentHeight =
            (availableHeight >= 420 ? 180.0 : availableHeight * 0.35).clamp(
          0.0,
          resolvedMaxAttachmentHeight,
        );
        final attachmentHeight = _stackedAttachmentHeight.clamp(
          resolvedMinAttachmentHeight,
          resolvedMaxAttachmentHeight,
        );
        final editorHeight = availableHeight - attachmentHeight;

        return Column(
          children: [
            SizedBox(
              height: attachmentHeight,
              child: _wrapTrackpadResizeRegion(
                axis: Axis.vertical,
                enabled: () => !_isAnyTextInputFocused,
                onDelta: (delta) =>
                    _updateStackedAttachmentHeight(availableHeight, delta),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: _buildAttachmentPreview(activeAttachment),
                ),
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
          _updateSideBySideAttachmentFraction(availableWidth, details.delta.dx);
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
          _updateStackedAttachmentHeight(availableHeight, details.delta.dy);
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

  bool get _isAnyTextInputFocused =>
      _titleFocusNode.hasFocus ||
      _findFocusNode.hasFocus ||
      _replaceFocusNode.hasFocus ||
      _focusNode.hasFocus;

  void _updateSideBySideAttachmentFraction(
    double availableWidth,
    double delta,
  ) {
    if (availableWidth <= 0 || delta == 0) return;
    setState(() {
      final nextWidth = availableWidth * _sideBySideAttachmentFraction + delta;
      _sideBySideAttachmentFraction =
          (nextWidth / availableWidth).clamp(0.25, 0.72);
    });
  }

  void _updateStackedAttachmentHeight(double availableHeight, double delta) {
    if (availableHeight <= 0 || delta == 0) return;
    setState(() {
      final maxAttachmentHeight = availableHeight > 180
          ? availableHeight - 180.0
          : availableHeight * 0.5;
      final resolvedMaxAttachmentHeight = maxAttachmentHeight.clamp(
        0.0,
        availableHeight,
      );
      final resolvedMinAttachmentHeight =
          (availableHeight >= 420 ? 180.0 : availableHeight * 0.35).clamp(
        0.0,
        resolvedMaxAttachmentHeight,
      );
      _stackedAttachmentHeight = (_stackedAttachmentHeight + delta).clamp(
        resolvedMinAttachmentHeight,
        resolvedMaxAttachmentHeight,
      );
    });
  }

  Widget _wrapTrackpadResizeRegion({
    required Axis axis,
    required ValueChanged<double> onDelta,
    required Widget child,
    bool Function()? enabled,
  }) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerPanZoomUpdate: (event) {
        if (!(enabled?.call() ?? true)) return;
        final panDelta = event.panDelta;
        final primaryDelta =
            axis == Axis.horizontal ? panDelta.dx : panDelta.dy;
        final crossDelta = axis == Axis.horizontal ? panDelta.dy : panDelta.dx;
        if (primaryDelta == 0 || primaryDelta.abs() < crossDelta.abs()) return;
        onDelta(primaryDelta);
      },
      child: child,
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
      child: Stack(
        key: _editorSurfaceKey,
        children: [
          Positioned.fill(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(
                  LogicalKeyboardKey.enter,
                  shift: true,
                ): _handleChecklistContinuationShortcut,
                const SingleActivator(
                  LogicalKeyboardKey.enter,
                  control: true,
                ): _handleChecklistOppositeStateShortcut,
                const SingleActivator(
                  LogicalKeyboardKey.enter,
                  meta: true,
                ): _handleChecklistOppositeStateShortcut,
              },
              child: QuillEditor(
                controller: _quillController,
                focusNode: _focusNode,
                scrollController: _scrollController,
                configurations: QuillEditorConfigurations(
                  editorKey: _editorKey,
                  embedBuilders: const [
                    TypeSyncKanbanEmbedBuilder(),
                    TypeSyncTableEmbedBuilder(),
                    MarkdownTableEmbedBuilder(),
                  ],
                  customLeadingBlockBuilder: _buildChecklistHoverLeading,
                  customStyleBuilder: _buildCustomEditorStyle,
                ),
              ),
            ),
          ),
          if (_showMatchGlow && _matchGlowRect != null)
            _buildMatchGlowOverlay(),
        ],
      ),
    );
  }

  TextStyle _buildCustomEditorStyle(Attribute<dynamic> attribute) {
    if (attribute.key != Attribute.background.key ||
        attribute.value is! String) {
      return const TextStyle();
    }

    try {
      final backgroundColor =
          AppColorPalette.parseHexColor(attribute.value! as String);
      return TextStyle(
        color: AppColorPalette.getContrastingTextColor(backgroundColor),
      );
    } catch (_) {
      return const TextStyle();
    }
  }

  Widget _buildMatchGlowOverlay() {
    final rect = _matchGlowRect!;
    final width = (rect.width + 44).clamp(86.0, double.infinity);
    final height = (rect.height + 26).clamp(36.0, double.infinity);
    final left = (rect.left - 22).clamp(0.0, double.infinity);
    final top = (rect.top - 12).clamp(0.0, double.infinity);

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _matchGlowController,
          builder: (context, child) {
            final pulse = _matchGlowController.value;
            final spread = 6 + (pulse * 8);
            final opacity = 0.3 + ((1 - pulse) * 0.45);
            return DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: opacity),
                    blurRadius: 16 + spread,
                    spreadRadius: spread,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _openSearchPanel({bool focusReplace = false}) {
    if (!_isSearchPanelVisible) {
      final initialQuery = _selectedPlainTextForSearch();
      _findController.value = TextEditingValue(
        text: initialQuery,
        selection: TextSelection.collapsed(offset: initialQuery.length),
      );
      _replaceController.clear();
      setState(() {
        _isSearchPanelVisible = true;
      });
    } else {
      setState(() {});
    }

    _refreshSearchMatches(navigateToCurrentMatch: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (focusReplace ? _replaceFocusNode : _findFocusNode).requestFocus();
      if (!focusReplace) {
        _findController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _findController.text.length,
        );
      }
    });
  }

  String _selectedPlainTextForSearch() {
    final selection = _quillController.selection;
    if (!selection.isValid || selection.isCollapsed) {
      return '';
    }

    final start = selection.start < 0 ? 0 : selection.start;
    final end = selection.end < start ? start : selection.end;
    return _quillController.document.getPlainText(start, end - start).trim();
  }

  void _closeSearchPanel() {
    setState(() {
      _isSearchPanelVisible = false;
    });
    _focusNode.requestFocus();
  }

  void _refreshSearchMatches({bool navigateToCurrentMatch = false}) {
    if (!_isSearchPanelVisible && _findController.text.trim().isEmpty) {
      if (_searchMatches.isEmpty && _currentSearchMatchIndex == -1) return;
      setState(() {
        _searchMatches = const <_EditorSearchMatch>[];
        _currentSearchMatchIndex = -1;
      });
      return;
    }

    final matches = _findAllSearchMatches(_findController.text);
    final previousMatch = (_currentSearchMatchIndex >= 0 &&
            _currentSearchMatchIndex < _searchMatches.length)
        ? _searchMatches[_currentSearchMatchIndex]
        : null;

    var nextIndex = -1;
    if (matches.isNotEmpty) {
      if (previousMatch != null) {
        nextIndex = matches.indexWhere(
          (match) =>
              match.startOffset == previousMatch.startOffset &&
              match.endOffset == previousMatch.endOffset,
        );
      }

      if (nextIndex == -1) {
        final selectionOffset = _currentSelectionSearchAnchor();
        nextIndex =
            matches.indexWhere((match) => match.startOffset >= selectionOffset);
        nextIndex = nextIndex == -1 ? 0 : nextIndex;
      }
    }

    final shouldNavigate = navigateToCurrentMatch &&
        matches.isNotEmpty &&
        nextIndex >= 0 &&
        nextIndex < matches.length;

    setState(() {
      _searchMatches = matches;
      _currentSearchMatchIndex = nextIndex;
    });

    if (shouldNavigate) {
      unawaited(_focusAndPulseSearchMatch(matches[nextIndex]));
    }
  }

  int _currentSelectionSearchAnchor() {
    final selection = _quillController.selection;
    if (!selection.isValid) return 0;
    final rawOffset = selection.baseOffset >= 0 ? selection.baseOffset : 0;
    return _safeDocumentOffset(rawOffset);
  }

  List<_EditorSearchMatch> _findAllSearchMatches(String rawQuery) {
    final query = rawQuery.trim();
    if (query.isEmpty) return const <_EditorSearchMatch>[];

    final indexedDocument = _buildIndexedSearchDocument();
    if (indexedDocument.searchText.isEmpty) {
      return const <_EditorSearchMatch>[];
    }

    final haystack = _matchCase
        ? indexedDocument.searchText
        : indexedDocument.searchText.toLowerCase();
    final needle = _matchCase ? query : query.toLowerCase();
    final matches = <_EditorSearchMatch>[];
    var start = 0;

    while (start <= haystack.length - needle.length) {
      final index = haystack.indexOf(needle, start);
      if (index == -1) break;
      final startOffset = indexedDocument.plainToDocumentOffsets[index];
      final endOffset =
          indexedDocument.plainToDocumentOffsets[index + needle.length - 1] + 1;
      matches.add(
        _EditorSearchMatch(
          startOffset: startOffset,
          endOffset: endOffset,
        ),
      );
      start = index + needle.length;
    }

    return matches;
  }

  ({String searchText, List<int> plainToDocumentOffsets})
      _buildIndexedSearchDocument() {
    final buffer = StringBuffer();
    final plainToDocumentOffsets = <int>[];
    var documentOffset = 0;

    for (final operation in _quillController.document.toDelta().toList()) {
      final insert = operation.data;
      if (insert is String) {
        final codeUnits = insert.codeUnits;
        for (final codeUnit in codeUnits) {
          buffer.writeCharCode(codeUnit);
          plainToDocumentOffsets.add(documentOffset);
          documentOffset += 1;
        }
        continue;
      }

      buffer.writeCharCode(0xFFFC);
      plainToDocumentOffsets.add(documentOffset);
      documentOffset += 1;
    }

    return (
      searchText: buffer.toString(),
      plainToDocumentOffsets: plainToDocumentOffsets,
    );
  }

  void _goToNextSearchMatch() {
    _goToSearchMatch(step: 1);
  }

  void _goToPreviousSearchMatch() {
    _goToSearchMatch(step: -1);
  }

  void _goToSearchMatch({required int step}) {
    if (_searchMatches.isEmpty) return;
    final currentIndex =
        _currentSearchMatchIndex >= 0 ? _currentSearchMatchIndex : 0;
    final nextIndex =
        (currentIndex + step + _searchMatches.length) % _searchMatches.length;
    setState(() {
      _currentSearchMatchIndex = nextIndex;
    });
    unawaited(_focusAndPulseSearchMatch(_searchMatches[nextIndex]));
  }

  Future<void> _focusAndPulseSearchMatch(
    _EditorSearchMatch match, {
    bool selectMatch = true,
  }) async {
    if (!mounted) return;

    final documentLength = _quillController.document.length;
    if (documentLength <= 0) return;

    final safeStart = match.startOffset.clamp(0, documentLength - 1);
    final safeEnd = match.endOffset.clamp(safeStart + 1, documentLength);
    if (safeEnd <= safeStart) return;
    _quillController.updateSelection(
      selectMatch
          ? TextSelection(baseOffset: safeStart, extentOffset: safeEnd)
          : TextSelection.collapsed(offset: safeStart),
      ChangeSource.local,
    );

    for (var attempt = 0; attempt < 8; attempt++) {
      if (!mounted) return;
      final editorState = _editorKey.currentState;
      if (editorState != null && _scrollController.hasClients) {
        await _scrollToMatchAndPulse(editorState, safeStart);
        return;
      }
      await Future.delayed(const Duration(milliseconds: 60));
    }
  }

  void _replaceCurrentMatch() {
    if (_currentSearchMatchIndex < 0 ||
        _currentSearchMatchIndex >= _searchMatches.length) {
      return;
    }

    final match = _searchMatches[_currentSearchMatchIndex];
    final replacement = _replaceController.text;
    final replacementEnd = match.startOffset + replacement.length;

    _quillController.replaceText(
      match.startOffset,
      match.length,
      replacement,
      TextSelection.collapsed(offset: replacementEnd),
    );

    _refreshSearchMatches();
    if (_searchMatches.isNotEmpty) {
      final nextIndex = _currentSearchMatchIndex.clamp(
        0,
        _searchMatches.length - 1,
      );
      setState(() {
        _currentSearchMatchIndex = nextIndex;
      });
      unawaited(_focusAndPulseSearchMatch(_searchMatches[nextIndex]));
    }
  }

  void _replaceAllMatches() {
    if (_searchMatches.isEmpty) return;

    final replacement = _replaceController.text;
    final matches = List<_EditorSearchMatch>.from(_searchMatches);
    for (final match in matches.reversed) {
      _quillController.replaceText(
        match.startOffset,
        match.length,
        replacement,
        const TextSelection.collapsed(offset: 0),
      );
    }

    _refreshSearchMatches();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Replaced ${matches.length} matches')),
      );
    }
  }

  void _formatAllMatches(Attribute<dynamic> attribute) {
    if (_searchMatches.isEmpty) return;

    final isInlineAttribute = attribute.scope == AttributeScope.inline;
    var formattedCount = 0;

    for (final match in _searchMatches) {
      final startOffset = match.startOffset;
      var endOffset = match.endOffset;

      if (isInlineAttribute) {
        final matchedText = _quillController.document
            .getPlainText(startOffset, endOffset - startOffset);
        if (matchedText.isEmpty) {
          continue;
        }

        if (matchedText.endsWith('\n')) {
          endOffset -= 1;
        }

        if (endOffset <= startOffset) {
          continue;
        }
      }

      _quillController.document.format(
        startOffset,
        endOffset - startOffset,
        attribute,
      );
      formattedCount += 1;
    }

    _focusNode.requestFocus();
    if (mounted && formattedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated $formattedCount matches')),
      );
    }
  }

  void _maybeNavigateToInitialSearchMatch() {
    if (_didAttemptInitialSearchJump) return;
    _didAttemptInitialSearchJump = true;

    final query = _initialRouteSearchQuery;
    if (query == null || query.isEmpty) return;

    final initialMatches = _findAllSearchMatches(query);
    if (initialMatches.isEmpty) return;
    final initialMatch = initialMatches.first;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        _focusAndPulseSearchMatch(initialMatch, selectMatch: false),
      );
    });
  }

  Future<void> _scrollToMatchAndPulse(
    EditorState editorState,
    int safeOffset,
  ) async {
    Rect caretRect;
    try {
      caretRect = editorState.renderEditor.getLocalRectForCaret(
        TextPosition(offset: safeOffset),
      );
    } catch (_) {
      return;
    }

    final scrollPosition = _scrollController.position;
    final targetOffset = (_scrollController.offset +
            caretRect.top -
            (scrollPosition.viewportDimension * 0.35))
        .clamp(scrollPosition.minScrollExtent, scrollPosition.maxScrollExtent);

    if ((targetOffset - _scrollController.offset).abs() > 4) {
      await _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }

    if (!mounted) return;

    final refreshedState = _editorKey.currentState;
    if (refreshedState == null) return;
    try {
      caretRect = refreshedState.renderEditor.getLocalRectForCaret(
        TextPosition(offset: safeOffset),
      );
    } catch (_) {
      return;
    }

    final editorRenderBox = refreshedState.renderEditor;
    final overlayContext = _editorSurfaceKey.currentContext;
    final overlayRenderObject = overlayContext?.findRenderObject();
    if (overlayRenderObject is! RenderBox) {
      return;
    }

    final overlayRect = Rect.fromPoints(
      editorRenderBox.localToGlobal(
        caretRect.topLeft,
        ancestor: overlayRenderObject,
      ),
      editorRenderBox.localToGlobal(
        caretRect.bottomRight,
        ancestor: overlayRenderObject,
      ),
    );

    setState(() {
      _matchGlowRect = overlayRect;
      _showMatchGlow = true;
    });

    _matchGlowStopTimer?.cancel();
    _matchGlowController.repeat(reverse: true);
    _matchGlowStopTimer = Timer(const Duration(milliseconds: 1650), () {
      if (!mounted) return;
      _matchGlowController.stop();
      setState(() {
        _showMatchGlow = false;
      });
    });
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 560;
          final actions = _buildAttachmentBarActions(
            canSideBySide: canSideBySide,
            showAttachmentPreview: showAttachmentPreview,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
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
                      attachment.name,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  if (!isCompact) ...[
                    const SizedBox(width: 8),
                    Text(
                      '1 attachment',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              if (isCompact)
                Text(
                  '1 attachment',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              if (isCompact) const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actions,
              ),
            ],
          );
        },
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 560;
              final actions = <Widget>[
                TextButton(
                  onPressed: () {
                    setState(() {
                      _attachmentsExpanded = !_attachmentsExpanded;
                      _hideAttachmentPreview = !_attachmentsExpanded;
                    });
                    unawaited(_persistAttachmentPreferences());
                  },
                  child: Text(_attachmentsExpanded ? 'Collapse' : 'Expand'),
                ),
                ..._buildAttachmentBarActions(
                  canSideBySide: canSideBySide,
                  showAttachmentPreview: showAttachmentPreview,
                  includePreviewToggle: activeAttachment != null,
                ),
              ];

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: actions,
                  ),
                  if (isCompact) const SizedBox(height: 0),
                ],
              );
            },
          ),
          if (_attachmentsExpanded) ...[
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final maxChipWidth = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : 320.0;
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: attachments
                        .map(
                          (attachment) => GestureDetector(
                            onLongPress: () => _showAttachmentOptions(
                              attachment,
                            ),
                            onSecondaryTap: () => _showAttachmentOptions(
                              attachment,
                            ),
                            child: ChoiceChip(
                              selected: activeAttachment?.id == attachment.id,
                              label: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: maxChipWidth,
                                ),
                                child: Text(
                                  attachment.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: true,
                                ),
                              ),
                              onSelected: (selected) {
                                setState(() {
                                  _activeAttachmentId =
                                      selected ? attachment.id : null;
                                  if (selected) {
                                    _attachmentsExpanded = true;
                                    _hideAttachmentPreview = false;
                                  }
                                });
                                unawaited(_persistAttachmentPreferences());
                              },
                            ),
                          ),
                        )
                        .toList(),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildAttachmentBarActions({
    required bool canSideBySide,
    required bool showAttachmentPreview,
    bool includePreviewToggle = true,
  }) {
    return [
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
      if (includePreviewToggle)
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: showAttachmentPreview
              ? 'Hide attachment preview'
              : 'Show attachment preview',
          onPressed: () {
            setState(() {
              _hideAttachmentPreview = !_hideAttachmentPreview;
              _attachmentsExpanded = !_hideAttachmentPreview;
            });
            unawaited(_persistAttachmentPreferences());
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
    ];
  }

  void _showAttachmentOptions(NoteAttachment attachment) {
    showModalBottomSheet(
      context: context,
      builder: (bottomSheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                'Delete',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () async {
                Navigator.pop(bottomSheetContext);
                await _deleteAttachment(attachment);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteAttachment(NoteAttachment attachment) async {
    final note = _note;
    if (note == null || !mounted) return;

    final notesProvider = context.read<NotesProvider>();
    final authService = context.read<AuthService>();
    final storageService = context.read<StorageService>();
    _diagnostics.info(
      'EditorScreen',
      'ATTACHMENT_DELETE requested note=${note.id} attachment=${attachment.id} name=${attachment.name} path=${attachment.path} remote=${_isRemoteAttachmentPath(attachment.path)}',
    );

    final deleteSucceeded = await _deleteAttachmentFile(
      note: note,
      attachment: attachment,
      userId: authService.userId,
      storageService: storageService,
    );
    if (!deleteSucceeded) {
      _diagnostics.error(
        'EditorScreen',
        'ATTACHMENT_DELETE storage delete failed note=${note.id} attachment=${attachment.id} error=${storageService.errorMessage ?? 'unknown'}',
      );
      if (mounted) {
        final errorMessage = storageService.errorMessage;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage ?? 'Failed to delete ${attachment.name}',
            ),
          ),
        );
      }
      return;
    }

    final isPrimaryPdfAttachment = note.pdfPath != null &&
        note.pdfPath == attachment.path &&
        !note.attachments.any((candidate) => candidate.id == attachment.id);

    final updatedAttachments = note.attachments
        .where((candidate) => candidate.id != attachment.id)
        .toList();
    final updatedNote = note.copyWith(
      attachments: updatedAttachments,
      pdfPath: isPrimaryPdfAttachment ? null : note.pdfPath,
      size: isPrimaryPdfAttachment ? 0 : note.size,
    );
    final success = await notesProvider.updateNote(updatedNote);
    if (!success) {
      _diagnostics.error(
        'EditorScreen',
        'ATTACHMENT_DELETE note update failed note=${note.id} attachment=${attachment.id}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Failed to update note after deleting ${attachment.name}'),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _note = notesProvider.getNoteById(note.id) ?? updatedNote;
      if (_activeAttachmentId == attachment.id) {
        _activeAttachmentId =
            updatedAttachments.isEmpty ? null : updatedAttachments.first.id;
      }
      if (updatedAttachments.isEmpty) {
        _hideAttachmentPreview = false;
      }
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Deleted: ${attachment.name}')));
    _diagnostics.info(
      'EditorScreen',
      'ATTACHMENT_DELETE completed note=${note.id} attachment=${attachment.id} remaining=${updatedAttachments.length}',
    );
  }

  Future<bool> _deleteAttachmentFile({
    required Note note,
    required NoteAttachment attachment,
    required String? userId,
    required StorageService storageService,
  }) async {
    _attachmentBytesFutures.remove(attachment.path);
    _attachmentTextFutures.remove(attachment.path);

    if (attachment.path.isEmpty || attachment.path.startsWith('data:')) {
      return true;
    }

    if (_isRemoteAttachmentPath(attachment.path)) {
      if (userId == null) {
        _diagnostics.error(
          'EditorScreen',
          'ATTACHMENT_DELETE remote delete missing user note=${note.id} attachment=${attachment.id}',
        );
        return false;
      }
      _diagnostics.info(
        'EditorScreen',
        'ATTACHMENT_DELETE attempting remote delete via stored path note=${note.id} attachment=${attachment.id} target=${attachment.path}',
      );
      final deletedStoredPath = await storageService.deleteFile(
        userId: userId,
        filePath: attachment.path,
      );
      if (deletedStoredPath) {
        return true;
      }

      final legacyPath = _buildCloudFilePath(
        noteId: note.id,
        itemId: attachment.id,
        fileName: attachment.name,
        bucket: 'attachments',
      );
      _diagnostics.warning(
        'EditorScreen',
        'ATTACHMENT_DELETE stored path delete failed, trying legacy path note=${note.id} attachment=${attachment.id} target=$legacyPath',
      );
      return storageService.deleteFile(
        userId: userId,
        filePath: legacyPath,
      );
    }

    try {
      final file = File(attachment.path);
      if (await file.exists()) {
        await file.delete();
      }
      _diagnostics.info(
        'EditorScreen',
        'ATTACHMENT_DELETE deleted local file note=${note.id} attachment=${attachment.id} path=${attachment.path}',
      );
      return true;
    } catch (e) {
      _diagnostics.error(
        'EditorScreen',
        'ATTACHMENT_DELETE local delete failed note=${note.id} attachment=${attachment.id} path=${attachment.path} error=$e',
      );
      return false;
    }
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
        return _buildInlinePdfPreview(
          bytes,
          identity: attachment.id,
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
          return RemotePdfEmbed(
            key: ValueKey('remote-pdf-${attachment.path}'),
            url: attachment.path,
          );
        }
        return FutureBuilder<Uint8List?>(
          key: ValueKey('remote-pdf-future-${attachment.path}'),
          future: _cachedAttachmentBytes(attachment.path),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData) {
              return _buildAttachmentUnavailable(attachment);
            }
            return _buildInlinePdfPreview(
              snapshot.data!,
              identity: attachment.path,
            );
          },
        );
      }

      if (_isSvgAttachment(extension, mimeType)) {
        return FutureBuilder<Uint8List?>(
          future: _cachedAttachmentBytes(attachment.path),
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
                future: _cachedAttachmentBytes(attachment.path),
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
          future: _cachedAttachmentText(attachment.path),
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
      return PdfViewerWidget(
        key: ValueKey('local-pdf-${attachment.path}'),
        pdfFile: file,
      );
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insert_drive_file_outlined, size: 52),
              const SizedBox(height: 12),
              Text(
                attachment.name,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                '${(attachment.size / 1024).toStringAsFixed(1)} KB',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _openAttachmentExternally(attachment),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open externally'),
              ),
            ],
          ),
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

  Future<Uint8List?> _cachedAttachmentBytes(String path) {
    return _attachmentBytesFutures.putIfAbsent(
      path,
      () => _fetchAttachmentBytes(path),
    );
  }

  Future<String?> _cachedAttachmentText(String path) {
    return _attachmentTextFutures.putIfAbsent(path, () async {
      final bytes = await _cachedAttachmentBytes(path);
      if (bytes == null) return null;
      return utf8.decode(bytes, allowMalformed: true);
    });
  }

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

  Widget _buildInlinePdfPreview(
    Uint8List bytes, {
    Object? identity,
  }) {
    return InlinePdfPreview(
      key: identity == null ? null : ValueKey('inline-pdf-$identity'),
      pdfBytes: bytes,
    );
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

  void _showEditorSyncMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _currentEditorContent() {
    return jsonEncode(
      _sanitizeDeltaOperations(_quillController.document.toDelta().toJson()),
    );
  }

  bool _hasUnsavedLocalEditorChanges() {
    if (_note == null) {
      return false;
    }
    return _currentEditorContent() != _normalizedStoredContent(_note!.content);
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
              leading: Icon(
                widget.isSideBySideOpen
                    ? Icons.close
                    : Icons.splitscreen_outlined,
              ),
              title: Text(
                widget.isSideBySideOpen
                    ? 'Close side by side'
                    : 'Open side by side',
              ),
              onTap: () {
                Navigator.pop(context);
                if (_note == null) return;
                if (widget.onSideBySideAction != null) {
                  widget.onSideBySideAction!.call();
                  return;
                }
                AppRouter.openSplitEditor(
                  this.context,
                  primaryNoteId: _note!.id,
                  initialSecondaryFolderId: _note!.folderId ?? widget.folderId,
                  replaceCurrent: true,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Search and replace'),
              subtitle: const Text('Find, replace, or format repeated text'),
              onTap: () {
                Navigator.pop(context);
                _openSearchPanel();
              },
            ),
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

  void _insertTable() {
    final selection = _quillController.selection;
    final baseOffset = selection.baseOffset < 0 ? 0 : selection.baseOffset;
    final extentOffset =
        selection.extentOffset < 0 ? baseOffset : selection.extentOffset;
    final insertOffset = baseOffset <= extentOffset ? baseOffset : extentOffset;
    final replaceLength = (baseOffset - extentOffset).abs();
    final table = TypeSyncTableData.empty();

    _quillController.replaceText(
      insertOffset,
      selection.isValid ? replaceLength : 0,
      TypeSyncTableEmbed.toBlockEmbed(table),
      TextSelection.collapsed(offset: insertOffset + 1),
    );

    _focusNode.requestFocus();
  }

  void _insertKanban() {
    final selection = _quillController.selection;
    final baseOffset = selection.baseOffset < 0 ? 0 : selection.baseOffset;
    final extentOffset =
        selection.extentOffset < 0 ? baseOffset : selection.extentOffset;
    final insertOffset = baseOffset <= extentOffset ? baseOffset : extentOffset;
    final replaceLength = (baseOffset - extentOffset).abs();
    final board = TypeSyncKanbanData.empty();

    _quillController.replaceText(
      insertOffset,
      selection.isValid ? replaceLength : 0,
      TypeSyncKanbanEmbed.toBlockEmbed(board),
      TextSelection.collapsed(offset: insertOffset + 1),
    );

    unawaited(
      _markCurrentNoteRequiresVersion(
        TypeSyncKanbanEmbed.minimumSupportedAppVersion,
      ),
    );
    _focusNode.requestFocus();
  }

  void _showTagDialog() {
    if (_note == null) return;

    final tagsProvider = context.read<TagsProvider>();
    final notesProvider = context.read<NotesProvider>();
    final authService = context.read<AuthService>();
    final userId = authService.storageUserId;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return _TagDialogContent(
          note: _note!,
          tagsProvider: tagsProvider,
          notesProvider: notesProvider,
          userId: userId,
          onUpdated: () {
            if (mounted) setState(() {});
          },
        );
      },
    );
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
          content = RichTextPlainTextService.extractPlainText(_note!.content);
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
      _attachmentsExpanded = true;
      _hideAttachmentPreview = false;
    });
    unawaited(_persistAttachmentPreferences());

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
          note = note.copyWith(
            pdfPath: remotePath,
            size: note.size > 0 ? note.size : await file.length(),
          );
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
      final normalizedContent = _normalizedStoredContent(providerNote.content);
      final delta =
          Delta.fromJson(jsonDecode(normalizedContent) as List<dynamic>);
      final hadFocus = _focusNode.hasFocus;
      final selection = _quillController.selection;
      final nextDocument = Document.fromDelta(delta);

      setState(() {
        _isUpdatingFromExternal = true;
        _replaceQuillControllerDocument(
          nextDocument,
          preferredSelection: hadFocus ? selection : null,
        );

        _note = providerNote;
        _lastSavedContent = normalizedContent;
        _characterCount = providerNote.characterCount;
        _lineCount = providerNote.lineCount;
        _syncTitleField(providerNote.title);

        _isUpdatingFromExternal = false;
      });
    } catch (e) {
      final document = Document()..insert(0, providerNote.content);
      final hadFocus = _focusNode.hasFocus;
      final selection = _quillController.selection;
      setState(() {
        _isUpdatingFromExternal = true;
        _replaceQuillControllerDocument(
          document,
          preferredSelection: hadFocus ? selection : null,
        );
        _note = providerNote;
        _lastSavedContent = providerNote.content;
        _characterCount = providerNote.characterCount;
        _lineCount = providerNote.lineCount;
        _syncTitleField(providerNote.title);
        _isUpdatingFromExternal = false;
      });
      debugPrint('Error updating from external source: $e');
    }
  }

  void _replaceQuillControllerDocument(
    Document document, {
    TextSelection? preferredSelection,
  }) {
    final previousController = _quillController;
    final nextController = QuillController(
      document: document,
      selection: _selectionWithinDocument(
        document,
        preferredSelection ?? previousController.selection,
      ),
    );
    nextController.addListener(_onContentChanged);
    previousController.removeListener(_onContentChanged);
    _quillController = nextController;
    previousController.dispose();
  }

  TextSelection _selectionWithinDocument(
    Document document,
    TextSelection selection,
  ) {
    final maxOffset = document.length > 0 ? document.length - 1 : 0;

    int clampOffset(int value) {
      if (value < 0) return 0;
      return value.clamp(0, maxOffset).toInt();
    }

    if (!selection.isValid) {
      return TextSelection.collapsed(offset: clampOffset(0));
    }

    return TextSelection(
      baseOffset: clampOffset(selection.baseOffset),
      extentOffset: clampOffset(selection.extentOffset),
    );
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

/// Dialog for adding / removing tags on a note.
class _TagDialogContent extends StatefulWidget {
  const _TagDialogContent({
    required this.note,
    required this.tagsProvider,
    required this.notesProvider,
    required this.userId,
    required this.onUpdated,
  });

  final Note note;
  final TagsProvider tagsProvider;
  final NotesProvider notesProvider;
  final String? userId;
  final VoidCallback onUpdated;

  @override
  State<_TagDialogContent> createState() => _TagDialogContentState();
}

class _TagDialogContentState extends State<_TagDialogContent> {
  final TextEditingController _controller = TextEditingController();
  late List<String> _currentTagIds;

  @override
  void initState() {
    super.initState();
    _currentTagIds = List<String>.from(widget.note.tags);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _addTag(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || widget.userId == null) return;

    final tag = await widget.tagsProvider.findOrCreateTag(
      userId: widget.userId!,
      name: trimmed,
    );
    if (tag == null) return;

    if (!_currentTagIds.contains(tag.id)) {
      await widget.notesProvider.addTag(widget.note.id, tag.id);
      setState(() {
        _currentTagIds.add(tag.id);
      });
      widget.onUpdated();
    }
    _controller.clear();
  }

  Future<void> _removeTag(String tagId) async {
    await widget.notesProvider.removeTag(widget.note.id, tagId);
    setState(() {
      _currentTagIds.remove(tagId);
    });
    widget.onUpdated();
  }

  @override
  Widget build(BuildContext context) {
    final allTags = widget.tagsProvider.tags;
    final assignedTags =
        allTags.where((t) => _currentTagIds.contains(t.id)).toList();
    final unassignedTags =
        allTags.where((t) => !_currentTagIds.contains(t.id)).toList();

    // Filter unassigned tags by the current text input
    final query = _controller.text.trim().toLowerCase();
    final filteredUnassigned = query.isEmpty
        ? unassignedTags
        : unassignedTags
            .where((t) => t.name.toLowerCase().contains(query))
            .toList();

    final showCreateOption =
        query.isNotEmpty && !allTags.any((t) => t.name.toLowerCase() == query);

    return AlertDialog(
      title: const Text('Tags'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Text field for adding new tags
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Add a tag...',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _addTag(_controller.text),
                ),
                border: const OutlineInputBorder(),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onSubmitted: _addTag,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),

            // Current tags on this note
            if (assignedTags.isNotEmpty) ...[
              Text(
                'Current tags',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: assignedTags.map((tag) {
                  return Chip(
                    label: Text(tag.name),
                    backgroundColor: _parseColor(tag.color),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => _removeTag(tag.id),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],

            // "Create new" option
            if (showCreateOption)
              ListTile(
                dense: true,
                leading: const Icon(Icons.add_circle_outline, size: 20),
                title: Text('Create "$query"'),
                onTap: () => _addTag(_controller.text),
              ),

            // Existing unassigned tags to pick from
            if (filteredUnassigned.isNotEmpty) ...[
              Text(
                'Available tags',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: filteredUnassigned.map((tag) {
                      return ActionChip(
                        label: Text(tag.name),
                        backgroundColor:
                            _parseColor(tag.color)?.withValues(alpha: 0.3),
                        onPressed: () async {
                          await widget.notesProvider
                              .addTag(widget.note.id, tag.id);
                          setState(() {
                            _currentTagIds.add(tag.id);
                          });
                          widget.onUpdated();
                        },
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Color? _parseColor(String hex) {
    try {
      final colorHex = hex.replaceFirst('#', '');
      if (colorHex.length == 6) {
        return Color(int.parse('FF$colorHex', radix: 16));
      }
      if (colorHex.length == 8) {
        return Color(int.parse(colorHex, radix: 16));
      }
    } catch (_) {}
    return null;
  }
}
