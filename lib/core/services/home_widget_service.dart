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
      'de.khonager.typesync.TypeSyncUpcomingWidgetProvider';
  static const String iosWidgetName = 'TypeSyncUpcomingWidget';
  static const String iosAppGroupId = 'group.de.khonager.typesync';

  static const String widgetImageKey = 'typesync_upcoming_image';
  static const String compactWidgetImageKey = 'typesync_upcoming_image_280x140';
  static const String mediumTallWidgetImageKey =
      'typesync_upcoming_image_360x232';
  static const String wideWidgetImageKey = 'typesync_upcoming_image_480x176';
  static const String wideTallWidgetImageKey =
      'typesync_upcoming_image_480x232';
  static const String placeholderTitleKey =
      'typesync_upcoming_placeholder_title';
  static const String placeholderSubtitleKey =
      'typesync_upcoming_placeholder_subtitle';
  static const Size defaultWidgetSize = Size(360, 176);
  static const List<_WidgetSnapshotVariant> _androidWidgetVariants = [
    _WidgetSnapshotVariant(
      key: compactWidgetImageKey,
      logicalSize: Size(280, 140),
    ),
    _WidgetSnapshotVariant(
      key: widgetImageKey,
      logicalSize: defaultWidgetSize,
    ),
    _WidgetSnapshotVariant(
      key: mediumTallWidgetImageKey,
      logicalSize: Size(360, 232),
    ),
    _WidgetSnapshotVariant(
      key: wideWidgetImageKey,
      logicalSize: Size(480, 176),
    ),
    _WidgetSnapshotVariant(
      key: wideTallWidgetImageKey,
      logicalSize: Size(480, 232),
    ),
  ];

  bool _configured = false;
  bool _disabledForSession = false;

  bool get _supportsWidgets {
    if (kIsWeb) {
      return false;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // The repo currently lacks the native WidgetKit extension target and
      // App Group setup described in docs/ios_home_widget_setup.md.
      // Avoid touching the iOS home_widget bridge during startup until that
      // native setup exists, otherwise launch can fail very early.
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.android;
  }

  Future<void> syncUpcoming({
    required List<UpcomingItemViewData> items,
    required Brightness brightness,
    required Color accentColor,
  }) async {
    if (!_supportsWidgets || _disabledForSession) {
      return;
    }

    try {
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

      final renderOperations = <Future<String>>[
        HomeWidget.renderFlutterWidget(
          _buildPreview(
            items: items,
            brightness: brightness,
            accentColor: accentColor,
            logicalSize: defaultWidgetSize,
          ),
          key: widgetImageKey,
          logicalSize: defaultWidgetSize,
        ),
      ];

      if (defaultTargetPlatform == TargetPlatform.android) {
        renderOperations.addAll(
          _androidWidgetVariants
              .where((variant) => variant.key != widgetImageKey)
              .map(
                (variant) => HomeWidget.renderFlutterWidget(
                  _buildPreview(
                    items: items,
                    brightness: brightness,
                    accentColor: accentColor,
                    logicalSize: variant.logicalSize,
                  ),
                  key: variant.key,
                  logicalSize: variant.logicalSize,
                ),
              ),
        );
      }

      await Future.wait(renderOperations);

      await HomeWidget.updateWidget(
        name: androidWidgetName,
        qualifiedAndroidName: androidQualifiedName,
        iOSName: iosWidgetName,
      );
    } catch (e) {
      _disabledForSession = true;
      debugPrint('HomeWidgetService disabled for this launch: $e');
    }
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
    required Size logicalSize,
  }) {
    final theme = brightness == Brightness.dark
        ? AppTheme.darkTheme(accentColor)
        : AppTheme.lightTheme(accentColor);

    return Theme(
      data: theme,
      child: MediaQuery(
        data: MediaQueryData(
          size: logicalSize,
          devicePixelRatio: 2,
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: logicalSize.width,
            height: logicalSize.height,
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

class _WidgetSnapshotVariant {
  final String key;
  final Size logicalSize;

  const _WidgetSnapshotVariant({
    required this.key,
    required this.logicalSize,
  });
}
