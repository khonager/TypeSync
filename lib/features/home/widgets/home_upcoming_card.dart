library;

import 'package:flutter/material.dart';

import '../models/upcoming_item_view_data.dart';

class HomeUpcomingCard extends StatelessWidget {
  final List<UpcomingItemViewData> items;
  final ValueChanged<UpcomingItemViewData>? onItemTap;
  final String title;
  final EdgeInsetsGeometry contentPadding;

  const HomeUpcomingCard({
    required this.items,
    super.key,
    this.onItemTap,
    this.title = 'Upcoming',
    this.contentPadding = const EdgeInsets.fromLTRB(12, 10, 12, 8),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < items.length; i++)
              _UpcomingRow(
                item: items[i],
                showDivider: i < items.length - 1,
                onTap: onItemTap == null ? null : () => onItemTap!(items[i]),
              ),
          ],
        ),
      ),
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  final UpcomingItemViewData item;
  final bool showDivider;
  final VoidCallback? onTap;

  const _UpcomingRow({
    required this.item,
    required this.showDivider,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = item.accentColor(theme);
    final row = Padding(
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
    );

    return Column(
      children: [
        if (onTap == null)
          row
        else
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: row,
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
