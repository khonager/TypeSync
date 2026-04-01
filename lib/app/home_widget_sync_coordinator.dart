library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/providers/calendar_provider.dart';
import '../core/providers/homework_provider.dart';
import '../core/services/home_widget_service.dart';
import '../core/services/theme_service.dart';
import '../core/utils/color_value_compat.dart';
import '../features/home/models/upcoming_item_view_data.dart';

class HomeWidgetSyncCoordinator extends StatefulWidget {
  final Widget child;

  const HomeWidgetSyncCoordinator({
    required this.child,
    super.key,
  });

  @override
  State<HomeWidgetSyncCoordinator> createState() =>
      _HomeWidgetSyncCoordinatorState();
}

class _HomeWidgetSyncCoordinatorState extends State<HomeWidgetSyncCoordinator> {
  String? _lastSignature;

  @override
  Widget build(BuildContext context) {
    final calendarProvider = context.watch<CalendarProvider>();
    final homeworkProvider = context.watch<HomeworkProvider>();
    final themeService = context.watch<ThemeService>();

    final items = UpcomingItemViewData.build(
      calendarEvents: calendarProvider.upcomingEvents,
      homeworkItems: homeworkProvider.homework,
      limit: 6,
    );
    final brightness = themeService.currentBrightness;
    final accentColor = themeService.accentColor;
    final signature = _buildSignature(
      items: items,
      brightness: brightness,
      accentColor: accentColor,
      calendarLoading: calendarProvider.isLoading,
      homeworkLoading: homeworkProvider.isLoading,
    );

    if (signature != _lastSignature) {
      _lastSignature = signature;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        HomeWidgetService.instance.syncUpcoming(
          items: items,
          brightness: brightness,
          accentColor: accentColor,
        );
      });
    }

    return widget.child;
  }

  String _buildSignature({
    required List<UpcomingItemViewData> items,
    required Brightness brightness,
    required Color accentColor,
    required bool calendarLoading,
    required bool homeworkLoading,
  }) {
    final itemSignature = items
        .map(
          (item) => [
            item.kind.name,
            item.title,
            item.dateTime.toIso8601String(),
            item.primaryMeta,
            item.secondaryMeta ?? '',
            item.isOverdue ? '1' : '0',
          ].join('|'),
        )
        .join('||');

    return [
      calendarLoading ? 'calendar-loading' : 'calendar-ready',
      homeworkLoading ? 'homework-loading' : 'homework-ready',
      brightness.name,
      colorToArgb32(accentColor).toString(),
      itemSignature,
    ].join('::');
  }
}
