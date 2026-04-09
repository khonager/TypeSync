library;

import 'package:flutter/material.dart';

import '../models/upcoming_item_view_data.dart';

class HomeUpcomingCard extends StatelessWidget {
  final List<UpcomingItemViewData> items;
  final ValueChanged<UpcomingItemViewData>? onItemTap;
  final ValueChanged<UpcomingItemViewData>? onItemCheck;
  final String title;
  final EdgeInsetsGeometry contentPadding;
  final HomeUpcomingCardLayout layout;
  final String emptyMessage;
  final String? emptySubtitle;

  const HomeUpcomingCard({
    required this.items,
    super.key,
    this.onItemTap,
    this.onItemCheck,
    this.title = 'Upcoming',
    this.contentPadding = const EdgeInsets.fromLTRB(12, 10, 12, 8),
    this.layout = const HomeUpcomingCardLayout(),
    this.emptyMessage = 'No upcoming items',
    this.emptySubtitle,
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
            SizedBox(height: layout.titleBottomSpacing),
            if (items.isEmpty)
              _EmptyUpcomingState(
                message: emptyMessage,
                subtitle: emptySubtitle,
              )
            else
              for (var i = 0; i < items.length; i++)
                _UpcomingRow(
                  item: items[i],
                  showDivider: i < items.length - 1,
                  onTap: onItemTap == null ? null : () => onItemTap!(items[i]),
                  onCheckTap: onItemCheck == null || !items[i].isCompletable
                      ? null
                      : () => onItemCheck!(items[i]),
                  layout: layout,
                ),
          ],
        ),
      ),
    );
  }
}

class HomeUpcomingCardLayout {
  final double titleBottomSpacing;
  final double rowVerticalPadding;
  final double iconSize;
  final double iconSpacing;
  final double metaSpacing;
  final double minMetaWidth;
  final double secondaryMetaSpacing;
  final BorderRadius itemBorderRadius;

  const HomeUpcomingCardLayout({
    this.titleBottomSpacing = 4,
    this.rowVerticalPadding = 10,
    this.iconSize = 18,
    this.iconSpacing = 10,
    this.metaSpacing = 12,
    this.minMetaWidth = 74,
    this.secondaryMetaSpacing = 1,
    this.itemBorderRadius = const BorderRadius.all(Radius.circular(10)),
  });
}

class _UpcomingRow extends StatelessWidget {
  final UpcomingItemViewData item;
  final bool showDivider;
  final VoidCallback? onTap;
  final VoidCallback? onCheckTap;
  final HomeUpcomingCardLayout layout;

  const _UpcomingRow({
    required this.item,
    required this.showDivider,
    required this.layout,
    this.onTap,
    this.onCheckTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = item.accentColor(theme);
    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: layout.rowVerticalPadding),
      child: Row(
        children: [
          Icon(
            item.icon,
            size: layout.iconSize,
            color: accentColor,
          ),
          SizedBox(width: layout.iconSpacing),
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
          SizedBox(width: layout.metaSpacing),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(minWidth: layout.minMetaWidth),
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
                      SizedBox(height: layout.secondaryMetaSpacing),
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
              if (onCheckTap != null) ...[
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Mark complete',
                  onPressed: onCheckTap,
                  icon: Icon(
                    Icons.check_circle_outline,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
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
              borderRadius: layout.itemBorderRadius,
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

class _EmptyUpcomingState extends StatelessWidget {
  final String message;
  final String? subtitle;

  const _EmptyUpcomingState({
    required this.message,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
