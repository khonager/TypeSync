/// Timetable Screen
///
/// Weekly class timetable view.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/timetable_entry.dart';
import '../../../core/providers/timetable_provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/widgets/desktop_window_frame.dart';

/// Timetable screen showing weekly class schedule
class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  Weekday _selectedDay = Weekday.values[DateTime.now().weekday - 1];

  @override
  void initState() {
    super.initState();
    // Defer initialization until after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  Future<void> _initializeData() async {
    final authService = context.read<AuthService>();
    final userId = authService.storageUserId;

    if (userId != null) {
      await context.read<TimetableProvider>().initialize(userId);
    }
    if (!mounted) return;
    if (authService.userId != null && authService.effectiveSyncEnabled) {
      await context.read<SyncService>().fetchWorkspaceSnapshot(
            authService.userId!,
          );
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
        title: const Text('Timetable'),
        actions: withDesktopWindowControls(const []),
      ),
      body: Column(
        children: [
          // Day selector
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: Weekday.values.map((day) {
                  final isSelected = day == _selectedDay;
                  final isToday = day.index == DateTime.now().weekday - 1;

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(day.shortName),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedDay = day);
                        }
                      },
                      avatar: isToday && !isSelected
                          ? Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          const Divider(),

          // Timetable content
          Expanded(
            child: _buildTimetableContent(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEntry,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildTimetableContent() {
    final timetableProvider = context.watch<TimetableProvider>();
    final entries = timetableProvider.getEntriesForDay(_selectedDay);

    if (timetableProvider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.schedule,
              size: 64,
              color: Colors.grey.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No classes on ${_selectedDay.fullName}',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap + to add a class',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final color = Color(int.parse(entry.color.replaceFirst('#', '0xFF')));

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: color.withValues(alpha: 0.2),
          child: ListTile(
            onTap: () => _openEntryEditor(existingEntry: entry),
            contentPadding: const EdgeInsets.all(16),
            leading: Container(
              width: 4,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            title: Text(
              entry.subject,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.teacher != null && entry.teacher!.isNotEmpty)
                  Text('Teacher: ${entry.teacher}'),
                if (entry.room != null && entry.room!.isNotEmpty)
                  Text('Room: ${entry.room}'),
                const SizedBox(height: 8),
                Text(
                  '${entry.startTimeFormatted} - ${entry.endTimeFormatted}',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _deleteEntry(entry.id),
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteEntry(String entryId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Class'),
        content: const Text('Are you sure you want to delete this class?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      await context.read<TimetableProvider>().deleteEntry(entryId);
    }
  }

  void _addEntry() {
    _openEntryEditor();
  }

  void _openEntryEditor({TimetableEntry? existingEntry}) {
    final isEditing = existingEntry != null;
    final subjectController = TextEditingController(
      text: existingEntry?.subject,
    );
    final teacherController = TextEditingController(
      text: existingEntry?.teacher,
    );
    final roomController = TextEditingController(text: existingEntry?.room);
    var startHour = existingEntry?.startHour ?? 9;
    var startMinute = existingEntry?.startMinute ?? 0;
    var endHour = existingEntry?.endHour ?? 10;
    var endMinute = existingEntry?.endMinute ?? 0;
    var selectedWeekday = existingEntry?.weekday ?? _selectedDay;

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
                    isEditing ? 'Edit Class' : 'Add Class',
                    style: Theme.of(context).textTheme.titleLarge,
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
                  TextField(
                    controller: teacherController,
                    decoration: const InputDecoration(
                      labelText: 'Teacher',
                      hintText: 'e.g., Mr. Smith',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: roomController,
                    decoration: const InputDecoration(
                      labelText: 'Room',
                      hintText: 'e.g., Room 101',
                    ),
                  ),
                  const SizedBox(height: 16),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Day',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<Weekday>(
                        value: selectedWeekday,
                        isDense: true,
                        items: Weekday.values.map((day) {
                          return DropdownMenuItem(
                            value: day,
                            child: Text(day.fullName),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setModalState(() {
                              selectedWeekday = value;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Start Hour',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: startHour,
                              isDense: true,
                              items:
                                  List.generate(14, (i) => i + 7).map((hour) {
                                return DropdownMenuItem(
                                  value: hour,
                                  child: Text('$hour:00'),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setModalState(() {
                                    startHour = value;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Start Minute',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: startMinute,
                              isDense: true,
                              items: [0, 15, 30, 45].map((minute) {
                                return DropdownMenuItem(
                                  value: minute,
                                  child: Text(
                                    ':${minute.toString().padLeft(2, '0')}',
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setModalState(() {
                                    startMinute = value;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'End Hour',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: endHour,
                              isDense: true,
                              items:
                                  List.generate(14, (i) => i + 7).map((hour) {
                                return DropdownMenuItem(
                                  value: hour,
                                  child: Text('$hour:00'),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setModalState(() {
                                    endHour = value;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'End Minute',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: endMinute,
                              isDense: true,
                              items: [0, 15, 30, 45].map((minute) {
                                return DropdownMenuItem(
                                  value: minute,
                                  child: Text(
                                    ':${minute.toString().padLeft(2, '0')}',
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setModalState(() {
                                    endMinute = value;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () async {
                      if (subjectController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please enter a subject'),
                          ),
                        );
                        return;
                      }

                      final authService = context.read<AuthService>();
                      final userId = authService.storageUserId;
                      if (userId == null) return;

                      if (isEditing) {
                        await context.read<TimetableProvider>().updateEntry(
                              existingEntry.copyWith(
                                subject: subjectController.text,
                                teacher: teacherController.text.isEmpty
                                    ? null
                                    : teacherController.text,
                                room: roomController.text.isEmpty
                                    ? null
                                    : roomController.text,
                                weekday: selectedWeekday,
                                startHour: startHour,
                                startMinute: startMinute,
                                endHour: endHour,
                                endMinute: endMinute,
                              ),
                            );
                      } else {
                        await context.read<TimetableProvider>().createEntry(
                              userId: userId,
                              subject: subjectController.text,
                              teacher: teacherController.text.isEmpty
                                  ? null
                                  : teacherController.text,
                              room: roomController.text.isEmpty
                                  ? null
                                  : roomController.text,
                              weekday: selectedWeekday,
                              startHour: startHour,
                              startMinute: startMinute,
                              endHour: endHour,
                              endMinute: endMinute,
                            );
                      }

                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                    child: Text(isEditing ? 'Save Changes' : 'Add Class'),
                  ),
                  if (isEditing) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () async {
                        await context
                            .read<TimetableProvider>()
                            .deleteEntry(existingEntry.id);
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                      child: const Text(
                        'Delete Class',
                        style: TextStyle(color: Colors.red),
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
}
