/// Anytype import service
///
/// Imports Anytype Markdown exports into the active TypeSync workspace.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../models/folder.dart';
import '../models/note.dart';
import '../models/typesync_kanban_embed.dart';
import '../models/typesync_table_embed.dart';
import '../providers/folders_provider.dart';
import '../providers/notes_provider.dart';
import 'diagnostics_service.dart';
import 'local_file_service.dart';
import 'markdown_rich_text_service.dart';
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
  final Map<String, String> importedPathsByRelativeTarget;

  const _ImportedAttachmentBatch({
    required this.attachments,
    required this.totalSize,
    this.skippedEntries = const [],
    this.importedPathsByRelativeTarget = const {},
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
      return _importNativeExport(
        exportDirectory: exportDirectory,
        noteUserId: noteUserId,
        notesProvider: notesProvider,
        foldersProvider: foldersProvider,
      );
    }

    var importedNotes = 0;
    var importedFolders = 0;
    var importedAttachments = 0;

    for (final markdownFile in markdownFiles) {
      final relativeFilePath =
          _relativePath(markdownFile.path, exportDirectory);

      try {
        final rawMarkdown = await markdownFile.readAsString();
        final relativeDirectory = _relativeDirectoryForFile(
          markdownFile,
          exportDirectory,
          rawMarkdown: rawMarkdown,
        );

        final folderResult = await _ensureFolderPath(
          relativeDirectory: relativeDirectory,
          folderIdsByRelativePath: folderIdsByRelativePath,
          foldersProvider: foldersProvider,
          userId: noteUserId,
        );
        importedFolders += folderResult.createdFolders;

        final initialConversion =
            MarkdownRichTextService.instance.convertAnytypeMarkdown(
          rawMarkdown: rawMarkdown,
          fallbackTitle: _titleForMarkdownFile(markdownFile),
        );
        final note = await notesProvider.createNote(
          userId: noteUserId,
          folderId: folderResult.folderId,
          title: initialConversion.title,
          content: initialConversion.quillContentJson,
          type: NoteType.text,
          size: initialConversion.quillContentJson.length,
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

        final finalConversion =
            MarkdownRichTextService.instance.convertAnytypeMarkdown(
          rawMarkdown: rawMarkdown,
          fallbackTitle: _titleForMarkdownFile(markdownFile),
          pathReplacements: attachments.importedPathsByRelativeTarget,
        );

        if (attachments.attachments.isNotEmpty ||
            finalConversion.quillContentJson !=
                initialConversion.quillContentJson ||
            finalConversion.title != initialConversion.title) {
          await notesProvider.updateNote(
            note.copyWith(
              title: finalConversion.title,
              content: finalConversion.quillContentJson,
              attachments: attachments.attachments,
              size: finalConversion.quillContentJson.length +
                  attachments.totalSize,
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

  Future<AnytypeImportResult> _importNativeExport({
    required Directory exportDirectory,
    required String noteUserId,
    required NotesProvider notesProvider,
    required FoldersProvider foldersProvider,
  }) async {
    final objectFiles = await _collectNativeObjectFiles(exportDirectory);
    if (objectFiles.isEmpty) {
      return const AnytypeImportResult(
        importedNotes: 0,
        importedFolders: 0,
        importedAttachments: 0,
        skippedEntries: ['No Markdown or Anytype object notes were found'],
      );
    }

    final typeNames = await _loadNativeTypeNames(exportDirectory);
    final nativeContext = await _loadNativeImportContext(
      exportDirectory,
      objectFiles: objectFiles,
      typeNames: typeNames,
    );
    final folderIdsByRelativePath = <String, String?>{'': null};
    final failedEntries = <String>[];
    var importedNotes = 0;
    var importedFolders = 0;

    for (final objectFile in objectFiles) {
      final relativeFilePath = _relativePath(objectFile.path, exportDirectory);

      try {
        final jsonData = jsonDecode(await objectFile.readAsString());
        if (jsonData is! Map<String, dynamic> || jsonData['sbType'] != 'Page') {
          continue;
        }

        final data = _nativeData(jsonData);
        if (data == null) {
          continue;
        }

        final details = _mapValue(data['details']);
        final title = _stringValue(details?['name']) ??
            path.basenameWithoutExtension(objectFile.path);
        final relativeDirectory = _nativeFolderForObject(data, typeNames);
        final folderResult = await _ensureFolderPath(
          relativeDirectory: relativeDirectory,
          folderIdsByRelativePath: folderIdsByRelativePath,
          foldersProvider: foldersProvider,
          userId: noteUserId,
        );
        importedFolders += folderResult.createdFolders;

        final content = _convertNativeObjectToQuillJson(data, nativeContext);
        final note = await notesProvider.createNote(
          userId: noteUserId,
          folderId: folderResult.folderId,
          title: title,
          content: content,
          type: NoteType.text,
          size: content.length,
        );

        if (note == null) {
          failedEntries.add(relativeFilePath);
          continue;
        }

        importedNotes++;
      } catch (error) {
        failedEntries.add(relativeFilePath);
        _diagnostics.error(
          'AnytypeImportService',
          'Failed to import native Anytype object $relativeFilePath: $error',
        );
      }
    }

    return AnytypeImportResult(
      importedNotes: importedNotes,
      importedFolders: importedFolders,
      importedAttachments: 0,
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

  Future<List<File>> _collectNativeObjectFiles(
    Directory exportDirectory,
  ) async {
    final objectsDirectory =
        Directory(path.join(exportDirectory.path, 'objects'));
    if (!await objectsDirectory.exists()) {
      return const [];
    }

    final files = <File>[];
    await for (final entity
        in objectsDirectory.list(recursive: false, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.pb.json')) {
        files.add(entity);
      }
    }
    files.sort((left, right) => left.path.compareTo(right.path));
    return files;
  }

  Future<Map<String, String>> _loadNativeTypeNames(
    Directory exportDirectory,
  ) async {
    final typesDirectory = Directory(path.join(exportDirectory.path, 'types'));
    if (!await typesDirectory.exists()) {
      return const {};
    }

    final namesByKey = <String, String>{};
    await for (final entity
        in typesDirectory.list(recursive: false, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.pb.json')) {
        continue;
      }

      try {
        final jsonData = jsonDecode(await entity.readAsString());
        final data =
            jsonData is Map<String, dynamic> ? _nativeData(jsonData) : null;
        final details = _mapValue(data?['details']);
        final name = _stringValue(details?['name']);
        if (name == null || name.isEmpty) {
          continue;
        }

        final id = _stringValue(details?['id']);
        final uniqueKey = _stringValue(details?['uniqueKey']);
        if (id != null) {
          namesByKey[id] = name;
        }
        if (uniqueKey != null) {
          namesByKey[uniqueKey] = name;
        }
      } catch (_) {
        // Type metadata is best effort; pages can still import at root.
      }
    }

    return namesByKey;
  }

  Future<_NativeImportContext> _loadNativeImportContext(
    Directory exportDirectory, {
    required List<File> objectFiles,
    required Map<String, String> typeNames,
  }) async {
    final objectDataById = <String, Map<String, dynamic>>{};
    final objectNamesById = <String, String>{};

    for (final objectFile in objectFiles) {
      try {
        final jsonData = jsonDecode(await objectFile.readAsString());
        final data =
            jsonData is Map<String, dynamic> ? _nativeData(jsonData) : null;
        if (data == null) {
          continue;
        }

        final details = _mapValue(data['details']);
        final objectId = _stringValue(details?['id']);
        if (objectId == null || objectId.isEmpty) {
          continue;
        }

        objectDataById[objectId] = data;

        final name = _stringValue(details?['name']);
        if (name != null && name.trim().isNotEmpty) {
          objectNamesById[objectId] = name.trim();
        }
      } catch (_) {
        // Best-effort metadata loading. Import can continue without it.
      }
    }

    final relationMetadataByKey = <String, _NativeRelationMetadata>{};
    final relationsDirectory =
        Directory(path.join(exportDirectory.path, 'relations'));
    if (await relationsDirectory.exists()) {
      await for (final entity
          in relationsDirectory.list(recursive: false, followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.pb.json')) {
          continue;
        }

        try {
          final jsonData = jsonDecode(await entity.readAsString());
          final data =
              jsonData is Map<String, dynamic> ? _nativeData(jsonData) : null;
          final details = _mapValue(data?['details']);
          final key = _stringValue(details?['relationKey']);
          if (key == null || key.isEmpty) {
            continue;
          }

          relationMetadataByKey[key] = _NativeRelationMetadata(
            name: _stringValue(details?['name']) ?? key,
            format: details?['relationFormat'] as num?,
          );
        } catch (_) {
          // Ignore malformed relation definitions.
        }
      }
    }

    final relationOptionNamesById = <String, String>{};
    final relationOptionsDirectory =
        Directory(path.join(exportDirectory.path, 'relationsOptions'));
    if (await relationOptionsDirectory.exists()) {
      await for (final entity in relationOptionsDirectory.list(
        recursive: false,
        followLinks: false,
      )) {
        if (entity is! File || !entity.path.endsWith('.pb.json')) {
          continue;
        }

        try {
          final jsonData = jsonDecode(await entity.readAsString());
          final data =
              jsonData is Map<String, dynamic> ? _nativeData(jsonData) : null;
          final details = _mapValue(data?['details']);
          final optionId = _stringValue(details?['id']);
          final name = _stringValue(details?['name']);
          if (optionId != null &&
              optionId.isNotEmpty &&
              name != null &&
              name.trim().isNotEmpty) {
            relationOptionNamesById[optionId] = name.trim();
          }
        } catch (_) {
          // Ignore malformed relation option values.
        }
      }
    }

    return _NativeImportContext(
      typeNames: typeNames,
      relationMetadataByKey: relationMetadataByKey,
      relationOptionNamesById: relationOptionNamesById,
      objectDataById: objectDataById,
      objectNamesById: objectNamesById,
    );
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
        importedPathsByRelativeTarget: {},
      );
    }

    final attachments = <NoteAttachment>[];
    final skippedEntries = <String>[];
    final importedPathsByRelativeTarget = <String, String>{};
    var totalSize = 0;

    for (final referencedFile in referencedFiles) {
      final file = referencedFile.file;
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

      final markdownTarget = referencedFile.isImage
          ? storedPath
          : _markdownTargetForStoredPath(storedPath);
      importedPathsByRelativeTarget[referencedFile.relativeMarkdownTarget] =
          markdownTarget;

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
      importedPathsByRelativeTarget: importedPathsByRelativeTarget,
    );
  }

  Future<List<_ReferencedMarkdownFile>> _resolveLinkedFiles(
    File markdownFile,
    Directory exportDirectory,
  ) async {
    final content = await markdownFile.readAsString();
    final referencedPaths = extractReferencedLocalPaths(content);
    final resolvedFiles = <_ReferencedMarkdownFile>[];
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
        resolvedFiles.add(
          _ReferencedMarkdownFile(
            file: file,
            relativeMarkdownTarget: referencedPath,
            isImage: _isLikelyImageFile(file.path),
          ),
        );
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
    Directory exportDirectory, {
    required String rawMarkdown,
  }) {
    final relativePath = path.relative(
      file.parent.path,
      from: exportDirectory.path,
    );
    if (relativePath != '.') {
      return relativePath;
    }

    return inferFolderPathFromMarkdownMetadata(rawMarkdown: rawMarkdown);
  }

  static String inferFolderPathFromMarkdownMetadata({
    required String rawMarkdown,
  }) {
    final frontMatterValues =
        MarkdownRichTextService.extractAnytypeFrontMatterValues(
      rawMarkdown: rawMarkdown,
    );
    if (frontMatterValues.isEmpty) {
      return '';
    }

    const preferredKeys = <String>[
      'Folder',
      'Folders',
      'Class',
      'Classes',
      'Course',
      'Courses',
      'Subject',
      'Subjects',
      'Topic',
      'Topics',
      'Area',
      'Areas',
      'Project',
      'Projects',
      'Notebook',
      'Notebooks',
      'Collection',
      'Collections',
      'Set',
      'Sets',
      'Tag',
      'Tags',
    ];
    final preferredValue = _firstFrontMatterValueForKeys(
      frontMatterValues,
      preferredKeys,
    );
    final sanitizedPreferred = _sanitizeFolderCandidate(preferredValue);
    if (sanitizedPreferred != null) {
      return sanitizedPreferred;
    }

    const ignoredKeys = <String>{
      'id',
      'name',
      'title',
      'object type',
      'type',
      'created',
      'creation date',
      'created at',
      'last modified',
      'last modified date',
      'updated',
      'updated at',
      'description',
      'source',
      'origin',
      'cover',
      'icon',
      'layout',
    };

    for (final entry in frontMatterValues.entries) {
      if (ignoredKeys.contains(entry.key.toLowerCase())) {
        continue;
      }

      for (final value in entry.value) {
        final candidate = _sanitizeFolderCandidate(value);
        if (candidate != null) {
          return candidate;
        }
      }
    }

    final objectType = _sanitizeFolderCandidate(
      _firstFrontMatterValueForKeys(
        frontMatterValues,
        const ['Object type', 'Type'],
      ),
    );
    if (objectType == null || _isGenericAnytypeObjectType(objectType)) {
      return '';
    }
    return objectType;
  }

  static String _relativePath(String targetPath, Directory exportDirectory) {
    return path.relative(targetPath, from: exportDirectory.path);
  }

  static String _titleForMarkdownFile(File markdownFile) {
    final title = path.basenameWithoutExtension(markdownFile.path).trim();
    return title.isEmpty ? 'Imported note' : title;
  }

  static Map<String, dynamic>? _nativeData(Map<String, dynamic> jsonData) {
    final snapshot = _mapValue(jsonData['snapshot']);
    final data = _mapValue(snapshot?['data']);
    return data;
  }

  static String _nativeFolderForObject(
    Map<String, dynamic> data,
    Map<String, String> typeNames,
  ) {
    final details = _mapValue(data['details']);
    final typeId = _stringValue(details?['type']);
    if (typeId != null) {
      final typeName = typeNames[typeId];
      if (typeName != null && typeName.trim().isNotEmpty) {
        return _sanitizePathSegment(typeName.trim());
      }
    }

    final objectTypes = data['objectTypes'];
    if (objectTypes is List) {
      for (final objectType in objectTypes) {
        final key = _stringValue(objectType);
        final typeName = key == null ? null : typeNames[key];
        if (typeName != null && typeName.trim().isNotEmpty) {
          return _sanitizePathSegment(typeName.trim());
        }
      }
    }

    return '';
  }

  static String convertNativeObjectToQuillJsonForTesting(
    Map<String, dynamic> data, {
    Map<String, String> typeNames = const {},
    Map<String, String> relationNamesByKey = const {},
    Map<String, String> relationOptionNamesById = const {},
    Map<String, Map<String, dynamic>> objectDataById = const {},
    Map<String, String> objectNamesById = const {},
  }) {
    final relationMetadataByKey = {
      for (final entry in relationNamesByKey.entries)
        entry.key: _NativeRelationMetadata(name: entry.value),
    };

    return _convertNativeObjectToQuillJson(
      data,
      _NativeImportContext(
        typeNames: typeNames,
        relationMetadataByKey: relationMetadataByKey,
        relationOptionNamesById: relationOptionNamesById,
        objectDataById: objectDataById,
        objectNamesById: objectNamesById,
      ),
    );
  }

  static String _convertNativeObjectToQuillJson(
    Map<String, dynamic> data,
    _NativeImportContext context,
  ) {
    final blocks = (data['blocks'] as List?)
            ?.whereType<Map<Object?, Object?>>()
            .map((block) => Map<String, dynamic>.from(block))
            .toList() ??
        const <Map<String, dynamic>>[];
    final blocksById = {
      for (final block in blocks)
        if (_stringValue(block['id']) != null)
          _stringValue(block['id'])!: block,
    };
    final root = blocks.isEmpty ? null : blocks.first;
    final operations = <Map<String, dynamic>>[];
    final visited = <String>{};

    void visit(String id) {
      if (!visited.add(id)) {
        return;
      }

      if (id == 'header' || id == 'title' || id == 'featuredRelations') {
        return;
      }

      final block = blocksById[id];
      if (block == null) {
        return;
      }

      if (_appendNativeStructuredBlock(
        operations,
        block,
        blocksById,
        data,
        context: context,
      )) {
        return;
      }

      _appendNativeTextBlock(operations, block);
      final childrenIds = block['childrenIds'];
      if (childrenIds is List) {
        for (final childId in childrenIds) {
          final child = _stringValue(childId);
          if (child != null) {
            visit(child);
          }
        }
      }
    }

    final rootChildren = root?['childrenIds'];
    if (rootChildren is List) {
      for (final childId in rootChildren) {
        final child = _stringValue(childId);
        if (child != null) {
          visit(child);
        }
      }
    }

    if (operations.isEmpty) {
      operations.add({'insert': '\n'});
    }

    return jsonEncode(operations);
  }

  static bool _appendNativeStructuredBlock(
    List<Map<String, dynamic>> operations,
    Map<String, dynamic> block,
    Map<String, Map<String, dynamic>> blocksById,
    Map<String, dynamic> data, {
    required _NativeImportContext context,
  }) {
    if (block['table'] is Map) {
      final table = _buildNativeTableData(block, blocksById);
      if (table != null) {
        operations
            .add({'insert': TypeSyncTableEmbed.toBlockEmbed(table).toJson()});
        operations.add({'insert': '\n'});
      }
      return true;
    }

    final dataview = _mapValue(block['dataview']);
    if (dataview != null) {
      final embed = _buildNativeDataviewEmbed(
        data,
        dataview,
        context,
      );
      if (embed != null) {
        operations.add({'insert': embed});
        operations.add({'insert': '\n'});
      } else {
        final label = _nativeDataviewLabel(data, dataview);
        operations.add({'insert': '[$label]\n'});
      }
      return true;
    }

    return false;
  }

  static TypeSyncTableData? _buildNativeTableData(
    Map<String, dynamic> tableBlock,
    Map<String, Map<String, dynamic>> blocksById,
  ) {
    final childIds = (tableBlock['childrenIds'] as List?)
            ?.map(_stringValue)
            .whereType<String>()
            .toList() ??
        const <String>[];
    if (childIds.isEmpty) {
      return null;
    }

    Map<String, dynamic>? columnsBlock;
    Map<String, dynamic>? rowsBlock;

    for (final childId in childIds) {
      final child = blocksById[childId];
      final layout = _mapValue(child?['layout']);
      final style = _stringValue(layout?['style']);
      if (style == 'TableColumns') {
        columnsBlock = child;
      } else if (style == 'TableRows') {
        rowsBlock = child;
      }
    }

    final columnIds = (columnsBlock?['childrenIds'] as List?)
            ?.map(_stringValue)
            .whereType<String>()
            .toList() ??
        const <String>[];
    final widths = <double>[
      for (final columnId in columnIds)
        ((blocksById[columnId]?['fields'] as Map?)?['width'] as num?)
                ?.toDouble() ??
            180,
    ];

    final rowIds = (rowsBlock?['childrenIds'] as List?)
            ?.map(_stringValue)
            .whereType<String>()
            .toList() ??
        const <String>[];
    if (rowIds.isEmpty) {
      return null;
    }

    final rows = <List<String>>[];
    var headerRowCount = 0;
    for (final rowId in rowIds) {
      final rowBlock = blocksById[rowId];
      if (rowBlock == null) {
        continue;
      }

      final cellIds = (rowBlock['childrenIds'] as List?)
              ?.map(_stringValue)
              .whereType<String>()
              .toList() ??
          const <String>[];
      if (cellIds.isEmpty) {
        continue;
      }

      final row = <String>[
        for (final cellId in cellIds)
          _nativeBlockPlainText(blocksById[cellId], blocksById).trim(),
      ];
      rows.add(row);

      final tableRow = _mapValue(rowBlock['tableRow']);
      if ((tableRow?['isHeader'] as bool?) ?? false) {
        headerRowCount++;
      }
    }

    if (rows.isEmpty) {
      return null;
    }

    final columnCount = widths.isNotEmpty
        ? widths.length
        : rows.map((row) => row.length).fold(0, (a, b) => a > b ? a : b);
    final normalizedRows = [
      for (final row in rows)
        List<String>.generate(
          columnCount,
          (index) => index < row.length ? row[index] : '',
        ),
    ];

    return TypeSyncTableData(
      rows: normalizedRows,
      columnWidths: widths.isNotEmpty
          ? List<double>.generate(
              columnCount,
              (index) => index < widths.length ? widths[index] : 180,
            )
          : List<double>.filled(columnCount, 180),
      headerRowCount: headerRowCount > 0 ? headerRowCount : 1,
    );
  }

  static Map<String, dynamic>? _buildNativeDataviewEmbed(
    Map<String, dynamic> data,
    Map<String, dynamic> dataview,
    _NativeImportContext context,
  ) {
    final views = (dataview['views'] as List?)
            ?.whereType<Map<Object?, Object?>>()
            .map((view) => Map<String, dynamic>.from(view))
            .toList() ??
        const <Map<String, dynamic>>[];
    if (views.isEmpty) {
      return null;
    }

    final activeViewId = _stringValue(dataview['activeView']);
    final view = (activeViewId == null || activeViewId.isEmpty)
        ? views.first
        : views.firstWhere(
            (candidate) => _stringValue(candidate['id']) == activeViewId,
            orElse: () => views.first,
          );

    final objectIds = _nativeDataviewObjectIds(data);
    final relationConfigs = (view['relations'] as List?)
            ?.whereType<Map<Object?, Object?>>()
            .map((relation) => Map<String, dynamic>.from(relation))
            .toList() ??
        const <Map<String, dynamic>>[];
    final visibleRelations = relationConfigs.where((relation) {
      return relation['isVisible'] != false &&
          (_stringValue(relation['key'])?.isNotEmpty ?? false);
    }).toList();
    final relationsToShow = visibleRelations.isNotEmpty
        ? visibleRelations
        : [
            const {'key': 'name', 'width': 200},
          ];

    final viewType = (_stringValue(view['type']) ?? '').trim();
    final groupRelationKey =
        _stringValue(view['groupRelationKey'])?.trim() ?? '';
    if (viewType == 'Graph' &&
        groupRelationKey.isNotEmpty &&
        !_looksLikeDateRelation(groupRelationKey)) {
      final board = _buildNativeKanbanData(
        data,
        objectIds,
        groupRelationKey,
        relationsToShow,
        context,
      );
      if (board != null) {
        return TypeSyncKanbanEmbed.toBlockEmbed(board).toJson();
      }
    }

    final table = _buildNativeDataviewTableData(
      objectIds,
      relationsToShow,
      context,
    );
    if (table == null) {
      return null;
    }
    return TypeSyncTableEmbed.toBlockEmbed(table).toJson();
  }

  static List<String> _nativeDataviewObjectIds(Map<String, dynamic> data) {
    final collections = _mapValue(data['collections']);
    final collectionObjects = (collections?['objects'] as List?)
            ?.map(_stringValue)
            .whereType<String>()
            .toList() ??
        const <String>[];
    if (collectionObjects.isNotEmpty) {
      return collectionObjects;
    }

    final details = _mapValue(data['details']);
    return (details?['links'] as List?)
            ?.map(_stringValue)
            .whereType<String>()
            .toList() ??
        const <String>[];
  }

  static TypeSyncTableData? _buildNativeDataviewTableData(
    List<String> objectIds,
    List<Map<String, dynamic>> relationsToShow,
    _NativeImportContext context,
  ) {
    if (relationsToShow.isEmpty) {
      return null;
    }

    final headers = <String>[
      for (final relation in relationsToShow)
        _nativeRelationLabel(_stringValue(relation['key'])!, context),
    ];
    final widths = <double>[
      for (final relation in relationsToShow)
        (relation['width'] as num?)?.toDouble() ?? 180,
    ];

    final rows = <List<String>>[headers];
    for (final objectId in objectIds) {
      final objectData = context.objectDataById[objectId];
      final details = _mapValue(objectData?['details']);
      rows.add([
        for (final relation in relationsToShow)
          _stringifyNativeRelationValue(
            details,
            _stringValue(relation['key'])!,
            context,
          ),
      ]);
    }

    return TypeSyncTableData(
      rows: rows,
      columnWidths: widths,
      headerRowCount: 1,
    );
  }

  static TypeSyncKanbanData? _buildNativeKanbanData(
    Map<String, dynamic> data,
    List<String> objectIds,
    String groupRelationKey,
    List<Map<String, dynamic>> relationsToShow,
    _NativeImportContext context,
  ) {
    final columnsByTitle = <String, List<TypeSyncKanbanCardData>>{};

    for (final objectId in objectIds) {
      final objectData = context.objectDataById[objectId];
      final details = _mapValue(objectData?['details']);
      final title =
          _stringifyNativeRelationValue(details, 'name', context).trim();
      if (title.isEmpty) {
        continue;
      }

      final group = _stringifyNativeRelationValue(
        details,
        groupRelationKey,
        context,
      ).trim();
      final columnTitle = group.isEmpty ? 'Ungrouped' : group;
      final descriptionLines = <String>[];
      for (final relation in relationsToShow) {
        final key = _stringValue(relation['key']);
        if (key == null || key == 'name' || key == groupRelationKey) {
          continue;
        }
        final value = _stringifyNativeRelationValue(details, key, context);
        if (value.trim().isEmpty) {
          continue;
        }
        descriptionLines.add(
          '${_nativeRelationLabel(key, context)}: $value',
        );
      }

      if (descriptionLines.isEmpty) {
        final snippet = _stringValue(details?['snippet'])?.trim() ?? '';
        if (snippet.isNotEmpty) {
          descriptionLines.add(snippet);
        }
      }

      columnsByTitle.putIfAbsent(columnTitle, () => <TypeSyncKanbanCardData>[]);
      columnsByTitle[columnTitle]!.add(
        TypeSyncKanbanCardData.create(
          title: title,
          description: descriptionLines.join('\n'),
        ),
      );
    }

    if (columnsByTitle.isEmpty) {
      return null;
    }

    final details = _mapValue(data['details']);
    return TypeSyncKanbanData.empty(
      title: _stringValue(details?['name'])?.trim().isNotEmpty == true
          ? _stringValue(details?['name'])!.trim()
          : 'Kanban board',
      columnTitles: const [],
    ).copyWith(
      columns: columnsByTitle.entries.map((entry) {
        return TypeSyncKanbanColumnData.create(
          title: entry.key,
          cards: entry.value,
        );
      }).toList(),
    );
  }

  static String _nativeDataviewLabel(
    Map<String, dynamic> data,
    Map<String, dynamic> dataview,
  ) {
    final details = _mapValue(data['details']);
    final title = _stringValue(details?['name'])?.trim();
    if (title != null && title.isNotEmpty) {
      return 'Anytype view: $title';
    }
    final views = dataview['views'];
    if (views is List && views.isNotEmpty) {
      final firstView = _mapValue(views.first);
      final type = _stringValue(firstView?['type'])?.trim();
      if (type != null && type.isNotEmpty) {
        return 'Anytype $type view';
      }
    }
    return 'Anytype view';
  }

  static String _nativeBlockPlainText(
    Map<String, dynamic>? block,
    Map<String, Map<String, dynamic>> blocksById,
  ) {
    if (block == null) {
      return '';
    }

    final text = _mapValue(block['text']);
    final value = _stringValue(text?['text']);
    if (value != null) {
      return value;
    }

    final childrenIds = (block['childrenIds'] as List?)
            ?.map(_stringValue)
            .whereType<String>()
            .toList() ??
        const <String>[];
    if (childrenIds.isEmpty) {
      return '';
    }

    final parts = <String>[];
    for (final childId in childrenIds) {
      final childText = _nativeBlockPlainText(blocksById[childId], blocksById);
      if (childText.trim().isNotEmpty) {
        parts.add(childText.trim());
      }
    }
    return parts.join('\n');
  }

  static String _nativeRelationLabel(
    String relationKey,
    _NativeImportContext context,
  ) {
    final metadata = context.relationMetadataByKey[relationKey];
    final label = metadata?.name.trim();
    if (label != null && label.isNotEmpty) {
      return label;
    }

    final normalized = relationKey
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAllMapped(RegExp(r'(?<=[a-z])(?=[A-Z])'), (_) => ' ')
        .trim();
    if (normalized.isEmpty) {
      return relationKey;
    }
    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  static String _stringifyNativeRelationValue(
    Map<String, dynamic>? details,
    String relationKey,
    _NativeImportContext context,
  ) {
    if (details == null) {
      return '';
    }

    final value = details[relationKey];
    return _stringifyNativeValue(value, relationKey, context);
  }

  static String _stringifyNativeValue(
    Object? value,
    String relationKey,
    _NativeImportContext context,
  ) {
    if (value == null) {
      return '';
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return '';
      }
      if (relationKey == 'type') {
        return context.typeNames[trimmed] ??
            context.objectNamesById[trimmed] ??
            trimmed;
      }
      return context.relationOptionNamesById[trimmed] ??
          context.objectNamesById[trimmed] ??
          trimmed;
    }
    if (value is bool) {
      return value ? 'Yes' : 'No';
    }
    if (value is num) {
      if (_looksLikeDateRelation(relationKey)) {
        final milliseconds =
            value > 9999999999 ? value.toInt() : value.toInt() * 1000;
        final date = DateTime.fromMillisecondsSinceEpoch(
          milliseconds,
          isUtc: true,
        );
        final month = date.month.toString().padLeft(2, '0');
        final day = date.day.toString().padLeft(2, '0');
        return '${date.year}-$month-$day';
      }
      return '$value';
    }
    if (value is List) {
      return value
          .map((entry) => _stringifyNativeValue(entry, relationKey, context))
          .where((entry) => entry.trim().isNotEmpty)
          .join(', ');
    }
    if (value is Map) {
      final mapValue = _mapValue(value);
      return _stringifyNativeValue(
        mapValue?['name'] ?? mapValue?['id'] ?? value.toString(),
        relationKey,
        context,
      );
    }
    return '$value';
  }

  static bool _looksLikeDateRelation(String relationKey) {
    final normalized = relationKey.trim().toLowerCase();
    return normalized.contains('date') || normalized.contains('time');
  }

  static void _appendNativeTextBlock(
    List<Map<String, dynamic>> operations,
    Map<String, dynamic> block,
  ) {
    final text = _mapValue(block['text']);
    if (text == null) {
      return;
    }

    final value = _stringValue(text['text']) ?? '';
    final textAttributes = <String, dynamic>{};
    final lineAttributes = <String, dynamic>{};

    final textColor = MarkdownRichTextService.quillColorFromCss(
      _stringValue(text['color']),
    );
    if (textColor != null) {
      textAttributes['color'] = textColor;
    }

    final backgroundColor = MarkdownRichTextService.quillColorFromCss(
      _stringValue(block['backgroundColor']),
    );
    if (backgroundColor != null) {
      textAttributes['background'] = backgroundColor;
    }

    switch (_stringValue(text['style'])) {
      case 'Marked':
        lineAttributes['list'] = 'bullet';
      case 'Numbered':
        lineAttributes['list'] = 'ordered';
      case 'Checkbox':
        lineAttributes['list'] = 'unchecked';
      case 'Header1':
      case 'Header':
        lineAttributes['header'] = 1;
      case 'Header2':
        lineAttributes['header'] = 2;
      case 'Header3':
        lineAttributes['header'] = 3;
    }

    operations.add({
      'insert': value,
      if (textAttributes.isNotEmpty) 'attributes': textAttributes,
    });
    operations.add({
      'insert': '\n',
      if (lineAttributes.isNotEmpty) 'attributes': lineAttributes,
    });
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

  static String? _firstFrontMatterValueForKeys(
    Map<String, List<String>> values,
    List<String> keys,
  ) {
    for (final key in keys) {
      for (final entry in values.entries) {
        if (entry.key.toLowerCase() != key.toLowerCase()) {
          continue;
        }
        for (final value in entry.value) {
          if (value.trim().isNotEmpty) {
            return value.trim();
          }
        }
      }
    }
    return null;
  }

  static String? _sanitizeFolderCandidate(String? value) {
    if (value == null) {
      return null;
    }

    final sanitized = _sanitizePathSegment(value);
    if (sanitized.isEmpty || _looksLikeMetadataOnlyValue(sanitized)) {
      return null;
    }
    return sanitized;
  }

  static bool _looksLikeMetadataOnlyValue(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return true;
    }
    if (Uri.tryParse(trimmed)?.hasScheme == true) {
      return true;
    }
    if (RegExp(r'^\d{4}-\d{2}-\d{2}(?:[T\s].*)?$').hasMatch(trimmed)) {
      return true;
    }
    return false;
  }

  static bool _isGenericAnytypeObjectType(String value) {
    return const {
      'page',
      'note',
      'bookmark',
      'task',
      'file',
      'tag',
    }.contains(value.trim().toLowerCase());
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

  static String _sanitizePathSegment(String segment) {
    return segment.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
  }

  static bool _isLikelyImageFile(String filePath) {
    return const {
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.bmp',
      '.svg',
      '.tif',
      '.tiff',
      '.ico',
      '.avif',
    }.contains(path.extension(filePath).toLowerCase());
  }

  static String _markdownTargetForStoredPath(String storedPath) {
    if (storedPath.startsWith('http://') || storedPath.startsWith('https://')) {
      return storedPath;
    }
    return Uri.file(storedPath).toString();
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

  static Map<String, dynamic>? _mapValue(Object? value) {
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  static String? _stringValue(Object? value) {
    return value is String ? value : null;
  }
}

class _ReferencedMarkdownFile {
  final File file;
  final String relativeMarkdownTarget;
  final bool isImage;

  const _ReferencedMarkdownFile({
    required this.file,
    required this.relativeMarkdownTarget,
    required this.isImage,
  });
}

class _NativeImportContext {
  final Map<String, String> typeNames;
  final Map<String, _NativeRelationMetadata> relationMetadataByKey;
  final Map<String, String> relationOptionNamesById;
  final Map<String, Map<String, dynamic>> objectDataById;
  final Map<String, String> objectNamesById;

  const _NativeImportContext({
    required this.typeNames,
    required this.relationMetadataByKey,
    required this.relationOptionNamesById,
    required this.objectDataById,
    required this.objectNamesById,
  });
}

class _NativeRelationMetadata {
  final String name;
  final num? format;

  const _NativeRelationMetadata({
    required this.name,
    this.format,
  });
}
