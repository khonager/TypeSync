library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:typesync/core/models/calendar_event.dart';
import 'package:typesync/core/providers/calendar_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDir;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('typesync_calendar_test_');
    Hive.init(hiveDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (await hiveDir.exists()) {
      await hiveDir.delete(recursive: true);
    }
  });

  group('CalendarProvider todo completion', () {
    test('completed todo is anchored to the day it was checked off', () async {
      final provider = CalendarProvider();
      await provider.initialize('user-1');

      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final created = await provider.createEvent(
        userId: 'user-1',
        title: 'Finish worksheet',
        startTime: yesterday,
        type: EventType.todo,
      );

      expect(created, isNotNull);

      final success = await provider.toggleTodoCompletion(
        eventId: created!.id,
        isCompleted: true,
      );

      expect(success, isTrue);

      final updated = provider.getEventById(created.id);
      final today = DateTime.now();

      expect(updated, isNotNull);
      expect(updated!.isCompleted, isTrue);
      expect(updated.completedAt, isNotNull);
      expect(updated.calendarDate.year, today.year);
      expect(updated.calendarDate.month, today.month);
      expect(updated.calendarDate.day, today.day);
      expect(updated.startTime.year, today.year);
      expect(updated.startTime.month, today.month);
      expect(updated.startTime.day, today.day);
    });

    test('unchecking a todo clears its completion timestamp', () async {
      final provider = CalendarProvider();
      await provider.initialize('user-2');

      final created = await provider.createEvent(
        userId: 'user-2',
        title: 'Review notes',
        startTime: DateTime.now(),
        type: EventType.todo,
      );

      expect(created, isNotNull);

      await provider.toggleTodoCompletion(
        eventId: created!.id,
        isCompleted: true,
      );
      final success = await provider.toggleTodoCompletion(
        eventId: created.id,
        isCompleted: false,
      );

      expect(success, isTrue);

      final updated = provider.getEventById(created.id);
      expect(updated, isNotNull);
      expect(updated!.isCompleted, isFalse);
      expect(updated.completedAt, isNull);
    });

    test('creating events for multiple dates links them with one series id',
        () async {
      final provider = CalendarProvider();
      await provider.initialize('user-3');

      final created = await provider.createEventsForDates(
        userId: 'user-3',
        title: 'Revision block',
        dates: [
          DateTime(2026, 6, 17),
          DateTime(2026, 6, 18),
          DateTime(2026, 6, 20),
        ],
        startTimeTemplate: DateTime(2026, 6, 17, 9, 30),
        type: EventType.reminder,
      );

      expect(created, hasLength(3));
      expect(created.map((event) => event.seriesId).toSet(), hasLength(1));
      expect(created.first.seriesId, isNotNull);
      expect(
        created.map((event) => event.startTime.day).toList()..sort(),
        [17, 18, 20],
      );
      expect(
        created.every(
          (event) => event.startTime.hour == 9 && event.startTime.minute == 30,
        ),
        isTrue,
      );
    });
  });
}
