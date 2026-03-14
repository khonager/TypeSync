/// Local File Service
///
/// Manages local file storage for PDFs and other files.
/// Handles copying files to app storage directory and provides file access.
library;

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Service for managing local file storage
///
/// Handles copying files to app storage and managing file paths.
class LocalFileService {
  static LocalFileService? _instance;
  static LocalFileService get instance {
    _instance ??= LocalFileService._();
    return _instance!;
  }

  LocalFileService._();

  Directory? _appFilesDirectory;
  String? _activeUserId;
  bool _initialized = false;

  /// Initialize the service and create app files directory
  Future<void> initialize(String userId) async {
    // Local file storage is not supported on Web in the same way
    if (kIsWeb) {
      _activeUserId = userId;
      _initialized = true;
      return;
    }

    if (_initialized && _activeUserId == userId && _appFilesDirectory != null) {
      return;
    }

    try {
      final appDir = await getApplicationDocumentsDirectory();
      _appFilesDirectory =
          Directory(path.join(appDir.path, 'typesync_files', userId));
      _activeUserId = userId;

      if (!await _appFilesDirectory!.exists()) {
        await _appFilesDirectory!.create(recursive: true);
      }

      _initialized = true;
    } catch (e) {
      debugPrint('Failed to initialize LocalFileService: $e');
      rethrow;
    }
  }

  /// Get the app files directory path
  String? get filesDirectoryPath => _appFilesDirectory?.path;

  /// Copy a file to app storage and return the new path
  ///
  /// [sourcePath] - Path to the source file
  /// [fileName] - Optional custom file name, otherwise uses source file name
  /// Returns the new file path in app storage, or null if failed
  Future<String?> copyFileToStorage(
    String sourcePath, {
    String? fileName,
  }) async {
    if (!_initialized || _appFilesDirectory == null) {
      debugPrint('LocalFileService not initialized');
      return null;
    }

    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        debugPrint('Source file does not exist: $sourcePath');
        return null;
      }

      final fileNameToUse = fileName ?? path.basename(sourcePath);
      String destPath = path.join(_appFilesDirectory!.path, fileNameToUse);
      File destFile = File(destPath);

      // If file already exists, add a suffix
      if (await destFile.exists()) {
        final nameWithoutExt = path.basenameWithoutExtension(fileNameToUse);
        final ext = path.extension(fileNameToUse);
        int counter = 1;
        String newName;
        do {
          newName = '$nameWithoutExt ($counter)$ext';
          destPath = path.join(_appFilesDirectory!.path, newName);
          destFile = File(destPath);
          counter++;
        } while (await destFile.exists());
      }

      await sourceFile.copy(destPath);
      return destPath;
    } catch (e) {
      debugPrint('Failed to copy file to storage: $e');
      return null;
    }
  }

  /// Write raw bytes to app storage and return the stored path.
  Future<String?> writeBytesToStorage(
    List<int> bytes, {
    required String fileName,
  }) async {
    if (!_initialized || _appFilesDirectory == null) {
      debugPrint('LocalFileService not initialized');
      return null;
    }

    try {
      String destPath = path.join(_appFilesDirectory!.path, fileName);
      File destFile = File(destPath);

      if (await destFile.exists()) {
        final nameWithoutExt = path.basenameWithoutExtension(fileName);
        final ext = path.extension(fileName);
        int counter = 1;
        String newName;
        do {
          newName = '$nameWithoutExt ($counter)$ext';
          destPath = path.join(_appFilesDirectory!.path, newName);
          destFile = File(destPath);
          counter++;
        } while (await destFile.exists());
      }

      await destFile.writeAsBytes(bytes, flush: true);
      return destPath;
    } catch (e) {
      debugPrint('Failed to write file to storage: $e');
      return null;
    }
  }

  /// Get file path in app storage
  ///
  /// Returns the full path if file exists, null otherwise
  Future<String?> getFileInStorage(String fileName) async {
    if (!_initialized || _appFilesDirectory == null) {
      return null;
    }

    final filePath = path.join(_appFilesDirectory!.path, fileName);
    final file = File(filePath);

    if (await file.exists()) {
      return filePath;
    }

    return null;
  }

  /// Delete a file from app storage
  Future<bool> deleteFileFromStorage(String fileName) async {
    if (!_initialized || _appFilesDirectory == null) {
      return false;
    }

    try {
      final filePath = path.join(_appFilesDirectory!.path, fileName);
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('Failed to delete file from storage: $e');
      return false;
    }
  }

  /// Export a file to a destination path
  ///
  /// [sourceFileName] - Name of the file in app storage
  /// [destinationPath] - Full path where to export the file
  Future<bool> exportFile(String sourceFileName, String destinationPath) async {
    if (!_initialized || _appFilesDirectory == null) {
      return false;
    }

    try {
      final sourcePath = path.join(_appFilesDirectory!.path, sourceFileName);
      final sourceFile = File(sourcePath);

      if (!await sourceFile.exists()) {
        debugPrint('Source file does not exist: $sourcePath');
        return false;
      }

      final destFile = File(destinationPath);
      final destDir = destFile.parent;

      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }

      await sourceFile.copy(destinationPath);
      return true;
    } catch (e) {
      debugPrint('Failed to export file: $e');
      return false;
    }
  }

  /// Get file size in bytes
  Future<int?> getFileSize(String fileName) async {
    if (!_initialized || _appFilesDirectory == null) {
      return null;
    }

    try {
      final filePath = path.join(_appFilesDirectory!.path, fileName);
      final file = File(filePath);

      if (await file.exists()) {
        return await file.length();
      }

      return null;
    } catch (e) {
      debugPrint('Failed to get file size: $e');
      return null;
    }
  }

  /// Check if a file exists in app storage
  Future<bool> fileExists(String fileName) async {
    if (!_initialized || _appFilesDirectory == null) {
      return false;
    }

    final filePath = path.join(_appFilesDirectory!.path, fileName);
    final file = File(filePath);
    return file.exists();
  }

  /// Get all files in app storage
  Future<List<String>> getAllFiles() async {
    if (!_initialized || _appFilesDirectory == null) {
      return [];
    }

    try {
      final files = <String>[];
      final dir = _appFilesDirectory!;

      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            files.add(path.basename(entity.path));
          }
        }
      }

      return files;
    } catch (e) {
      debugPrint('Failed to list files: $e');
      return [];
    }
  }

  /// Clear all files from app storage (use with caution)
  Future<bool> clearAllFiles() async {
    if (!_initialized || _appFilesDirectory == null) {
      return false;
    }

    try {
      if (await _appFilesDirectory!.exists()) {
        await for (final entity in _appFilesDirectory!.list()) {
          if (entity is File) {
            await entity.delete();
          } else if (entity is Directory) {
            await entity.delete(recursive: true);
          }
        }
      }
      return true;
    } catch (e) {
      debugPrint('Failed to clear files: $e');
      return false;
    }
  }

  Future<bool> deleteWorkspaceFiles(String userId) async {
    if (kIsWeb) {
      return true;
    }

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final workspaceDir =
          Directory(path.join(appDir.path, 'typesync_files', userId));

      if (await workspaceDir.exists()) {
        await workspaceDir.delete(recursive: true);
      }

      if (_activeUserId == userId) {
        _appFilesDirectory = null;
        _activeUserId = null;
        _initialized = false;
      }

      return true;
    } catch (e) {
      debugPrint('Failed to delete workspace files: $e');
      return false;
    }
  }
}
