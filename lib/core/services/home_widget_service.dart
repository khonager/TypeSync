library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../../features/home/models/upcoming_item_view_data.dart';
import '../../features/home/widgets/home_note_widget_preview.dart';
import '../../features/home/widgets/home_upcoming_widget_preview.dart';
import '../models/note.dart';
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
  static const String largestMetricKey = 'typesync_largest_metric';
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

  Future<void> syncNoteWidgets({
    required List<Note> recentlyOpened,
    required List<Note> frequentlyOpened,
    required List<Note> notes,
    required int Function(String noteId) openCountFor,
    required DateTime? Function(String noteId) lastOpenedAtFor,
    required Brightness brightness,
    required Color accentColor,
  }) async {
    if (!_supportsWidgets || _disabledForSession) return;

    try {
      await _configurePlatform();
      final largestBySize = [...notes]
        ..sort((a, b) => _fileBytes(b).compareTo(_fileBytes(a)));
      final largestByCharacters = [...notes]
        ..sort((a, b) => b.characterCount.compareTo(a.characterCount));
      final largestByLines = [...notes]
        ..sort((a, b) => b.lineCount.compareTo(a.lineCount));

      await Future.wait([
        _renderNoteWidget(
          kind: 'recent',
          title: 'Recently opened',
          icon: Icons.history,
          notes: recentlyOpened,
          emptyMessage: 'Open a note to see it here',
          detailFor: (note) => _relativeTime(lastOpenedAtFor(note.id)),
          brightness: brightness,
          accentColor: accentColor,
        ),
        _renderNoteWidget(
          kind: 'frequent',
          title: 'Frequently opened',
          icon: Icons.local_fire_department_outlined,
          notes: frequentlyOpened,
          emptyMessage: 'Your most-used notes will appear here',
          detailFor: (note) => '${openCountFor(note.id)} opens',
          brightness: brightness,
          accentColor: accentColor,
        ),
        _renderNoteWidget(
          kind: 'largest_size',
          title: 'Largest notes',
          icon: Icons.storage_outlined,
          notes: largestBySize,
          emptyMessage: 'No notes yet',
          detailFor: (note) => _formatBytes(_fileBytes(note)),
          brightness: brightness,
          accentColor: accentColor,
        ),
        _renderNoteWidget(
          kind: 'largest_characters',
          title: 'Largest notes',
          icon: Icons.text_fields,
          notes: largestByCharacters,
          emptyMessage: 'No notes yet',
          detailFor: (note) => '${note.characterCount} chars',
          brightness: brightness,
          accentColor: accentColor,
        ),
        _renderNoteWidget(
          kind: 'largest_lines',
          title: 'Largest notes',
          icon: Icons.format_list_numbered,
          notes: largestByLines,
          emptyMessage: 'No notes yet',
          detailFor: (note) => '${note.lineCount} lines',
          brightness: brightness,
          accentColor: accentColor,
        ),
      ]);

      await Future.wait([
        _updateAndroidWidget('TypeSyncRecentlyOpenedWidgetProvider'),
        _updateAndroidWidget('TypeSyncFrequentlyOpenedWidgetProvider'),
        _updateAndroidWidget('TypeSyncLargestNotesWidgetProvider'),
      ]);
    } catch (e) {
      _disabledForSession = true;
      debugPrint('Note home widgets disabled for this launch: $e');
    }
  }

  Future<void> _renderNoteWidget({
    required String kind,
    required String title,
    required IconData icon,
    required List<Note> notes,
    required String emptyMessage,
    required String Function(Note note) detailFor,
    required Brightness brightness,
    required Color accentColor,
  }) {
    return HomeWidget.renderFlutterWidget(
      _buildNotePreview(
        title: title,
        icon: icon,
        notes: notes,
        emptyMessage: emptyMessage,
        detailFor: detailFor,
        brightness: brightness,
        accentColor: accentColor,
      ),
      key: 'typesync_${kind}_image',
      logicalSize: defaultWidgetSize,
    );
  }

  Future<void> _updateAndroidWidget(String name) => HomeWidget.updateWidget(
        name: name,
        qualifiedAndroidName: 'de.khonager.typesync.$name',
      );

  Widget _buildNotePreview({
    required String title,
    required IconData icon,
    required List<Note> notes,
    required String emptyMessage,
    required String Function(Note note) detailFor,
    required Brightness brightness,
    required Color accentColor,
  }) {
    final theme = AppTheme.darkTheme(accentColor);
    return Theme(
      data: theme,
      child: MediaQuery(
        data:
            const MediaQueryData(size: defaultWidgetSize, devicePixelRatio: 2),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: defaultWidgetSize.width,
            height: defaultWidgetSize.height,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: HomeNoteWidgetPreview(
                title: title,
                icon: icon,
                notes: notes,
                emptyMessage: emptyMessage,
                detailFor: detailFor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  int _fileBytes(Note note) =>
      note.size +
      note.attachments.fold(0, (sum, attachment) => sum + attachment.size);

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _relativeTime(DateTime? date) {
    if (date == null) return '';
    final difference = DateTime.now().difference(date);
    if (difference.inMinutes < 1) return 'now';
    if (difference.inHours < 1) return '${difference.inMinutes}m';
    if (difference.inDays < 1) return '${difference.inHours}h';
    return '${difference.inDays}d';
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
