/// Homework Model
/// 
/// Represents a homework task in the todo list.

import 'package:equatable/equatable.dart';
import 'package:hive/hive.dart';

part 'homework.g.dart';

/// Priority level for homework tasks
@HiveType(typeId: 5)
enum HomeworkPriority {
  @HiveField(0)
  low,
  
  @HiveField(1)
  medium,
  
  @HiveField(2)
  high,
  
  @HiveField(3)
  urgent,
}

/// Homework task model
@HiveType(typeId: 4)
class Homework extends Equatable {
  /// Unique identifier
  @HiveField(0)
  final String id;
  
  /// Task title
  @HiveField(1)
  final String title;
  
  /// Task description
  @HiveField(2)
  final String? description;
  
  /// Subject/class name
  @HiveField(3)
  final String? subject;
  
  /// Due date
  @HiveField(4)
  final DateTime? dueDate;
  
  /// Priority level
  @HiveField(5)
  final HomeworkPriority priority;
  
  /// Completion status
  @HiveField(6)
  final bool isCompleted;
  
  /// Related note ID (if linked to a note)
  @HiveField(7)
  final String? noteId;
  
  /// User ID
  @HiveField(8)
  final String userId;
  
  /// Creation timestamp
  @HiveField(9)
  final DateTime createdAt;
  
  /// Last update timestamp
  @HiveField(10)
  final DateTime updatedAt;
  
  /// Sync status
  @HiveField(11)
  final bool isDirty;
  
  /// Deleted status
  @HiveField(12)
  final bool isDeleted;

  const Homework({
    required this.id,
    required this.title,
    this.description,
    this.subject,
    this.dueDate,
    this.priority = HomeworkPriority.medium,
    this.isCompleted = false,
    this.noteId,
    required this.userId,
    required this.createdAt,
    required this.updatedAt,
    this.isDirty = true,
    this.isDeleted = false,
  });

  factory Homework.create({
    required String id,
    required String userId,
    required String title,
    String? description,
    String? subject,
    DateTime? dueDate,
    HomeworkPriority priority = HomeworkPriority.medium,
  }) {
    final now = DateTime.now();
    return Homework(
      id: id,
      title: title,
      description: description,
      subject: subject,
      dueDate: dueDate,
      priority: priority,
      userId: userId,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Checks if homework is overdue
  bool get isOverdue {
    if (dueDate == null || isCompleted) return false;
    return DateTime.now().isAfter(dueDate!);
  }

  /// Gets days until due date
  int? get daysUntilDue {
    if (dueDate == null) return null;
    return dueDate!.difference(DateTime.now()).inDays;
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
    id, title, description, subject, dueDate, priority,
    isCompleted, noteId, userId, createdAt, updatedAt, isDirty, isDeleted,
  ];
}

