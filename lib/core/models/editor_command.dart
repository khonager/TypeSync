library;

/// A user-defined slash command that expands to plain text in the editor.
class EditorCommand {
  final String trigger;
  final String template;

  const EditorCommand({
    required this.trigger,
    required this.template,
  });

  Map<String, dynamic> toMap() => {
        'trigger': trigger,
        'template': template,
      };

  factory EditorCommand.fromMap(Map<String, dynamic> map) {
    return EditorCommand(
      trigger: map['trigger'] as String? ?? '',
      template: map['template'] as String? ?? '',
    );
  }
}
