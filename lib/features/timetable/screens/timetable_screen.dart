/// Timetable Screen
/// 
/// Weekly class timetable view.

import 'package:flutter/material.dart';

import '../../../core/models/timetable_entry.dart';

/// Timetable screen showing weekly class schedule
class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  Weekday _selectedDay = Weekday.values[DateTime.now().weekday - 1];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Timetable'),
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
    // TODO: Load actual timetable entries from provider
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.schedule,
            size: 64,
            color: Colors.grey.withOpacity(0.5),
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

  void _addEntry() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
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
                  'Add Class',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                const TextField(
                  decoration: InputDecoration(
                    labelText: 'Subject',
                    hintText: 'e.g., Mathematics',
                  ),
                ),
                const SizedBox(height: 16),
                const TextField(
                  decoration: InputDecoration(
                    labelText: 'Teacher',
                    hintText: 'e.g., Mr. Smith',
                  ),
                ),
                const SizedBox(height: 16),
                const TextField(
                  decoration: InputDecoration(
                    labelText: 'Room',
                    hintText: 'e.g., Room 101',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: 'Start Hour',
                        ),
                        value: 9,
                        items: List.generate(14, (i) => i + 7).map((hour) {
                          return DropdownMenuItem(
                            value: hour,
                            child: Text('$hour:00'),
                          );
                        }).toList(),
                        onChanged: (value) {},
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: 'End Hour',
                        ),
                        value: 10,
                        items: List.generate(14, (i) => i + 7).map((hour) {
                          return DropdownMenuItem(
                            value: hour,
                            child: Text('$hour:00'),
                          );
                        }).toList(),
                        onChanged: (value) {},
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // TODO: Save entry
                  },
                  child: const Text('Add Class'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

