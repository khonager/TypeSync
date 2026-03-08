/// File Picker Helper
///
/// Provides cross-platform file and directory picking with Linux fallbacks
/// when zenity is not available.
library;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';


/// Helper class for file picking with Linux fallbacks
class FilePickerHelper {
  /// Pick file metadata. On web, `PlatformFile.bytes` is available and
  /// `PlatformFile.path` is null.
  static Future<PlatformFile?> pickPlatformFile({
    required BuildContext context,
    String? dialogTitle,
    List<String>? allowedExtensions,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: allowedExtensions != null ? FileType.custom : FileType.any,
        allowedExtensions: allowedExtensions,
        allowMultiple: false,
        withData: kIsWeb,
      );

      if (result != null && result.files.isNotEmpty) {
        return result.files.single;
      }
    } catch (e) {
      debugPrint('File picker failed: $e');
    }
    return null;
  }

  /// Pick a file with native platform picker
  static Future<String?> pickFile({
    required BuildContext context,
    String? dialogTitle,
    List<String>? allowedExtensions,
  }) async {
    final picked = await pickPlatformFile(
      context: context,
      dialogTitle: dialogTitle,
      allowedExtensions: allowedExtensions,
    );
    if (picked == null) return null;

    if (kIsWeb) {
      // Web does not expose a filesystem path.
      return null;
    }
    return picked.path;
  }

  /// Pick a directory with native platform picker
  static Future<String?> pickDirectory({
    required BuildContext context,
    String? dialogTitle,
  }) async {
    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: dialogTitle,
      );

      if (result != null) {
        return result;
      }
    } catch (e) {
      debugPrint('Directory picker failed: $e');
    }
    return null;
  }

  /// Save a file with native platform picker
  /// Note: Only supported on Desktop (Windows, macOS, Linux)
  static Future<String?> saveFile({
    required BuildContext context,
    String? dialogTitle,
    String? fileName,
    String? fileExtension,
  }) async {
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
      debugPrint('Save file dialog failed: $e');
    }
    return null;
  }
}
