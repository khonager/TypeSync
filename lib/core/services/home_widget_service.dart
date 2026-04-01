library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../../features/home/models/upcoming_item_view_data.dart';
import '../../features/home/widgets/home_upcoming_widget_preview.dart';
import '../theme/app_theme.dart';

class HomeWidgetService {
  HomeWidgetService._();

  static final HomeWidgetService instance = HomeWidgetService._();

  static const String androidWidgetName = 'TypeSyncUpcomingWidgetProvider';
  static const String androidQualifiedName =
      'com.khonager.typesync.TypeSyncUpcomingWidgetProvider';
  static const String iosWidgetName = 'TypeSyncUpcomingWidget';
  static const String iosAppGroupId = 'group.com.khonager.typesync';

  static const String widgetImageKey = 'typesync_upcoming_image';
  static const String placeholderTitleKey = 'typesync_upcoming_placeholder_title';
  static const String placeholderSubtitleKey =
      'typesync_upcoming_placeholder_subtitle';

  bool _configured = false;

  bool get _supportsWidgets {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<void> syncUpcoming({
    required List<UpcomingItemViewData> items,
    required Brightness brightness,
    required Color accentColor,
  }) async {
    if (!_supportsWidgets) {
      return;
    }

    await _configurePlatform();

    final placeholderTitle =
        items.isEmpty ? 'No upcoming items' : 'Upcoming in TypeSync';
    final placeholderSubtitle = items.isEmpty
        ? 'Open TypeSync to add homework or events'
        : 'Open the app to refresh this widget';

    await HomeWidget.saveWidgetData<String>(
      placeholderTitleKey,
      placeholderTitle,
    );
    await HomeWidget.saveWidgetData<String>(
      placeholderSubtitleKey,
      placeholderSubtitle,
    );

    await HomeWidget.renderFlutterWidget(
      _buildPreview(
        items: items,
        brightness: brightness,
        accentColor: accentColor,
      ),
      key: widgetImageKey,
      logicalSize: const Size(360, 176),
    );

    await HomeWidget.updateWidget(
      name: androidWidgetName,
      qualifiedAndroidName: androidQualifiedName,
      iOSName: iosWidgetName,
    );
  }

  Future<void> _configurePlatform() async {
    if (_configured) {
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await HomeWidget.setAppGroupId(iosAppGroupId);
    }

    _configured = true;
  }

  Widget _buildPreview({
    required List<UpcomingItemViewData> items,
    required Brightness brightness,
    required Color accentColor,
  }) {
    final theme = brightness == Brightness.dark
        ? AppTheme.darkTheme(accentColor)
        : AppTheme.lightTheme(accentColor);

    return Theme(
      data: theme,
      child: MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 176),
          devicePixelRatio: 2,
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: HomeUpcomingWidgetPreview(items: items),
            ),
          ),
        ),
      ),
    );
  }
}
