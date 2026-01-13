/// Editor Toolbar Widget
/// 
/// Bottom toolbar with formatting options matching the design.

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

/// Rich text editing toolbar
/// 
/// Provides quick access to common formatting options:
/// - Navigation (prev/next)
/// - Quotes
/// - Hash/headers
class EditorToolbar extends StatelessWidget {
  final quill.QuillController controller;
  final VoidCallback onInsertPdf;

  const EditorToolbar({
    super.key,
    required this.controller,
    required this.onInsertPdf,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Colors.white.withOpacity(0.1),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Previous (undo)
            _ToolbarButton(
              icon: Icons.chevron_left,
              onTap: () {
                // Navigate to previous position or undo
                if (controller.hasUndo) {
                  controller.undo();
                }
              },
            ),
            
            // Next (redo)
            _ToolbarButton(
              icon: Icons.chevron_right,
              onTap: () {
                if (controller.hasRedo) {
                  controller.redo();
                }
              },
            ),
            
            // Single quote / inline code
            _ToolbarButton(
              icon: Icons.format_quote,
              label: '"',
              onTap: () {
                // Toggle inline code style
                final selection = controller.selection;
                if (selection.isCollapsed) {
                  controller.document.insert(selection.start, '"');
                } else {
                  // Wrap selection in quotes
                  final text = controller.document.getPlainText(
                    selection.start,
                    selection.end - selection.start,
                  );
                  controller.replaceText(
                    selection.start,
                    selection.end - selection.start,
                    '"$text"',
                    null,
                  );
                }
              },
            ),
            
            // Double quote / block quote
            _ToolbarButton(
              icon: Icons.format_quote,
              label: '""',
              onTap: () {
                // Toggle block quote
                controller.formatSelection(quill.Attribute.blockQuote);
              },
            ),
            
            // Hash / Header toggle
            _ToolbarButton(
              icon: Icons.tag,
              label: '#',
              onTap: () {
                _showHeaderOptions(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showHeaderOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Normal text'),
              onTap: () {
                Navigator.pop(context);
                controller.formatSelection(quill.Attribute.header);
              },
            ),
            ListTile(
              title: Text(
                'Heading 1',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              onTap: () {
                Navigator.pop(context);
                controller.formatSelection(quill.Attribute.h1);
              },
            ),
            ListTile(
              title: Text(
                'Heading 2',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              onTap: () {
                Navigator.pop(context);
                controller.formatSelection(quill.Attribute.h2);
              },
            ),
            ListTile(
              title: Text(
                'Heading 3',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              onTap: () {
                Navigator.pop(context);
                controller.formatSelection(quill.Attribute.h3);
              },
            ),
            ListTile(
              leading: const Icon(Icons.format_list_bulleted),
              title: const Text('Bullet list'),
              onTap: () {
                Navigator.pop(context);
                controller.formatSelection(quill.Attribute.ul);
              },
            ),
            ListTile(
              leading: const Icon(Icons.format_list_numbered),
              title: const Text('Numbered list'),
              onTap: () {
                Navigator.pop(context);
                controller.formatSelection(quill.Attribute.ol);
              },
            ),
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('Code block'),
              onTap: () {
                Navigator.pop(context);
                controller.formatSelection(quill.Attribute.codeBlock);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Individual toolbar button
class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;

  const _ToolbarButton({
    required this.icon,
    this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: label != null
            ? Text(
                label!,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              )
            : Icon(icon, size: 24),
      ),
    );
  }
}

