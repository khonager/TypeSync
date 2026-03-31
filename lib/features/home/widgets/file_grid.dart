/// File Grid Widget
///
/// Displays notes/files in a grid layout.
library;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../core/models/note.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/color_utils.dart';

int _noteTotalBytes(Note note) {
  var total = note.size;
  for (final attachment in note.attachments) {
    total += attachment.size;
  }
  return total;
}

String _formatBytes(int bytes) {
  if (bytes < 1000) return '$bytes B';
  if (bytes < 1000 * 1000) return '${(bytes / 1000).toStringAsFixed(1)} KB';
  if (bytes < 1000 * 1000 * 1000) {
    return '${(bytes / (1000 * 1000)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1000 * 1000 * 1000)).toStringAsFixed(2)} GB';
}

/// Grid view for files/notes
class FileGrid extends StatelessWidget {
  final List<Note> notes;
  final void Function(String) onNoteTap;
  final void Function(String) onNoteLongPress;
  final bool useLongPressDrag;
  final VoidCallback? onDragStarted;
  final ValueChanged<Offset>? onDragPositionChanged;
  final VoidCallback? onDragEnded;

  const FileGrid({
    required this.notes,
    required this.onNoteTap,
    required this.onNoteLongPress,
    this.useLongPressDrag = false,
    this.onDragStarted,
    this.onDragPositionChanged,
    this.onDragEnded,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => FileGridItem(
          key: ValueKey('${notes[index].id}-${notes[index].backgroundColor}'),
          note: notes[index],
          onTap: () => onNoteTap(notes[index].id),
          onLongPress: () => onNoteLongPress(notes[index].id),
          useLongPressDrag: useLongPressDrag,
          onDragStarted: onDragStarted,
          onDragPositionChanged: onDragPositionChanged,
          onDragEnded: onDragEnded,
        ),
        childCount: notes.length,
      ),
    );
  }
}

/// Individual file item in grid
class FileGridItem extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool useLongPressDrag;
  final VoidCallback? onDragStarted;
  final ValueChanged<Offset>? onDragPositionChanged;
  final VoidCallback? onDragEnded;

  const FileGridItem({
    required this.note,
    required this.onTap,
    required this.onLongPress,
    this.useLongPressDrag = false,
    this.onDragStarted,
    this.onDragPositionChanged,
    this.onDragEnded,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // Get icon based on note type
    IconData icon;
    switch (note.type) {
      case NoteType.pdf:
        icon = Icons.picture_as_pdf;
        break;
      case NoteType.markdown:
        icon = Icons.code;
        break;
      default:
        icon = Icons.description_outlined;
    }

    final bgColor = note.backgroundColor != null
        ? Color(int.parse(note.backgroundColor!.replaceFirst('#', '0xFF')))
        : AppTheme.darkSurface;

    final iconColor = AppColorPalette.getIconColor(bgColor);
    final textColor = AppColorPalette.getContrastingTextColor(bgColor);
    final child = _buildFileContent(
      context,
      icon: icon,
      textColor: textColor,
      iconColor: Colors.white54,
    );
    final childWhenDragging = Opacity(
      opacity: 0.3,
      child: _buildFileContent(
        context,
        icon: icon,
        textColor: textColor,
        iconColor: iconColor,
      ),
    );
    final feedback = Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 48, color: iconColor),
      ),
    );

    if (useLongPressDrag) {
      return LongPressDraggable<String>(
        data: 'note:${note.id}',
        feedback: feedback,
        childWhenDragging: childWhenDragging,
        onDragStarted: onDragStarted,
        onDragUpdate: (details) =>
            onDragPositionChanged?.call(details.globalPosition),
        onDragEnd: (_) => onDragEnded?.call(),
        child: child,
      );
    }

    return Draggable<String>(
      data: 'note:${note.id}',
      feedback: feedback,
      childWhenDragging: childWhenDragging,
      onDragStarted: onDragStarted,
      onDragUpdate: (details) =>
          onDragPositionChanged?.call(details.globalPosition),
      onDragEnd: (_) => onDragEnded?.call(),
      child: child,
    );
  }

  Widget _buildFileContent(
    BuildContext context, {
    required IconData icon,
    required Color textColor,
    required Color iconColor,
  }) {
    final attachmentCount = note.attachments.length;

    return GestureDetector(
      onTap: onTap,
      onLongPress: useLongPressDrag && _isMobilePlatform() ? null : onLongPress,
      onSecondaryTap: onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: note.backgroundColor != null
                    ? Color(
                        int.parse(
                          note.backgroundColor!.replaceFirst('#', '0xFF'),
                        ),
                      )
                    : AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Icon(
                      icon,
                      size: 48,
                      color: iconColor,
                    ),
                  ),
                  if (note.isFavorite)
                    const Positioned(
                      top: 8,
                      right: 8,
                      child: Icon(
                        Icons.star,
                        size: 16,
                        color: Colors.amber,
                      ),
                    ),
                  if (note.localOnly)
                    const Positioned(
                      top: 8,
                      left: 8,
                      child: Icon(
                        Icons.cloud_off_outlined,
                        size: 14,
                        color: Colors.orangeAccent,
                      ),
                    ),
                  if (attachmentCount > 0)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: _CountBadge(
                        icon: Icons.attach_file,
                        label: '$attachmentCount',
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            note.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: textColor,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  bool _isMobilePlatform() {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
}

/// List view for files/notes
class FileList extends StatelessWidget {
  final List<Note> notes;
  final void Function(String) onNoteTap;
  final void Function(String) onNoteLongPress;

  const FileList({
    required this.notes,
    required this.onNoteTap,
    required this.onNoteLongPress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => FileListItem(
          note: notes[index],
          onTap: () => onNoteTap(notes[index].id),
          onLongPress: () => onNoteLongPress(notes[index].id),
        ),
        childCount: notes.length,
      ),
    );
  }
}

/// Individual file item in list
class FileListItem extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const FileListItem({
    required this.note,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, y');

    IconData icon;
    switch (note.type) {
      case NoteType.pdf:
        icon = Icons.picture_as_pdf;
        break;
      case NoteType.markdown:
        icon = Icons.code;
        break;
      default:
        icon = Icons.description_outlined;
    }

    final bgColor = note.backgroundColor != null
        ? Color(int.parse(note.backgroundColor!.replaceFirst('#', '0xFF')))
        : AppTheme.darkSurface;

    final iconColor = AppColorPalette.getIconColor(bgColor);
    final textColor = AppColorPalette.getContrastingTextColor(bgColor);
    final attachmentCount = note.attachments.length;
    final totalBytes = _noteTotalBytes(note);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          onSecondaryTap: onLongPress,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // File icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: note.backgroundColor != null
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: iconColor),
                ),
                const SizedBox(width: 16),
                // File info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              note.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: textColor,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (attachmentCount > 0)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _CountBadge(
                                icon: Icons.attach_file,
                                label: '$attachmentCount',
                              ),
                            ),
                          if (note.isFavorite)
                            const Icon(
                              Icons.star,
                              size: 16,
                              color: Colors.amber,
                            ),
                          if (note.localOnly)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(
                                Icons.cloud_off_outlined,
                                size: 16,
                                color: Colors.orangeAccent,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${dateFormat.format(note.updatedAt)} • ${_formatBytes(totalBytes)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: textColor.withValues(alpha: 0.7),
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _CountBadge({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
