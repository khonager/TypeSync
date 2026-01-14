/// File Browser Dialog
///
/// A cross-platform file and directory browser dialog that works
/// on all platforms without requiring zenity or other external tools.
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// File browser dialog for selecting files or directories
class FileBrowserDialog extends StatefulWidget {
  final String? initialPath;
  final bool selectDirectory;
  final String? dialogTitle;
  final List<String>? allowedExtensions;

  const FileBrowserDialog({
    super.key,
    this.initialPath,
    this.selectDirectory = false,
    this.dialogTitle,
    this.allowedExtensions,
  });

  /// Show file browser dialog
  static Future<String?> show({
    required BuildContext context,
    String? initialPath,
    bool selectDirectory = false,
    String? dialogTitle,
    List<String>? allowedExtensions,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (context) => FileBrowserDialog(
        initialPath: initialPath,
        selectDirectory: selectDirectory,
        dialogTitle: dialogTitle,
        allowedExtensions: allowedExtensions,
      ),
    );
  }

  @override
  State<FileBrowserDialog> createState() => _FileBrowserDialogState();
}

class _FileBrowserDialogState extends State<FileBrowserDialog> {
  Directory? _currentDirectory;
  List<FileSystemEntity> _items = [];
  bool _isLoading = false;
  String? _errorMessage;
  final TextEditingController _pathController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeDirectory();
  }

  Future<void> _initializeDirectory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      Directory? startDir;

      if (widget.initialPath != null) {
        startDir = Directory(widget.initialPath!);
        if (!await startDir.exists()) {
          startDir = null;
        }
      }

      if (startDir == null) {
        // Get default directory based on platform
        if (Platform.isLinux || Platform.isMacOS) {
          startDir = Directory(Platform.environment['HOME'] ?? '/');
        } else if (Platform.isWindows) {
          startDir = Directory(Platform.environment['USERPROFILE'] ?? 'C:\\');
        } else {
          // Mobile platforms
          final appDir = await getApplicationDocumentsDirectory();
          startDir = appDir.parent;
        }
      }

      _currentDirectory = startDir;
      _pathController.text = startDir.path;
      await _loadDirectory(startDir);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load directory: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadDirectory(Directory dir) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = <FileSystemEntity>[];

      await for (final entity in dir.list()) {
        // Filter by extension if specified
        if (widget.allowedExtensions != null && entity is File) {
          final ext = path.extension(entity.path).toLowerCase();
          if (!widget.allowedExtensions!.any((e) => ext == '.$e')) {
            continue;
          }
        }

        items.add(entity);
      }

      // Sort: directories first, then files, both alphabetically
      items.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir != bIsDir) {
          return aIsDir ? -1 : 1;
        }
        return path.basename(a.path).toLowerCase().compareTo(
              path.basename(b.path).toLowerCase(),
            );
      });

      setState(() {
        _items = items;
        _currentDirectory = dir;
        _pathController.text = dir.path;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load directory: $e';
        _isLoading = false;
      });
    }
  }

  void _navigateTo(Directory dir) {
    _loadDirectory(dir);
  }

  void _navigateUp() {
    if (_currentDirectory != null) {
      final parent = _currentDirectory!.parent;
      if (parent.path != _currentDirectory!.path) {
        _loadDirectory(parent);
      }
    }
  }

  void _navigateToPath() {
    final newPath = _pathController.text.trim();
    if (newPath.isNotEmpty) {
      final dir = Directory(newPath);
      if (dir.existsSync()) {
        _loadDirectory(dir);
      } else {
        setState(() {
          _errorMessage = 'Directory does not exist';
        });
      }
    }
  }

  void _selectItem(FileSystemEntity entity) {
    if (entity is Directory) {
      if (widget.selectDirectory) {
        Navigator.pop(context, entity.path);
      } else {
        _navigateTo(entity);
      }
    } else if (entity is File) {
      if (!widget.selectDirectory) {
        Navigator.pop(context, entity.path);
      }
    }
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.dialogTitle ??
                          (widget.selectDirectory
                              ? 'Select Directory'
                              : 'Select File'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Path bar
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: _currentDirectory != null ? _navigateUp : null,
                    tooltip: 'Go up',
                  ),
                  Expanded(
                    child: TextField(
                      controller: _pathController,
                      decoration: const InputDecoration(
                        hintText: 'Enter path...',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      onSubmitted: (_) => _navigateToPath(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _currentDirectory != null
                        ? () => _loadDirectory(_currentDirectory!)
                        : null,
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ),

            // Error message
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(8),
                color: Theme.of(context).colorScheme.errorContainer,
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // File list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.folder_open,
                                size: 64,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.3),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'This folder is empty',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withOpacity(0.6),
                                    ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            final isDirectory = item is Directory;
                            final isFile = item is File;
                            final name = path.basename(item.path);
                            final isSelectable =
                                widget.selectDirectory ? isDirectory : isFile;

                            return ListTile(
                              leading: Icon(
                                isDirectory ? Icons.folder : Icons.description,
                                color: isDirectory ? Colors.blue : Colors.grey,
                              ),
                              title: Text(name),
                              subtitle: isFile
                                  ? Text(
                                      _formatFileSize(item),
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    )
                                  : null,
                              trailing: isDirectory && !widget.selectDirectory
                                  ? const Icon(Icons.chevron_right)
                                  : null,
                              onTap: isSelectable
                                  ? () => _selectItem(item)
                                  : isDirectory
                                      ? () => _navigateTo(item)
                                      : null,
                            );
                          },
                        ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  if (widget.selectDirectory && _currentDirectory != null)
                    ElevatedButton(
                      onPressed: () =>
                          Navigator.pop(context, _currentDirectory!.path),
                      child: const Text('Select Folder'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatFileSize(File file) {
    try {
      final size = file.lengthSync();
      if (size < 1024) {
        return '$size B';
      } else if (size < 1024 * 1024) {
        return '${(size / 1024).toStringAsFixed(1)} KB';
      } else if (size < 1024 * 1024 * 1024) {
        return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
      } else {
        return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
      }
    } catch (e) {
      return '';
    }
  }
}
