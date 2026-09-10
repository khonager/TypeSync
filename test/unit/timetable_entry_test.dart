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
  });
}
