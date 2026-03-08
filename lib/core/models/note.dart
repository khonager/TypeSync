/// Note Model
library;

///
/// Represents a note document in TypeSync. Contains the content,
/// metadata, and sync information for each note.

import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// Note type enum
enum NoteType {
  text,
  markdown,
  pdf,
}

/// File attachment metadata for a note.
class NoteAttachment extends Equatable {
  final String id;
  final String name;
  final String path;
  final String? mimeType;
  final int size;
  final DateTime addedAt;

  const NoteAttachment({
    required this.id,
    required this.name,
    required this.path,
    required this.size,
    required this.addedAt,
    this.mimeType,
  });

  factory NoteAttachment.create({
    required String name,
    required String path,
    required int size,
    String? mimeType,
  }) {
    return NoteAttachment(
      id: const Uuid().v4(),
      name: name,
      path: path,
      mimeType: mimeType,
      size: size,
      addedAt: DateTime.now(),
    );
  }

  NoteAttachment copyWith({
    String? id,
    String? name,
    String? path,
    String? mimeType,
    int? size,
    DateTime? addedAt,
  }) {
    return NoteAttachment(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      mimeType: mimeType ?? this.mimeType,
      size: size ?? this.size,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'mimeType': mimeType,
      'size': size,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  factory NoteAttachment.fromJson(Map<String, dynamic> json) {
    return NoteAttachment(
      id: json['id'] as String? ?? const Uuid().v4(),
      name: json['name'] as String? ?? 'Attachment',
      path: json['path'] as String? ?? '',
      mimeType: json['mimeType'] as String?,
      size: json['size'] as int? ?? 0,
      addedAt: json['addedAt'] != null
          ? DateTime.parse(json['addedAt'] as String)
          : DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [id, name, path, mimeType, size, addedAt];
}

/// Note model representing a single document
///
/// Stores the note content, metadata, and synchronization state.
class Note extends Equatable {
  /// Unique identifier for the note
  final String id;

  /// Display title of the note
  final String title;

  /// Raw content of the note (JSON for rich text, markdown string, etc.)
  final String content;

  /// Type of note (text, markdown, pdf)
  final NoteType type;

  /// Parent folder ID (null if in root)
  final String? folderId;

  /// List of tag IDs associated with this note
  final List<String> tags;

  /// Background color as hex string (e.g., '#1C1C1E')
  final String? backgroundColor;

  /// Creation timestamp
  final DateTime createdAt;

  /// Last modification timestamp
  final DateTime updatedAt;

  /// Last sync timestamp with cloud
  final DateTime? syncedAt;

  /// Whether note has unsynced changes
  final bool isDirty;

  /// Whether note is marked as favorite
  final bool isFavorite;

  /// Whether note is in trash
  final bool isDeleted;

  /// Character count for the note content
  final int characterCount;

  /// Line count for the note content
  final int lineCount;

  /// Size of the note in bytes
  final int size;

  /// User ID who owns this note
  final String userId;

  /// PDF file path if type is pdf
  final String? pdfPath;

  /// File attachments attached to this note
  final List<NoteAttachment> attachments;

  /// Whether this note should remain local-only and never sync to cloud
  final bool localOnly;

  /// Whether this note has an unresolved merge conflict
  final bool hasConflict;

  /// The incoming cloud content that conflicts with local changes
  final String? conflictContent;

  const Note({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.userId,
    this.type = NoteType.text,
    this.folderId,
    this.tags = const [],
    this.backgroundColor,
    this.syncedAt,
    this.isDirty = true,
    this.isFavorite = false,
    this.isDeleted = false,
    this.characterCount = 0,
    this.lineCount = 0,
    this.size = 0,
    this.pdfPath,
    this.attachments = const [],
    this.localOnly = false,
    this.hasConflict = false,
    this.conflictContent,
  });

  /// Creates a new note with default values
  factory Note.create({
    required String id,
    required String userId,
    String title = 'No name',
    String content = '',
    NoteType type = NoteType.text,
    String? folderId,
  }) {
    final now = DateTime.now();
    return Note(
      id: id,
      title: title,
      content: content,
      type: type,
      folderId: folderId,
      createdAt: now,
      updatedAt: now,
      userId: userId,
    );
  }

  /// Creates a copy of this note with updated fields
  Note copyWith({
    String? id,
    String? title,
    String? content,
    NoteType? type,
    String? folderId,
    List<String>? tags,
    String? backgroundColor,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? syncedAt,
    bool? isDirty,
    bool? isFavorite,
    bool? isDeleted,
    int? characterCount,
    int? lineCount,
    int? size,
    String? userId,
    String? pdfPath,
    List<NoteAttachment>? attachments,
    bool? localOnly,
    bool backgroundColorSet = false,
    bool? hasConflict,
    String? conflictContent,
    bool clearConflictContent = false,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      type: type ?? this.type,
      folderId: folderId ?? this.folderId,
      tags: tags ?? this.tags,
      backgroundColor: backgroundColorSet
          ? backgroundColor
          : (backgroundColor ?? this.backgroundColor),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncedAt: syncedAt ?? this.syncedAt,
      isDirty: isDirty ?? this.isDirty,
      isFavorite: isFavorite ?? this.isFavorite,
      isDeleted: isDeleted ?? this.isDeleted,
      characterCount: characterCount ?? this.characterCount,
      lineCount: lineCount ?? this.lineCount,
      size: size ?? this.size,
      userId: userId ?? this.userId,
      pdfPath: pdfPath ?? this.pdfPath,
      attachments: attachments ?? this.attachments,
      localOnly: localOnly ?? this.localOnly,
      hasConflict: hasConflict ?? this.hasConflict,
      conflictContent: clearConflictContent
          ? null
          : (conflictContent ?? this.conflictContent),
    );
  }

  /// Converts the note to a JSON map for Firebase sync
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'type': type.index,
      'folderId': folderId,
      'tags': tags,
      'backgroundColor': backgroundColor,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'syncedAt': syncedAt?.toIso8601String(),
      'isFavorite': isFavorite,
      'isDeleted': isDeleted,
      'characterCount': characterCount,
      'lineCount': lineCount,
      'size': size,
      'userId': userId,
      'pdfPath': pdfPath,
      'attachments': attachments.map((attachment) => attachment.toJson()).toList(),
      'localOnly': localOnly,
      // We explicitly don't sync conflict state up to the cloud;
      // the cloud is just the source of truth for the remote version.
      // But if we did want to serialize them locally somehow, we might.
      // For now, Firestore toJson doesn't need them.
    };
  }

  /// Creates a note from a JSON map (from Firebase)
  factory Note.fromJson(Map<String, dynamic> json) {
    final rawType = json['type'];
    int typeIndex;
    if (rawType is int) {
      typeIndex = rawType;
    } else if (rawType is String) {
      typeIndex = int.tryParse(rawType) ?? 0;
    } else {
      typeIndex = 0;
    }
    if (typeIndex < 0 || typeIndex >= NoteType.values.length) {
      typeIndex = 0;
    }

    return Note(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'No name',
      content: json['content'] as String? ?? '',
      type: NoteType.values[typeIndex],
      folderId: json['folderId'] as String?,
      tags: json['tags'] != null
          ? List<String>.from(json['tags'] as List<dynamic>)
          : <String>[],
      backgroundColor: json['backgroundColor'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.now(),
      syncedAt: json['syncedAt'] != null
          ? DateTime.parse(json['syncedAt'] as String)
          : null,
      isDirty: false, // Coming from server, so not dirty
      isFavorite: json['isFavorite'] as bool? ?? false,
      isDeleted: json['isDeleted'] as bool? ?? false,
      characterCount: json['characterCount'] as int? ?? 0,
      lineCount: json['lineCount'] as int? ?? 0,
      size: json['size'] as int? ?? 0,
      userId: json['userId'] as String? ?? '',
      pdfPath: json['pdfPath'] as String?,
      attachments: (json['attachments'] as List<dynamic>?)
              ?.map(
                (attachment) => NoteAttachment.fromJson(
                  Map<String, dynamic>.from(attachment as Map),
                ),
              )
              .toList() ??
          <NoteAttachment>[],
      localOnly: json['localOnly'] as bool? ?? false,
      hasConflict: false, // from server is never conflicted
      conflictContent: null,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        content,
        type,
        folderId,
        tags,
        backgroundColor,
        createdAt,
        updatedAt,
        syncedAt,
        isDirty,
        isFavorite,
        isDeleted,
        characterCount,
        lineCount,
        size,
        userId,
        pdfPath,
        attachments,
        localOnly,
        hasConflict,
        conflictContent,
      ];
}
