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
    test('applies new calendar events received while the app is open',
        () async {
      final provider = CalendarProvider();
      await provider.initialize('user-live-calendar');
      final remoteEvent = CalendarEvent(
        id: 'remote-event',
        userId: 'user-live-calendar',
        title: 'Added on another device',
        startTime: DateTime(2026, 7, 29, 14),
        createdAt: DateTime(2026, 7, 29, 13),
        isDirty: false,
      );

      provider.handleCloudUpdate([remoteEvent]);

      expect(provider.getEventById(remoteEvent.id), remoteEvent);
      expect(provider.getEventsForDate(remoteEvent.startTime), [remoteEvent]);
    });

    test('hides events deleted on another device', () async {
      final provider = CalendarProvider();
      await provider.initialize('user-live-calendar-delete');
      final remoteEvent = CalendarEvent(
        id: 'remote-deleted-event',
        userId: 'user-live-calendar-delete',
        title: 'Deleted elsewhere',
        startTime: DateTime(2026, 7, 29, 14),
        createdAt: DateTime(2026, 7, 29, 13),
        isDirty: false,
      );
      provider.handleCloudUpdate([remoteEvent]);

      provider.handleCloudUpdate([
        remoteEvent.copyWith(isDeleted: true),
      ]);

      expect(provider.events, isEmpty);
      expect(provider.getEventsForDate(remoteEvent.startTime), isEmpty);
    });

    test('lists completed todos after active calendar items', () async {
      final provider = CalendarProvider();
      await provider.initialize('user-calendar-order');

      final day = DateTime(2026, 7, 6);
      final completedTodo = await provider.createEvent(
        userId: 'user-calendar-order',
        title: 'Completed first',
        startTime: day.add(const Duration(hours: 8)),
        type: EventType.todo,
      );
      final activeTodo = await provider.createEvent(
        userId: 'user-calendar-order',
        title: 'Active second',
        startTime: day.add(const Duration(hours: 10)),
        type: EventType.todo,
      );
      final event = await provider.createEvent(
        userId: 'user-calendar-order',
        title: 'Calendar event',
        startTime: day.add(const Duration(hours: 9)),
        type: EventType.reminder,
      );

      await provider.toggleTodoCompletion(
        eventId: completedTodo!.id,
        isCompleted: true,
      );

      expect(
        provider.getEventsForDate(day).map((item) => item.id),
        [event!.id, activeTodo!.id, completedTodo.id],
      );
    });

    test('completed todo stays on its current calendar day', () async {
      final provider = CalendarProvider();
      await provider.initialize('user-1');

      final checkedDay = DateTime.now().subtract(const Duration(days: 1));
      final created = await provider.createEvent(
        userId: 'user-1',
        title: 'Finish worksheet',
        startTime: checkedDay,
        type: EventType.todo,
      );

      expect(created, isNotNull);

      final success = await provider.toggleTodoCompletion(
        eventId: created!.id,
        isCompleted: true,
      );

      expect(success, isTrue);

      final updated = provider.getEventById(created.id);

      expect(updated, isNotNull);
      expect(updated!.isCompleted, isTrue);
      expect(updated.completedAt, isNotNull);
      expect(updated.calendarDate.year, checkedDay.year);
      expect(updated.calendarDate.month, checkedDay.month);
      expect(updated.calendarDate.day, checkedDay.day);
      expect(updated.startTime.year, checkedDay.year);
      expect(updated.startTime.month, checkedDay.month);
      expect(updated.startTime.day, checkedDay.day);

      await provider.closeWorkspace();

      final reopenedProvider = CalendarProvider();
      await reopenedProvider.initialize('user-1');
      final reopened = reopenedProvider.getEventById(created.id);

      expect(reopened, isNotNull);
      expect(reopened!.isCompleted, isTrue);
      expect(reopened.calendarDate.year, checkedDay.year);
      expect(reopened.calendarDate.month, checkedDay.month);
      expect(reopened.calendarDate.day, checkedDay.day);
    });

    test('completed todo is not rolled over on the next day', () async {
      var now = DateTime(2026, 7, 6, 9);
      final provider = CalendarProvider(now: () => now);
      await provider.initialize('user-rollover-completed');

      final checkedDay = DateTime(2026, 7, 5, 8, 30);
      final created = await provider.createEvent(
        userId: 'user-rollover-completed',
        title: 'Already done',
        startTime: checkedDay,
        type: EventType.todo,
      );

      expect(created, isNotNull);
      await provider.toggleTodoCompletion(
        eventId: created!.id,
        isCompleted: true,
      );

      now = DateTime(2026, 7, 7, 9);
      await provider.rollOverPendingTodos();

      final updated = provider.getEventById(created.id);
      expect(updated, isNotNull);
      expect(updated!.isCompleted, isTrue);
      expect(updated.startTime, checkedDay);
      expect(updated.rolloverCount, 0);
      expect(provider.getEventsForDate(DateTime(2026, 7, 7)), isEmpty);
    });

    test('stale unchecked cloud update cannot make completed todo roll over',
        () async {
      var now = DateTime(2026, 7, 6, 9);
      final provider = CalendarProvider(now: () => now);
      await provider.initialize('user-stale-cloud');

      final checkedDay = DateTime(2026, 7, 5, 8, 30);
      final created = await provider.createEvent(
        userId: 'user-stale-cloud',
        title: 'Done before sync race',
        startTime: checkedDay,
        type: EventType.todo,
      );

      expect(created, isNotNull);
      await provider.toggleTodoCompletion(
        eventId: created!.id,
        isCompleted: true,
      );
      provider.debugClearDirtyFlagsForTesting();

      provider.handleCloudUpdate([
        provider.getEventById(created.id)!.copyWith(
              isCompleted: false,
              completedAt: null,
              isDirty: false,
            ),
      ]);

      final afterCloudUpdate = provider.getEventById(created.id);
      expect(afterCloudUpdate, isNotNull);
      expect(afterCloudUpdate!.isCompleted, isTrue);
      expect(afterCloudUpdate.completedAt, isNotNull);
      expect(afterCloudUpdate.startTime, checkedDay);

      now = DateTime(2026, 7, 7, 9);
      await provider.rollOverPendingTodos();

      final afterRollover = provider.getEventById(created.id);
      expect(afterRollover, isNotNull);
      expect(afterRollover!.isCompleted, isTrue);
      expect(afterRollover.startTime, checkedDay);
      expect(afterRollover.rolloverCount, 0);
      expect(provider.getEventsForDate(DateTime(2026, 7, 7)), isEmpty);
    });

    test('pending overdue todo rolls over to the current day', () async {
      var now = DateTime(2026, 7, 6, 9);
      final provider = CalendarProvider(now: () => now);
      await provider.initialize('user-rollover-pending');

      final originalDay = DateTime(2026, 7, 5, 8, 30);
      final created = await provider.createEvent(
        userId: 'user-rollover-pending',
        title: 'Still pending',
        startTime: originalDay,
        type: EventType.todo,
      );

      expect(created, isNotNull);

      now = DateTime(2026, 7, 7, 9);
      await provider.rollOverPendingTodos();

      final updated = provider.getEventById(created!.id);
      expect(updated, isNotNull);
      expect(updated!.isCompleted, isFalse);
      expect(updated.startTime, DateTime(2026, 7, 7, 8, 30));
      expect(updated.rolloverCount, 2);
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
