/// Calendar Event Model
/// 
/// Represents a calendar event such as a test reminder or class.

import 'package:equatable/equatable.dart';
import 'package:hive/hive.dart';

part 'calendar_event.g.dart';

/// Type of calendar event
@HiveType(typeId: 7)
enum EventType {
  @HiveField(0)
  test,
  
  @HiveField(1)
  exam,
  
  @HiveField(2)
  assignment,
  
  @HiveField(3)
  class_,
  
  @HiveField(4)
  reminder,
  
  @HiveField(5)
  other,
}

/// Calendar event model for test reminders and scheduling
@HiveType(typeId: 6)
class CalendarEvent extends Equatable {
  /// Unique identifier
  @HiveField(0)
  final String id;
  
  /// Event title
  @HiveField(1)
  final String title;
  
  /// Event description
  @HiveField(2)
  final String? description;
  
  /// Event type
  @HiveField(3)
  final EventType type;
  
  /// Event start time
  @HiveField(4)
  final DateTime startTime;
  
  /// Event end time
  @HiveField(5)
  final DateTime? endTime;
  
  /// Subject/class name
  @HiveField(6)
  final String? subject;
  
  /// Location
  @HiveField(7)
  final String? location;
  
  /// Color as hex string
  @HiveField(8)
  final String? color;
  
  /// Whether to send reminder notification
  @HiveField(9)
  final bool hasReminder;
  
  /// Minutes before event to send reminder
  @HiveField(10)
  final int reminderMinutesBefore;
  
  /// Related note ID
  @HiveField(11)
  final String? noteId;
  
  /// User ID
  @HiveField(12)
  final String userId;
  
  /// Creation timestamp
  @HiveField(13)
  final DateTime createdAt;
  
  /// Sync status
  @HiveField(14)
  final bool isDirty;
  
  /// Deleted status
  @HiveField(15)
  final bool isDeleted;
  
  /// Whether this is a recurring event
  @HiveField(16)
  final bool isRecurring;
  
  /// Recurrence rule (iCal format)
  @HiveField(17)
  final String? recurrenceRule;

  const CalendarEvent({
    required this.id,
    required this.title,
    this.description,
    this.type = EventType.reminder,
    required this.startTime,
    this.endTime,
    this.subject,
    this.location,
    this.color,
    this.hasReminder = true,
    this.reminderMinutesBefore = 30,
    this.noteId,
    required this.userId,
    required this.createdAt,
    this.isDirty = true,
    this.isDeleted = false,
    this.isRecurring = false,
    this.recurrenceRule,
  });

  factory CalendarEvent.create({
    required String id,
    required String userId,
    required String title,
    required DateTime startTime,
    EventType type = EventType.reminder,
    String? description,
    DateTime? endTime,
    String? subject,
  }) {
    return CalendarEvent(
      id: id,
      title: title,
      description: description,
      type: type,
      startTime: startTime,
      endTime: endTime,
      subject: subject,
      userId: userId,
      createdAt: DateTime.now(),
    );
  }

  /// Checks if event is happening today
  bool get isToday {
    final now = DateTime.now();
    return startTime.year == now.year &&
           startTime.month == now.month &&
           startTime.day == now.day;
  }

  /// Checks if event is upcoming within the next week
  bool get isUpcoming {
    final now = DateTime.now();
    final weekFromNow = now.add(const Duration(days: 7));
    return startTime.isAfter(now) && startTime.isBefore(weekFromNow);
  }

  /// Gets duration if end time is set
  Duration? get duration {
    if (endTime == null) return null;
    return endTime!.difference(startTime);
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
    String? userId,
    DateTime? createdAt,
    bool? isDirty,
    bool? isDeleted,
    bool? isRecurring,
    String? recurrenceRule,
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
      reminderMinutesBefore: reminderMinutesBefore ?? this.reminderMinutesBefore,
      noteId: noteId ?? this.noteId,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
      isDirty: isDirty ?? this.isDirty,
      isDeleted: isDeleted ?? this.isDeleted,
      isRecurring: isRecurring ?? this.isRecurring,
      recurrenceRule: recurrenceRule ?? this.recurrenceRule,
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
    'userId': userId,
    'createdAt': createdAt.toIso8601String(),
    'isDeleted': isDeleted,
    'isRecurring': isRecurring,
    'recurrenceRule': recurrenceRule,
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
    userId: json['userId'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    isDirty: false,
    isDeleted: json['isDeleted'] as bool? ?? false,
    isRecurring: json['isRecurring'] as bool? ?? false,
    recurrenceRule: json['recurrenceRule'] as String?,
  );

  @override
  List<Object?> get props => [
    id, title, description, type, startTime, endTime, subject, location,
    color, hasReminder, reminderMinutesBefore, noteId, userId, createdAt,
    isDirty, isDeleted, isRecurring, recurrenceRule,
  ];
}

