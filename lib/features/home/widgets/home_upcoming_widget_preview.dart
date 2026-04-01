library;

import 'package:flutter/material.dart';

import '../models/upcoming_item_view_data.dart';
import 'home_upcoming_card.dart';

class HomeUpcomingWidgetPreview extends StatelessWidget {
  final List<UpcomingItemViewData> items;
  final HomeUpcomingWidgetLayoutSpec? layoutSpec;

  const HomeUpcomingWidgetPreview({
    required this.items,
    this.layoutSpec,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedLayout = layoutSpec ??
            HomeUpcomingWidgetLayoutSpec.fromSize(
              constraints.biggest,
            );
        final visibleItems =
            items.take(resolvedLayout.maxItems).toList(growable: false);
        final hasItems = visibleItems.isNotEmpty;

        return SizedBox.expand(
          child: Material(
            color: Colors.transparent,
            child: hasItems
                ? HomeUpcomingCard(
                    items: visibleItems,
                    contentPadding: resolvedLayout.contentPadding,
                  )
                : _EmptyUpcomingCard(
                    contentPadding: resolvedLayout.contentPadding,
                  ),
          ),
        );
      },
    );
  }
}

class HomeUpcomingWidgetLayoutSpec {
  final int maxItems;
  final EdgeInsets contentPadding;

  const HomeUpcomingWidgetLayoutSpec({
    required this.maxItems,
    required this.contentPadding,
  });

  factory HomeUpcomingWidgetLayoutSpec.fromSize(Size size) {
    final isCompact = size.height < 150;
    final isTall = size.height >= 220;
    final horizontalPadding = size.width >= 420 ? 16.0 : 14.0;

    return HomeUpcomingWidgetLayoutSpec(
      maxItems: isTall ? 4 : (isCompact ? 2 : 3),
      contentPadding: EdgeInsets.fromLTRB(
        horizontalPadding,
        isCompact ? 10 : 12,
        horizontalPadding,
        isCompact ? 8 : 10,
      ),
    );
  }
}

class _EmptyUpcomingCard extends StatelessWidget {
  final EdgeInsetsGeometry contentPadding;

  const _EmptyUpcomingCard({
    required this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: contentPadding,
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
