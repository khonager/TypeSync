library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/models/calendar_event.dart';
import '../../../core/models/homework.dart';

enum UpcomingItemKind {
  calendar,
  homework,
}

class UpcomingItemViewData {
  final UpcomingItemKind kind;
  final String title;
  final DateTime dateTime;
  final String primaryMeta;
  final String? secondaryMeta;
  final IconData icon;
  final bool isOverdue;

  const UpcomingItemViewData({
    required this.kind,
    required this.title,
    required this.dateTime,
    required this.primaryMeta,
    required this.secondaryMeta,
    required this.icon,
    required this.isOverdue,
  });

  factory UpcomingItemViewData.fromCalendarEvent(CalendarEvent event) {
    return UpcomingItemViewData(
      kind: UpcomingItemKind.calendar,
      title: event.title,
      dateTime: event.startTime,
      primaryMeta: formatDayLabel(event.startTime),
      secondaryMeta: DateFormat.jm().format(event.startTime),
      icon: _calendarIcon(event.type),
      isOverdue: false,
    );
  }

  factory UpcomingItemViewData.fromHomework(Homework homework) {
    final dueDate = homework.dueDate!;
    return UpcomingItemViewData(
      kind: UpcomingItemKind.homework,
      title: homework.title,
      dateTime: dueDate,
      primaryMeta:
          homework.isOverdue ? 'Overdue' : 'Due ${formatDayLabel(dueDate)}',
      secondaryMeta: _formatHomeworkTime(dueDate),
      icon: Icons.assignment_outlined,
      isOverdue: homework.isOverdue,
    );
  }

  static List<UpcomingItemViewData> build({
    required List<CalendarEvent> calendarEvents,
    required List<Homework> homeworkItems,
    int? limit,
  }) {
    final items = <UpcomingItemViewData>[
      ...calendarEvents.map(UpcomingItemViewData.fromCalendarEvent),
      ...homeworkItems
          .where((item) => !item.isCompleted && item.dueDate != null)
          .map(UpcomingItemViewData.fromHomework),
    ];

    items.sort((a, b) {
      if (a.isOverdue != b.isOverdue) {
        return a.isOverdue ? -1 : 1;
      }

      final dateCompare = a.dateTime.compareTo(b.dateTime);
      if (dateCompare != 0) {
        return dateCompare;
      }

      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    if (limit != null && items.length > limit) {
      return items.take(limit).toList(growable: false);
    }

    return items;
  }

  Color accentColor(ThemeData theme) {
    if (isOverdue) {
      return theme.colorScheme.error;
    }

    return kind == UpcomingItemKind.homework
        ? const Color(0xFFE39A34)
        : theme.colorScheme.primary;
  }

  static IconData _calendarIcon(EventType type) {
    switch (type) {
      case EventType.test:
      case EventType.exam:
        return Icons.event_note_outlined;
      case EventType.assignment:
        return Icons.assignment_turned_in_outlined;
      case EventType.classEvent:
        return Icons.school_outlined;
      case EventType.reminder:
        return Icons.notifications_outlined;
      case EventType.other:
        return Icons.event_outlined;
    }
  }

  static String formatDayLabel(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dateTime.year, dateTime.month, dateTime.day);
    final dayOffset = date.difference(today).inDays;

    if (dayOffset == 0) {
      return 'Today';
    }
    if (dayOffset == 1) {
      return 'Tomorrow';
    }
    if (dayOffset > 1 && dayOffset < 7) {
      return DateFormat('EEE').format(dateTime);
    }
    return DateFormat('MMM d').format(dateTime);
  }

  static String? _formatHomeworkTime(DateTime dueDate) {
    final hasMeaningfulTime =
        dueDate.hour != 0 || dueDate.minute != 0 || dueDate.second != 0;
    if (!hasMeaningfulTime) {
      return null;
    }

    return DateFormat.jm().format(dueDate);
  }
}
