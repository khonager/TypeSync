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
  });
}
