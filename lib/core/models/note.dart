/// Note Model
/// 
/// Represents a note document in TypeSync. Contains the content,
/// metadata, and sync information for each note.

import 'package:equatable/equatable.dart';
import 'package:hive/hive.dart';

part 'note.g.dart';

/// Hive type adapter for NoteType enum
@HiveType(typeId: 1)
enum NoteType {
  @HiveField(0)
  text,
  
  @HiveField(1)
  markdown,
  
  @HiveField(2)
  pdf,
}

/// Note model representing a single document
/// 
/// Stores the note content, metadata, and synchronization state.
/// Uses Hive for local persistence and Equatable for value comparison.
@HiveType(typeId: 0)
class Note extends Equatable {
  /// Unique identifier for the note
  @HiveField(0)
  final String id;
  
  /// Display title of the note
  @HiveField(1)
  final String title;
  
  /// Raw content of the note (JSON for rich text, markdown string, etc.)
  @HiveField(2)
  final String content;
  
  /// Type of note (text, markdown, pdf)
  @HiveField(3)
  final NoteType type;
  
  /// Parent folder ID (null if in root)
  @HiveField(4)
  final String? folderId;
  
  /// List of tag IDs associated with this note
  @HiveField(5)
  final List<String> tags;
  
  /// Background color as hex string (e.g., '#1C1C1E')
  @HiveField(6)
  final String? backgroundColor;
  
  /// Creation timestamp
  @HiveField(7)
  final DateTime createdAt;
  
  /// Last modification timestamp
  @HiveField(8)
  final DateTime updatedAt;
  
  /// Last sync timestamp with cloud
  @HiveField(9)
  final DateTime? syncedAt;
  
  /// Whether note has unsynced changes
  @HiveField(10)
  final bool isDirty;
  
  /// Whether note is marked as favorite
  @HiveField(11)
  final bool isFavorite;
  
  /// Whether note is in trash
  @HiveField(12)
  final bool isDeleted;
  
  /// Character count for the note content
  @HiveField(13)
  final int characterCount;
  
  /// Line count for the note content
  @HiveField(14)
  final int lineCount;
  
  /// User ID who owns this note
  @HiveField(15)
  final String userId;
  
  /// PDF file path if type is pdf
  @HiveField(16)
  final String? pdfPath;

  const Note({
    required this.id,
    required this.title,
    required this.content,
    this.type = NoteType.text,
    this.folderId,
    this.tags = const [],
    this.backgroundColor,
    required this.createdAt,
    required this.updatedAt,
    this.syncedAt,
    this.isDirty = true,
    this.isFavorite = false,
    this.isDeleted = false,
    this.characterCount = 0,
    this.lineCount = 0,
    required this.userId,
    this.pdfPath,
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
    String? userId,
    String? pdfPath,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      type: type ?? this.type,
      folderId: folderId ?? this.folderId,
      tags: tags ?? this.tags,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncedAt: syncedAt ?? this.syncedAt,
      isDirty: isDirty ?? this.isDirty,
      isFavorite: isFavorite ?? this.isFavorite,
      isDeleted: isDeleted ?? this.isDeleted,
      characterCount: characterCount ?? this.characterCount,
      lineCount: lineCount ?? this.lineCount,
      userId: userId ?? this.userId,
      pdfPath: pdfPath ?? this.pdfPath,
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
      'userId': userId,
      'pdfPath': pdfPath,
    };
  }

  /// Creates a note from a JSON map (from Firebase)
  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      type: NoteType.values[json['type'] as int],
      folderId: json['folderId'] as String?,
      tags: List<String>.from(json['tags'] ?? []),
      backgroundColor: json['backgroundColor'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      syncedAt: json['syncedAt'] != null
          ? DateTime.parse(json['syncedAt'] as String)
          : null,
      isDirty: false, // Coming from server, so not dirty
      isFavorite: json['isFavorite'] as bool? ?? false,
      isDeleted: json['isDeleted'] as bool? ?? false,
      characterCount: json['characterCount'] as int? ?? 0,
      lineCount: json['lineCount'] as int? ?? 0,
      userId: json['userId'] as String,
      pdfPath: json['pdfPath'] as String?,
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
    userId,
    pdfPath,
  ];
}

