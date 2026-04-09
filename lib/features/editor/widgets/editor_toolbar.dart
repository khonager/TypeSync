/// Editor Toolbar Widget
///
/// Dockable horizontal toolbar with formatting options.
library;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../../core/utils/color_utils.dart';

enum EditorToolbarAnchor { top, bottom }

/// Rich text editing toolbar
///
/// Provides quick access to common formatting options:
/// - Text formatting (bold, italic, underline)
/// - Text color and marker
/// - Alignment
/// - Lists (checklist, numbered with auto-detection)
/// - Code blocks
class EditorToolbar extends StatefulWidget {
  final QuillController controller;
  final VoidCallback onInsertPdf;
  final VoidCallback onInsertTable;
  final VoidCallback onInsertKanban;
  final EditorToolbarAnchor anchor;
  final ValueChanged<EditorToolbarAnchor> onAnchorChanged;

  const EditorToolbar({
    required this.controller,
    required this.onInsertPdf,
    required this.onInsertTable,
    required this.onInsertKanban,
    required this.anchor,
    required this.onAnchorChanged,
    super.key,
  });

  @override
  State<EditorToolbar> createState() => _EditorToolbarState();
}

class _EditorToolbarState extends State<EditorToolbar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant EditorToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleControllerChanged);
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isBottomAnchored = widget.anchor == EditorToolbarAnchor.bottom;
    final keyboardGap =
        isBottomAnchored && MediaQuery.of(context).viewInsets.bottom > 0
            ? 8.0
            : 0.0;

    return SafeArea(
      top: !isBottomAnchored,
      bottom: isBottomAnchored,
      minimum: EdgeInsets.fromLTRB(
        12,
        isBottomAnchored ? 8 : 12,
        12,
        isBottomAnchored ? 12 : 8,
      ),
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: keyboardGap),
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: colors.primary.withValues(alpha: 0.18),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                scrollbars: false,
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    _ToolbarButton(
                      icon: Icons.vertical_align_top,
                      tooltip: 'Anchor to top',
                      isActive: widget.anchor == EditorToolbarAnchor.top,
                      onTap: () =>
                          widget.onAnchorChanged(EditorToolbarAnchor.top),
                    ),
                    _ToolbarButton(
                      icon: Icons.vertical_align_bottom,
                      tooltip: 'Anchor to bottom',
                      isActive: isBottomAnchored,
                      onTap: () =>
                          widget.onAnchorChanged(EditorToolbarAnchor.bottom),
                    ),
                    _ToolbarDivider(color: colors.outlineVariant),
                    _ToolbarButton(
                      icon: Icons.format_bold,
                      tooltip: 'Bold',
                      isActive: _hasFormat(Attribute.bold),
                      onTap: () =>
                          widget.controller.formatSelection(Attribute.bold),
                    ),
                    _ToolbarButton(
                      icon: Icons.format_italic,
                      tooltip: 'Italic',
                      isActive: _hasFormat(Attribute.italic),
                      onTap: () =>
                          widget.controller.formatSelection(Attribute.italic),
                    ),
                    _ToolbarButton(
                      icon: Icons.format_underlined,
                      tooltip: 'Underline',
                      isActive: _hasFormat(Attribute.underline),
                      onTap: () => widget.controller
                          .formatSelection(Attribute.underline),
                    ),
                    _ToolbarButton(
                      icon: Icons.format_color_text,
                      tooltip: 'Text color',
                      onTap: _showColorPicker,
                    ),
                    _ToolbarButton(
                      icon: Icons.border_color,
                      tooltip: 'Highlight',
                      onTap: _showMarkerColorPicker,
                    ),
                    _ToolbarDivider(color: colors.outlineVariant),
                    _ToolbarButton(
                      icon: Icons.picture_as_pdf_outlined,
                      tooltip: 'Insert PDF',
                      onTap: widget.onInsertPdf,
                    ),
                    _ToolbarButton(
                      icon: Icons.table_chart_outlined,
                      tooltip: 'Insert table',
                      onTap: widget.onInsertTable,
                    ),
                    _ToolbarButton(
                      icon: Icons.view_kanban_outlined,
                      tooltip: 'Insert kanban',
                      onTap: widget.onInsertKanban,
                    ),
                    _ToolbarDivider(color: colors.outlineVariant),
                    _ToolbarButton(
                      icon: Icons.format_align_left,
                      tooltip: 'Align left',
                      onTap: () => _setAlignment(TextAlign.left),
                    ),
                    _ToolbarButton(
                      icon: Icons.format_align_center,
                      tooltip: 'Align center',
                      onTap: () => _setAlignment(TextAlign.center),
                    ),
                    _ToolbarButton(
                      icon: Icons.format_align_right,
                      tooltip: 'Align right',
                      onTap: () => _setAlignment(TextAlign.right),
                    ),
                    _ToolbarDivider(color: colors.outlineVariant),
                    _ToolbarButton(
                      icon: Icons.check_box,
                      tooltip: 'Checklist',
                      isActive: _hasFormat(Attribute.checked),
                      onTap: () =>
                          widget.controller.formatSelection(Attribute.checked),
                    ),
                    _ToolbarButton(
                      icon: Icons.format_list_numbered,
                      tooltip: 'Numbered list',
                      isActive: _hasFormat(Attribute.ol),
                      onTap: () =>
                          widget.controller.formatSelection(Attribute.ol),
                    ),
                    _ToolbarButton(
                      icon: Icons.code,
                      tooltip: 'Code block',
                      isActive: _hasFormat(Attribute.codeBlock),
                      onTap: _toggleCodeBlock,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _hasFormat(Attribute<dynamic> attribute) {
    try {
      final format = widget.controller.getSelectionStyle();
      return format.containsKey(attribute.key);
    } catch (_) {
      return false;
    }
  }

  void _toggleCodeBlock() {
    final selection = widget.controller.selection;
    if (selection.isCollapsed) {
      widget.controller.document.insert(selection.start, '\n');
      widget.controller.formatSelection(Attribute.codeBlock);
      return;
    }
    widget.controller.formatSelection(Attribute.codeBlock);
  }

  void _setAlignment(TextAlign align) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Alignment: $align')));
  }

  void _showColorPicker() {
    final currentStyle = widget.controller.getSelectionStyle();
    final colorAttr = currentStyle.attributes[Attribute.color.key];
    final currentColor = colorAttr?.value as String?;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Text Color'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ColorOption(
              color: Colors.white,
              onTap: () => _setTextColor(null, dialogContext),
              isSelected: currentColor == null,
              label: 'Default',
            ),
            ...AppColorPalette.textColors.map(
              (colorOption) => _ColorOption(
                color: colorOption.color,
                onTap: () => _setTextColor(colorOption.hex, dialogContext),
                isSelected: currentColor == colorOption.hex,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showMarkerColorPicker() {
    final currentStyle = widget.controller.getSelectionStyle();
    final bgAttr = currentStyle.attributes[Attribute.background.key];
    final currentBgColor = bgAttr?.value as String?;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Marker Color'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ColorOption(
              color: Colors.transparent,
              onTap: () => _setMarkerColor(null, dialogContext),
              isSelected: currentBgColor == null,
              label: 'None',
            ),
            ...AppColorPalette.markerColors.map(
              (colorOption) => _ColorOption(
                color: colorOption.color,
                onTap: () => _setMarkerColor(colorOption.hex, dialogContext),
                isSelected: currentBgColor == colorOption.hex,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _setTextColor(String? colorHex, BuildContext dialogContext) {
    Navigator.pop(dialogContext);
    if (colorHex == null) {
      final selection = widget.controller.selection;
      if (selection.isValid && !selection.isCollapsed) {
        widget.controller.document.format(
          selection.start,
          selection.end - selection.start,
          Attribute.color,
        );
      } else if (selection.isValid) {
        widget.controller.document.format(selection.start, 0, Attribute.color);
      }
      return;
    }
    widget.controller.formatSelection(ColorAttribute(colorHex));
  }

  void _setMarkerColor(String? colorHex, BuildContext dialogContext) {
    Navigator.pop(dialogContext);
    if (colorHex == null) {
      final selection = widget.controller.selection;
      if (selection.isValid && !selection.isCollapsed) {
        widget.controller.document.format(
          selection.start,
          selection.end - selection.start,
          Attribute.background,
        );
      } else if (selection.isValid) {
        widget.controller.document.format(
          selection.start,
          0,
          Attribute.background,
        );
      }
      return;
    }
    widget.controller.formatSelection(BackgroundAttribute(colorHex));
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isActive;
  final String tooltip;

  const _ToolbarButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: isActive
              ? colors.primary.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                icon,
                size: 20,
                color: isActive
                    ? colors.primary
                    : Theme.of(context).iconTheme.color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  final Color color;

  const _ToolbarDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: color.withValues(alpha: 0.65),
    );
  }
}

/// Color option widget
class _ColorOption extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;
  final bool isSelected;
  final String? label;

  const _ColorOption({
    required this.color,
    required this.onTap,
    this.isSelected = false,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).dividerColor;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
        ),
        alignment: Alignment.center,
        child: label == null
            ? null
            : Text(
                label!,
                style: Theme.of(context).textTheme.labelSmall,
                textAlign: TextAlign.center,
              ),
      ),
    );
  }
}
