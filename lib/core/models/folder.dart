/// Folder Model
library;

///
/// Represents a folder in the TypeSync file system.
/// Folders can contain notes and other subfolders.

import 'package:equatable/equatable.dart';

/// Folder model for organizing notes
///
/// Supports nested folder structure with customizable appearance.
class Folder extends Equatable {
  /// Unique identifier for the folder
  final String id;

  /// Display name of the folder
  final String name;

  /// Optional subtitle/description
  final String? subtitle;

  /// Parent folder ID (null if in root)
  final String? parentId;

  /// Background color as hex string
  final String? backgroundColor;

  /// Icon identifier (defaults to folder icon)
  final String icon;

  /// Creation timestamp
  final DateTime createdAt;

  /// Last modification timestamp
  final DateTime updatedAt;

  /// Last sync timestamp
  final DateTime? syncedAt;

  /// Whether folder has unsynced changes
  final bool isDirty;

  /// Whether folder is deleted (soft delete)
  final bool isDeleted;

  /// User ID who owns this folder
  final String userId;

  /// Sort order within parent
  final int sortOrder;

  const Folder({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.userId,
    this.subtitle,
    this.parentId,
    this.backgroundColor,
    this.icon = 'folder',
    this.syncedAt,
    this.isDirty = true,
    this.isDeleted = false,
    this.sortOrder = 0,
  });

  /// Creates a new folder with default values
  factory Folder.create({
    required String id,
    required String userId,
    required String name,
    String? subtitle,
    String? parentId,
  }) {
    final now = DateTime.now();
    return Folder(
      id: id,
      name: name,
      subtitle: subtitle,
      parentId: parentId,
      createdAt: now,
      updatedAt: now,
      userId: userId,
    );
  }

  static const Object _noChange = Object();

  /// Creates a copy with updated fields
  Folder copyWith({
    String? id,
    String? name,
    Object? subtitle = _noChange,
    Object? parentId = _noChange,
    Object? backgroundColor = _noChange,
    String? icon,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? syncedAt,
    bool? isDirty,
    bool? isDeleted,
    String? userId,
    int? sortOrder,
  }) {
    return Folder(
      id: id ?? this.id,
      name: name ?? this.name,
      subtitle:
          identical(subtitle, _noChange) ? this.subtitle : subtitle as String?,
      parentId:
          identical(parentId, _noChange) ? this.parentId : parentId as String?,
      backgroundColor: identical(backgroundColor, _noChange)
          ? this.backgroundColor
          : backgroundColor as String?,
      icon: icon ?? this.icon,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncedAt: syncedAt ?? this.syncedAt,
      isDirty: isDirty ?? this.isDirty,
      isDeleted: isDeleted ?? this.isDeleted,
      userId: userId ?? this.userId,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  /// Converts to JSON for Firebase sync
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'subtitle': subtitle,
      'parentId': parentId,
      'backgroundColor': backgroundColor,
      'icon': icon,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'syncedAt': syncedAt?.toIso8601String(),
      'isDeleted': isDeleted,
      'userId': userId,
      'sortOrder': sortOrder,
    };
  }

  /// Creates from JSON (Firebase)
  factory Folder.fromJson(Map<String, dynamic> json) {
    return Folder(
      id: json['id'] as String,
      name: json['name'] as String,
      subtitle: json['subtitle'] as String?,
      parentId: json['parentId'] as String?,
      backgroundColor: json['backgroundColor'] as String?,
      icon: json['icon'] as String? ?? 'folder',
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      syncedAt: json['syncedAt'] != null
          ? DateTime.parse(json['syncedAt'] as String)
          : null,
      isDirty: false,
      isDeleted: json['isDeleted'] as bool? ?? false,
      userId: json['userId'] as String,
      sortOrder: json['sortOrder'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        subtitle,
        parentId,
        backgroundColor,
        icon,
        createdAt,
        updatedAt,
        syncedAt,
        isDirty,
        isDeleted,
        userId,
        sortOrder,
      ];
}
