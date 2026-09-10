/// Timetable Screen
///
/// Weekly class timetable view.
library;

import 'dart:async';

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
        title: Consumer<TimetableProvider>(
          builder: (context, provider, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Timetable'),
              Text(
                provider.activeTimetable.name,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
        actions: withDesktopWindowControls([
          PopupMenuButton<String>(
            tooltip: 'Manage timetables',
            icon: const Icon(Icons.view_week_outlined),
            onSelected: _handleTimetableAction,
            itemBuilder: (context) {
              final provider = context.read<TimetableProvider>();
              return [
                ...provider.timetables.map(
                  (timetable) => PopupMenuItem(
                    value: 'select:${timetable.id}',
                    child: Row(
                      children: [
                        Icon(
                          timetable.id == provider.activeTimetableId
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Flexible(child: Text(timetable.name)),
                      ],
                    ),
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'new',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.add),
                    title: Text('New timetable'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'rename',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Rename current'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  enabled: provider.timetables.length > 1,
                  child: const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline),
                    title: Text('Delete current'),
                  ),
                ),
              ];
            },
          ),
        ]),
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

  Future<void> _handleTimetableAction(String action) async {
    final provider = context.read<TimetableProvider>();
    if (action.startsWith('select:')) {
      await provider.selectTimetable(action.substring('select:'.length));
      return;
    }
    if (action == 'new') {
      final name = await _requestTimetableName(title: 'New timetable');
      if (name != null) await provider.createTimetable(name);
      return;
    }
    if (action == 'rename') {
      final name = await _requestTimetableName(
        title: 'Rename timetable',
        initialValue: provider.activeTimetable.name,
      );
      if (name != null) await provider.renameActiveTimetable(name);
      return;
    }
    if (action == 'delete') {
      final name = provider.activeTimetable.name;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete timetable?'),
          content: Text('Delete "$name" and all of its classes?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed == true) await provider.deleteActiveTimetable();
    }
  }

  Future<String?> _requestTimetableName({
    required String title,
    String initialValue = '',
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'e.g., A Werk or 2026',
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _openEntryEditor({TimetableEntry? existingEntry}) async {
    final provider = context.read<TimetableProvider>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => _TimetableEntryEditorSheet(
        existingEntry: existingEntry,
        initialWeekday: _selectedDay,
        timetableId: provider.activeTimetableId,
        timetableName: provider.activeTimetable.name,
      ),
    );
  }
}

class _TimetableEntryEditorSheet extends StatefulWidget {
  final TimetableEntry? existingEntry;
  final Weekday initialWeekday;
  final String timetableId;
  final String timetableName;

  const _TimetableEntryEditorSheet({
    required this.existingEntry,
    required this.initialWeekday,
    required this.timetableId,
    required this.timetableName,
  });

  @override
  State<_TimetableEntryEditorSheet> createState() =>
      _TimetableEntryEditorSheetState();
}

class _TimetableEntryEditorSheetState
    extends State<_TimetableEntryEditorSheet> {
  late final TextEditingController _subjectController;
  late String _teacher;
  late String _room;
  late Weekday _weekday;
  late int _startHour;
  late int _startMinute;
  late int _endHour;
  late int _endMinute;
  TimetableEntry? _entry;
  Timer? _saveTimer;
  Future<void>? _pendingSave;
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _entry = widget.existingEntry;
    _subjectController = TextEditingController(text: _entry?.subject ?? '');
    _teacher = _entry?.teacher ?? '';
    _room = _entry?.room ?? '';
    _weekday = _entry?.weekday ?? widget.initialWeekday;
    _startHour = _entry?.startHour ?? 9;
    _startMinute = _entry?.startMinute ?? 0;
    _endHour = _entry?.endHour ?? 10;
    _endMinute = _entry?.endMinute ?? 0;
    _subjectController.addListener(_scheduleSave);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _subjectController.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    if (mounted) setState(() => _saved = false);
    _saveTimer = Timer(const Duration(milliseconds: 350), _persist);
  }

  Future<void> _persist() async {
    _saveTimer?.cancel();
    final subject = _subjectController.text.trim();
    if (subject.isEmpty) return;
    final teacher = _teacher.trim().isEmpty ? null : _teacher.trim();
    final room = _room.trim().isEmpty ? null : _room.trim();
    final weekday = _weekday;
    final startHour = _startHour;
    final startMinute = _startMinute;
    final endHour = _endHour;
    final endMinute = _endMinute;
    final provider = context.read<TimetableProvider>();
    final userId = context.read<AuthService>().storageUserId;
    final previousSave = _pendingSave ?? Future<void>.value();

    _saving = true;
    if (mounted) setState(() {});
    late final Future<void> currentSave;
    currentSave = previousSave.then((_) async {
      if (_entry == null) {
        if (userId != null) {
          _entry = await provider.createEntry(
            userId: userId,
            subject: subject,
            teacher: teacher,
            room: room,
            weekday: weekday,
            startHour: startHour,
            startMinute: startMinute,
            endHour: endHour,
            endMinute: endMinute,
            timetableId: widget.timetableId,
            timetableName: widget.timetableName,
          );
        }
      } else {
        final updated = _entry!.copyWith(
          subject: subject,
          teacher: teacher,
          room: room,
          weekday: weekday,
          startHour: startHour,
          startMinute: startMinute,
          endHour: endHour,
          endMinute: endMinute,
        );
        if (await provider.updateEntry(updated)) _entry = updated;
      }
    });
    _pendingSave = currentSave;
    await currentSave;
    if (identical(_pendingSave, currentSave)) {
      _pendingSave = null;
      _saving = false;
      if (mounted) setState(() => _saved = _entry != null);
    }
  }

  Future<void> _finish() async {
    if (_subjectController.text.trim().isEmpty) {
      if (_entry == null) {
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a subject')),
        );
      }
      return;
    }
    await _persist();
    if (mounted) Navigator.pop(context);
  }

  void _change(VoidCallback change) {
    setState(change);
    _scheduleSave();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<TimetableProvider>();
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _entry == null ? 'Add Class' : 'Edit Class',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: _saving
                          ? const Text('Saving…', key: ValueKey('saving'))
                          : _saved
                              ? const Text('Saved', key: ValueKey('saved'))
                              : const SizedBox.shrink(key: ValueKey('idle')),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _subjectController,
                  autofocus: _entry == null,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    hintText: 'e.g., Mathematics',
                  ),
                ),
                const SizedBox(height: 16),
                _SuggestionTextField(
                  initialValue: _teacher,
                  label: 'Teacher',
                  hint: 'e.g., Mr. Smith',
                  suggestions: provider.teacherSuggestions,
                  onChanged: (value) {
                    _teacher = value;
                    _scheduleSave();
                  },
                ),
                const SizedBox(height: 16),
                _SuggestionTextField(
                  initialValue: _room,
                  label: 'Room',
                  hint: 'e.g., Room 101',
                  suggestions: provider.roomSuggestions,
                  onChanged: (value) {
                    _room = value;
                    _scheduleSave();
                  },
                ),
                const SizedBox(height: 16),
                _dropdown<Weekday>(
                  label: 'Day',
                  value: _weekday,
                  values: Weekday.values,
                  labelFor: (day) => day.fullName,
                  onChanged: (value) => _change(() => _weekday = value),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _dropdown<int>(
                        label: 'Start hour',
                        value: _startHour,
                        values: List.generate(17, (index) => index + 5),
                        labelFor: (hour) => hour.toString().padLeft(2, '0'),
                        onChanged: (value) => _change(() => _startHour = value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _dropdown<int>(
                        label: 'Minute',
                        value: _startMinute,
                        values: const [0, 15, 30, 45],
                        labelFor: (minute) =>
                            ':${minute.toString().padLeft(2, '0')}',
                        onChanged: (value) =>
                            _change(() => _startMinute = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _dropdown<int>(
                        label: 'End hour',
                        value: _endHour,
                        values: List.generate(17, (index) => index + 5),
                        labelFor: (hour) => hour.toString().padLeft(2, '0'),
                        onChanged: (value) => _change(() => _endHour = value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _dropdown<int>(
                        label: 'Minute',
                        value: _endMinute,
                        values: const [0, 15, 30, 45],
                        labelFor: (minute) =>
                            ':${minute.toString().padLeft(2, '0')}',
                        onChanged: (value) => _change(() => _endMinute = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton(onPressed: _finish, child: const Text('Done')),
                if (widget.existingEntry != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () async {
                      _saveTimer?.cancel();
                      await _pendingSave;
                      await provider.deleteEntry(widget.existingEntry!.id);
                      if (context.mounted) Navigator.pop(context);
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
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<T> values,
    required String Function(T) labelFor,
    required ValueChanged<T> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: values
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Text(labelFor(item)),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _SuggestionTextField extends StatelessWidget {
  final String initialValue;
  final String label;
  final String hint;
  final List<String> suggestions;
  final ValueChanged<String> onChanged;

  const _SuggestionTextField({
    required this.initialValue,
    required this.label,
    required this.hint,
    required this.suggestions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: initialValue),
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        if (query.isEmpty) return suggestions;
        return suggestions.where(
          (suggestion) => suggestion.toLowerCase().contains(query),
        );
      },
      onSelected: onChanged,
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          onSubmitted: (_) => onSubmitted(),
          decoration: InputDecoration(labelText: label, hintText: hint),
        );
      },
    );
  }
}
