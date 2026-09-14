library;

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
