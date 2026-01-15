/// File Picker Helper
///
/// Provides cross-platform file and directory picking with Linux fallbacks
/// when zenity is not available.
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

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

    if (!context.mounted) return null;

    // Use custom file browser as fallback
    return FileBrowserDialog.show(
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

    if (!context.mounted) return null;

    // Use custom file browser as fallback
    return FileBrowserDialog.show(
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

    if (!context.mounted) return null;

    // Use custom file browser to select directory, then append filename
    final directory = await FileBrowserDialog.show(
      context: context,
      selectDirectory: true,
      dialogTitle: dialogTitle ?? 'Select Save Location',
    );

    if (directory != null && fileName != null) {
      return '$directory/$fileName';
    }

    if (!context.mounted) return null;

    // Final fallback: text input
    return _saveFileFallback(context, dialogTitle, fileName);
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
