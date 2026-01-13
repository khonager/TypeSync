/// Folder Model
/// 
/// Represents a folder in the TypeSync file system.
/// Folders can contain notes and other subfolders.

import 'package:equatable/equatable.dart';
import 'package:hive/hive.dart';

part 'folder.g.dart';

/// Folder model for organizing notes
/// 
/// Supports nested folder structure with customizable appearance.
@HiveType(typeId: 2)
class Folder extends Equatable {
  /// Unique identifier for the folder
  @HiveField(0)
  final String id;
  
  /// Display name of the folder
  @HiveField(1)
  final String name;
  
  /// Optional subtitle/description
  @HiveField(2)
  final String? subtitle;
  
  /// Parent folder ID (null if in root)
  @HiveField(3)
  final String? parentId;
  
  /// Background color as hex string
  @HiveField(4)
  final String? backgroundColor;
  
  /// Icon identifier (defaults to folder icon)
  @HiveField(5)
  final String icon;
  
  /// Creation timestamp
  @HiveField(6)
  final DateTime createdAt;
  
  /// Last modification timestamp
  @HiveField(7)
  final DateTime updatedAt;
  
  /// Last sync timestamp
  @HiveField(8)
  final DateTime? syncedAt;
  
  /// Whether folder has unsynced changes
  @HiveField(9)
  final bool isDirty;
  
  /// Whether folder is deleted (soft delete)
  @HiveField(10)
  final bool isDeleted;
  
  /// User ID who owns this folder
  @HiveField(11)
  final String userId;
  
  /// Sort order within parent
  @HiveField(12)
  final int sortOrder;

  const Folder({
    required this.id,
    required this.name,
    this.subtitle,
    this.parentId,
    this.backgroundColor,
    this.icon = 'folder',
    required this.createdAt,
    required this.updatedAt,
    this.syncedAt,
    this.isDirty = true,
    this.isDeleted = false,
    required this.userId,
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

  /// Creates a copy with updated fields
  Folder copyWith({
    String? id,
    String? name,
    String? subtitle,
    String? parentId,
    String? backgroundColor,
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
      subtitle: subtitle ?? this.subtitle,
      parentId: parentId ?? this.parentId,
      backgroundColor: backgroundColor ?? this.backgroundColor,
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

