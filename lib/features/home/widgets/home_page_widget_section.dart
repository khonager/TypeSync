/// Swipeable, locally configured widgets shown at the top of the home page.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/note.dart';
import '../../../core/providers/calendar_provider.dart';
import '../../../core/providers/homework_provider.dart';
import '../../../core/providers/notes_provider.dart';
import '../../../core/routes/app_router.dart';
import '../../../core/services/theme_service.dart';
import '../models/upcoming_item_view_data.dart';
import 'home_note_widget_preview.dart';
import 'home_upcoming_card.dart';

enum _LargestNotesMetric { size, characters, lines }

class HomePageWidgetSection extends StatefulWidget {
  const HomePageWidgetSection({super.key});

  @override
  State<HomePageWidgetSection> createState() => _HomePageWidgetSectionState();
}

class _HomePageWidgetSectionState extends State<HomePageWidgetSection> {
  static const int _initialPage = 10000;
  final PageController _controller = PageController(initialPage: _initialPage);
  HomePageWidgetType? _currentWidget;
  _LargestNotesMetric _largestMetric = _LargestNotesMetric.size;
  String? _appliedSelectionSignature;
  HomePageWidgetType? _appliedSavedWidget;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();
    final selected = themeService.selectedHomePageWidgets;
    if (selected.isEmpty) return const SizedBox.shrink();

    final savedWidget = selected.contains(themeService.lastViewedHomePageWidget)
        ? themeService.lastViewedHomePageWidget
        : selected.first;
    _applySavedPage(selected, savedWidget);

    return Consumer3<CalendarProvider, HomeworkProvider, NotesProvider>(
      builder: (context, calendarProvider, homeworkProvider, notesProvider, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Column(
            children: [
              SizedBox(
                // Upcoming rows can contain a two-line date/time label. This
                // fits three such rows without clipping every carousel page.
                height: 266,
                child: PageView.builder(
                  controller: _controller,
                  itemBuilder: (context, page) {
                    final type = selected[page % selected.length];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: _buildWidget(
                        type,
                        calendarProvider: calendarProvider,
                        homeworkProvider: homeworkProvider,
                        notesProvider: notesProvider,
                      ),
                    );
                  },
                  onPageChanged: (page) {
                    final type = selected[page % selected.length];
                    if (_currentWidget != type) {
                      setState(() => _currentWidget = type);
                    }
                    themeService.setLastViewedHomePageWidget(type);
                  },
                ),
              ),
              if (selected.length > 1) ...[
                const SizedBox(height: 7),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: selected
                      .map(
                        (type) => AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width:
                              (_currentWidget ?? savedWidget) == type ? 16 : 6,
                          height: 6,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            color: (_currentWidget ?? savedWidget) == type
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context)
                                    .colorScheme
                                    .outline
                                    .withValues(alpha: 0.35),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _applySavedPage(
    List<HomePageWidgetType> selected,
    HomePageWidgetType savedWidget,
  ) {
    final selectionSignature = selected.map((widget) => widget.index).join(',');
    if (_appliedSelectionSignature == selectionSignature &&
        _appliedSavedWidget == savedWidget) {
      return;
    }
    _appliedSelectionSignature = selectionSignature;
    _appliedSavedWidget = savedWidget;
    _currentWidget = savedWidget;
    final targetPage = _initialPage -
        (_initialPage % selected.length) +
        selected.indexOf(savedWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.hasClients) _controller.jumpToPage(targetPage);
    });
  }

  Widget _buildWidget(
    HomePageWidgetType type, {
    required CalendarProvider calendarProvider,
    required HomeworkProvider homeworkProvider,
    required NotesProvider notesProvider,
  }) {
    switch (type) {
      case HomePageWidgetType.upcoming:
        final items = UpcomingItemViewData.build(
          calendarEvents: calendarProvider.upcomingEvents,
          homeworkItems: homeworkProvider.homework,
          limit: 3,
        );
        return HomeUpcomingCard(
          items: items,
          emptySubtitle: 'Add homework or events to see them here',
          onItemTap: (item) => AppRouter.navigateTo(
            context,
            item.kind == UpcomingItemKind.homework
                ? AppRouter.homework
                : AppRouter.calendar,
          ),
          onItemCheck: (item) async {
            if (item.isCompletable) {
              await homeworkProvider.toggleCompletion(item.sourceId);
            }
          },
        );
      case HomePageWidgetType.recentlyOpened:
        return _noteWidget(
          title: 'Recently opened',
          icon: Icons.history,
          notes: notesProvider.recentlyOpenedNotes,
          emptyMessage: 'Open a note to see it here',
          detailFor: (note) =>
              _relativeTime(notesProvider.lastOpenedAtFor(note.id)),
        );
      case HomePageWidgetType.frequentlyOpened:
        return _noteWidget(
          title: 'Frequently opened',
          icon: Icons.local_fire_department_outlined,
          notes: notesProvider.frequentlyOpenedNotes,
          emptyMessage: 'Your most-used notes will appear here',
          detailFor: (note) => '${notesProvider.openCountFor(note.id)} opens',
        );
      case HomePageWidgetType.largestNotes:
        return _largestNotesWidget(notesProvider.notes);
    }
  }

  Widget _noteWidget({
    required String title,
    required IconData icon,
    required List<Note> notes,
    required String emptyMessage,
    required String Function(Note) detailFor,
  }) {
    return HomeNoteWidgetPreview(
      title: title,
      icon: icon,
      notes: notes,
      emptyMessage: emptyMessage,
      detailFor: detailFor,
      onNoteTap: _openNote,
    );
  }

  Widget _largestNotesWidget(List<Note> notes) {
    final sorted = [...notes]
      ..sort((a, b) => _metricValue(b).compareTo(_metricValue(a)));
    return Stack(
      children: [
        HomeNoteWidgetPreview(
          title: 'Largest notes · ${_largestMetric.label}',
          icon: _largestMetric.icon,
          notes: sorted,
          emptyMessage: 'No notes yet',
          detailFor: (note) => _largestMetric.format(note),
          onNoteTap: _openNote,
        ),
        Positioned(
          top: 5,
          right: 4,
          child: PopupMenuButton<_LargestNotesMetric>(
            tooltip: 'Largest notes metric',
            icon: const Icon(Icons.tune, size: 18),
            onSelected: (metric) => setState(() => _largestMetric = metric),
            itemBuilder: (context) => _LargestNotesMetric.values
                .map(
                  (metric) => CheckedPopupMenuItem(
                    value: metric,
                    checked: metric == _largestMetric,
                    child: Text(metric.label),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  int _metricValue(Note note) => switch (_largestMetric) {
        _LargestNotesMetric.size => note.size +
            note.attachments
                .fold(0, (sum, attachment) => sum + attachment.size),
        _LargestNotesMetric.characters => note.characterCount,
        _LargestNotesMetric.lines => note.lineCount,
      };

  void _openNote(Note note) {
    AppRouter.openEditor(context, noteId: note.id, folderId: note.folderId);
  }

  String _relativeTime(DateTime? date) {
    if (date == null) return '';
    final difference = DateTime.now().difference(date);
    if (difference.inMinutes < 1) return 'now';
    if (difference.inHours < 1) return '${difference.inMinutes}m';
    if (difference.inDays < 1) return '${difference.inHours}h';
    return '${difference.inDays}d';
  }
}

extension on _LargestNotesMetric {
  String get label => switch (this) {
        _LargestNotesMetric.size => 'Size',
        _LargestNotesMetric.characters => 'Characters',
        _LargestNotesMetric.lines => 'Lines',
      };

  IconData get icon => switch (this) {
        _LargestNotesMetric.size => Icons.storage_outlined,
        _LargestNotesMetric.characters => Icons.text_fields,
        _LargestNotesMetric.lines => Icons.format_list_numbered,
      };

  String format(Note note) => switch (this) {
        _LargestNotesMetric.size => _formatBytes(_noteBytes(note)),
        _LargestNotesMetric.characters => '${note.characterCount} chars',
        _LargestNotesMetric.lines => '${note.lineCount} lines',
      };
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

int _noteBytes(Note note) =>
    note.size +
    note.attachments.fold(0, (sum, attachment) => sum + attachment.size);
