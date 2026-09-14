library;

import '../../../core/models/editor_command.dart';

class EditorCommandMenuState {
  final int start;
  final int length;
  final String query;
  final List<EditorCommand> matches;

  const EditorCommandMenuState({
    required this.start,
    required this.length,
    required this.query,
    required this.matches,
  });

  EditorCommand? get exactMatch {
    for (final command in matches) {
      if (command.trigger == query.toLowerCase()) return command;
    }
    return null;
  }
}

EditorCommandMenuState? commandMenuStateAt({
  required String documentText,
  required int caretOffset,
  required List<EditorCommand> commands,
}) {
  if (caretOffset < 0 || caretOffset > documentText.length) return null;

  final lineStart = caretOffset == 0
      ? 0
      : documentText.lastIndexOf('\n', caretOffset - 1) + 1;
  final query = documentText.substring(lineStart, caretOffset);
  if (!query.startsWith('/') || query.contains(RegExp(r'\s'))) return null;

  final normalizedQuery = query.toLowerCase();
  final matches = commands
      .where((command) => command.trigger.startsWith(normalizedQuery))
      .toList(growable: false);
  if (matches.isEmpty) return null;

  return EditorCommandMenuState(
    start: lineStart,
    length: caretOffset - lineStart,
    query: query,
    matches: matches,
  );
}

/// The document range and replacement for an exact slash command line.
class EditorCommandExpansion {
  final int start;
  final int length;
  final String replacement;

  const EditorCommandExpansion({
    required this.start,
    required this.length,
    required this.replacement,
  });
}

EditorCommandExpansion? commandExpansionAt({
  required String documentText,
  required int insertionOffset,
  required String? Function(String trigger) resolveTemplate,
}) {
  if (insertionOffset < 0 || insertionOffset > documentText.length) {
    return null;
  }

  final lineStart = insertionOffset == 0
      ? 0
      : documentText.lastIndexOf('\n', insertionOffset - 1) + 1;
  final trigger = documentText.substring(lineStart, insertionOffset);
  if (!trigger.startsWith('/') || trigger.contains(RegExp(r'\s'))) {
    return null;
  }

  final template = resolveTemplate(trigger);
  if (template == null) return null;
  return EditorCommandExpansion(
    start: lineStart,
    length: insertionOffset - lineStart,
    replacement: template,
  );
}
