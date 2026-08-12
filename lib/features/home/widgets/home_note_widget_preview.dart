/// Rendered preview used by the note-focused Android home widgets.
library;

import 'package:flutter/material.dart';

import '../../../core/models/note.dart';

class HomeNoteWidgetPreview extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Note> notes;
  final String Function(Note note) detailFor;
  final String emptyMessage;
  final ValueChanged<Note>? onNoteTap;

  const HomeNoteWidgetPreview({
    required this.title,
    required this.icon,
    required this.notes,
    required this.detailFor,
    required this.emptyMessage,
    this.onNoteTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: colorScheme.primary),
                const SizedBox(width: 9),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            if (notes.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    emptyMessage,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              for (var index = 0; index < notes.take(4).length; index++)
                _NoteRow(
                  note: notes[index],
                  detail: detailFor(notes[index]),
                  showDivider: index < notes.take(4).length - 1,
                  onTap:
                      onNoteTap == null ? null : () => onNoteTap!(notes[index]),
                ),
          ],
        ),
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  final Note note;
  final String detail;
  final bool showDivider;
  final VoidCallback? onTap;

  const _NoteRow({
    required this.note,
    required this.detail,
    required this.showDivider,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(
                children: [
                  Icon(
                    note.type == NoteType.pdf
                        ? Icons.picture_as_pdf_outlined
                        : Icons.description_outlined,
                    size: 19,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      note.title.trim().isEmpty ? 'Untitled note' : note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    detail,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            color: colorScheme.outline.withValues(alpha: 0.08),
          ),
      ],
    );
  }
}
