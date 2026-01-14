/// Editor Toolbar Widget
/// 
/// Floating draggable toolbar with formatting options.

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

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

  const EditorToolbar({
    super.key,
    required this.controller,
    required this.onInsertPdf,
  });

  @override
  State<EditorToolbar> createState() => _EditorToolbarState();
}

class _EditorToolbarState extends State<EditorToolbar> {
  Offset _position = const Offset(16, 100); // Bottom left by default
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    // Listen for keyboard shortcuts
    widget.controller.addListener(_handleKeyboardShortcuts);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleKeyboardShortcuts);
    super.dispose();
  }

  void _handleKeyboardShortcuts() {
    // Handle <> shortcut for code blocks
    // This is a simplified version - in production you'd use RawKeyboardListener
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final appBarHeight = AppBar().preferredSize.height + MediaQuery.of(context).padding.top;
    
    // Get toolbar size to calculate proper bounds
    final toolbarWidth = _isExpanded ? 250.0 : 50.0;
    final toolbarHeight = _isExpanded ? 400.0 : 50.0;
    
    // Ensure position is within bounds - allow movement to edges but not through app bar
    final left = _position.dx.clamp(0.0, screenSize.width - toolbarWidth);
    // Bottom constraint: can go all the way to top (0) but toolbar must stay below app bar
    // When at bottom=0, toolbar top edge is at toolbarHeight from bottom
    // We want toolbar top edge to be at appBarHeight from top
    // So: bottom = screenHeight - appBarHeight - toolbarHeight
    // But we also want to allow it to go to 0 (all the way to top of content area)
    final maxBottom = screenSize.height - appBarHeight - toolbarHeight;
    final minBottom = 0.0; // Can go all the way to top
    final bottom = _position.dy.clamp(minBottom, maxBottom);
    
    return Positioned(
      left: left,
      bottom: bottom,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(24),
        color: Colors.transparent,
        child: GestureDetector(
          onPanUpdate: (details) {
            setState(() {
              final currentWidth = _isExpanded ? 250.0 : 50.0;
              final currentHeight = _isExpanded ? 400.0 : 50.0;
              final appBarHeight = AppBar().preferredSize.height + MediaQuery.of(context).padding.top;
              // Allow toolbar to go all the way to top (bottom = 0) but ensure it doesn't overlap app bar
              final maxBottom = screenSize.height - appBarHeight - currentHeight;
              final minBottom = 0.0;
              
              final newDx = (_position.dx + details.delta.dx).clamp(0.0, screenSize.width - currentWidth);
              final newDy = (_position.dy - details.delta.dy).clamp(minBottom, maxBottom);
              _position = Offset(newDx, newDy);
            });
          },
          child: Container(
            constraints: BoxConstraints(
              maxWidth: toolbarWidth,
              minWidth: 50,
              maxHeight: toolbarHeight,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _isExpanded ? _buildExpandedToolbar() : _buildCollapsedToolbar(),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedToolbar() {
    return InkWell(
      onTap: () => setState(() => _isExpanded = true),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Icon(
          Icons.edit,
          size: 20,
          color: Theme.of(context).iconTheme.color,
        ),
      ),
    );
  }

  Widget _buildExpandedToolbar() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 250),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with close button
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Format',
                  style: Theme.of(context).textTheme.labelSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => setState(() => _isExpanded = false),
              ),
            ],
          ),
          const Divider(height: 8),
          // Formatting buttons
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _ToolbarButton(
                icon: Icons.format_bold,
                isActive: _hasFormat(Attribute.bold),
                onTap: () => widget.controller.formatSelection(Attribute.bold),
              ),
              _ToolbarButton(
                icon: Icons.format_italic,
                isActive: _hasFormat(Attribute.italic),
                onTap: () => widget.controller.formatSelection(Attribute.italic),
              ),
              _ToolbarButton(
                icon: Icons.format_underlined,
                isActive: _hasFormat(Attribute.underline),
                onTap: () => widget.controller.formatSelection(Attribute.underline),
              ),
              _ToolbarButton(
                icon: Icons.format_color_text,
                onTap: () => _showColorPicker(),
              ),
              _ToolbarButton(
                icon: Icons.border_color,
                onTap: () => _showMarkerColorPicker(),
              ),
              _ToolbarButton(
                icon: Icons.format_align_left,
                onTap: () => _setAlignment(TextAlign.left),
              ),
              _ToolbarButton(
                icon: Icons.format_align_center,
                onTap: () => _setAlignment(TextAlign.center),
              ),
              _ToolbarButton(
                icon: Icons.format_align_right,
                onTap: () => _setAlignment(TextAlign.right),
              ),
              _ToolbarButton(
                icon: Icons.check_box,
                isActive: _hasFormat(Attribute.checked),
                onTap: () => widget.controller.formatSelection(Attribute.checked),
              ),
              _ToolbarButton(
                icon: Icons.format_list_numbered,
                isActive: _hasFormat(Attribute.ol),
                onTap: () => widget.controller.formatSelection(Attribute.ol),
              ),
              _ToolbarButton(
                icon: Icons.code,
                isActive: _hasFormat(Attribute.codeBlock),
                onTap: () => _toggleCodeBlock(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _hasFormat(Attribute attribute) {
    try {
      final format = widget.controller.getSelectionStyle();
      return format.containsKey(attribute.key);
    } catch (e) {
      return false;
    }
  }

  void _toggleCodeBlock() {
    final selection = widget.controller.selection;
    if (selection.isCollapsed) {
      // Insert code block at cursor position
      widget.controller.document.insert(selection.start, '\n');
      widget.controller.formatSelection(Attribute.codeBlock);
    } else {
      // Wrap selected text in code block
      widget.controller.formatSelection(Attribute.codeBlock);
    }
  }

  void _setAlignment(TextAlign align) {
    // Note: Quill doesn't directly support alignment, this is a placeholder
    // You may need to use custom attributes or blocks
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Alignment: $align')),
    );
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Text Color'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ColorOption(color: Colors.black, onTap: () => _setTextColor('#000000')),
            _ColorOption(color: Colors.red, onTap: () => _setTextColor('#FF0000')),
            _ColorOption(color: Colors.blue, onTap: () => _setTextColor('#0000FF')),
            _ColorOption(color: Colors.green, onTap: () => _setTextColor('#00FF00')),
            _ColorOption(color: Colors.orange, onTap: () => _setTextColor('#FFA500')),
            _ColorOption(color: Colors.purple, onTap: () => _setTextColor('#800080')),
          ],
        ),
      ),
    );
  }

  void _showMarkerColorPicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marker Color'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ColorOption(color: Colors.yellow, onTap: () => _setMarkerColor('#FFFF00')),
            _ColorOption(color: Colors.orange, onTap: () => _setMarkerColor('#FFA500')),
            _ColorOption(color: Colors.pink, onTap: () => _setMarkerColor('#FFC0CB')),
            _ColorOption(color: Colors.cyan, onTap: () => _setMarkerColor('#00FFFF')),
            _ColorOption(color: Colors.lime, onTap: () => _setMarkerColor('#00FF00')),
          ],
        ),
      ),
    );
  }

  void _setTextColor(String color) {
    Navigator.pop(context);
    // Quill color formatting - placeholder for now
    // Color formatting requires custom attribute setup in Quill
    // For now, show a message that this feature needs implementation
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Text color formatting coming soon - requires custom Quill setup'),
      ),
    );
  }

  void _setMarkerColor(String color) {
    Navigator.pop(context);
    // Note: Quill may not have built-in marker support, this is a placeholder
    // You may need to use custom attributes
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Marker color feature coming soon')),
    );
  }
}

/// Individual toolbar button
class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isActive;

  const _ToolbarButton({
    required this.icon,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive
          ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: 20,
            color: isActive
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).iconTheme.color,
          ),
        ),
      ),
    );
  }
}

/// Color option widget
class _ColorOption extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const _ColorOption({
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey, width: 1),
        ),
      ),
    );
  }
}
