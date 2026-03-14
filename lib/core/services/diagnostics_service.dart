library;

import 'package:flutter/foundation.dart';

enum DiagnosticLevel {
  info,
  warning,
  error,
}

class DiagnosticEntry {
  final DateTime timestamp;
  final DiagnosticLevel level;
  final String source;
  final String message;

  const DiagnosticEntry({
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
  });

  String toDisplayLine() {
    final levelName = level.name.toUpperCase();
    final time = timestamp.toIso8601String();
    return '[$time] [$levelName] [$source] $message';
  }
}

class DiagnosticsService extends ChangeNotifier {
  DiagnosticsService._();

  static final DiagnosticsService instance = DiagnosticsService._();

  static const int _maxEntries = 300;

  final List<DiagnosticEntry> _entries = [];

  List<DiagnosticEntry> get entries => List.unmodifiable(_entries);

  bool get hasEntries => _entries.isNotEmpty;

  void info(String source, String message) {
    _add(DiagnosticLevel.info, source, message);
  }

  void warning(String source, String message) {
    _add(DiagnosticLevel.warning, source, message);
  }

  void error(String source, String message) {
    _add(DiagnosticLevel.error, source, message);
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  String exportText() {
    return _entries.map((entry) => entry.toDisplayLine()).join('\n');
  }

  void _add(DiagnosticLevel level, String source, String message) {
    _entries.add(
      DiagnosticEntry(
        timestamp: DateTime.now(),
        level: level,
        source: source,
        message: message,
      ),
    );

    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }

    debugPrint('[${level.name.toUpperCase()}][$source] $message');
    notifyListeners();
  }
}
