/// Folder Grid Widget
/// 
/// Displays folders in a grid layout matching the design.

import 'package:flutter/material.dart';

import '../../../core/models/folder.dart';
import '../../../core/theme/app_theme.dart';

/// Grid view for folders
class FolderGrid extends StatelessWidget {
  final List<Folder> folders;
  final Function(String) onFolderTap;
  final Function(String) onFolderLongPress;

  const FolderGrid({
    super.key,
    required this.folders,
    required this.onFolderTap,
    required this.onFolderLongPress,
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
        ),
        childCount: folders.length,
      ),
    );
  }
}

/// Individual folder item in grid
class FolderGridItem extends StatelessWidget {
  final Folder folder;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const FolderGridItem({
    super.key,
    required this.folder,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    // Parse background color if set
    final bgColor = folder.backgroundColor != null
        ? Color(int.parse(folder.backgroundColor!.replaceFirst('#', '0xFF')))
        : AppTheme.folderDefault;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Folder icon container
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Icon(
                  Icons.folder,
                  size: 48,
                  color: Colors.white54,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Folder name
          Text(
            folder.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
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
  final Function(String) onFolderTap;
  final Function(String) onFolderLongPress;

  const FolderList({
    super.key,
    required this.folders,
    required this.onFolderTap,
    required this.onFolderLongPress,
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
    super.key,
    required this.folder,
    required this.onTap,
    required this.onLongPress,
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
                      if (folder.subtitle != null && folder.subtitle!.isNotEmpty)
                        Text(
                          folder.subtitle!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
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

