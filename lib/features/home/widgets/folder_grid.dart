/// Folder Grid Widget
///
/// Displays folders in a grid layout matching the design.
library;

import 'package:flutter/material.dart';

import '../../../core/models/folder.dart';
import '../../../core/theme/app_theme.dart';

/// Grid view for folders
class FolderGrid extends StatelessWidget {
  final List<Folder> folders;
  final Function(String) onFolderTap;
  final Function(String) onFolderLongPress;
  final Function(String noteId, String folderId)? onNoteDropped;
  final Function(String folderId, String? newParentId)? onFolderDropped;

  const FolderGrid({
    required this.folders,
    required this.onFolderTap,
    required this.onFolderLongPress,
    super.key,
    this.onNoteDropped,
    this.onFolderDropped,
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
        (context, index) => FolderGridItem(
          folder: folders[index],
          onTap: () => onFolderTap(folders[index].id),
          onLongPress: () => onFolderLongPress(folders[index].id),
          onNoteDropped: onNoteDropped,
          onFolderDropped: onFolderDropped,
        ),
        childCount: folders.length,
      ),
    );
  }
}

/// Individual folder item in grid
class FolderGridItem extends StatefulWidget {
  final Folder folder;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Function(String noteId, String folderId)? onNoteDropped;
  final Function(String folderId, String? newParentId)? onFolderDropped;

  const FolderGridItem({
    required this.folder,
    required this.onTap,
    required this.onLongPress,
    super.key,
    this.onNoteDropped,
    this.onFolderDropped,
  });

  @override
  State<FolderGridItem> createState() => _FolderGridItemState();
}

class _FolderGridItemState extends State<FolderGridItem> {
  bool _isDragOver = false;

  @override
  Widget build(BuildContext context) {
    // Parse background color if set
    final bgColor = widget.folder.backgroundColor != null
        ? Color(
            int.parse(widget.folder.backgroundColor!.replaceFirst('#', '0xFF')),
          )
        : AppTheme.folderDefault;

    return Draggable<String>(
      data: 'folder:${widget.folder.id}',
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
          child: const Icon(Icons.folder, size: 48, color: Colors.white54),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildFolderContent(bgColor),
      ),
      child: DragTarget<String>(
        onWillAcceptWithDetails: (data) => data != 'folder:${widget.folder.id}',
        onAcceptWithDetails: (data) {
          if (data.startsWith('note:')) {
            final noteId = data.substring(5);
            widget.onNoteDropped?.call(noteId, widget.folder.id);
          } else if (data.startsWith('folder:')) {
            final folderId = data.substring(7);
            widget.onFolderDropped?.call(folderId, widget.folder.id);
          }
          setState(() {
            _isDragOver = false;
          });
        },
        onLeave: (data) {
          setState(() {
            _isDragOver = false;
          });
        },
        onMove: (details) {
          setState(() {
            _isDragOver = true;
          });
        },
        builder: (context, candidateData, rejectedData) {
          return _buildFolderContent(
            _isDragOver
                ? Theme.of(context).colorScheme.primary.withOpacity(0.5)
                : bgColor,
            showBorder: _isDragOver,
          );
        },
      ),
    );
  }

  Widget _buildFolderContent(Color bgColor, {bool showBorder = false}) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Folder icon container
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
                border: showBorder
                    ? Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      )
                    : null,
              ),
              child: Center(
                child: Icon(
                  showBorder ? Icons.folder_open : Icons.folder,
                  size: 48,
                  color: Colors.white54,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Folder name
          Text(
            widget.folder.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          // Subtitle if present
          if (widget.folder.subtitle != null &&
              widget.folder.subtitle!.isNotEmpty)
            Text(
              widget.folder.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                    fontSize: 10,
                  ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}

/// List view for folders
class FolderList extends StatelessWidget {
  final List<Folder> folders;
  final Function(String) onFolderTap;
  final Function(String) onFolderLongPress;

  const FolderList({
    required this.folders,
    required this.onFolderTap,
    required this.onFolderLongPress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => FolderListItem(
          folder: folders[index],
          onTap: () => onFolderTap(folders[index].id),
          onLongPress: () => onFolderLongPress(folders[index].id),
        ),
        childCount: folders.length,
      ),
    );
  }
}

/// Individual folder item in list - matches the widget design (top right in mockup)
class FolderListItem extends StatelessWidget {
  final Folder folder;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const FolderListItem({
    required this.folder,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = folder.backgroundColor != null
        ? Color(int.parse(folder.backgroundColor!.replaceFirst('#', '0xFF')))
        : AppTheme.darkSurface;

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
                // Folder icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.folder,
                    color: Colors.white54,
                  ),
                ),
                const SizedBox(width: 16),
                // Folder name and subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        folder.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (folder.subtitle != null &&
                          folder.subtitle!.isNotEmpty)
                        Text(
                          folder.subtitle!,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey,
                                  ),
                        ),
                    ],
                  ),
                ),
                // Arrow indicator
                const Icon(
                  Icons.chevron_right,
                  color: Colors.grey,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
