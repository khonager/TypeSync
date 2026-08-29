import 'package:flutter/material.dart';

import '../../../core/utils/note_conflict_diff.dart';

class NoteConflictResolverDialog extends StatefulWidget {
  const NoteConflictResolverDialog({
    required this.diff,
    super.key,
  });

  final NoteConflictDiff diff;

  @override
  State<NoteConflictResolverDialog> createState() =>
      _NoteConflictResolverDialogState();
}

class _NoteConflictResolverDialogState
    extends State<NoteConflictResolverDialog> {
  late final List<NoteConflictChoice?> _choices =
      List<NoteConflictChoice?>.filled(widget.diff.conflictCount, null);
  bool _showUnchanged = false;

  bool get _isComplete => _choices.every((choice) => choice != null);

  void _chooseAll(NoteConflictChoice choice) {
    setState(() {
      for (var index = 0; index < _choices.length; index++) {
        _choices[index] = choice;
      }
    });
  }

  void _applyResolution() {
    if (!_isComplete) return;
    Navigator.of(context).pop(
      widget.diff.resolve(_choices.cast<NoteConflictChoice>()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaSize = MediaQuery.sizeOf(context);
    final dialogWidth = (mediaSize.width - 80).clamp(280.0, 952.0);
    final dialogHeight = (mediaSize.height - 180).clamp(260.0, 620.0);

    return AlertDialog(
      key: const Key('note-conflict-resolver'),
      insetPadding: const EdgeInsets.all(16),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: [
          Icon(
            Icons.merge_type_rounded,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('Resolve note conflict')),
          IconButton(
            tooltip: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Review each changed block. Your current device is Local; the '
              'incoming synced copy is Cloud. Nothing is discarded until you '
              'apply the resolution.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  key: const Key('use-all-local'),
                  onPressed: () => _chooseAll(NoteConflictChoice.local),
                  icon: const Icon(Icons.computer_rounded),
                  label: const Text('Use all local'),
                ),
                OutlinedButton.icon(
                  key: const Key('use-all-cloud'),
                  onPressed: () => _chooseAll(NoteConflictChoice.cloud),
                  icon: const Icon(Icons.cloud_outlined),
                  label: const Text('Use all cloud'),
                ),
                FilterChip(
                  selected: _showUnchanged,
                  onSelected: (value) {
                    setState(() => _showUnchanged = value);
                  },
                  label: const Text('Show unchanged lines'),
                ),
                Text(
                  '${_choices.where((choice) => choice != null).length} of '
                  '${_choices.length} changes decided',
                  key: const Key('conflict-choice-progress'),
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: _buildSections(),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const Key('apply-conflict-resolution'),
          onPressed: _isComplete ? _applyResolution : null,
          icon: const Icon(Icons.check),
          label: const Text('Apply resolution'),
        ),
      ],
    );
  }

  List<Widget> _buildSections() {
    final widgets = <Widget>[];
    var conflictIndex = 0;
    for (final section in widget.diff.sections) {
      if (section.isConflict) {
        final currentConflictIndex = conflictIndex;
        widgets.add(
          _ConflictHunk(
            key: Key('conflict-hunk-$currentConflictIndex'),
            section: section,
            choice: _choices[currentConflictIndex],
            onChoiceChanged: (choice) {
              setState(() => _choices[currentConflictIndex] = choice);
            },
          ),
        );
        conflictIndex++;
      } else {
        widgets.add(
          _UnchangedLines(
            section: section,
            expanded: _showUnchanged,
          ),
        );
      }
      widgets.add(const SizedBox(height: 10));
    }
    return widgets;
  }
}

class _ConflictHunk extends StatelessWidget {
  const _ConflictHunk({
    required this.section,
    required this.choice,
    required this.onChoiceChanged,
    super.key,
  });

  final NoteConflictSection section;
  final NoteConflictChoice? choice;
  final ValueChanged<NoteConflictChoice> onChoiceChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(
          color: choice == null
              ? theme.colorScheme.error.withValues(alpha: 0.55)
              : theme.colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '@@ local line ${section.localStartLine} / '
              'cloud line ${section.cloudStartLine} @@',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final local = _VersionPanel(
                  title: 'LOCAL',
                  prefix: '-',
                  startLine: section.localStartLine,
                  lines: section.localLines,
                  counterpart: section.cloudLines,
                  selected: choice == NoteConflictChoice.local,
                  background: theme.colorScheme.errorContainer,
                  foreground: theme.colorScheme.onErrorContainer,
                  onTap: () => onChoiceChanged(NoteConflictChoice.local),
                );
                final cloud = _VersionPanel(
                  title: 'CLOUD',
                  prefix: '+',
                  startLine: section.cloudStartLine,
                  lines: section.cloudLines,
                  counterpart: section.localLines,
                  selected: choice == NoteConflictChoice.cloud,
                  background: theme.colorScheme.tertiaryContainer,
                  foreground: theme.colorScheme.onTertiaryContainer,
                  onTap: () => onChoiceChanged(NoteConflictChoice.cloud),
                );
                if (constraints.maxWidth >= 640) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: local),
                      const SizedBox(width: 10),
                      Expanded(child: cloud),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    local,
                    const SizedBox(height: 8),
                    cloud,
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _VersionPanel extends StatelessWidget {
  const _VersionPanel({
    required this.title,
    required this.prefix,
    required this.startLine,
    required this.lines,
    required this.counterpart,
    required this.selected,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String title;
  final String prefix;
  final int startLine;
  final List<NoteConflictLine> lines;
  final List<NoteConflictLine> counterpart;
  final bool selected;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: background.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected ? theme.colorScheme.primary : Colors.transparent,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selected
                        ? theme.colorScheme.primary
                        : foreground.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'USE $title',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (lines.isEmpty)
                Text(
                  '$prefix (remove this block)',
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.75),
                    fontFamily: 'monospace',
                    fontStyle: FontStyle.italic,
                  ),
                )
              else
                ...List.generate(lines.length, (index) {
                  return _DiffLine(
                    lineNumber: startLine + index,
                    prefix: prefix,
                    line: lines[index],
                    counterpart:
                        index < counterpart.length ? counterpart[index] : null,
                    foreground: foreground,
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiffLine extends StatelessWidget {
  const _DiffLine({
    required this.lineNumber,
    required this.prefix,
    required this.line,
    required this.counterpart,
    required this.foreground,
  });

  final int lineNumber;
  final String prefix;
  final NoteConflictLine line;
  final NoteConflictLine? counterpart;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final changedRange = _changedRange(line.text, counterpart?.text ?? '');
    final metadataOnlyDifference = counterpart != null &&
        line.text == counterpart!.text &&
        line.signature != counterpart!.signature;
    final baseStyle = TextStyle(
      color: foreground,
      fontFamily: 'monospace',
      height: 1.45,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 42,
          child: Text(
            '$prefix$lineNumber',
            style: baseStyle.copyWith(
              color: foreground.withValues(alpha: 0.65),
            ),
          ),
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: baseStyle,
              children: [
                ..._highlightedSpans(line.text, changedRange, baseStyle),
                if (metadataOnlyDifference)
                  TextSpan(
                    text: '  [${_lineMetadata(line)}]',
                    style: baseStyle.copyWith(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _lineMetadata(NoteConflictLine line) {
  final details = <String>{};
  for (final operation in line.operations) {
    final insert = operation['insert'];
    if (insert is Map<Object?, Object?>) {
      details.add('embed: ${insert.keys.join(', ')}');
    }
    final attributes = operation['attributes'];
    if (attributes is Map<Object?, Object?>) {
      for (final entry in attributes.entries) {
        details.add('${entry.key}: ${entry.value}');
      }
    }
  }
  return details.isEmpty ? 'plain text' : details.join(', ');
}

class _UnchangedLines extends StatelessWidget {
  const _UnchangedLines({required this.section, required this.expanded});

  final NoteConflictSection section;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!expanded) {
      return Center(
        child: Text(
          '⋯ ${section.localLines.length} unchanged '
          '${section.localLines.length == 1 ? 'line' : 'lines'} ⋯',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: List.generate(section.localLines.length, (index) {
            return Text(
              ' ${section.localStartLine + index}  '
              '${section.localLines[index].text}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            );
          }),
        ),
      ),
    );
  }
}

({int start, int end}) _changedRange(String value, String counterpart) {
  var start = 0;
  while (start < value.length &&
      start < counterpart.length &&
      value.codeUnitAt(start) == counterpart.codeUnitAt(start)) {
    start++;
  }

  var valueEnd = value.length;
  var counterpartEnd = counterpart.length;
  while (valueEnd > start &&
      counterpartEnd > start &&
      value.codeUnitAt(valueEnd - 1) ==
          counterpart.codeUnitAt(counterpartEnd - 1)) {
    valueEnd--;
    counterpartEnd--;
  }
  return (start: start, end: valueEnd);
}

List<InlineSpan> _highlightedSpans(
  String value,
  ({int start, int end}) range,
  TextStyle baseStyle,
) {
  if (value.isEmpty) {
    return <InlineSpan>[
      TextSpan(
        text: '(empty line)',
        style: baseStyle.copyWith(fontStyle: FontStyle.italic),
      ),
    ];
  }
  return <InlineSpan>[
    if (range.start > 0) TextSpan(text: value.substring(0, range.start)),
    if (range.end > range.start)
      TextSpan(
        text: value.substring(range.start, range.end),
        style: baseStyle.copyWith(
          fontWeight: FontWeight.w800,
          decoration: TextDecoration.underline,
        ),
      ),
    if (range.end < value.length) TextSpan(text: value.substring(range.end)),
  ];
}
