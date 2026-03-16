/// Anytype import service
///
/// Imports Anytype Markdown exports into the active TypeSync workspace.
library;

import 'dart:io';

import 'package:path/path.dart' as path;

import '../models/folder.dart';
import '../models/note.dart';
import '../providers/folders_provider.dart';
import '../providers/notes_provider.dart';
import 'diagnostics_service.dart';
import 'local_file_service.dart';
import 'storage_service.dart';

class AnytypeImportResult {
  final int importedNotes;
  final int importedFolders;
  final int importedAttachments;
  final List<String> skippedEntries;
  final List<String> failedEntries;

  const AnytypeImportResult({
    required this.importedNotes,
    required this.importedFolders,
    required this.importedAttachments,
    this.skippedEntries = const [],
    this.failedEntries = const [],
  });

  bool get hasWarnings => skippedEntries.isNotEmpty || failedEntries.isNotEmpty;
}

class _ImportedAttachmentBatch {
  final List<NoteAttachment> attachments;
  final int totalSize;
  final List<String> skippedEntries;

  const _ImportedAttachmentBatch({
    required this.attachments,
    required this.totalSize,
    this.skippedEntries = const [],
  });
}

class AnytypeImportService {
  AnytypeImportService({
    LocalFileService? localFileService,
    DiagnosticsService? diagnostics,
  })  : _localFileService = localFileService ?? LocalFileService.instance,
        _diagnostics = diagnostics ?? DiagnosticsService.instance;

  static AnytypeImportService? _instance;
  static AnytypeImportService get instance {
    _instance ??= AnytypeImportService();
    return _instance!;
  }

  final LocalFileService _localFileService;
  final DiagnosticsService _diagnostics;

  Future<AnytypeImportResult> importMarkdownExport({
    required Directory exportDirectory,
    required String noteUserId,
    required NotesProvider notesProvider,
    required FoldersProvider foldersProvider,
    required bool useCloudStorage,
    required String? cloudUserId,
    StorageService? storageService,
  }) async {
    final markdownFiles = await _collectMarkdownFiles(exportDirectory);
    final skippedEntries = <String>[];
    final failedEntries = <String>[];
    final folderIdsByRelativePath = <String, String?>{'': null};

    if (markdownFiles.isEmpty) {
      return const AnytypeImportResult(
        importedNotes: 0,
        importedFolders: 0,
        importedAttachments: 0,
        skippedEntries: ['No Markdown notes were found in the selected folder'],
      );
    }

    var importedNotes = 0;
    var importedFolders = 0;
    var importedAttachments = 0;

    for (final markdownFile in markdownFiles) {
      final relativeFilePath =
          _relativePath(markdownFile.path, exportDirectory);

      try {
        final relativeDirectory = _relativeDirectoryForFile(
          markdownFile,
          exportDirectory,
        );

        final folderResult = await _ensureFolderPath(
          relativeDirectory: relativeDirectory,
          folderIdsByRelativePath: folderIdsByRelativePath,
          foldersProvider: foldersProvider,
          userId: noteUserId,
        );
        importedFolders += folderResult.createdFolders;

        final content = await markdownFile.readAsString();
        final title = _titleForMarkdownFile(markdownFile);
        final note = await notesProvider.createNote(
          userId: noteUserId,
          folderId: folderResult.folderId,
          title: title,
          content: content,
          type: NoteType.markdown,
          size: content.length,
        );

        if (note == null) {
          failedEntries.add(relativeFilePath);
          _diagnostics.error(
            'AnytypeImportService',
            'Failed to create note for $relativeFilePath',
          );
          continue;
        }

        final attachments = await _importLinkedAttachments(
          markdownFile: markdownFile,
          exportDirectory: exportDirectory,
          note: note,
          useCloudStorage: useCloudStorage,
          cloudUserId: cloudUserId,
          storageService: storageService,
        );

        if (attachments.attachments.isNotEmpty) {
          await notesProvider.updateNote(
            note.copyWith(
              attachments: attachments.attachments,
              size: content.length + attachments.totalSize,
            ),
          );
        }

        skippedEntries.addAll(
          attachments.skippedEntries.map(
            (entry) => '$relativeFilePath -> $entry',
          ),
        );
        importedAttachments += attachments.attachments.length;
        importedNotes++;
      } catch (error) {
        failedEntries.add(relativeFilePath);
        _diagnostics.error(
          'AnytypeImportService',
          'Failed to import $relativeFilePath: $error',
        );
      }
    }

    return AnytypeImportResult(
      importedNotes: importedNotes,
      importedFolders: importedFolders,
      importedAttachments: importedAttachments,
      skippedEntries: skippedEntries,
      failedEntries: failedEntries,
    );
  }

  static List<String> extractReferencedLocalPaths(String markdownContent) {
    final matches =
        RegExp(r'!?\[[^\]]*\]\(([^)]+)\)').allMatches(markdownContent);
    final paths = <String>[];

    for (final match in matches) {
      final candidate = _normalizeMarkdownTarget(match.group(1));
      if (candidate == null) {
        continue;
      }
      paths.add(candidate);
    }

    return paths;
  }

  Future<List<File>> _collectMarkdownFiles(Directory exportDirectory) async {
    final files = <File>[];

    await for (final entity
        in exportDirectory.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }

      final basename = path.basename(entity.path);
      if (basename.startsWith('.')) {
        continue;
      }

      final extension = path.extension(entity.path).toLowerCase();
      if (extension == '.md' || extension == '.markdown') {
        files.add(entity);
      }
    }

    files.sort((left, right) => left.path.compareTo(right.path));
    return files;
  }

  Future<({String? folderId, int createdFolders})> _ensureFolderPath({
    required String relativeDirectory,
    required Map<String, String?> folderIdsByRelativePath,
    required FoldersProvider foldersProvider,
    required String userId,
  }) async {
    if (relativeDirectory.isEmpty) {
      return (folderId: null, createdFolders: 0);
    }

    final segments = path.split(relativeDirectory).where((part) {
      return part.isNotEmpty && part != '.';
    }).toList();

    var currentRelativePath = '';
    String? parentId;
    var createdFolders = 0;

    for (final segment in segments) {
      currentRelativePath = currentRelativePath.isEmpty
          ? segment
          : path.join(currentRelativePath, segment);

      if (folderIdsByRelativePath.containsKey(currentRelativePath)) {
        parentId = folderIdsByRelativePath[currentRelativePath];
        continue;
      }

      final existingFolder = _findFolderByName(
        foldersProvider.folders,
        segment,
        parentId,
      );

      if (existingFolder != null) {
        parentId = existingFolder.id;
        folderIdsByRelativePath[currentRelativePath] = existingFolder.id;
        continue;
      }

      final createdFolder = await foldersProvider.createFolder(
        userId: userId,
        name: segment,
        parentId: parentId,
      );
      if (createdFolder == null) {
        throw StateError('Unable to create folder for $currentRelativePath');
      }

      parentId = createdFolder.id;
      folderIdsByRelativePath[currentRelativePath] = createdFolder.id;
      createdFolders++;
    }

    return (folderId: parentId, createdFolders: createdFolders);
  }

  Future<_ImportedAttachmentBatch> _importLinkedAttachments({
    required File markdownFile,
    required Directory exportDirectory,
    required Note note,
    required bool useCloudStorage,
    required String? cloudUserId,
    StorageService? storageService,
  }) async {
    final referencedFiles = await _resolveLinkedFiles(
      markdownFile,
      exportDirectory,
    );

    if (referencedFiles.isEmpty) {
      return const _ImportedAttachmentBatch(
        attachments: [],
        totalSize: 0,
      );
    }

    final attachments = <NoteAttachment>[];
    final skippedEntries = <String>[];
    var totalSize = 0;

    for (final file in referencedFiles) {
      final fileName = path.basename(file.path);
      final fileSize = await file.length();
      final destinationName = '${note.id}_${_sanitizeFileName(fileName)}';

      String? storedPath;
      if (useCloudStorage && cloudUserId != null && storageService != null) {
        storedPath = await storageService.uploadFile(
          userId: cloudUserId,
          filePath: file.path,
          destinationPath: 'attachments/${note.id}/$destinationName',
          contentType: _mimeTypeForPath(file.path),
        );
      } else {
        storedPath = await _localFileService.copyFileToStorage(
          file.path,
          fileName: destinationName,
        );
      }

      if (storedPath == null) {
        skippedEntries.add('attachment skipped: $fileName');
        _diagnostics.warning(
          'AnytypeImportService',
          'Skipping attachment $fileName for note ${note.id}',
        );
        continue;
      }

      attachments.add(
        NoteAttachment.create(
          name: fileName,
          path: storedPath,
          size: fileSize,
          mimeType: _mimeTypeForPath(file.path),
        ),
      );
      totalSize += fileSize;
    }

    return _ImportedAttachmentBatch(
      attachments: attachments,
      totalSize: totalSize,
      skippedEntries: skippedEntries,
    );
  }

  Future<List<File>> _resolveLinkedFiles(
    File markdownFile,
    Directory exportDirectory,
  ) async {
    final content = await markdownFile.readAsString();
    final referencedPaths = extractReferencedLocalPaths(content);
    final resolvedFiles = <File>[];
    final seenPaths = <String>{};

    for (final referencedPath in referencedPaths) {
      final resolvedPath = path.normalize(
        path.join(markdownFile.parent.path, referencedPath),
      );

      if (!_isWithinOrEqual(exportDirectory.path, resolvedPath)) {
        continue;
      }

      final file = File(resolvedPath);
      if (!await file.exists()) {
        continue;
      }

      if (seenPaths.add(resolvedPath)) {
        resolvedFiles.add(file);
      }
    }

    return resolvedFiles;
  }

  static Folder? _findFolderByName(
    List<Folder> folders,
    String name,
    String? parentId,
  ) {
    for (final folder in folders) {
      if (folder.name == name && folder.parentId == parentId) {
        return folder;
      }
    }
    return null;
  }

  static String _relativeDirectoryForFile(
    File file,
    Directory exportDirectory,
  ) {
    final relativePath = path.relative(
      file.parent.path,
      from: exportDirectory.path,
    );
    return relativePath == '.' ? '' : relativePath;
  }

  static String _relativePath(String targetPath, Directory exportDirectory) {
    return path.relative(targetPath, from: exportDirectory.path);
  }

  static String _titleForMarkdownFile(File markdownFile) {
    final title = path.basenameWithoutExtension(markdownFile.path).trim();
    return title.isEmpty ? 'Imported note' : title;
  }

  static String? _normalizeMarkdownTarget(String? rawTarget) {
    if (rawTarget == null) {
      return null;
    }

    var target = rawTarget.trim();
    if (target.isEmpty) {
      return null;
    }

    if (target.startsWith('<') && target.endsWith('>')) {
      target = target.substring(1, target.length - 1).trim();
    }

    if (target.startsWith('#') ||
        target.startsWith('data:') ||
        target.startsWith('mailto:')) {
      return null;
    }

    final uri = Uri.tryParse(target);
    if (uri?.hasScheme == true) {
      return null;
    }

    target = Uri.decodeFull(target);
    if (path.isAbsolute(target)) {
      return null;
    }

    return target;
  }

  static bool _isWithinOrEqual(String parentPath, String targetPath) {
    final normalizedParent = path.normalize(parentPath);
    final normalizedTarget = path.normalize(targetPath);
    return path.equals(normalizedParent, normalizedTarget) ||
        path.isWithin(normalizedParent, normalizedTarget);
  }

  static String _sanitizeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[^\w.\- ]'), '_');
  }

  static String? _mimeTypeForPath(String filePath) {
    switch (path.extension(filePath).toLowerCase()) {
      case '.pdf':
        return 'application/pdf';
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.svg':
        return 'image/svg+xml';
      case '.txt':
        return 'text/plain';
      case '.md':
      case '.markdown':
        return 'text/markdown';
      case '.json':
        return 'application/json';
      case '.csv':
        return 'text/csv';
      case '.yaml':
      case '.yml':
        return 'application/yaml';
      case '.xml':
        return 'application/xml';
      default:
        return null;
    }
  }
}
