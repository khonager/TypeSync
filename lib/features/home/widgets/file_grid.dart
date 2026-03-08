/// File Grid Widget
///
/// Displays notes/files in a grid layout.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/models/note.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/color_utils.dart';

/// Grid view for files/notes
class FileGrid extends StatelessWidget {
  final List<Note> notes;
  final void Function(String) onNoteTap;
  final void Function(String) onNoteLongPress;

  const FileGrid({
    required this.notes,
    required this.onNoteTap,
    required this.onNoteLongPress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => FileGridItem(
          key: ValueKey('${notes[index].id}-${notes[index].backgroundColor}'),
          note: notes[index],
          onTap: () => onNoteTap(notes[index].id),
          onLongPress: () => onNoteLongPress(notes[index].id),
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

  const FileGridItem({
    required this.note,
    required this.onTap,
    required this.onLongPress,
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

    return Draggable<String>(
      data: 'note:${note.id}',
      feedback: Material(
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
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // File icon container
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
                      // File icon
                      Center(
                        child: Icon(
                          icon,
                          size: 48,
                          color: iconColor,
                        ),
                      ),
                      // Favorite indicator
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
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // File name
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
        ),
      ),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // File icon container
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
                    // File icon
                    Center(
                      child: Icon(
                        icon,
                        size: 48,
                        color: Colors.white54,
                      ),
                    ),
                    // Favorite indicator
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // File name
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
      ),
    );
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
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
                        dateFormat.format(note.updatedAt),
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
