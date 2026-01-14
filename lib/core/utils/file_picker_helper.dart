/// File Picker Helper
///
/// Provides cross-platform file and directory picking with Linux fallbacks
/// when zenity is not available.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../widgets/file_browser_dialog.dart';

/// Helper class for file picking with Linux fallbacks
class FilePickerHelper {
  /// Pick a file with fallback for Linux
  static Future<String?> pickFile({
    required BuildContext context,
    String? dialogTitle,
    List<String>? allowedExtensions,
  }) async {
    // Try native file picker first
    try {
      final result = await FilePicker.platform.pickFiles(
        type: allowedExtensions != null ? FileType.custom : FileType.any,
        allowedExtensions: allowedExtensions,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        return result.files.single.path;
      }
    } catch (e) {
      // If file_picker fails (e.g., zenity not found on Linux), use custom browser
      debugPrint('File picker failed: $e, using custom browser');
    }

    // Use custom file browser as fallback
    return await FileBrowserDialog.show(
      context: context,
      selectDirectory: false,
      dialogTitle: dialogTitle ?? 'Select File',
      allowedExtensions: allowedExtensions,
    );
  }

  /// Pick a directory with fallback for Linux
  static Future<String?> pickDirectory({
    required BuildContext context,
    String? dialogTitle,
  }) async {
    // Try native directory picker first
    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: dialogTitle,
      );

      if (result != null) {
        return result;
      }
    } catch (e) {
      // If file_picker fails (e.g., zenity not found on Linux), use custom browser
      debugPrint('Directory picker failed: $e, using custom browser');
    }

    // Use custom file browser as fallback
    return await FileBrowserDialog.show(
      context: context,
      selectDirectory: true,
      dialogTitle: dialogTitle ?? 'Select Directory',
    );
  }

  /// Save a file with fallback for Linux
  static Future<String?> saveFile({
    required BuildContext context,
    String? dialogTitle,
    String? fileName,
    String? fileExtension,
  }) async {
    // Try native save dialog first
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        type: fileExtension != null ? FileType.custom : FileType.any,
        allowedExtensions: fileExtension != null ? [fileExtension] : null,
      );

      if (result != null) {
        return result;
      }
    } catch (e) {
      // If file_picker fails (e.g., zenity not found on Linux), use custom browser
      debugPrint('Save file dialog failed: $e, using custom browser');
    }

    // Use custom file browser to select directory, then append filename
    final directory = await FileBrowserDialog.show(
      context: context,
      selectDirectory: true,
      dialogTitle: dialogTitle ?? 'Select Save Location',
    );

    if (directory != null && fileName != null) {
      return '$directory/$fileName';
    }

    // Final fallback: text input
    return await _saveFileFallback(context, dialogTitle, fileName);
  }

  /// Fallback file picker using text input dialog
  static Future<String?> _pickFileFallback(
    BuildContext context,
    String? dialogTitle,
    List<String>? allowedExtensions,
  ) async {
    final controller = TextEditingController();

    // Get default directory (home or documents)
    String? defaultPath;
    try {
      if (Platform.isLinux) {
        defaultPath = Platform.environment['HOME'] ?? '/home';
      }
    } catch (e) {
      defaultPath = null;
    }

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogTitle ?? 'Select File'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter the full path to the file:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: defaultPath != null
                    ? '$defaultPath/example.pdf'
                    : '/path/to/file',
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (value) {
                if (value.isNotEmpty) {
                  final file = File(value);
                  if (file.existsSync()) {
                    Navigator.pop(dialogContext, value);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('File does not exist')),
                    );
                  }
                }
              },
            ),
            if (allowedExtensions != null) ...[
              const SizedBox(height: 8),
              Text(
                'Allowed extensions: ${allowedExtensions.join(', ')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final path = controller.text.trim();
              if (path.isNotEmpty) {
                final file = File(path);
                if (file.existsSync()) {
                  Navigator.pop(dialogContext, path);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('File does not exist')),
                  );
                }
              }
            },
            child: const Text('Select'),
          ),
        ],
      ),
    );
  }

  /// Fallback directory picker using text input dialog
  static Future<String?> _pickDirectoryFallback(
    BuildContext context,
    String? dialogTitle,
  ) async {
    final controller = TextEditingController();

    // Get default directory (home)
    String? defaultPath;
    try {
      if (Platform.isLinux) {
        defaultPath = Platform.environment['HOME'] ?? '/home';
      }
    } catch (e) {
      defaultPath = null;
    }

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogTitle ?? 'Select Directory'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter the full path to the directory:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: defaultPath ?? '/path/to/directory',
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (value) {
                if (value.isNotEmpty) {
                  final dir = Directory(value);
                  if (dir.existsSync()) {
                    Navigator.pop(dialogContext, value);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Directory does not exist')),
                    );
                  }
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final path = controller.text.trim();
              if (path.isNotEmpty) {
                final dir = Directory(path);
                if (dir.existsSync()) {
                  Navigator.pop(dialogContext, path);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Directory does not exist')),
                  );
                }
              }
            },
            child: const Text('Select'),
          ),
        ],
      ),
    );
  }

  /// Fallback save file using text input dialog
  static Future<String?> _saveFileFallback(
    BuildContext context,
    String? dialogTitle,
    String? fileName,
  ) async {
    final controller = TextEditingController(text: fileName);

    // Get default directory (home or documents)
    String? defaultPath;
    try {
      if (Platform.isLinux) {
        defaultPath = Platform.environment['HOME'] ?? '/home';
      }
    } catch (e) {
      defaultPath = null;
    }

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogTitle ?? 'Save File'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter the full path where to save the file:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: defaultPath != null
                    ? '$defaultPath/$fileName'
                    : '/path/to/file',
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (value) {
                if (value.isNotEmpty) {
                  Navigator.pop(dialogContext, value);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final path = controller.text.trim();
              if (path.isNotEmpty) {
                Navigator.pop(dialogContext, path);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
