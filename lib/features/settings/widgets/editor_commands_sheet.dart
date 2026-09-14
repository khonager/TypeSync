library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/editor_command.dart';
import '../../../core/services/editor_command_service.dart';

class EditorCommandsSheet extends StatelessWidget {
  const EditorCommandsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.86,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Slash Commands',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add command',
                    onPressed: () => _showCommandDialog(context),
                    icon: const Icon(Icons.add),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Consumer<EditorCommandService>(
                builder: (context, service, _) {
                  if (!service.isLoaded) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (service.commands.isEmpty) {
                    return _EmptyCommands(
                      onAdd: () => _showCommandDialog(context),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: service.commands.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final command = service.commands[index];
                      return ListTile(
                        title: Text(command.trigger),
                        subtitle: Text(
                          command.template.replaceAll('\n', ' ↵ '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _showCommandDialog(
                          context,
                          command: command,
                        ),
                        trailing: IconButton(
                          tooltip: 'Delete ${command.trigger}',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteCommand(context, command),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCommandDialog(
    BuildContext context, {
    EditorCommand? command,
  }) async {
    final triggerController = TextEditingController(
      text: command?.trigger ?? '/',
    );
    triggerController.selection = TextSelection.collapsed(
      offset: triggerController.text.length,
    );
    final templateController = TextEditingController(
      text: command?.template ?? '',
    );
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(command == null ? 'New slash command' : 'Edit command'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: triggerController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Command',
                    hintText: '/list',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: templateController,
                  minLines: 4,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: 'Template text',
                    hintText: 'First item\nSecond item',
                    alignLabelWithHint: true,
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final result =
                    await context.read<EditorCommandService>().saveCommand(
                          trigger: triggerController.text,
                          template: templateController.text,
                          previousTrigger: command?.trigger,
                        );
                if (!dialogContext.mounted) return;
                if (result == null) {
                  Navigator.pop(dialogContext);
                } else {
                  setDialogState(() => error = result);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    triggerController.dispose();
    templateController.dispose();
  }

  Future<void> _deleteCommand(
    BuildContext context,
    EditorCommand command,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${command.trigger}?'),
        content: const Text('This removes the command and its template.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<EditorCommandService>().deleteCommand(
            command.trigger,
          );
    }
  }
}

class _EmptyCommands extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyCommands({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.data_object, size: 40),
            const SizedBox(height: 12),
            Text(
              'No slash commands yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Create a command, type it on its own line in a note, and press Enter to insert its template.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Create command'),
            ),
          ],
        ),
      ),
    );
  }
}
