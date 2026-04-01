/// Compact upcoming section for the home screen.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/models/calendar_event.dart';
import '../../../core/models/homework.dart';
import '../../../core/providers/calendar_provider.dart';
import '../../../core/providers/homework_provider.dart';
import '../../../core/routes/app_router.dart';

class HomeUpcomingSection extends StatelessWidget {
  static const int _maxVisibleItems = 3;

  const HomeUpcomingSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<CalendarProvider, HomeworkProvider>(
      builder: (context, calendarProvider, homeworkProvider, _) {
        if (calendarProvider.isLoading || homeworkProvider.isLoading) {
          return const SizedBox.shrink();
        }

        final items = _buildItems(calendarProvider, homeworkProvider);
        if (items.isEmpty) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final visibleItems =
            items.take(_maxVisibleItems).toList(growable: false);

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Upcoming',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (var i = 0; i < visibleItems.length; i++)
                    _UpcomingRow(
                      item: visibleItems[i],
                      showDivider: i < visibleItems.length - 1,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<_UpcomingItem> _buildItems(
    CalendarProvider calendarProvider,
    HomeworkProvider homeworkProvider,
  ) {
    final items = <_UpcomingItem>[
      ...calendarProvider.upcomingEvents.map(_UpcomingItem.fromCalendarEvent),
      ...homeworkProvider.homework
          .where((item) => !item.isCompleted && item.dueDate != null)
          .map(_UpcomingItem.fromHomework),
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

    return items;
  }
}

class _UpcomingRow extends StatelessWidget {
  final _UpcomingItem item;
  final bool showDivider;

  const _UpcomingRow({
    required this.item,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = item.accentColor(theme);

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => item.open(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Icon(
                    item.icon,
                    size: 18,
                    color: accentColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 74),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          item.primaryMeta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: accentColor,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.right,
                        ),
                        if (item.secondaryMeta != null) ...[
                          const SizedBox(height: 1),
                          Text(
                            item.secondaryMeta!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            color: theme.colorScheme.outline.withValues(alpha: 0.08),
          ),
      ],
    );
  }
}

enum _UpcomingKind {
  calendar,
  homework,
}

class _UpcomingItem {
  final _UpcomingKind kind;
  final String title;
  final DateTime dateTime;
  final String primaryMeta;
  final String? secondaryMeta;
  final IconData icon;
  final bool isOverdue;

  const _UpcomingItem({
    required this.kind,
    required this.title,
    required this.dateTime,
    required this.primaryMeta,
    required this.secondaryMeta,
    required this.icon,
    required this.isOverdue,
  });

  factory _UpcomingItem.fromCalendarEvent(CalendarEvent event) {
    return _UpcomingItem(
      kind: _UpcomingKind.calendar,
      title: event.title,
      dateTime: event.startTime,
      primaryMeta: _formatDayLabel(event.startTime),
      secondaryMeta: DateFormat.jm().format(event.startTime),
      icon: _calendarIcon(event.type),
      isOverdue: false,
    );
  }

  factory _UpcomingItem.fromHomework(Homework homework) {
    final dueDate = homework.dueDate!;
    return _UpcomingItem(
      kind: _UpcomingKind.homework,
      title: homework.title,
      dateTime: dueDate,
      primaryMeta:
          homework.isOverdue ? 'Overdue' : 'Due ${_formatDayLabel(dueDate)}',
      secondaryMeta: _formatHomeworkTime(dueDate),
      icon: Icons.assignment_outlined,
      isOverdue: homework.isOverdue,
    );
  }

  void open(BuildContext context) {
    AppRouter.navigateTo(
      context,
      kind == _UpcomingKind.homework ? AppRouter.homework : AppRouter.calendar,
    );
  }

  Color accentColor(ThemeData theme) {
    if (isOverdue) {
      return theme.colorScheme.error;
    }

    return kind == _UpcomingKind.homework
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

  static String _formatDayLabel(DateTime dateTime) {
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
