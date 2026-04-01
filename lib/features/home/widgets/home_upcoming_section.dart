/// Compact upcoming section for the home screen.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/calendar_provider.dart';
import '../../../core/providers/homework_provider.dart';
import '../../../core/routes/app_router.dart';
import '../models/upcoming_item_view_data.dart';
import 'home_upcoming_card.dart';

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

        final items = UpcomingItemViewData.build(
          calendarEvents: calendarProvider.upcomingEvents,
          homeworkItems: homeworkProvider.homework,
          limit: _maxVisibleItems,
        );
        if (items.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: HomeUpcomingCard(
            items: items,
            onItemTap: (item) {
              AppRouter.navigateTo(
                context,
                item.kind == UpcomingItemKind.homework
                    ? AppRouter.homework
                    : AppRouter.calendar,
              );
            },
          ),
        );
      },
    );
  }
}
