/// Compact upcoming section for the home screen.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/calendar_provider.dart';
import '../../../core/providers/homework_provider.dart';
import '../../../core/routes/app_router.dart';
import '../../../core/services/theme_service.dart';
import '../models/upcoming_item_view_data.dart';
import 'home_upcoming_card.dart';

class HomeUpcomingSection extends StatelessWidget {
  static const int _maxVisibleItems = 3;

  const HomeUpcomingSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer3<CalendarProvider, HomeworkProvider, ThemeService>(
      builder: (context, calendarProvider, homeworkProvider, themeService, _) {
        final visibilityMode = themeService.homeUpcomingVisibilityMode;
        if (visibilityMode == HomeUpcomingVisibilityMode.never) {
          return const SizedBox.shrink();
        }

        if (calendarProvider.isLoading || homeworkProvider.isLoading) {
          if (visibilityMode == HomeUpcomingVisibilityMode.always) {
            return const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: HomeUpcomingCard(
                items: [],
                emptyMessage: 'Loading upcoming items...',
              ),
            );
          }
          return const SizedBox.shrink();
        }

        final items = UpcomingItemViewData.build(
          calendarEvents: calendarProvider.upcomingEvents,
          homeworkItems: homeworkProvider.homework,
          limit: _maxVisibleItems,
        );
        if (visibilityMode == HomeUpcomingVisibilityMode.onlyWithItems &&
            items.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: HomeUpcomingCard(
            items: items,
            onItemTap: (item) {
              final arguments = item.kind == UpcomingItemKind.calendar
                  ? <String, Object>{'initialDate': item.dateTime}
                  : null;
              AppRouter.navigateTo(
                context,
                item.kind == UpcomingItemKind.homework
                    ? AppRouter.homework
                    : AppRouter.calendar,
                arguments: arguments,
              );
            },
            onItemCheck: (item) async {
              if (!item.isCompletable) return;
              await homeworkProvider.toggleCompletion(item.sourceId);
            },
            emptySubtitle: visibilityMode == HomeUpcomingVisibilityMode.always
                ? 'Open TypeSync to add homework or events'
                : null,
          ),
        );
      },
    );
  }
}
