/// Folder Grid Widget
///
/// Displays folders in a grid layout matching the design.
library;

import 'package:flutter/material.dart';

import '../../../core/models/folder.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/color_utils.dart';

class FolderVisualStats {
  final int recursiveFileCount;
  final int directFileCount;
  final int directSubfolderCount;
  final int totalBytes;

  const FolderVisualStats({
    required this.recursiveFileCount,
    required this.directFileCount,
    required this.directSubfolderCount,
    required this.totalBytes,
  });
}

/// Grid view for folders
class FolderGrid extends StatelessWidget {
  final List<Folder> folders;
  final Map<String, FolderVisualStats> folderStats;
  final void Function(String) onFolderTap;
  final void Function(String) onFolderLongPress;
  final void Function(String noteId, String folderId)? onNoteDropped;
  final void Function(String folderId, String? newParentId)? onFolderDropped;
  final bool useLongPressDrag;
  final VoidCallback? onDragStarted;
  final ValueChanged<Offset>? onDragPositionChanged;
  final VoidCallback? onDragEnded;

  const FolderGrid({
    required this.folders,
    required this.folderStats,
    required this.onFolderTap,
    required this.onFolderLongPress,
    super.key,
    this.onNoteDropped,
    this.onFolderDropped,
    this.useLongPressDrag = false,
    this.onDragStarted,
    this.onDragPositionChanged,
    this.onDragEnded,
  });

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => FolderGridItem(
          folder: folders[index],
          stats: folderStats[folders[index].id] ??
              const FolderVisualStats(
                recursiveFileCount: 0,
                directFileCount: 0,
                directSubfolderCount: 0,
                totalBytes: 0,
              ),
          onTap: () => onFolderTap(folders[index].id),
          onLongPress: () => onFolderLongPress(folders[index].id),
          onNoteDropped: onNoteDropped,
          onFolderDropped: onFolderDropped,
          useLongPressDrag: useLongPressDrag,
          onDragStarted: onDragStarted,
          onDragPositionChanged: onDragPositionChanged,
          onDragEnded: onDragEnded,
        ),
        childCount: folders.length,
      ),
    );
  }
}

/// Individual folder item in grid
class FolderGridItem extends StatelessWidget {
  final Folder folder;
  final FolderVisualStats stats;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final void Function(String noteId, String folderId)? onNoteDropped;
  final void Function(String folderId, String? newParentId)? onFolderDropped;
  final bool useLongPressDrag;
  final VoidCallback? onDragStarted;
  final ValueChanged<Offset>? onDragPositionChanged;
  final VoidCallback? onDragEnded;

  const FolderGridItem({
    required this.folder,
    required this.stats,
    required this.onTap,
    required this.onLongPress,
    super.key,
    this.onNoteDropped,
    this.onFolderDropped,
    this.useLongPressDrag = false,
    this.onDragStarted,
    this.onDragPositionChanged,
    this.onDragEnded,
  });

  @override
  Widget build(BuildContext context) {
    // Parse background color if set
    final bgColor = folder.backgroundColor != null
        ? Color(
            int.parse(folder.backgroundColor!.replaceFirst('#', '0xFF')),
          )
        : AppTheme.folderDefault;

    final child = DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          details.data != 'folder:${folder.id}',
      onAcceptWithDetails: (details) {
        final data = details.data;
        if (data.startsWith('note:')) {
          final noteId = data.substring(5);
          onNoteDropped?.call(noteId, folder.id);
        } else if (data.startsWith('folder:')) {
          final folderId = data.substring(7);
          onFolderDropped?.call(folderId, folder.id);
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isDragOver = candidateData.isNotEmpty;
        return _buildFolderContent(
          context,
          isDragOver
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
              : bgColor,
          showBorder: isDragOver,
        );
      },
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
        child: const Icon(Icons.folder, size: 48, color: Colors.white54),
      ),
    );
    final childWhenDragging = Opacity(
      opacity: 0.3,
      child: _buildFolderContent(context, bgColor),
    );

    if (useLongPressDrag) {
      return LongPressDraggable<String>(
        data: 'folder:${folder.id}',
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
      data: 'folder:${folder.id}',
      feedback: feedback,
      childWhenDragging: childWhenDragging,
      onDragStarted: onDragStarted,
      onDragUpdate: (details) =>
          onDragPositionChanged?.call(details.globalPosition),
      onDragEnd: (_) => onDragEnded?.call(),
      child: child,
    );
  }

  Widget _buildFolderContent(
    BuildContext context,
    Color bgColor, {
    bool showBorder = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      // Allow a stationary long-press to open the options sheet even when
      // long-press drag is enabled; dragging still begins once the pointer
      // moves after the long-press delay.
      onLongPress: onLongPress,
      onSecondaryTap: onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Folder icon container
          AspectRatio(
            aspectRatio: 1,
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
              child: Stack(
                children: [
                  Center(
                    child: Icon(
                      showBorder ? Icons.folder_open : Icons.folder,
                      size: 48,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  if (stats.recursiveFileCount > 0)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: _FolderCountBadge(
                        label: '${stats.recursiveFileCount}',
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Folder name
          Text(
            folder.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: folder.backgroundColor != null
                      ? AppColorPalette.getContrastingTextColor(bgColor)
                      : null,
                ),
            textAlign: TextAlign.center,
          ),
          // Subtitle if present
          if (folder.subtitle != null && folder.subtitle!.isNotEmpty)
            Text(
              folder.subtitle!,
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
  final Map<String, FolderVisualStats> folderStats;
  final void Function(String) onFolderTap;
  final void Function(String) onFolderLongPress;

  const FolderList({
    required this.folders,
    required this.folderStats,
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
          stats: folderStats[folders[index].id] ??
              const FolderVisualStats(
                recursiveFileCount: 0,
                directFileCount: 0,
                directSubfolderCount: 0,
                totalBytes: 0,
              ),
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
  final FolderVisualStats stats;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const FolderListItem({
    required this.folder,
    required this.stats,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = folder.backgroundColor != null
        ? Color(int.parse(folder.backgroundColor!.replaceFirst('#', '0xFF')))
        : AppTheme.darkSurface;
    final textColor = AppColorPalette.getContrastingTextColor(bgColor);
    final secondaryTextColor = textColor.withValues(alpha: 0.7);

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
                // Folder icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: folder.backgroundColor != null
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.folder,
                    color: textColor.withValues(alpha: 0.7),
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
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(color: textColor),
                      ),
                      Text(
                        '${stats.recursiveFileCount} files • ${_formatBytes(stats.totalBytes)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: secondaryTextColor,
                            ),
                      ),
                      if (folder.subtitle != null &&
                          folder.subtitle!.isNotEmpty)
                        Text(
                          folder.subtitle!,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: secondaryTextColor,
                                  ),
                        ),
                    ],
                  ),
                ),
                if (stats.recursiveFileCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _FolderCountBadge(
                      label: '${stats.recursiveFileCount}',
                    ),
                  ),
                // Arrow indicator
                Icon(
                  Icons.chevron_right,
                  color: secondaryTextColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1000) return '$bytes B';
    if (bytes < 1000 * 1000) return '${(bytes / 1000).toStringAsFixed(1)} KB';
    if (bytes < 1000 * 1000 * 1000) {
      return '${(bytes / (1000 * 1000)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1000 * 1000 * 1000)).toStringAsFixed(2)} GB';
  }
}

class _FolderCountBadge extends StatelessWidget {
  final String label;

  const _FolderCountBadge({
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
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
