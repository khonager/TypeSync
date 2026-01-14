/// Tag Model
library;
///
/// Represents a tag that can be attached to notes for organization.

import 'package:equatable/equatable.dart';

/// Tag model for categorizing notes
class Tag extends Equatable {
  final String id;
  final String name;
  final String color;
  final String userId;
  final DateTime createdAt;
  final bool isDirty;

  const Tag({
    required this.id,
    required this.name,
    required this.color,
    required this.userId,
    required this.createdAt,
    this.isDirty = true,
  });

  factory Tag.create({
    required String id,
    required String userId,
    required String name,
    String color = '#64D2FF',
  }) {
    return Tag(
      id: id,
      name: name,
      color: color,
      userId: userId,
      createdAt: DateTime.now(),
    );
  }

  Tag copyWith({
    String? id,
    String? name,
    String? color,
    String? userId,
    DateTime? createdAt,
    bool? isDirty,
  }) {
    return Tag(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
      isDirty: isDirty ?? this.isDirty,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        'userId': userId,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Tag.fromJson(Map<String, dynamic> json) => Tag(
        id: json['id'] as String,
        name: json['name'] as String,
        color: json['color'] as String,
        userId: json['userId'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        isDirty: false,
      );

  @override
  List<Object?> get props => [id, name, color, userId, createdAt, isDirty];
}
