/// Homework Model
library;
///
/// Represents a homework task in the todo list.

import 'package:equatable/equatable.dart';

/// Priority level for homework tasks
enum HomeworkPriority {
  low,
  medium,
  high,
  urgent,
}

/// Homework task model
class Homework extends Equatable {
  final String id;
  final String title;
  final String? description;
  final String? subject;
  final DateTime? dueDate;
  final HomeworkPriority priority;
  final bool isCompleted;
  final String? noteId;
  final String userId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDirty;
  final bool isDeleted;

  const Homework({
    required this.id,
    required this.title,
    required this.userId, required this.createdAt, required this.updatedAt, this.description,
    this.subject,
    this.dueDate,
    this.priority = HomeworkPriority.medium,
    this.isCompleted = false,
    this.noteId,
    this.isDirty = true,
    this.isDeleted = false,
  });

  bool get isOverdue {
    if (dueDate == null || isCompleted) return false;
    return DateTime.now().isAfter(dueDate!);
  }

  Homework copyWith({
    String? id,
    String? title,
    String? description,
    String? subject,
    DateTime? dueDate,
    HomeworkPriority? priority,
    bool? isCompleted,
    String? noteId,
    String? userId,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDirty,
    bool? isDeleted,
  }) {
    return Homework(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      subject: subject ?? this.subject,
      dueDate: dueDate ?? this.dueDate,
      priority: priority ?? this.priority,
      isCompleted: isCompleted ?? this.isCompleted,
      noteId: noteId ?? this.noteId,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDirty: isDirty ?? this.isDirty,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'subject': subject,
        'dueDate': dueDate?.toIso8601String(),
        'priority': priority.index,
        'isCompleted': isCompleted,
        'noteId': noteId,
        'userId': userId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'isDeleted': isDeleted,
      };

  factory Homework.fromJson(Map<String, dynamic> json) => Homework(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        subject: json['subject'] as String?,
        dueDate: json['dueDate'] != null
            ? DateTime.parse(json['dueDate'] as String)
            : null,
        priority: HomeworkPriority.values[json['priority'] as int? ?? 1],
        isCompleted: json['isCompleted'] as bool? ?? false,
        noteId: json['noteId'] as String?,
        userId: json['userId'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        isDirty: false,
        isDeleted: json['isDeleted'] as bool? ?? false,
      );

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        subject,
        dueDate,
        priority,
        isCompleted,
        noteId,
        userId,
        createdAt,
        updatedAt,
        isDirty,
        isDeleted,
      ];
}
