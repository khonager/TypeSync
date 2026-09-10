/// Timetable Entry Model
library;

///
/// Represents a recurring class/subject in the weekly timetable.

import 'package:equatable/equatable.dart';

/// A saved, named timetable that entries can belong to.
class TimetableDefinition extends Equatable {
  final String id;
  final String name;
  final int dayStartMinutes;
  final int classDurationMinutes;
  final int breakAfter2Minutes;
  final int breakAfter4Minutes;
  final int breakAfter6Minutes;

  const TimetableDefinition({
    required this.id,
    required this.name,
    this.dayStartMinutes = 8 * 60,
    this.classDurationMinutes = 45,
    this.breakAfter2Minutes = 15,
    this.breakAfter4Minutes = 15,
    this.breakAfter6Minutes = 30,
  });

  int startMinutesForSlot(int slot) {
    assert(slot >= 1);
    var minutes = dayStartMinutes + ((slot - 1) * classDurationMinutes);
    if (slot > 2) minutes += breakAfter2Minutes;
    if (slot > 4) minutes += breakAfter4Minutes;
    if (slot > 6) minutes += breakAfter6Minutes;
    return minutes;
  }

  int endMinutesForSlot(int slot) =>
      startMinutesForSlot(slot) + classDurationMinutes;

  int? slotForTimes(int startMinutes, int endMinutes, {int maxSlots = 12}) {
    for (var slot = 1; slot <= maxSlots; slot++) {
      if (startMinutesForSlot(slot) == startMinutes &&
          endMinutesForSlot(slot) == endMinutes) {
        return slot;
      }
    }
    return null;
  }

  TimetableDefinition copyWith({
    String? id,
    String? name,
    int? dayStartMinutes,
    int? classDurationMinutes,
    int? breakAfter2Minutes,
    int? breakAfter4Minutes,
    int? breakAfter6Minutes,
  }) =>
      TimetableDefinition(
        id: id ?? this.id,
        name: name ?? this.name,
        dayStartMinutes: dayStartMinutes ?? this.dayStartMinutes,
        classDurationMinutes: classDurationMinutes ?? this.classDurationMinutes,
        breakAfter2Minutes: breakAfter2Minutes ?? this.breakAfter2Minutes,
        breakAfter4Minutes: breakAfter4Minutes ?? this.breakAfter4Minutes,
        breakAfter6Minutes: breakAfter6Minutes ?? this.breakAfter6Minutes,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'dayStartMinutes': dayStartMinutes,
        'classDurationMinutes': classDurationMinutes,
        'breakAfter2Minutes': breakAfter2Minutes,
        'breakAfter4Minutes': breakAfter4Minutes,
        'breakAfter6Minutes': breakAfter6Minutes,
      };

  factory TimetableDefinition.fromJson(Map<dynamic, dynamic> json) =>
      TimetableDefinition(
        id: json['id'] as String,
        name: json['name'] as String,
        dayStartMinutes: (json['dayStartMinutes'] as num?)?.toInt() ?? 8 * 60,
        classDurationMinutes:
            (json['classDurationMinutes'] as num?)?.toInt() ?? 45,
        breakAfter2Minutes: (json['breakAfter2Minutes'] as num?)?.toInt() ?? 15,
        breakAfter4Minutes: (json['breakAfter4Minutes'] as num?)?.toInt() ?? 15,
        breakAfter6Minutes: (json['breakAfter6Minutes'] as num?)?.toInt() ?? 30,
      );

  @override
  List<Object> get props => [
        id,
        name,
        dayStartMinutes,
        classDurationMinutes,
        breakAfter2Minutes,
        breakAfter4Minutes,
        breakAfter6Minutes,
      ];
}

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
  final String timetableId;
  final String timetableName;
  final int? classSlot;
  final int? endClassSlot;
  final List<int> classSlots;
  final bool usesCustomTime;

  const TimetableEntry({
    required this.id,
    required this.subject,
    required this.weekday,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    required this.userId,
    this.teacher,
    this.room,
    this.color = '#64D2FF',
    this.isDirty = true,
    this.isDeleted = false,
    this.timetableId = 'default',
    this.timetableName = 'My timetable',
    this.classSlot,
    this.endClassSlot,
    this.classSlots = const [],
    this.usesCustomTime = false,
  });

  List<int> get selectedClassSlots {
    if (classSlots.isNotEmpty) {
      final slots = classSlots.toSet().where((slot) => slot >= 1).toList()
        ..sort();
      return slots;
    }
    if (classSlot == null) return const [];
    final lastSlot = endClassSlot ?? classSlot!;
    if (lastSlot < classSlot!) return [classSlot!];
    return List.generate(
      lastSlot - classSlot! + 1,
      (index) => classSlot! + index,
    );
  }

  String get startTimeFormatted =>
      '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}';

  String get endTimeFormatted =>
      '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}';

  TimetableEntry copyWith({
    String? id,
    String? subject,
    Object? teacher = _notProvided,
    Object? room = _notProvided,
    Weekday? weekday,
    int? startHour,
    int? startMinute,
    int? endHour,
    int? endMinute,
    String? color,
    String? userId,
    bool? isDirty,
    bool? isDeleted,
    String? timetableId,
    String? timetableName,
    Object? classSlot = _notProvided,
    Object? endClassSlot = _notProvided,
    Object? classSlots = _notProvided,
    bool? usesCustomTime,
  }) {
    return TimetableEntry(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      teacher:
          identical(teacher, _notProvided) ? this.teacher : teacher as String?,
      room: identical(room, _notProvided) ? this.room : room as String?,
      weekday: weekday ?? this.weekday,
      startHour: startHour ?? this.startHour,
      startMinute: startMinute ?? this.startMinute,
      endHour: endHour ?? this.endHour,
      endMinute: endMinute ?? this.endMinute,
      color: color ?? this.color,
      userId: userId ?? this.userId,
      isDirty: isDirty ?? this.isDirty,
      isDeleted: isDeleted ?? this.isDeleted,
      timetableId: timetableId ?? this.timetableId,
      timetableName: timetableName ?? this.timetableName,
      classSlot: identical(classSlot, _notProvided)
          ? this.classSlot
          : classSlot as int?,
      endClassSlot: identical(endClassSlot, _notProvided)
          ? this.endClassSlot
          : endClassSlot as int?,
      classSlots: identical(classSlots, _notProvided)
          ? this.classSlots
          : List<int>.unmodifiable(classSlots as List<int>),
      usesCustomTime: usesCustomTime ?? this.usesCustomTime,
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
        'timetableId': timetableId,
        'timetableName': timetableName,
        'classSlot': classSlot,
        'endClassSlot': endClassSlot,
        'classSlots': classSlots,
        'usesCustomTime': usesCustomTime,
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
        timetableId: json['timetableId'] as String? ?? 'default',
        timetableName: json['timetableName'] as String? ?? 'My timetable',
        classSlot: (json['classSlot'] as num?)?.toInt(),
        endClassSlot: (json['endClassSlot'] as num?)?.toInt(),
        classSlots: (json['classSlots'] as List<dynamic>?)
                ?.whereType<num>()
                .map((value) => value.toInt())
                .toList() ??
            const [],
        usesCustomTime: json['usesCustomTime'] as bool? ?? false,
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
        timetableId,
        timetableName,
        classSlot,
        endClassSlot,
        classSlots,
        usesCustomTime,
      ];
}

const Object _notProvided = Object();
