/// Homework Screen
///
/// Todo list for homework assignments.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/homework_provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/models/homework.dart';

/// Homework todo list screen
class HomeworkScreen extends StatefulWidget {
  const HomeworkScreen({super.key});

  @override
  State<HomeworkScreen> createState() => _HomeworkScreenState();
}

class _HomeworkScreenState extends State<HomeworkScreen> {
  // Filter state
  bool _showCompleted = false;

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
      await context.read<HomeworkProvider>().initialize(userId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final homeworkProvider = context.watch<HomeworkProvider>();
    final homework = homeworkProvider.getHomeworkByStatus(_showCompleted);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Homework'),
        actions: [
          IconButton(
            icon: Icon(
              _showCompleted ? Icons.visibility : Icons.visibility_off,
            ),
            onPressed: () {
              setState(() {
                _showCompleted = !_showCompleted;
              });
            },
            tooltip: _showCompleted ? 'Hide completed' : 'Show completed',
          ),
        ],
      ),
      body: homeworkProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildHomeworkList(homework),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addHomework,
        icon: const Icon(Icons.add),
        label: const Text('Add Task'),
      ),
    );
  }

  Widget _buildHomeworkList(List<Homework> homework) {
    if (homework.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: Colors.grey.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              'No homework yet',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap + to add a new task',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: homework.length,
      itemBuilder: (context, index) {
        final task = homework[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: CheckboxListTile(
            value: task.isCompleted,
            onChanged: (value) {
              context.read<HomeworkProvider>().toggleCompletion(task.id);
            },
            title: Text(
              task.title,
              style: TextStyle(
                decoration:
                    task.isCompleted ? TextDecoration.lineThrough : null,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (task.subject != null) Text('Subject: ${task.subject}'),
                if (task.dueDate != null)
                  Text(
                    'Due: ${task.dueDate!.day}/${task.dueDate!.month}/${task.dueDate!.year}',
                    style: TextStyle(
                      color: task.isOverdue ? Colors.red : null,
                    ),
                  ),
                if (task.description != null && task.description!.isNotEmpty)
                  Text(task.description!),
              ],
            ),
            secondary: Icon(
              _getPriorityIcon(task.priority),
              color: _getPriorityColor(task.priority),
            ),
          ),
        );
      },
    );
  }

  IconData _getPriorityIcon(HomeworkPriority priority) {
    switch (priority) {
      case HomeworkPriority.low:
        return Icons.arrow_downward;
      case HomeworkPriority.medium:
        return Icons.remove;
      case HomeworkPriority.high:
        return Icons.arrow_upward;
      case HomeworkPriority.urgent:
        return Icons.priority_high;
    }
  }

  Color _getPriorityColor(HomeworkPriority priority) {
    switch (priority) {
      case HomeworkPriority.low:
        return Colors.green;
      case HomeworkPriority.medium:
        return Colors.orange;
      case HomeworkPriority.high:
        return Colors.red;
      case HomeworkPriority.urgent:
        return Colors.purple;
    }
  }

  void _addHomework() {
    final taskController = TextEditingController();
    final subjectController = TextEditingController();
    final descriptionController = TextEditingController();
    HomeworkPriority selectedPriority = HomeworkPriority.medium;
    DateTime? selectedDueDate;

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
                    'Add Homework',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: taskController,
                    decoration: const InputDecoration(
                      labelText: 'Task',
                      hintText: 'e.g., Complete chapter 5 exercises',
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
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Priority',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<HomeworkPriority>(
                              value: selectedPriority,
                              isDense: true,
                              items: const [
                                DropdownMenuItem(
                                  value: HomeworkPriority.low,
                                  child: Text('Low'),
                                ),
                                DropdownMenuItem(
                                  value: HomeworkPriority.medium,
                                  child: Text('Medium'),
                                ),
                                DropdownMenuItem(
                                  value: HomeworkPriority.high,
                                  child: Text('High'),
                                ),
                                DropdownMenuItem(
                                  value: HomeworkPriority.urgent,
                                  child: Text('Urgent'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setModalState(() {
                                    selectedPriority = value;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate:
                                  DateTime.now().add(const Duration(days: 1)),
                              firstDate: DateTime.now(),
                              lastDate:
                                  DateTime.now().add(const Duration(days: 365)),
                            );
                            if (date != null) {
                              setModalState(() {
                                selectedDueDate = date;
                              });
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Due Date',
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  selectedDueDate != null
                                      ? '${selectedDueDate!.day}/${selectedDueDate!.month}/${selectedDueDate!.year}'
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
                      if (taskController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please enter a task title'),
                          ),
                        );
                        return;
                      }

                      final authService = context.read<AuthService>();
                      final userId = authService.userId;
                      if (userId == null) return;

                      await context.read<HomeworkProvider>().createHomework(
                            userId: userId,
                            title: taskController.text,
                            subject: subjectController.text.isEmpty
                                ? null
                                : subjectController.text,
                            description: descriptionController.text.isEmpty
                                ? null
                                : descriptionController.text,
                            dueDate: selectedDueDate,
                            priority: selectedPriority,
                          );

                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                    child: const Text('Add Task'),
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
