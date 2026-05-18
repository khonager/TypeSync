library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/note.dart';
import '../../../core/providers/notes_provider.dart';
import 'editor_screen.dart';

class SplitEditorScreen extends StatefulWidget {
  const SplitEditorScreen({
    required this.primaryNoteId,
    this.secondaryNoteId,
    super.key,
  });

  final String primaryNoteId;
  final String? secondaryNoteId;

  @override
  State<SplitEditorScreen> createState() => _SplitEditorScreenState();
}

class _SplitEditorScreenState extends State<SplitEditorScreen> {
  late String _primaryNoteId;
  String? _secondaryNoteId;
  double _primaryPaneFraction = 0.5;

  @override
  void initState() {
    super.initState();
    _primaryNoteId = widget.primaryNoteId;
    _secondaryNoteId = widget.secondaryNoteId;
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Side by Side'),
        actions: [
          if (secondaryNote != null)
            IconButton(
              tooltip: 'Swap panes',
              onPressed: _swapPanes,
              icon: const Icon(Icons.swap_horiz),
            ),
          IconButton(
            tooltip: secondaryNote == null ? 'Choose second note' : 'Replace second note',
            onPressed: _pickSecondaryNote,
            icon: const Icon(Icons.add_to_photos_outlined),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isStacked = constraints.maxWidth < 980;
          if (isStacked) {
            return Column(
              children: [
                Expanded(
                  child: _SplitPane(
                    label: 'Left',
                    note: primaryNote,
                    child: EditorScreen(
                      key: ValueKey('split-primary-${primaryNote.id}'),
                      noteId: primaryNote.id,
                      embedded: true,
                      onOpenSideBySide: _pickSecondaryNote,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: secondaryNote == null
                      ? _EmptySplitPane(onPickNote: _pickSecondaryNote)
                      : _SplitPane(
                          label: 'Right',
                          note: secondaryNote,
                          trailing: IconButton(
                            tooltip: 'Close right pane',
                            onPressed: () {
                              setState(() {
                                _secondaryNoteId = null;
                              });
                            },
                            icon: const Icon(Icons.close),
                          ),
                          child: EditorScreen(
                            key: ValueKey('split-secondary-${secondaryNote.id}'),
                            noteId: secondaryNote.id,
                            embedded: true,
                            onOpenSideBySide: _pickSecondaryNote,
                          ),
                        ),
                ),
              ],
            );
          }

          const handleWidth = 18.0;
          final availableWidth = (constraints.maxWidth - handleWidth).clamp(
            0.0,
            double.infinity,
          );
          final primaryWidth =
              (availableWidth * _primaryPaneFraction).clamp(320.0, availableWidth - 320.0);
          final secondaryWidth = availableWidth - primaryWidth;

          return Row(
            children: [
              SizedBox(
                width: primaryWidth,
                child: _SplitPane(
                  label: 'Left',
                  note: primaryNote,
                  child: EditorScreen(
                    key: ValueKey('split-primary-${primaryNote.id}'),
                    noteId: primaryNote.id,
                    embedded: true,
                    onOpenSideBySide: _pickSecondaryNote,
                  ),
                ),
              ),
              _ResizeHandle(
                onDrag: (delta) {
                  if (availableWidth <= 0) return;
                  setState(() {
                    final nextWidth = primaryWidth + delta;
                    _primaryPaneFraction =
                        (nextWidth / availableWidth).clamp(0.28, 0.72);
                  });
                },
              ),
              SizedBox(
                width: secondaryWidth,
                child: secondaryNote == null
                    ? _EmptySplitPane(onPickNote: _pickSecondaryNote)
                    : _SplitPane(
                        label: 'Right',
                        note: secondaryNote,
                        trailing: IconButton(
                          tooltip: 'Close right pane',
                          onPressed: () {
                            setState(() {
                              _secondaryNoteId = null;
                            });
                          },
                          icon: const Icon(Icons.close),
                        ),
                        child: EditorScreen(
                          key: ValueKey('split-secondary-${secondaryNote.id}'),
                          noteId: secondaryNote.id,
                          embedded: true,
                          onOpenSideBySide: _pickSecondaryNote,
                        ),
                      ),
              ),
            ],
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

  Future<void> _pickSecondaryNote() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _SplitNotePickerDialog(
        excludedIds: {
          _primaryNoteId,
          if (_secondaryNoteId != null) _secondaryNoteId!,
        },
      ),
    );

    if (!mounted || selected == null) return;
    setState(() {
      _secondaryNoteId = selected;
    });
  }
}

class _SplitPane extends StatelessWidget {
  const _SplitPane({
    required this.label,
    required this.note,
    required this.child,
    this.trailing,
  });

  final String label;
  final Note note;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
            border: Border(
              bottom: BorderSide(
                color: colors.outline.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: Row(
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  note.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _EmptySplitPane extends StatelessWidget {
  const _EmptySplitPane({
    required this.onPickNote,
  });

  final VoidCallback onPickNote;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chrome_reader_mode_outlined,
                size: 42,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                'Open another note here',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Pick a second note to compare, copy, or edit side by side.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onPickNote,
                icon: const Icon(Icons.add),
                label: const Text('Choose note'),
              ),
            ],
          ),
        ),
      ),
    );
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

class _SplitNotePickerDialog extends StatefulWidget {
  const _SplitNotePickerDialog({
    required this.excludedIds,
  });

  final Set<String> excludedIds;

  @override
  State<_SplitNotePickerDialog> createState() => _SplitNotePickerDialogState();
}

class _SplitNotePickerDialogState extends State<_SplitNotePickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notesProvider = context.watch<NotesProvider>();
    final normalizedQuery = _query.trim().toLowerCase();
    final notes = notesProvider.notes.where((note) {
      if (widget.excludedIds.contains(note.id)) return false;
      if (normalizedQuery.isEmpty) return true;
      return note.title.toLowerCase().contains(normalizedQuery);
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return AlertDialog(
      title: const Text('Choose second note'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search notes',
              ),
              onChanged: (value) {
                setState(() {
                  _query = value;
                });
              },
            ),
            const SizedBox(height: 12),
            Flexible(
              child: notes.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('No matching notes'),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: notes.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final note = notes[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            note.title.isEmpty ? 'Untitled' : note.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            'Updated ${MaterialLocalizations.of(context).formatShortDate(note.updatedAt)}',
                          ),
                          onTap: () => Navigator.pop(context, note.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
