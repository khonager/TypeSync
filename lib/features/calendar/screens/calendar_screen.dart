/// Calendar Screen
///
/// Calendar view with test reminders and events.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/providers/calendar_provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/models/calendar_event.dart';

/// Calendar screen for test reminders and events
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
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
              setState(() {
                _focusedDay = DateTime.now();
                _selectedDay = DateTime.now();
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Calendar widget
          TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            calendarFormat: _calendarFormat,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            onFormatChanged: (format) {
              setState(() {
                _calendarFormat = format;
              });
            },
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
            },
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              weekendTextStyle: TextStyle(
                color: Theme.of(context).colorScheme.error.withOpacity(0.7),
              ),
            ),
            headerStyle: HeaderStyle(
              formatButtonVisible: true,
              formatButtonDecoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),

          const Divider(),

          // Events for selected day
          Expanded(
            child: _selectedDay != null
                ? _buildEventsList()
                : const Center(
                    child: Text('Select a day to view events'),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEvent,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEventsList() {
    final calendarProvider = context.watch<CalendarProvider>();
    final events = calendarProvider.getEventsForDate(_selectedDay!);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Events for ${_selectedDay!.day}/${_selectedDay!.month}/${_selectedDay!.year}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        if (events.isEmpty)
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.event_available,
                  size: 48,
                  color: Colors.grey.withOpacity(0.5),
                ),
                const SizedBox(height: 8),
                const Text(
                  'No events scheduled',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          )
        else
          ...events.map((event) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Container(
                    width: 4,
                    height: double.infinity,
                    color: event.color != null
                        ? Color(
                            int.parse(event.color!.replaceFirst('#', '0xFF')))
                        : Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(event.title),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (event.subject != null)
                        Text('Subject: ${event.subject}'),
                      Text(
                        '${event.startTime.hour.toString().padLeft(2, '0')}:${event.startTime.minute.toString().padLeft(2, '0')}',
                      ),
                      if (event.description != null &&
                          event.description!.isNotEmpty)
                        Text(event.description!),
                    ],
                  ),
                  trailing: Icon(
                    _getEventTypeIcon(event.type),
                    color: event.color != null
                        ? Color(
                            int.parse(event.color!.replaceFirst('#', '0xFF')))
                        : null,
                  ),
                ),
              )),
      ],
    );
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
    DateTime? selectedDate;
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
                  DropdownButtonFormField<EventType>(
                    decoration: const InputDecoration(
                      labelText: 'Event Type',
                    ),
                    value: selectedType,
                    items: const [
                      DropdownMenuItem(
                          value: EventType.test, child: Text('Test')),
                      DropdownMenuItem(
                          value: EventType.exam, child: Text('Exam')),
                      DropdownMenuItem(
                          value: EventType.assignment,
                          child: Text('Assignment')),
                      DropdownMenuItem(
                          value: EventType.reminder, child: Text('Reminder')),
                      DropdownMenuItem(
                          value: EventType.classEvent,
                          child: Text('Class Event')),
                      DropdownMenuItem(
                          value: EventType.other, child: Text('Other')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setModalState(() {
                          selectedType = value;
                        });
                      }
                    },
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
                              initialDate: _selectedDay ?? DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate:
                                  DateTime.now().add(const Duration(days: 365)),
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
                                  selectedDate != null
                                      ? '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}'
                                      : 'Select',
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
                              labelText: 'Time',
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.access_time, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  selectedTime != null
                                      ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}'
                                      : 'Select',
                                  style: TextStyle(
                                    color: Theme.of(context).hintColor,
                                  ),
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
                              content: Text('Please enter an event title')),
                        );
                        return;
                      }

                      if (selectedDate == null || selectedTime == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Please select date and time')),
                        );
                        return;
                      }

                      final authService = context.read<AuthService>();
                      final userId = authService.userId;
                      if (userId == null) return;

                      final startTime = DateTime(
                        selectedDate!.year,
                        selectedDate!.month,
                        selectedDate!.day,
                        selectedTime!.hour,
                        selectedTime!.minute,
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

                      if (mounted) {
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
