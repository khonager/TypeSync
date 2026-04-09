/// Calendar Screen
///
/// Calendar view with test reminders and events.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/providers/calendar_provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/models/calendar_event.dart';

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

  final DateFormat _monthHeaderFormat = DateFormat.yMMMM();
  final DateFormat _dateLabelFormat = DateFormat('EEE, d MMM y');

  CalendarViewMode _viewMode = CalendarViewMode.month;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  late DateTime _focusedDay;
  DateTime? _selectedDay;
  late DateTime _selectedWeekStart;
  bool _handledInitialRouteAction = false;

  @override
  void initState() {
    super.initState();
    final now = _dateOnly(DateTime.now());
    _focusedDay = now;
    _selectedDay = null;
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
    final userId = authService.userId;
    if (userId != null) {
      await context.read<CalendarProvider>().initialize(userId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: () {
              final now = _dateOnly(DateTime.now());
              setState(() {
                _focusedDay = now;
                _selectedDay = now;
                _selectedWeekStart = _startOfIsoWeek(now);
              });
            },
          ),
        ],
      ),
      body: Consumer<CalendarProvider>(
        builder: (context, calendarProvider, _) {
          final eventDayKeys = calendarProvider.events
              .map((event) => _dateKey(event.startTime))
              .toSet();

          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (_viewMode != CalendarViewMode.year && _selectedDay != null) {
                setState(() {
                  _selectedDay = null;
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
              _selectedWeekStart = _startOfIsoWeek(_selectedDay ?? _focusedDay);
              _focusedDay = _selectedWeekStart;
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
        child: child,
      ),
    );
  }

  String _calendarHeaderLabel() {
    if (_viewMode == CalendarViewMode.year) {
      return '${_focusedDay.year}';
    }
    return _monthHeaderFormat.format(_focusedDay);
  }

  void _goToPreviousPeriod() {
    setState(() {
      switch (_viewMode) {
        case CalendarViewMode.month:
          _focusedDay =
              _dateOnly(DateTime(_focusedDay.year, _focusedDay.month - 1, 1));
          break;
        case CalendarViewMode.twoWeeks:
          _focusedDay = _dateOnly(
            _focusedDay.subtract(const Duration(days: 14)),
          );
          break;
        case CalendarViewMode.week:
          _focusedDay = _dateOnly(
            _focusedDay.subtract(const Duration(days: 7)),
          );
          break;
        case CalendarViewMode.year:
          _focusedDay = DateTime(_focusedDay.year - 1, 1, 1);
          _selectedWeekStart = _startOfIsoWeek(_focusedDay);
          _selectedDay = _selectedWeekStart;
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
          break;
        case CalendarViewMode.twoWeeks:
          _focusedDay = _dateOnly(_focusedDay.add(const Duration(days: 14)));
          break;
        case CalendarViewMode.week:
          _focusedDay = _dateOnly(_focusedDay.add(const Duration(days: 7)));
          break;
        case CalendarViewMode.year:
          _focusedDay = DateTime(_focusedDay.year + 1, 1, 1);
          _selectedWeekStart = _startOfIsoWeek(_focusedDay);
          _selectedDay = _selectedWeekStart;
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
      startingDayOfWeek: StartingDayOfWeek.monday,
      selectedDayPredicate: (day) =>
          _selectedDay != null && isSameDay(_selectedDay, day),
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          if (_selectedDay != null && isSameDay(_selectedDay, selectedDay)) {
            _selectedDay = null;
          } else {
            _selectedDay = _dateOnly(selectedDay);
          }
          _focusedDay = _dateOnly(focusedDay);
          _selectedWeekStart = _startOfIsoWeek(_dateOnly(selectedDay));
        });
      },
      onPageChanged: (focusedDay) {
        setState(() {
          _focusedDay = _dateOnly(focusedDay);
        });
      },
      headerVisible: false,
      calendarBuilders: CalendarBuilders(
        defaultBuilder: (context, day, _) => _buildDayCell(
          day,
          hasEvents: eventDayKeys.contains(_dateKey(day)),
        ),
        outsideBuilder: (context, day, _) => _buildDayCell(
          day,
          hasEvents: eventDayKeys.contains(_dateKey(day)),
          isOutside: true,
        ),
        todayBuilder: (context, day, _) => _buildDayCell(
          day,
          hasEvents: eventDayKeys.contains(_dateKey(day)),
          isToday: true,
        ),
        selectedBuilder: (context, day, _) => _buildDayCell(
          day,
          hasEvents: eventDayKeys.contains(_dateKey(day)),
          isSelected: true,
        ),
      ),
    );
  }

  Widget _buildDayCell(
    DateTime day, {
    required bool hasEvents,
    bool isSelected = false,
    bool isToday = false,
    bool isOutside = false,
  }) {
    final theme = Theme.of(context);
    final textColor = isSelected
        ? theme.colorScheme.onPrimary
        : isOutside
            ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
            : null;

    final BoxDecoration? decoration;
    if (isSelected) {
      decoration = BoxDecoration(
        color: theme.colorScheme.primary,
        shape: BoxShape.circle,
        border: hasEvents
            ? Border.all(color: theme.colorScheme.onPrimary, width: 1.5)
            : null,
      );
    } else if (isToday) {
      decoration = BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.25),
        shape: BoxShape.circle,
        border: hasEvents
            ? Border.all(color: theme.colorScheme.primary, width: 1.4)
            : null,
      );
    } else if (hasEvents) {
      decoration = BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: theme.colorScheme.primary, width: 1.3),
      );
    } else {
      decoration = null;
    }

    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 34,
        height: 34,
        decoration: decoration,
        alignment: Alignment.center,
        child: Text(
          '${day.day}',
          style: TextStyle(color: textColor),
        ),
      ),
    );
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
                _selectedDay = week.start;
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
    final hasSelectedDayFilter =
        _viewMode != CalendarViewMode.year && _selectedDay != null;
    final range = hasSelectedDayFilter
        ? DateTimeRange(start: _selectedDay!, end: _selectedDay!)
        : _visibleRange();
    final events = _eventsInRange(
      calendarProvider.events,
      start: range.start,
      end: range.end,
    );
    final header = hasSelectedDayFilter
        ? 'Events on ${DateFormat('EEE, d MMM y').format(range.start)}'
        : _eventsHeaderForRange(range.start, range.end);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          header,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        if (events.isEmpty)
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
          ...events.map(
            (event) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Container(
                  width: 4,
                  height: double.infinity,
                  color: event.color != null
                      ? Color(
                          int.parse(event.color!.replaceFirst('#', '0xFF')),
                        )
                      : Theme.of(context).colorScheme.primary,
                ),
                title: Text(event.title),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (event.subject != null &&
                        event.subject!.trim().isNotEmpty)
                      Text('Subject: ${event.subject}'),
                    Text(
                      _eventDateTimeLabel(event),
                    ),
                    if (event.description != null &&
                        event.description!.trim().isNotEmpty)
                      Text(event.description!),
                  ],
                ),
                trailing: Icon(
                  _getEventTypeIcon(event.type),
                  color: event.color != null
                      ? Color(
                          int.parse(event.color!.replaceFirst('#', '0xFF')),
                        )
                      : null,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _eventDateTimeLabel(CalendarEvent event) {
    final date = _dateLabelFormat.format(event.startTime);
    if (_isAllDay(event.startTime)) {
      return '$date • All day';
    }
    return '$date • ${DateFormat.Hm().format(event.startTime)}';
  }

  String _eventsHeaderForRange(DateTime start, DateTime end) {
    if (_viewMode == CalendarViewMode.month) {
      return 'Events in ${_monthHeaderFormat.format(_focusedDay)}';
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
        end: start.add(const Duration(days: 6)),
      );
    }

    if (_viewMode == CalendarViewMode.month) {
      final start = DateTime(_focusedDay.year, _focusedDay.month, 1);
      final end = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);
      return DateTimeRange(start: start, end: end);
    }

    final start = _startOfIsoWeek(_focusedDay);
    final end = _viewMode == CalendarViewMode.twoWeeks
        ? start.add(const Duration(days: 13))
        : start.add(const Duration(days: 6));
    return DateTimeRange(start: start, end: end);
  }

  List<CalendarEvent> _eventsInRange(
    List<CalendarEvent> source, {
    required DateTime start,
    required DateTime end,
  }) {
    return source.where((event) {
      final eventDate = _dateOnly(event.startTime);
      return !eventDate.isBefore(_dateOnly(start)) &&
          !eventDate.isAfter(_dateOnly(end));
    }).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  bool _weekHasEvents(
    List<CalendarEvent> source, {
    required DateTime start,
    required DateTime end,
  }) {
    final from = _dateOnly(start);
    final to = _dateOnly(end);
    return source.any((event) {
      final eventDate = _dateOnly(event.startTime);
      return !eventDate.isBefore(from) && !eventDate.isAfter(to);
    });
  }

  List<_YearWeekItem> _buildWeeksForYear(int year) {
    final totalWeeks = _isoWeekNumber(DateTime(year, 12, 28));
    final firstWeekStart = _startOfIsoWeek(DateTime(year, 1, 4));

    return List<_YearWeekItem>.generate(totalWeeks, (index) {
      final start = firstWeekStart.add(Duration(days: index * 7));
      final end = start.add(const Duration(days: 6));
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
    return _selectedDay ?? _focusedDay;
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
    return date.subtract(Duration(days: date.weekday - DateTime.monday));
  }

  int _isoWeekNumber(DateTime value) {
    final date = _dateOnly(value);
    final thursday = date.add(Duration(days: DateTime.thursday - date.weekday));
    final firstThursday = DateTime(thursday.year, 1, 4);
    final firstWeekStart = _startOfIsoWeek(firstThursday);
    return (thursday.difference(firstWeekStart).inDays ~/ 7) + 1;
  }

  IconData _getEventTypeIcon(EventType type) {
    switch (type) {
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
    final titleController = TextEditingController();
    final subjectController = TextEditingController();
    final descriptionController = TextEditingController();
    EventType selectedType = EventType.reminder;
    DateTime selectedDate = _defaultDateForNewEvent();
    TimeOfDay? selectedTime;

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
                    'Add Event',
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
                        child: InkWell(
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
                                const Icon(Icons.calendar_today, size: 16),
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
                              initialTime: TimeOfDay.now(),
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
                                Text(
                                  selectedTime != null
                                      ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}'
                                      : 'No time (all day)',
                                  style: TextStyle(
                                    color: Theme.of(context).hintColor,
                                  ),
                                ),
                                if (selectedTime != null) ...[
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () {
                                      setModalState(() {
                                        selectedTime = null;
                                      });
                                    },
                                    child: const Icon(
                                      Icons.clear,
                                      size: 16,
                                    ),
                                  ),
                                ],
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
                      final userId = authService.userId;
                      if (userId == null) return;

                      final startTime = DateTime(
                        selectedDate.year,
                        selectedDate.month,
                        selectedDate.day,
                        selectedTime?.hour ?? 0,
                        selectedTime?.minute ?? 0,
                      );

                      await context.read<CalendarProvider>().createEvent(
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

                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                    child: const Text('Add Event'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
