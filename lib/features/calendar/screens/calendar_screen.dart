/// Calendar Screen
///
/// Calendar view with test reminders and events.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/models/calendar_event.dart';
import '../../../core/providers/calendar_provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/widgets/desktop_window_frame.dart';

enum CalendarViewMode {
  month,
  twoWeeks,
  week,
  year,
}

class _YearWeekItem {
  final int weekNumber;
  final DateTime start;
  final DateTime end;

  const _YearWeekItem({
    required this.weekNumber,
    required this.start,
    required this.end,
  });
}

class _CalendarEventGroup {
  final List<CalendarEvent> events;

  const _CalendarEventGroup(this.events);

  CalendarEvent get primary => events.first;
}

class _DayHitRegion {
  final DateTime day;
  final DateTime pageDay;
  final Rect rect;

  const _DayHitRegion({
    required this.day,
    required this.pageDay,
    required this.rect,
  });
}

class _DayBoundsReporter extends StatefulWidget {
  final DateTime day;
  final DateTime pageDay;
  final ValueChanged<_DayHitRegion> onChanged;
  final VoidCallback onRemoved;
  final Widget child;

  const _DayBoundsReporter({
    required this.day,
    required this.pageDay,
    required this.onChanged,
    required this.onRemoved,
    required this.child,
  });

  @override
  State<_DayBoundsReporter> createState() => _DayBoundsReporterState();
}

class _DayBoundsReporterState extends State<_DayBoundsReporter> {
  @override
  void initState() {
    super.initState();
    _scheduleReport();
  }

  @override
  void didUpdateWidget(covariant _DayBoundsReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleReport();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleReport();
  }

  @override
  void dispose() {
    widget.onRemoved();
    super.dispose();
  }

  void _scheduleReport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final renderObject = context.findRenderObject() as RenderBox?;
      if (renderObject == null || !renderObject.hasSize) {
        return;
      }

      final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
      widget.onChanged(
        _DayHitRegion(
          day: widget.day,
          pageDay: widget.pageDay,
          rect: rect,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Calendar screen for test reminders and events
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static final DateTime _firstCalendarDay = DateTime(2020, 1, 1);
  static final DateTime _lastCalendarDay = DateTime(2035, 12, 31);
  static const Duration _calendarMorphDuration = Duration(milliseconds: 260);
  static const double _calendarRowHeight = 52;
  static const double _calendarDaysOfWeekHeight = 16;
  static const double _selectedCircleSize = 36;

  final DateFormat _monthHeaderFormat = DateFormat.yMMMM();
  final DateFormat _dateLabelFormat = DateFormat('EEE, d MMM y');
  final Map<int, DateTime> _selectedDays = <int, DateTime>{};
  final Map<String, _DayHitRegion> _dayHitRegions = <String, _DayHitRegion>{};
  final GlobalKey _calendarViewportKey = GlobalKey();

  CalendarViewMode _viewMode = CalendarViewMode.month;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  late DateTime _focusedDay;
  late DateTime _visiblePageDay;
  late DateTime _selectedWeekStart;
  DateTime? _lastInteractedDay;
  DateTime? _dragAnchorDay;
  int? _activePointer;
  bool _isPointerDragSelecting = false;
  bool _isLongPressDragSelecting = false;
  bool _selectionDragMoved = false;
  bool _suppressNextTap = false;
  bool _handledInitialRouteAction = false;

  @override
  void initState() {
    super.initState();
    final now = _dateOnly(DateTime.now());
    _focusedDay = now;
    _visiblePageDay = now;
    _selectedWeekStart = _startOfIsoWeek(now);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handledInitialRouteAction) {
      return;
    }
    _handledInitialRouteAction = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    final shouldOpenComposer = args is Map && args['openComposer'] == true;
    if (shouldOpenComposer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _addEvent();
      });
    }
  }

  Future<void> _initializeData() async {
    final authService = context.read<AuthService>();
    final userId = authService.storageUserId;
    if (userId != null) {
      await context.read<CalendarProvider>().initialize(userId);
    }
    if (!mounted) return;
    final cloudUserId = authService.userId;
    if (cloudUserId != null && authService.effectiveSyncEnabled) {
      await context.read<SyncService>().fetchWorkspaceSnapshot(cloudUserId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: desktopWindowDragArea(),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Calendar'),
        actions: withDesktopWindowControls([
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: () {
              final now = _dateOnly(DateTime.now());
              setState(() {
                _focusedDay = now;
                _visiblePageDay = now;
                _selectedWeekStart = _startOfIsoWeek(now);
                _selectOnly(now);
              });
            },
          ),
        ]),
      ),
      body: Consumer<CalendarProvider>(
        builder: (context, calendarProvider, _) {
          final eventDayKeys = calendarProvider.events
              .map((event) => _dateKey(calendarProvider.eventDateFor(event)))
              .toSet();

          return Listener(
            behavior: HitTestBehavior.translucent,
            onPointerMove: _handlePointerTrackMove,
            onPointerUp: _handlePointerFinish,
            onPointerCancel: _handlePointerCancel,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                if (_viewMode != CalendarViewMode.year &&
                    _selectedDays.isNotEmpty) {
                  setState(() {
                    _selectedDays.clear();
                  });
                }
              },
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  _buildViewModeSelector(),
                  const SizedBox(height: 8),
                  _buildCalendarHeader(),
                  _buildCalendarViewport(
                    eventDayKeys: eventDayKeys,
                    calendarProvider: calendarProvider,
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _buildVisibleRangeEventsList(calendarProvider),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEvent,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildViewModeSelector() {
    final isSelected = [
      _viewMode == CalendarViewMode.month,
      _viewMode == CalendarViewMode.twoWeeks,
      _viewMode == CalendarViewMode.week,
      _viewMode == CalendarViewMode.year,
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ToggleButtons(
        isSelected: isSelected,
        borderRadius: BorderRadius.circular(10),
        onPressed: (index) {
          final selectedMode = switch (index) {
            0 => CalendarViewMode.month,
            1 => CalendarViewMode.twoWeeks,
            2 => CalendarViewMode.week,
            3 => CalendarViewMode.year,
            _ => CalendarViewMode.month,
          };
          setState(() {
            _viewMode = selectedMode;
            if (selectedMode != CalendarViewMode.year) {
              _calendarFormat = switch (selectedMode) {
                CalendarViewMode.month => CalendarFormat.month,
                CalendarViewMode.twoWeeks => CalendarFormat.twoWeeks,
                CalendarViewMode.week => CalendarFormat.week,
                CalendarViewMode.year => CalendarFormat.month,
              };
            } else {
              final baseDay = _lastInteractedDay ?? _focusedDay;
              _selectedWeekStart = _startOfIsoWeek(baseDay);
              _focusedDay = _selectedWeekStart;
              _visiblePageDay = _selectedWeekStart;
            }
          });
        },
        children: const [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Month'),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('2 Weeks'),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Week'),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Year (KW)'),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarHeader() {
    final label = _calendarHeaderLabel();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: _goToPreviousPeriod,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: _calendarMorphDuration,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.15),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Text(
                label,
                key: ValueKey(label),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          IconButton(
            onPressed: _goToNextPeriod,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarViewport({
    required Set<int> eventDayKeys,
    required CalendarProvider calendarProvider,
  }) {
    final child = _viewMode == CalendarViewMode.year
        ? _buildYearCalendar(calendarProvider)
        : _buildStandardCalendar(eventDayKeys);

    return AnimatedSize(
      duration: _calendarMorphDuration,
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.hardEdge,
      child: KeyedSubtree(
        key: ValueKey(_viewMode == CalendarViewMode.year ? 'kw-year' : 'day'),
        child: Container(
          key: _calendarViewportKey,
          child: child,
        ),
      ),
    );
  }

  String _calendarHeaderLabel() {
    if (_viewMode == CalendarViewMode.year) {
      return '${_focusedDay.year}';
    }
    return _monthHeaderFormat.format(_visiblePageDay);
  }

  void _goToPreviousPeriod() {
    setState(() {
      switch (_viewMode) {
        case CalendarViewMode.month:
          _focusedDay =
              _dateOnly(DateTime(_focusedDay.year, _focusedDay.month - 1, 1));
          _visiblePageDay = _focusedDay;
          break;
        case CalendarViewMode.twoWeeks:
          _focusedDay = _addDays(_focusedDay, -14);
          _visiblePageDay = _focusedDay;
          break;
        case CalendarViewMode.week:
          _focusedDay = _addDays(_focusedDay, -7);
          _visiblePageDay = _focusedDay;
          break;
        case CalendarViewMode.year:
          _focusedDay = DateTime(_focusedDay.year - 1, 1, 1);
          _visiblePageDay = _focusedDay;
          _selectedWeekStart = _startOfIsoWeek(_focusedDay);
          break;
      }
    });
  }

  void _goToNextPeriod() {
    setState(() {
      switch (_viewMode) {
        case CalendarViewMode.month:
          _focusedDay =
              _dateOnly(DateTime(_focusedDay.year, _focusedDay.month + 1, 1));
          _visiblePageDay = _focusedDay;
          break;
        case CalendarViewMode.twoWeeks:
          _focusedDay = _addDays(_focusedDay, 14);
          _visiblePageDay = _focusedDay;
          break;
        case CalendarViewMode.week:
          _focusedDay = _addDays(_focusedDay, 7);
          _visiblePageDay = _focusedDay;
          break;
        case CalendarViewMode.year:
          _focusedDay = DateTime(_focusedDay.year + 1, 1, 1);
          _visiblePageDay = _focusedDay;
          _selectedWeekStart = _startOfIsoWeek(_focusedDay);
          break;
      }
    });
  }

  Widget _buildStandardCalendar(Set<int> eventDayKeys) {
    return TableCalendar(
      firstDay: _firstCalendarDay,
      lastDay: _lastCalendarDay,
      focusedDay: _focusedDay,
      calendarFormat: _calendarFormat,
      rowHeight: _calendarRowHeight,
      daysOfWeekHeight: _calendarDaysOfWeekHeight,
      sixWeekMonthsEnforced: false,
      startingDayOfWeek: StartingDayOfWeek.monday,
      availableGestures: AvailableGestures.horizontalSwipe,
      selectedDayPredicate: _isDateSelected,
      onPageChanged: (focusedDay) {
        setState(() {
          _focusedDay = _dateOnly(focusedDay);
          _visiblePageDay = _focusedDay;
        });
      },
      headerVisible: false,
      calendarBuilders: CalendarBuilders(
        defaultBuilder: (context, day, focusedDay) => _buildInteractiveDayCell(
          day,
          pageDay: _dateOnly(focusedDay),
          eventDayKeys: eventDayKeys,
          hasEvents: eventDayKeys.contains(_dateKey(day)),
        ),
        outsideBuilder: (context, day, focusedDay) => _buildInteractiveDayCell(
          day,
          pageDay: _dateOnly(focusedDay),
          eventDayKeys: eventDayKeys,
          hasEvents: eventDayKeys.contains(_dateKey(day)),
          isOutside: true,
        ),
        todayBuilder: (context, day, focusedDay) => _buildInteractiveDayCell(
          day,
          pageDay: _dateOnly(focusedDay),
          eventDayKeys: eventDayKeys,
          hasEvents: eventDayKeys.contains(_dateKey(day)),
          isToday: true,
        ),
        selectedBuilder: (context, day, focusedDay) => _buildInteractiveDayCell(
          day,
          pageDay: _dateOnly(focusedDay),
          eventDayKeys: eventDayKeys,
          hasEvents: eventDayKeys.contains(_dateKey(day)),
          isSelectedOverride: true,
        ),
      ),
    );
  }

  Widget _buildInteractiveDayCell(
    DateTime day, {
    required DateTime pageDay,
    required Set<int> eventDayKeys,
    required bool hasEvents,
    bool isToday = false,
    bool isOutside = false,
    bool isSelectedOverride = false,
  }) {
    final normalizedDay = _dateOnly(day);
    final isSelected = isSelectedOverride || _isDateSelected(normalizedDay);

    final cell = Listener(
      onPointerDown: (event) => _handleDayPointerDown(
        day: normalizedDay,
        event: event,
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _handleDayTap(normalizedDay),
        onLongPressStart: (_) => _startLongPressSelection(normalizedDay),
        onLongPressEnd: (_) => _finishLongPressSelection(normalizedDay),
        child: _buildDayCell(
          normalizedDay,
          eventDayKeys: eventDayKeys,
          hasEvents: hasEvents,
          isSelected: isSelected,
          isToday: isToday,
          isOutside: isOutside,
        ),
      ),
    );

    if (_viewMode != CalendarViewMode.month) {
      return cell;
    }

    return _DayBoundsReporter(
      day: normalizedDay,
      pageDay: pageDay,
      onChanged: _updateDayHitRegion,
      onRemoved: () => _removeDayHitRegion(pageDay, normalizedDay),
      child: cell,
    );
  }

  Widget _buildDayCell(
    DateTime day, {
    required Set<int> eventDayKeys,
    required bool hasEvents,
    bool isSelected = false,
    bool isToday = false,
    bool isOutside = false,
  }) {
    final theme = Theme.of(context);
    final connectsLeft = isSelected && _selectionConnectsLeft(day);
    final connectsRight = isSelected && _selectionConnectsRight(day);
    final isIsolatedSelection = isSelected && !connectsLeft && !connectsRight;
    final isRunLeader = isSelected && !connectsLeft;
    final runLength = isRunLeader ? _selectionRunLength(day) : 0;
    final runHasEvents =
        isRunLeader && _selectionRunHasEvents(day, eventDayKeys);
    final textColor = isSelected
        ? theme.colorScheme.onPrimary
        : isOutside
            ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
            : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = constraints.maxWidth;
        final circleInset =
            ((cellWidth - _selectedCircleSize) / 2).clamp(0.0, cellWidth / 2);

        final selectionDecoration = BoxDecoration(
          color: theme.colorScheme.primary,
          shape: isIsolatedSelection ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: isIsolatedSelection
              ? null
              : BorderRadius.circular(_selectedCircleSize / 2),
          border: runHasEvents || (isIsolatedSelection && hasEvents)
              ? Border.all(color: theme.colorScheme.onPrimary, width: 1.5)
              : null,
        );

        final defaultDecoration = isToday
            ? BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.25),
                shape: BoxShape.circle,
                border: hasEvents
                    ? Border.all(color: theme.colorScheme.primary, width: 1.4)
                    : null,
              )
            : hasEvents
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: theme.colorScheme.primary, width: 1.3),
                  )
                : null;

        if (isIsolatedSelection) {
          return SizedBox.expand(
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: _selectedCircleSize,
                  height: _selectedCircleSize,
                  decoration: selectionDecoration,
                ),
                Text(
                  '${day.day}',
                  style: TextStyle(color: textColor),
                ),
              ],
            ),
          );
        }

        final selectionWidth =
            _selectedCircleSize + ((runLength - 1).clamp(0, 6) * cellWidth);

        return SizedBox.expand(
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (isRunLeader)
                Positioned(
                  left: circleInset,
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      width: selectionWidth,
                      height: _selectedCircleSize,
                      decoration: selectionDecoration,
                    ),
                  ),
                )
              else if (!isSelected && defaultDecoration != null)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 34,
                  height: 34,
                  decoration: defaultDecoration,
                ),
              Text(
                '${day.day}',
                style: TextStyle(color: textColor),
              ),
            ],
          ),
        );
      },
    );
  }

  int _selectionRunLength(DateTime startDay) {
    if (!_isDateSelected(startDay)) {
      return 0;
    }

    var length = 1;
    var cursor = _dateOnly(startDay);
    while (cursor.weekday != DateTime.sunday) {
      final nextDay = _addDays(cursor, 1);
      if (!_isDateSelected(nextDay)) {
        break;
      }
      length++;
      cursor = nextDay;
    }
    return length;
  }

  bool _selectionRunHasEvents(DateTime startDay, Set<int> eventDayKeys) {
    final runLength = _selectionRunLength(startDay);
    for (var index = 0; index < runLength; index++) {
      final day = _addDays(startDay, index);
      if (eventDayKeys.contains(_dateKey(day))) {
        return true;
      }
    }
    return false;
  }

  Widget _buildYearCalendar(CalendarProvider calendarProvider) {
    final weeks = _buildWeeksForYear(_focusedDay.year);
    final selectedKey = _dateKey(_selectedWeekStart);
    const columns = 7;
    const crossAxisSpacing = 6.0;
    const mainAxisSpacing = 6.0;
    const cellExtent = 46.0;
    final rowCount = (weeks.length / columns).ceil();
    final gridHeight =
        (rowCount * cellExtent) + ((rowCount - 1) * mainAxisSpacing) + 8;

    return SizedBox(
      height: gridHeight,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        itemCount: weeks.length,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: crossAxisSpacing,
          mainAxisSpacing: mainAxisSpacing,
          mainAxisExtent: cellExtent,
        ),
        itemBuilder: (context, index) {
          final week = weeks[index];
          final weekKey = _dateKey(week.start);
          final isSelected = weekKey == selectedKey;
          final hasEvents = _weekHasEvents(
            calendarProvider.events,
            start: week.start,
            end: week.end,
          );

          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              setState(() {
                _selectedWeekStart = week.start;
                _focusedDay = week.start;
                _lastInteractedDay = week.start;
              });
            },
            child: Tooltip(
              message:
                  'KW ${week.weekNumber} (${week.start.day}.${week.start.month} - ${week.end.day}.${week.end.month})',
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    shape: BoxShape.circle,
                    border: hasEvents
                        ? Border.all(
                            color: isSelected
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.primary,
                            width: 1.3,
                          )
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${week.weekNumber}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Theme.of(context).colorScheme.onPrimary
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVisibleRangeEventsList(CalendarProvider calendarProvider) {
    final selectedDates = _viewMode == CalendarViewMode.year
        ? <DateTime>[]
        : _sortedSelectedDays();
    final hasExplicitSelection = selectedDates.isNotEmpty;
    final range = hasExplicitSelection ? null : _visibleRange();
    final events = hasExplicitSelection
        ? _eventsForSelectedDates(calendarProvider.events, selectedDates)
        : _eventsInRange(
            calendarProvider.events,
            start: range!.start,
            end: range.end,
          );
    final groups = _buildEventGroups(
      events,
      collapseSeries: selectedDates.length > 1,
    );

    final header = hasExplicitSelection
        ? _eventsHeaderForSelection(selectedDates)
        : _eventsHeaderForRange(range!.start, range.end);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          header,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        if (groups.isEmpty)
          SizedBox(
            height: 220,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.event_available,
                    size: 48,
                    color: Colors.grey.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'No events in this range',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          )
        else
          ...groups.map(
            (group) => _buildEventGroupCard(
              calendarProvider: calendarProvider,
              group: group,
            ),
          ),
      ],
    );
  }

  Widget _buildEventGroupCard({
    required CalendarProvider calendarProvider,
    required _CalendarEventGroup group,
  }) {
    final event = group.primary;
    final accentColor = _eventAccentColor(event);
    final titleStyle = event.isTodo && event.isCompleted
        ? TextStyle(
            decoration: TextDecoration.lineThrough,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
          )
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _openEventEditor(
          existingEvent: event,
          linkedEvents: group.events,
        ),
        leading: event.isTodo
            ? Checkbox(
                value: group.events.every((item) => item.isCompleted),
                onChanged: (value) async {
                  if (value == null) return;
                  for (final item in group.events) {
                    await calendarProvider.toggleTodoCompletion(
                      eventId: item.id,
                      isCompleted: value,
                    );
                  }
                },
              )
            : Container(
                width: 4,
                height: double.infinity,
                color: accentColor,
              ),
        title: Text(event.title, style: titleStyle),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (event.subject != null && event.subject!.trim().isNotEmpty)
              Text(
                'Subject: ${event.subject}',
                style: titleStyle,
              ),
            Text(
              _eventGroupDateTimeLabel(group),
              style: titleStyle,
            ),
            if (event.description != null &&
                event.description!.trim().isNotEmpty)
              Text(event.description!, style: titleStyle),
            if (group.events.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Applies to ${group.events.length} selected days',
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (event.isTodo && !event.isCompleted && event.rolloverCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  event.rolloverCount == 1
                      ? 'Carried over from yesterday'
                      : 'Carried over for ${event.rolloverCount} days',
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        trailing: Icon(
          _getEventTypeIcon(event.type),
          color: accentColor,
        ),
      ),
    );
  }

  String _eventDateTimeLabel(CalendarEvent event) {
    final date = _dateLabelFormat.format(event.calendarDate);
    if (_isAllDay(event.startTime)) {
      return '$date • All day';
    }
    return '$date • ${DateFormat.Hm().format(event.startTime)}';
  }

  String _eventGroupDateTimeLabel(_CalendarEventGroup group) {
    if (group.events.length == 1) {
      return _eventDateTimeLabel(group.primary);
    }

    final dates = group.events
        .map((event) => _dateOnly(event.calendarDate))
        .toSet()
        .toList()
      ..sort((a, b) => a.compareTo(b));
    final start = dates.first;
    final end = dates.last;
    final dateLabel = dates.length == 1
        ? _dateLabelFormat.format(start)
        : '${DateFormat('d MMM y').format(start)} - ${DateFormat('d MMM y').format(end)}';

    if (_isAllDay(group.primary.startTime)) {
      return '$dateLabel • All day';
    }
    return '$dateLabel • ${DateFormat.Hm().format(group.primary.startTime)}';
  }

  String _eventsHeaderForSelection(List<DateTime> selectedDates) {
    if (selectedDates.length == 1) {
      return 'Events on ${DateFormat('EEE, d MMM y').format(selectedDates.first)}';
    }
    return 'Events across ${selectedDates.length} selected days';
  }

  String _eventsHeaderForRange(DateTime start, DateTime end) {
    if (_viewMode == CalendarViewMode.month) {
      return 'Events in ${_monthHeaderFormat.format(_visiblePageDay)}';
    }
    if (_viewMode == CalendarViewMode.year) {
      final week = _isoWeekNumber(start);
      return 'Events in KW $week (${DateFormat('d MMM').format(start)} - ${DateFormat('d MMM').format(end)})';
    }
    if (_viewMode == CalendarViewMode.week) {
      return 'Events in Week (${DateFormat('d MMM').format(start)} - ${DateFormat('d MMM').format(end)})';
    }
    return 'Events in 2 Weeks (${DateFormat('d MMM').format(start)} - ${DateFormat('d MMM').format(end)})';
  }

  DateTimeRange _visibleRange() {
    if (_viewMode == CalendarViewMode.year) {
      final start = _selectedWeekStart;
      return DateTimeRange(
        start: start,
        end: _addDays(start, 6),
      );
    }

    if (_viewMode == CalendarViewMode.month) {
      final start = DateTime(_visiblePageDay.year, _visiblePageDay.month, 1);
      final end = DateTime(_visiblePageDay.year, _visiblePageDay.month + 1, 0);
      return DateTimeRange(start: start, end: end);
    }

    final start = _startOfIsoWeek(_focusedDay);
    final end = _viewMode == CalendarViewMode.twoWeeks
        ? _addDays(start, 13)
        : _addDays(start, 6);
    return DateTimeRange(start: start, end: end);
  }

  List<CalendarEvent> _eventsForSelectedDates(
    List<CalendarEvent> source,
    List<DateTime> selectedDates,
  ) {
    final selectedKeys = selectedDates.map(_dateKey).toSet();
    return source.where((event) {
      return selectedKeys.contains(_dateKey(_dateOnly(event.calendarDate)));
    }).toList()
      ..sort((a, b) => a.calendarDate.compareTo(b.calendarDate));
  }

  List<CalendarEvent> _eventsInRange(
    List<CalendarEvent> source, {
    required DateTime start,
    required DateTime end,
  }) {
    return source.where((event) {
      final eventDate = _dateOnly(event.calendarDate);
      return !eventDate.isBefore(_dateOnly(start)) &&
          !eventDate.isAfter(_dateOnly(end));
    }).toList()
      ..sort((a, b) => a.calendarDate.compareTo(b.calendarDate));
  }

  List<_CalendarEventGroup> _buildEventGroups(
    List<CalendarEvent> events, {
    required bool collapseSeries,
  }) {
    if (!collapseSeries) {
      return events.map((event) => _CalendarEventGroup([event])).toList();
    }

    final grouped = <String, List<CalendarEvent>>{};
    for (final event in events) {
      final key = event.seriesId ?? event.id;
      grouped.putIfAbsent(key, () => <CalendarEvent>[]).add(event);
    }

    final groups = grouped.values.map((items) {
      items.sort((a, b) => a.calendarDate.compareTo(b.calendarDate));
      return _CalendarEventGroup(items);
    }).toList()
      ..sort(
          (a, b) => a.primary.calendarDate.compareTo(b.primary.calendarDate));

    return groups;
  }

  bool _weekHasEvents(
    List<CalendarEvent> source, {
    required DateTime start,
    required DateTime end,
  }) {
    final from = _dateOnly(start);
    final to = _dateOnly(end);
    return source.any((event) {
      final eventDate = _dateOnly(event.calendarDate);
      return !eventDate.isBefore(from) && !eventDate.isAfter(to);
    });
  }

  List<_YearWeekItem> _buildWeeksForYear(int year) {
    final totalWeeks = _isoWeekNumber(DateTime(year, 12, 28));
    final firstWeekStart = _startOfIsoWeek(DateTime(year, 1, 4));

    return List<_YearWeekItem>.generate(totalWeeks, (index) {
      final start = _addDays(firstWeekStart, index * 7);
      final end = _addDays(start, 6);
      return _YearWeekItem(
        weekNumber: index + 1,
        start: _dateOnly(start),
        end: _dateOnly(end),
      );
    });
  }

  DateTime _defaultDateForNewEvent() {
    if (_viewMode == CalendarViewMode.year) {
      return _selectedWeekStart;
    }
    final selectedDates = _sortedSelectedDays();
    return selectedDates.isNotEmpty ? selectedDates.first : _focusedDay;
  }

  bool _isDateSelected(DateTime day) {
    return _selectedDays.containsKey(_dateKey(_dateOnly(day)));
  }

  bool _selectionConnectsLeft(DateTime day) {
    if (day.weekday == DateTime.monday) {
      return false;
    }
    return _isDateSelected(_addDays(day, -1));
  }

  bool _selectionConnectsRight(DateTime day) {
    if (day.weekday == DateTime.sunday) {
      return false;
    }
    return _isDateSelected(_addDays(day, 1));
  }

  bool _isOutsideVisibleMonth(DateTime day) {
    if (_viewMode != CalendarViewMode.month) {
      return false;
    }
    return day.month != _visiblePageDay.month ||
        day.year != _visiblePageDay.year;
  }

  List<DateTime> _sortedSelectedDays() {
    final dates = _selectedDays.values.toList()..sort((a, b) => a.compareTo(b));
    return dates;
  }

  bool _isShiftPressed() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
  }

  bool _isToggleModifierPressed() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
  }

  void _handleDayTap(DateTime day) {
    if (_suppressNextTap) {
      _suppressNextTap = false;
      return;
    }

    setState(() {
      if (_isOutsideVisibleMonth(day) &&
          !_isShiftPressed() &&
          !_isToggleModifierPressed()) {
        return;
      }
      if (_isShiftPressed() && _lastInteractedDay != null) {
        _addRangeToSelection(_lastInteractedDay!, day);
      } else if (_isToggleModifierPressed()) {
        _toggleDaySelection(day);
      } else {
        _selectOnly(day);
      }
    });
  }

  void _handleDayPointerDown({
    required DateTime day,
    required PointerDownEvent event,
  }) {
    if (_viewMode == CalendarViewMode.year) {
      return;
    }
    if (event.kind != PointerDeviceKind.mouse ||
        event.buttons != kPrimaryMouseButton ||
        _isShiftPressed() ||
        _isToggleModifierPressed()) {
      return;
    }
    if (_isOutsideVisibleMonth(day)) {
      return;
    }

    _activePointer = event.pointer;
    _dragAnchorDay = day;
    _isPointerDragSelecting = true;
    _selectionDragMoved = false;
    setState(() {
      _selectOnly(day);
    });
  }

  void _handlePointerTrackMove(PointerMoveEvent event) {
    if (_viewMode == CalendarViewMode.year) {
      return;
    }

    final isTrackedMousePointer = _activePointer == event.pointer;
    if (!isTrackedMousePointer && !_isLongPressDragSelecting) {
      return;
    }

    final isMouseDrag = _isPointerDragSelecting &&
        event.kind == PointerDeviceKind.mouse &&
        isTrackedMousePointer;
    final isTouchDrag = _isLongPressDragSelecting;
    if (!isMouseDrag && !isTouchDrag) {
      return;
    }

    if (_dragAnchorDay == null) {
      return;
    }

    final hit = _calendarHitTest(event.position);
    final hoveredDay = hit?.$1;
    if (hoveredDay == null) {
      return;
    }
    if (_isOutsideVisibleMonth(hoveredDay)) {
      return;
    }

    final didCrossIntoAnotherDay = !isSameDay(_dragAnchorDay, hoveredDay);
    if (didCrossIntoAnotherDay) {
      _selectionDragMoved = true;
      _suppressNextTap = true;
    }

    if (_selectionDragMoved || isTouchDrag) {
      final effectiveHoveredDay = hoveredDay;
      setState(() {
        _setSelectionRange(_dragAnchorDay!, effectiveHoveredDay);
      });
    }
  }

  void _startLongPressSelection(DateTime day) {
    if (_viewMode == CalendarViewMode.year) {
      return;
    }
    if (_isOutsideVisibleMonth(day)) {
      return;
    }
    _dragAnchorDay = day;
    _isLongPressDragSelecting = true;
    _selectionDragMoved = false;
    _suppressNextTap = true;
  }

  void _finishLongPressSelection(DateTime day) {
    if (_viewMode == CalendarViewMode.year) {
      return;
    }

    setState(() {
      if (!_selectionDragMoved) {
        _toggleDaySelection(day);
      }
    });
    _resetSelectionGesture();
  }

  void _handlePointerFinish(PointerUpEvent event) {
    if (_activePointer == event.pointer) {
      _resetSelectionGesture();
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_activePointer == event.pointer) {
      _resetSelectionGesture();
    }
  }

  void _resetSelectionGesture() {
    _activePointer = null;
    _dragAnchorDay = null;
    _isPointerDragSelecting = false;
    _isLongPressDragSelecting = false;
    _selectionDragMoved = false;
  }

  (DateTime, String)? _calendarHitTest(Offset globalPosition) {
    if (_viewMode == CalendarViewMode.month) {
      final region = _hitTestCurrentMonthRegion(globalPosition);
      if (region != null) {
        return (region.day, 'month');
      }
      return null;
    }

    final viewportContext = _calendarViewportKey.currentContext;
    final viewportBox = viewportContext?.findRenderObject() as RenderBox?;
    if (viewportBox == null || !viewportBox.hasSize) {
      return null;
    }

    final viewportRect =
        viewportBox.localToGlobal(Offset.zero) & viewportBox.size;
    if (!viewportRect.contains(globalPosition)) {
      return null;
    }

    final local = viewportBox.globalToLocal(globalPosition);
    if (local.dy < _calendarDaysOfWeekHeight) {
      return null;
    }

    final columnWidth = viewportBox.size.width / 7;
    if (columnWidth <= 0) {
      return null;
    }

    final row =
        ((local.dy - _calendarDaysOfWeekHeight) / _calendarRowHeight).floor();
    final column = (local.dx / columnWidth).floor();

    if (column < 0 || column > 6 || row < 0) {
      return null;
    }

    final totalRows = _visibleGridRowCount();
    if (row >= totalRows) {
      return null;
    }

    final gridStart = _visibleGridStart();
    final candidate = _addDays(gridStart, row * 7 + column);
    if (candidate.isBefore(_firstCalendarDay) ||
        candidate.isAfter(_lastCalendarDay)) {
      return null;
    }
    return (_dateOnly(candidate), 'grid r$row c$column');
  }

  _DayHitRegion? _hitTestCurrentMonthRegion(Offset globalPosition) {
    final viewportContext = _calendarViewportKey.currentContext;
    final viewportBox = viewportContext?.findRenderObject() as RenderBox?;
    if (viewportBox == null || !viewportBox.hasSize) {
      return null;
    }

    final viewportRect =
        viewportBox.localToGlobal(Offset.zero) & viewportBox.size;
    if (!viewportRect.contains(globalPosition)) {
      return null;
    }

    final regions = _dayHitRegions.values
        .where(_isCurrentMonthRegion)
        .where((region) => region.rect.overlaps(viewportRect))
        .toList();

    for (final region in regions) {
      if (region.rect.contains(globalPosition)) {
        return region;
      }
    }

    if (regions.isEmpty) {
      return null;
    }

    final rowBuckets = <double, List<_DayHitRegion>>{};
    for (final region in regions) {
      final centerY = region.rect.center.dy;
      double? bucketKey;
      for (final key in rowBuckets.keys) {
        if ((key - centerY).abs() <= 12) {
          bucketKey = key;
          break;
        }
      }
      rowBuckets
          .putIfAbsent(bucketKey ?? centerY, () => <_DayHitRegion>[])
          .add(region);
    }

    final rows = rowBuckets.values.toList()
      ..sort(
          (a, b) => a.first.rect.center.dy.compareTo(b.first.rect.center.dy));

    List<_DayHitRegion>? nearestRow;
    var nearestRowDistance = double.infinity;
    for (final row in rows) {
      final distance = (row.first.rect.center.dy - globalPosition.dy).abs();
      if (distance < nearestRowDistance) {
        nearestRowDistance = distance;
        nearestRow = row;
      }
    }

    if (nearestRow == null || nearestRowDistance > (_calendarRowHeight / 2)) {
      return null;
    }

    nearestRow.sort((a, b) => a.rect.center.dx.compareTo(b.rect.center.dx));

    _DayHitRegion? nearestRegion;
    var nearestColumnDistance = double.infinity;
    for (final region in nearestRow) {
      final distance = (region.rect.center.dx - globalPosition.dx).abs();
      if (distance < nearestColumnDistance) {
        nearestColumnDistance = distance;
        nearestRegion = region;
      }
    }

    if (nearestRegion == null ||
        nearestColumnDistance > (nearestRegion.rect.width / 2)) {
      return null;
    }

    return nearestRegion;
  }

  void _updateDayHitRegion(_DayHitRegion region) {
    _dayHitRegions[_dayHitRegionId(region.pageDay, region.day)] = region;
  }

  void _removeDayHitRegion(DateTime pageDay, DateTime day) {
    _dayHitRegions.remove(_dayHitRegionId(pageDay, day));
  }

  bool _isCurrentMonthRegion(_DayHitRegion region) {
    return region.pageDay.year == _visiblePageDay.year &&
        region.pageDay.month == _visiblePageDay.month;
  }

  String _dayHitRegionId(DateTime pageDay, DateTime day) {
    return '${pageDay.year}-${pageDay.month}-${_dateKey(day)}';
  }

  void _selectOnly(DateTime day) {
    final normalizedDay = _dateOnly(day);
    _selectedDays
      ..clear()
      ..[_dateKey(normalizedDay)] = normalizedDay;
    _lastInteractedDay = normalizedDay;
    _focusedDay = normalizedDay;
    _selectedWeekStart = _startOfIsoWeek(normalizedDay);
  }

  void _toggleDaySelection(DateTime day) {
    final normalizedDay = _dateOnly(day);
    final key = _dateKey(normalizedDay);
    if (_selectedDays.containsKey(key)) {
      _selectedDays.remove(key);
    } else {
      _selectedDays[key] = normalizedDay;
    }
    _lastInteractedDay = normalizedDay;
    _focusedDay = normalizedDay;
    _selectedWeekStart = _startOfIsoWeek(normalizedDay);
  }

  void _addRangeToSelection(DateTime start, DateTime end) {
    for (final day in _daysBetween(start, end)) {
      _selectedDays[_dateKey(day)] = day;
    }
    final normalizedEnd = _dateOnly(end);
    _lastInteractedDay = normalizedEnd;
    _focusedDay = normalizedEnd;
    _selectedWeekStart = _startOfIsoWeek(normalizedEnd);
  }

  void _setSelectionRange(DateTime start, DateTime end) {
    _selectedDays.clear();
    for (final day in _daysBetween(start, end)) {
      _selectedDays[_dateKey(day)] = day;
    }
    final normalizedEnd = _dateOnly(end);
    _lastInteractedDay = normalizedEnd;
    _focusedDay = normalizedEnd;
    _selectedWeekStart = _startOfIsoWeek(normalizedEnd);
  }

  DateTime _visibleGridStart() {
    if (_viewMode == CalendarViewMode.month) {
      final firstOfMonth = DateTime(
        _visiblePageDay.year,
        _visiblePageDay.month,
        1,
      );
      return _startOfIsoWeek(firstOfMonth);
    }

    return _startOfIsoWeek(_focusedDay);
  }

  int _visibleGridRowCount() {
    return switch (_viewMode) {
      CalendarViewMode.week => 1,
      CalendarViewMode.twoWeeks => 2,
      CalendarViewMode.year => 0,
      CalendarViewMode.month =>
        ((_visibleRange().duration.inDays + 1) / 7).ceil(),
    };
  }

  Iterable<DateTime> _daysBetween(DateTime a, DateTime b) sync* {
    final start = _dateOnly(a.isBefore(b) ? a : b);
    final end = _dateOnly(a.isBefore(b) ? b : a);
    var cursor = start;
    while (!cursor.isAfter(end)) {
      yield cursor;
      cursor = _addDays(cursor, 1);
    }
  }

  DateTime _addDays(DateTime value, int days) {
    final date = _dateOnly(value);
    return DateTime(date.year, date.month, date.day + days);
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  int _dateKey(DateTime value) {
    return value.year * 10000 + value.month * 100 + value.day;
  }

  bool _isAllDay(DateTime value) {
    return value.hour == 0 &&
        value.minute == 0 &&
        value.second == 0 &&
        value.millisecond == 0 &&
        value.microsecond == 0;
  }

  DateTime _startOfIsoWeek(DateTime value) {
    final date = _dateOnly(value);
    return _addDays(date, DateTime.monday - date.weekday);
  }

  int _isoWeekNumber(DateTime value) {
    final date = _dateOnly(value);
    final thursday = _addDays(date, DateTime.thursday - date.weekday);
    final firstThursday = DateTime(thursday.year, 1, 4);
    final firstWeekStart = _startOfIsoWeek(firstThursday);
    return (thursday.difference(firstWeekStart).inDays ~/ 7) + 1;
  }

  IconData _getEventTypeIcon(EventType type) {
    switch (type) {
      case EventType.todo:
        return Icons.check_circle_outline;
      case EventType.test:
        return Icons.quiz;
      case EventType.exam:
        return Icons.school;
      case EventType.assignment:
        return Icons.assignment;
      case EventType.classEvent:
        return Icons.class_;
      case EventType.reminder:
        return Icons.notifications;
      case EventType.other:
        return Icons.event;
    }
  }

  void _addEvent() {
    _openEventEditor(
      initialDate: _defaultDateForNewEvent(),
    );
  }

  void _openEventEditor({
    CalendarEvent? existingEvent,
    DateTime? initialDate,
    List<CalendarEvent>? linkedEvents,
  }) {
    final isEditing = existingEvent != null;
    final effectiveLinkedEvents = linkedEvents ?? <CalendarEvent>[];
    final isBatchEdit = isEditing && effectiveLinkedEvents.length > 1;
    final selectedCreateDates = !isEditing && _viewMode != CalendarViewMode.year
        ? _sortedSelectedDays()
        : <DateTime>[];
    final isMultiCreate = selectedCreateDates.length > 1;
    final titleController = TextEditingController(text: existingEvent?.title);
    final subjectController = TextEditingController(
      text: existingEvent?.subject,
    );
    final descriptionController = TextEditingController(
      text: existingEvent?.description,
    );
    EventType selectedType = existingEvent?.type ?? EventType.todo;
    DateTime selectedDate = _dateOnly(
      existingEvent?.startTime ?? initialDate ?? _defaultDateForNewEvent(),
    );
    TimeOfDay? selectedTime =
        _isAllDay(existingEvent?.startTime ?? selectedDate)
            ? null
            : TimeOfDay.fromDateTime(existingEvent!.startTime);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    isEditing ? 'Edit Event' : 'Add Event',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Event Title',
                      hintText: 'e.g., Math Test',
                    ),
                  ),
                  const SizedBox(height: 16),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Event Type',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<EventType>(
                        value: selectedType,
                        isDense: true,
                        items: const [
                          DropdownMenuItem(
                            value: EventType.todo,
                            child: Text('ToDo'),
                          ),
                          DropdownMenuItem(
                            value: EventType.test,
                            child: Text('Test'),
                          ),
                          DropdownMenuItem(
                            value: EventType.exam,
                            child: Text('Exam'),
                          ),
                          DropdownMenuItem(
                            value: EventType.assignment,
                            child: Text('Assignment'),
                          ),
                          DropdownMenuItem(
                            value: EventType.reminder,
                            child: Text('Reminder'),
                          ),
                          DropdownMenuItem(
                            value: EventType.classEvent,
                            child: Text('Class Event'),
                          ),
                          DropdownMenuItem(
                            value: EventType.other,
                            child: Text('Other'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setModalState(() {
                              selectedType = value;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: subjectController,
                    decoration: const InputDecoration(
                      labelText: 'Subject',
                      hintText: 'e.g., Mathematics',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: isBatchEdit || isMultiCreate
                            ? InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Dates',
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.calendar_today, size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        isBatchEdit
                                            ? '${effectiveLinkedEvents.length} linked event dates'
                                            : '${selectedCreateDates.length} selected dates',
                                        style: TextStyle(
                                          color: Theme.of(context).hintColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : InkWell(
                                onTap: () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: selectedDate,
                                    firstDate: _firstCalendarDay,
                                    lastDate: _lastCalendarDay,
                                  );
                                  if (date != null) {
                                    setModalState(() {
                                      selectedDate = date;
                                    });
                                  }
                                },
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                    labelText: 'Date',
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.calendar_today,
                                          size: 16),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                                        style: TextStyle(
                                          color: Theme.of(context).hintColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final time = await showTimePicker(
                              context: context,
                              initialTime: selectedTime ?? TimeOfDay.now(),
                            );
                            if (time != null) {
                              setModalState(() {
                                selectedTime = time;
                              });
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Time (optional)',
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.access_time, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    selectedTime != null
                                        ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}'
                                        : 'No time (all day)',
                                    style: TextStyle(
                                      color: Theme.of(context).hintColor,
                                    ),
                                  ),
                                ),
                                if (selectedTime != null)
                                  InkWell(
                                    onTap: () {
                                      setModalState(() {
                                        selectedTime = null;
                                      });
                                    },
                                    child: const Icon(Icons.clear, size: 16),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      hintText: 'Additional details...',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () async {
                      if (titleController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please enter an event title'),
                          ),
                        );
                        return;
                      }

                      final authService = context.read<AuthService>();
                      final userId = authService.storageUserId;
                      if (userId == null) return;

                      final startTime = DateTime(
                        selectedDate.year,
                        selectedDate.month,
                        selectedDate.day,
                        selectedTime?.hour ?? 0,
                        selectedTime?.minute ?? 0,
                      );

                      final provider = context.read<CalendarProvider>();

                      if (isBatchEdit) {
                        for (final event in effectiveLinkedEvents) {
                          await provider.updateEvent(
                            event.copyWith(
                              title: titleController.text,
                              description: descriptionController.text.isEmpty
                                  ? null
                                  : descriptionController.text,
                              type: selectedType,
                              startTime: DateTime(
                                event.startTime.year,
                                event.startTime.month,
                                event.startTime.day,
                                selectedTime?.hour ?? 0,
                                selectedTime?.minute ?? 0,
                              ),
                              subject: subjectController.text.isEmpty
                                  ? null
                                  : subjectController.text,
                              isCompleted: selectedType == EventType.todo
                                  ? event.isCompleted
                                  : false,
                              completedAt: selectedType == EventType.todo
                                  ? event.completedAt
                                  : null,
                              rolloverCount: selectedType == EventType.todo
                                  ? event.rolloverCount
                                  : 0,
                            ),
                          );
                        }
                      } else if (isEditing) {
                        await provider.updateEvent(
                          existingEvent.copyWith(
                            title: titleController.text,
                            description: descriptionController.text.isEmpty
                                ? null
                                : descriptionController.text,
                            type: selectedType,
                            startTime: startTime,
                            subject: subjectController.text.isEmpty
                                ? null
                                : subjectController.text,
                            isCompleted: selectedType == EventType.todo
                                ? existingEvent.isCompleted
                                : false,
                            completedAt: selectedType == EventType.todo
                                ? existingEvent.completedAt
                                : null,
                            rolloverCount: selectedType == EventType.todo
                                ? existingEvent.rolloverCount
                                : 0,
                          ),
                        );
                      } else if (isMultiCreate) {
                        await provider.createEventsForDates(
                          userId: userId,
                          title: titleController.text,
                          dates: selectedCreateDates,
                          startTimeTemplate: startTime,
                          description: descriptionController.text.isEmpty
                              ? null
                              : descriptionController.text,
                          type: selectedType,
                          subject: subjectController.text.isEmpty
                              ? null
                              : subjectController.text,
                        );
                      } else {
                        await provider.createEvent(
                          userId: userId,
                          title: titleController.text,
                          description: descriptionController.text.isEmpty
                              ? null
                              : descriptionController.text,
                          type: selectedType,
                          startTime: startTime,
                          subject: subjectController.text.isEmpty
                              ? null
                              : subjectController.text,
                        );
                      }

                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                    child: Text(isEditing ? 'Save Changes' : 'Add Event'),
                  ),
                  if (isEditing) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () async {
                        if (isBatchEdit) {
                          for (final event in effectiveLinkedEvents) {
                            await context.read<CalendarProvider>().deleteEvent(
                                  event.id,
                                );
                          }
                        } else {
                          await context
                              .read<CalendarProvider>()
                              .deleteEvent(existingEvent.id);
                        }
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                      child: Text(
                        isBatchEdit
                            ? 'Delete All Linked Events'
                            : 'Delete Event',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _eventAccentColor(CalendarEvent event) {
    if (event.color != null) {
      return Color(int.parse(event.color!.replaceFirst('#', '0xFF')));
    }

    if (!event.isTodo) {
      return Theme.of(context).colorScheme.primary;
    }

    if (event.isCompleted) {
      return Theme.of(context).colorScheme.outline;
    }

    final base = Theme.of(context).colorScheme.primary;
    final warning = Theme.of(context).colorScheme.error;
    final intensity = (event.rolloverCount / 4).clamp(0.0, 1.0);
    return Color.lerp(base, warning, intensity) ?? base;
  }
}
