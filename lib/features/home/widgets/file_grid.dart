/// File Grid Widget
/// 
/// Displays notes/files in a grid layout.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/models/note.dart';
import '../../../core/theme/app_theme.dart';

/// Grid view for files/notes
class FileGrid extends StatelessWidget {
  final List<Note> notes;
  final Function(String) onNoteTap;
  final Function(String) onNoteLongPress;

  const FileGrid({
    super.key,
    required this.notes,
    required this.onNoteTap,
    required this.onNoteLongPress,
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
    super.key,
    required this.note,
    required this.onTap,
    required this.onLongPress,
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

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // File icon container
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
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
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// List view for files/notes
class FileList extends StatelessWidget {
  final List<Note> notes;
  final Function(String) onNoteTap;
  final Function(String) onNoteLongPress;

  const FileList({
    super.key,
    required this.notes,
    required this.onNoteTap,
    required this.onNoteLongPress,
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
    super.key,
    required this.note,
    required this.onTap,
    required this.onLongPress,
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: AppTheme.darkSurface,
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
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: Colors.white54),
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
                              style: Theme.of(context).textTheme.titleMedium,
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
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateFormat.format(note.updatedAt),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
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

