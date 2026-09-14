library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/editor_command.dart';

/// Stores and resolves user-defined editor slash commands on this device.
class EditorCommandService extends ChangeNotifier {
  static const String _commandsKey = 'editor_commands_v1';
  static final RegExp _validTrigger = RegExp(r'^/[a-z0-9_-]+$');

  List<EditorCommand> _commands = const [];
  bool _isLoaded = false;

  EditorCommandService() {
    _load();
  }

  List<EditorCommand> get commands => List.unmodifiable(_commands);
  bool get isLoaded => _isLoaded;

  static String normalizeTrigger(String value) {
    final trimmed = value.trim().toLowerCase();
    if (trimmed.isEmpty) return '';
    return trimmed.startsWith('/') ? trimmed : '/$trimmed';
  }

  static String? validateTrigger(String value) {
    final trigger = normalizeTrigger(value);
    if (trigger.isEmpty) return 'Enter a command name.';
    if (!_validTrigger.hasMatch(trigger)) {
      return 'Use letters, numbers, hyphens, or underscores only.';
    }
    return null;
  }

  EditorCommand? commandForTrigger(String value) {
    final trigger = normalizeTrigger(value);
    for (final command in _commands) {
      if (command.trigger == trigger) return command;
    }
    return null;
  }

  Future<String?> saveCommand({
    required String trigger,
    required String template,
    String? previousTrigger,
  }) async {
    final validationError = validateTrigger(trigger);
    if (validationError != null) return validationError;
    if (template.trim().isEmpty) return 'Enter template text.';

    final normalized = normalizeTrigger(trigger);
    final previous =
        previousTrigger == null ? null : normalizeTrigger(previousTrigger);
    final duplicate = _commands.any(
      (command) => command.trigger == normalized && command.trigger != previous,
    );
    if (duplicate) return 'That command already exists.';

    final updated = _commands
        .where((command) => command.trigger != previous)
        .toList(growable: true)
      ..add(EditorCommand(trigger: normalized, template: template));
    updated.sort((a, b) => a.trigger.compareTo(b.trigger));
    _commands = List.unmodifiable(updated);
    notifyListeners();
    await _save();
    return null;
  }

  Future<void> deleteCommand(String trigger) async {
    final normalized = normalizeTrigger(trigger);
    _commands = List.unmodifiable(
      _commands.where((command) => command.trigger != normalized),
    );
    notifyListeners();
    await _save();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = prefs.getString(_commandsKey);
      if (encoded != null && encoded.isNotEmpty) {
        final decoded = jsonDecode(encoded) as List<dynamic>;
        _commands = List.unmodifiable(
          decoded
              .map((entry) => Map<String, dynamic>.from(entry as Map))
              .map(EditorCommand.fromMap)
              .where(
                (command) =>
                    validateTrigger(command.trigger) == null &&
                    command.template.isNotEmpty,
              ),
        );
      }
    } catch (error) {
      debugPrint('Failed to load editor commands: $error');
      _commands = const [];
    }

    _isLoaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _commandsKey,
        jsonEncode(_commands.map((command) => command.toMap()).toList()),
      );
    } catch (error) {
      debugPrint('Failed to save editor commands: $error');
    }
  }
}
