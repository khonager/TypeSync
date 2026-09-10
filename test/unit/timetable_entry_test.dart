import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:typesync/core/models/timetable_entry.dart';
import 'package:typesync/core/providers/timetable_provider.dart';

void main() {
  group('TimetableEntry', () {
    const entry = TimetableEntry(
      id: 'entry-1',
      subject: 'Mathematics',
      teacher: 'Ms. Smith',
      room: '101',
      weekday: Weekday.monday,
      startHour: 9,
      startMinute: 0,
      endHour: 10,
      endMinute: 0,
      userId: 'user-1',
      timetableId: '2026',
      timetableName: '2026',
      classSlot: 7,
      endClassSlot: 8,
      classSlots: [7, 8],
      usesCustomTime: true,
    );

    test('round-trips named timetable fields through JSON', () {
      expect(
        TimetableEntry.fromJson(entry.toJson()),
        entry.copyWith(isDirty: false),
      );
    });

    test('can explicitly clear teacher and room', () {
      final cleared = entry.copyWith(teacher: null, room: null);

      expect(cleared.teacher, isNull);
      expect(cleared.room, isNull);
    });

    test('loads old cloud entries into the default timetable', () {
      final json = entry.toJson()
        ..remove('timetableId')
        ..remove('timetableName');
      final restored = TimetableEntry.fromJson(json);

      expect(restored.timetableId, 'default');
      expect(restored.timetableName, 'My timetable');
    });

    test('calculates default class slots around the configured breaks', () {
      const schedule = TimetableDefinition(id: 'default', name: 'School');

      expect(schedule.startMinutesForSlot(1), 8 * 60);
      expect(schedule.endMinutesForSlot(1), 8 * 60 + 45);
      expect(schedule.startMinutesForSlot(3), 9 * 60 + 45);
      expect(schedule.startMinutesForSlot(7), 13 * 60 + 30);
      expect(schedule.endMinutesForSlot(7), 14 * 60 + 15);
      expect(schedule.slotForTimes(13 * 60 + 30, 14 * 60 + 15), 7);
    });

    test('round-trips customized class timing settings', () {
      const schedule = TimetableDefinition(
        id: 'custom',
        name: 'Custom',
        dayStartMinutes: 7 * 60 + 30,
        classDurationMinutes: 50,
        breakAfter2Minutes: 10,
        breakAfter4Minutes: 20,
        breakAfter6Minutes: 25,
      );

      expect(TimetableDefinition.fromJson(schedule.toJson()), schedule);
    });
  });

  group('TimetableProvider', () {
    late Directory hiveDirectory;

    setUp(() async {
      hiveDirectory =
          await Directory.systemTemp.createTemp('typesync_timetable_');
      Hive.init(hiveDirectory.path);
    });

    tearDown(() async {
      await Hive.close();
      await hiveDirectory.delete(recursive: true);
    });

    test('persists, switches, and filters named timetables', () async {
      final provider = TimetableProvider();
      await provider.initialize('user-1');
      await provider.createEntry(
        userId: 'user-1',
        subject: 'Math',
        teacher: 'Ms. Smith',
        room: '101',
        weekday: Weekday.monday,
        startHour: 9,
        startMinute: 0,
        endHour: 10,
        endMinute: 0,
      );

      final second = await provider.createTimetable('2027');
      await provider.createEntry(
        userId: 'user-1',
        subject: 'Physics',
        teacher: 'Dr. Jones',
        room: 'Lab A',
        weekday: Weekday.monday,
        startHour: 10,
        startMinute: 0,
        endHour: 11,
        endMinute: 0,
      );

      expect(provider.entries.map((entry) => entry.subject), ['Physics']);
      expect(provider.teacherSuggestions, ['Dr. Jones', 'Ms. Smith']);
      expect(provider.roomSuggestions, ['101', 'Lab A']);

      await provider.closeWorkspace();
      await provider.initialize('user-1');

      expect(provider.activeTimetableId, second!.id);
      expect(provider.activeTimetable.name, '2027');
      expect(provider.entries.map((entry) => entry.subject), ['Physics']);
    });

    test('updates slot times while preserving manual overrides', () async {
      final provider = TimetableProvider();
      await provider.initialize('user-2');
      final scheduled = await provider.createEntry(
        userId: 'user-2',
        subject: 'Scheduled',
        weekday: Weekday.monday,
        startHour: 8,
        startMinute: 0,
        endHour: 9,
        endMinute: 30,
        classSlot: 1,
        endClassSlot: 2,
        classSlots: [1, 2],
      );
      final custom = await provider.createEntry(
        userId: 'user-2',
        subject: 'Custom',
        weekday: Weekday.monday,
        startHour: 8,
        startMinute: 5,
        endHour: 8,
        endMinute: 50,
        classSlot: 1,
        usesCustomTime: true,
      );

      final updated = await provider.updateActiveTimetableSchedule(
        dayStartMinutes: 7 * 60 + 30,
        classDurationMinutes: 50,
        breakAfter2Minutes: 10,
        breakAfter4Minutes: 20,
        breakAfter6Minutes: 25,
      );

      expect(updated, isTrue);
      expect(provider.getEntryById(scheduled!.id)!.startTimeFormatted, '07:30');
      expect(provider.getEntryById(scheduled.id)!.endTimeFormatted, '09:10');
      expect(provider.getEntryById(custom!.id)!.startTimeFormatted, '08:05');

      await provider.closeWorkspace();
      await provider.initialize('user-2');
      expect(provider.activeTimetable.classDurationMinutes, 50);
      expect(provider.activeTimetable.breakAfter6Minutes, 25);
      expect(provider.getEntryById(scheduled.id)!.endClassSlot, 2);
      expect(provider.getEntryById(scheduled.id)!.classSlots, [1, 2]);
    });
  });
}
