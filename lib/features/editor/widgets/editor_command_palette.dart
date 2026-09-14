library;

import 'package:flutter/material.dart';

import '../../../core/models/editor_command.dart';
import '../utils/editor_command_expansion.dart';

class EditorCommandPalette extends StatelessWidget {
  final EditorCommandMenuState state;
  final ValueChanged<EditorCommand> onSelected;

  const EditorCommandPalette({
    required this.state,
    required this.onSelected,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final previewCommand = state.exactMatch ?? state.matches.first;

    return Align(
      alignment: Alignment.bottomLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 300),
        child: Card(
          margin: const EdgeInsets.all(8),
          elevation: 8,
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showSeparatePreview = constraints.maxWidth >= 430;
              final commandList = _CommandList(
                state: state,
                previewCommand: previewCommand,
                showInlinePreview: !showSeparatePreview,
                onSelected: onSelected,
              );
              if (!showSeparatePreview) return commandList;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 210, child: commandList),
                  VerticalDivider(
                    width: 1,
                    color: colors.outlineVariant,
                  ),
                  Expanded(
                    child: _TemplatePreview(
                      command: previewCommand,
                      isExact: state.exactMatch != null,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CommandList extends StatelessWidget {
  final EditorCommandMenuState state;
  final EditorCommand previewCommand;
  final bool showInlinePreview;
  final ValueChanged<EditorCommand> onSelected;

  const _CommandList({
    required this.state,
    required this.previewCommand,
    required this.showInlinePreview,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Commands',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Text(
                '${state.matches.length}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: state.matches.length,
            itemBuilder: (context, index) {
              final command = state.matches[index];
              final isPreviewed = command.trigger == previewCommand.trigger;
              return ListTile(
                dense: true,
                selected: isPreviewed,
                title: Text(
                  command.trigger,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: showInlinePreview
                    ? Text(
                        command.template.replaceAll('\n', ' ↵ '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
                trailing: const Icon(Icons.keyboard_return, size: 17),
                onTap: () => onSelected(command),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TemplatePreview extends StatelessWidget {
  final EditorCommand command;
  final bool isExact;

  const _TemplatePreview({required this.command, required this.isExact});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isExact ? 'Press Enter to insert' : 'Template preview',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                command.template,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.45,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
