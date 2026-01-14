/// Timetable Entry Model
library;
///
/// Represents a recurring class/subject in the weekly timetable.

import 'package:equatable/equatable.dart';

/// Day of the week
enum Weekday {
  monday,
  tuesday,
  wednesday,
  thursday,
  friday,
  saturday,
  sunday,
}

/// Extension for weekday display names
extension WeekdayExtension on Weekday {
  String get shortName {
    switch (this) {
      case Weekday.monday:
        return 'Mon';
      case Weekday.tuesday:
        return 'Tue';
      case Weekday.wednesday:
        return 'Wed';
      case Weekday.thursday:
        return 'Thu';
      case Weekday.friday:
        return 'Fri';
      case Weekday.saturday:
        return 'Sat';
      case Weekday.sunday:
        return 'Sun';
    }
  }

  String get fullName {
    switch (this) {
      case Weekday.monday:
        return 'Monday';
      case Weekday.tuesday:
        return 'Tuesday';
      case Weekday.wednesday:
        return 'Wednesday';
      case Weekday.thursday:
        return 'Thursday';
      case Weekday.friday:
        return 'Friday';
      case Weekday.saturday:
        return 'Saturday';
      case Weekday.sunday:
        return 'Sunday';
    }
  }
}

/// Timetable entry for weekly schedule
class TimetableEntry extends Equatable {
  final String id;
  final String subject;
  final String? teacher;
  final String? room;
  final Weekday weekday;
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;
  final String color;
  final String userId;
  final bool isDirty;
  final bool isDeleted;

  const TimetableEntry({
    required this.id,
    required this.subject,
    this.teacher,
    this.room,
    required this.weekday,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    this.color = '#64D2FF',
    required this.userId,
    this.isDirty = true,
    this.isDeleted = false,
  });

  String get startTimeFormatted =>
      '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}';

  String get endTimeFormatted =>
      '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}';

  TimetableEntry copyWith({
    String? id,
    String? subject,
    String? teacher,
    String? room,
    Weekday? weekday,
    int? startHour,
    int? startMinute,
    int? endHour,
    int? endMinute,
    String? color,
    String? userId,
    bool? isDirty,
    bool? isDeleted,
  }) {
    return TimetableEntry(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      teacher: teacher ?? this.teacher,
      room: room ?? this.room,
      weekday: weekday ?? this.weekday,
      startHour: startHour ?? this.startHour,
      startMinute: startMinute ?? this.startMinute,
      endHour: endHour ?? this.endHour,
      endMinute: endMinute ?? this.endMinute,
      color: color ?? this.color,
      userId: userId ?? this.userId,
      isDirty: isDirty ?? this.isDirty,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'teacher': teacher,
        'room': room,
        'weekday': weekday.index,
        'startHour': startHour,
        'startMinute': startMinute,
        'endHour': endHour,
        'endMinute': endMinute,
        'color': color,
        'userId': userId,
        'isDeleted': isDeleted,
      };

  factory TimetableEntry.fromJson(Map<String, dynamic> json) => TimetableEntry(
        id: json['id'] as String,
        subject: json['subject'] as String,
        teacher: json['teacher'] as String?,
        room: json['room'] as String?,
        weekday: Weekday.values[json['weekday'] as int],
        startHour: json['startHour'] as int,
        startMinute: json['startMinute'] as int,
        endHour: json['endHour'] as int,
        endMinute: json['endMinute'] as int,
        color: json['color'] as String? ?? '#64D2FF',
        userId: json['userId'] as String,
        isDirty: false,
        isDeleted: json['isDeleted'] as bool? ?? false,
      );

  @override
  List<Object?> get props => [
        id,
        subject,
        teacher,
        room,
        weekday,
        startHour,
        startMinute,
        endHour,
        endMinute,
        color,
        userId,
        isDirty,
        isDeleted,
      ];
}
