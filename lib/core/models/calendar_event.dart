/// Calendar Event Model
///
/// Represents a calendar event such as a test reminder or class.
library;

import 'package:equatable/equatable.dart';

/// Type of calendar event
enum EventType {
  test,
  exam,
  assignment,
  classEvent,
  reminder,
  other,
  todo,
}

/// Calendar event model for test reminders and scheduling
class CalendarEvent extends Equatable {
  static const Object _unset = Object();

  final String id;
  final String title;
  final String? description;
  final EventType type;
  final DateTime startTime;
  final DateTime? endTime;
  final String? subject;
  final String? location;
  final String? color;
  final bool hasReminder;
  final int reminderMinutesBefore;
  final String? noteId;
  final String? seriesId;
  final bool isCompleted;
  final DateTime? completedAt;
  final int rolloverCount;
  final String userId;
  final DateTime createdAt;
  final bool isDirty;
  final bool isDeleted;

  const CalendarEvent({
    required this.id,
    required this.title,
    required this.startTime,
    required this.userId,
    required this.createdAt,
    this.description,
    this.type = EventType.todo,
    this.endTime,
    this.subject,
    this.location,
    this.color,
    this.hasReminder = true,
    this.reminderMinutesBefore = 30,
    this.noteId,
    this.seriesId,
    this.isCompleted = false,
    this.completedAt,
    this.rolloverCount = 0,
    this.isDirty = true,
    this.isDeleted = false,
  });

  bool get isTodo => type == EventType.todo;

  DateTime get calendarDate {
    if (isTodo && isCompleted && completedAt != null) {
      return completedAt!;
    }
    return startTime;
  }

  bool get isToday {
    final now = DateTime.now();
    return startTime.year == now.year &&
        startTime.month == now.month &&
        startTime.day == now.day;
  }

  CalendarEvent copyWith({
    String? id,
    String? title,
    String? description,
    EventType? type,
    DateTime? startTime,
    DateTime? endTime,
    String? subject,
    String? location,
    String? color,
    bool? hasReminder,
    int? reminderMinutesBefore,
    String? noteId,
    Object? seriesId = _unset,
    bool? isCompleted,
    Object? completedAt = _unset,
    int? rolloverCount,
    String? userId,
    DateTime? createdAt,
    bool? isDirty,
    bool? isDeleted,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      type: type ?? this.type,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      subject: subject ?? this.subject,
      location: location ?? this.location,
      color: color ?? this.color,
      hasReminder: hasReminder ?? this.hasReminder,
      reminderMinutesBefore:
          reminderMinutesBefore ?? this.reminderMinutesBefore,
      noteId: noteId ?? this.noteId,
      seriesId: seriesId == _unset ? this.seriesId : seriesId as String?,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt:
          completedAt == _unset ? this.completedAt : completedAt as DateTime?,
      rolloverCount: rolloverCount ?? this.rolloverCount,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
      isDirty: isDirty ?? this.isDirty,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'type': type.index,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime?.toIso8601String(),
        'subject': subject,
        'location': location,
        'color': color,
        'hasReminder': hasReminder,
        'reminderMinutesBefore': reminderMinutesBefore,
        'noteId': noteId,
        'seriesId': seriesId,
        'isCompleted': isCompleted,
        'completedAt': completedAt?.toIso8601String(),
        'rolloverCount': rolloverCount,
        'userId': userId,
        'createdAt': createdAt.toIso8601String(),
        'isDeleted': isDeleted,
      };

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        type: EventType.values[json['type'] as int? ?? 4],
        startTime: DateTime.parse(json['startTime'] as String),
        endTime: json['endTime'] != null
            ? DateTime.parse(json['endTime'] as String)
            : null,
        subject: json['subject'] as String?,
        location: json['location'] as String?,
        color: json['color'] as String?,
        hasReminder: json['hasReminder'] as bool? ?? true,
        reminderMinutesBefore: json['reminderMinutesBefore'] as int? ?? 30,
        noteId: json['noteId'] as String?,
        seriesId: json['seriesId'] as String?,
        isCompleted: json['isCompleted'] as bool? ?? false,
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : null,
        rolloverCount: json['rolloverCount'] as int? ?? 0,
        userId: json['userId'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        isDirty: false,
        isDeleted: json['isDeleted'] as bool? ?? false,
      );

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        type,
        startTime,
        endTime,
        subject,
        location,
        color,
        hasReminder,
        reminderMinutesBefore,
        noteId,
        seriesId,
        isCompleted,
        completedAt,
        rolloverCount,
        userId,
        createdAt,
        isDirty,
        isDeleted,
      ];
}
