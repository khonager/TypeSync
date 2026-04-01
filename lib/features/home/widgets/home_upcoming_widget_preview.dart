library;

import 'package:flutter/material.dart';

import '../models/upcoming_item_view_data.dart';
import 'home_upcoming_card.dart';

class HomeUpcomingWidgetPreview extends StatelessWidget {
  final List<UpcomingItemViewData> items;

  const HomeUpcomingWidgetPreview({
    required this.items,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final hasItems = items.isNotEmpty;

    return SizedBox(
      width: 340,
      child: Material(
        color: Colors.transparent,
        child: hasItems
            ? HomeUpcomingCard(
                items: items,
                contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              )
            : _EmptyUpcomingCard(),
      ),
    );
  }
}

class _EmptyUpcomingCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Upcoming',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No upcoming items',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Open TypeSync to add homework or events',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
