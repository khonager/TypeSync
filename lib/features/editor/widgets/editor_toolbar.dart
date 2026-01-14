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
  final GlobalKey _toolbarKey = GlobalKey();
  double? _measuredHeight;

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      _measuredHeight = null; // Reset to remeasure
    });
  }
  
  double _getToolbarHeight() {
    // Use measured height if available, otherwise use conservative estimate
    if (_measuredHeight != null) {
      return _measuredHeight!;
    }
    // Conservative estimates - use small value for expanded to ensure it can reach top
    // Even if actual toolbar is taller, this allows it to go to top (may extend slightly above)
    return _isExpanded ? 100.0 : 50.0;
  }
  
  void _measureToolbar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _toolbarKey.currentContext != null) {
        final renderBox = _toolbarKey.currentContext!.findRenderObject() as RenderBox?;
        if (renderBox != null && renderBox.hasSize) {
          final height = renderBox.size.height;
          if (_measuredHeight != height) {
            setState(() {
              _measuredHeight = height;
            });
          }
        }
      }
    });
  }

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
    final appBarHeight = AppBar().preferredSize.height;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final totalAppBarHeight = appBarHeight + statusBarHeight;
    
    // Get toolbar size to calculate proper bounds
    final toolbarWidth = _isExpanded ? 250.0 : 50.0;
    // Get actual or estimated toolbar height
    final toolbarHeight = _getToolbarHeight();
    
    // The Stack is in the body, which is below the app bar
    // Body height = screenHeight - totalAppBarHeight
    final bodyHeight = screenSize.height - totalAppBarHeight;
    
    // Ensure position is within bounds - allow movement to edges but not through app bar
    final left = _position.dx.clamp(0.0, screenSize.width - toolbarWidth);
    // Bottom constraint: 
    // - maxBottom: when toolbar top edge is at the top of body (right below app bar)
    //   bottom = bodyHeight - toolbarHeight (toolbar top at top of body)
    // - minBottom: 0 (toolbar at bottom of body)
    final maxBottom = bodyHeight - toolbarHeight;
    final minBottom = 0.0;
    // Ensure maxBottom is valid (at least 0)
    final clampedMaxBottom = maxBottom > minBottom ? maxBottom : minBottom;
    final bottom = _position.dy.clamp(minBottom, clampedMaxBottom);
    
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
              final currentHeight = _getToolbarHeight();
              final appBarHeight = AppBar().preferredSize.height;
              final statusBarHeight = MediaQuery.of(context).padding.top;
              final bodyHeight = screenSize.height - appBarHeight - statusBarHeight;
              
              // Allow toolbar to go all the way to top (toolbar top at top of body)
              // maxBottom: when toolbar top edge is at top of body
              // bottom = bodyHeight - currentHeight
              final maxBottom = bodyHeight - currentHeight;
              final minBottom = 0.0; // Can go all the way to bottom
              final clampedMaxBottom = maxBottom > minBottom ? maxBottom : minBottom;
              
              final newDx = (_position.dx + details.delta.dx).clamp(0.0, screenSize.width - currentWidth);
              final newDy = (_position.dy - details.delta.dy).clamp(minBottom, clampedMaxBottom);
              _position = Offset(newDx, newDy);
            });
          },
          child: Container(
            key: _toolbarKey,
            constraints: BoxConstraints(
              maxWidth: toolbarWidth,
              minWidth: 50,
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
            child: Builder(
              builder: (context) {
                // Measure toolbar after build
                _measureToolbar();
                return _isExpanded ? _buildExpandedToolbar() : _buildCollapsedToolbar();
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedToolbar() {
    return InkWell(
      onTap: _toggleExpanded,
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
                onPressed: _toggleExpanded,
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
    // Check current text color
    final currentStyle = widget.controller.getSelectionStyle();
    final currentColor = currentStyle[Attribute.color.key] as String?;

    showDialog(
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
            _ColorOption(color: const Color(0xFFFFFFFF), onTap: () => _setTextColor('#FFFFFF', dialogContext), isSelected: currentColor == '#FFFFFF'), // White
            _ColorOption(color: const Color(0xFF64D2FF), onTap: () => _setTextColor('#64D2FF', dialogContext), isSelected: currentColor == '#64D2FF'), // Teal/cyan
            _ColorOption(color: const Color(0xFF90EE90), onTap: () => _setTextColor('#90EE90', dialogContext), isSelected: currentColor == '#90EE90'), // Light green
            _ColorOption(color: const Color(0xFFFFB6C1), onTap: () => _setTextColor('#FFB6C1', dialogContext), isSelected: currentColor == '#FFB6C1'), // Light pink
            _ColorOption(color: const Color(0xFFFFD700), onTap: () => _setTextColor('#FFD700', dialogContext), isSelected: currentColor == '#FFD700'), // Gold
            _ColorOption(color: const Color(0xFFFFA500), onTap: () => _setTextColor('#FFA500', dialogContext), isSelected: currentColor == '#FFA500'), // Orange
            _ColorOption(color: const Color(0xFF9370DB), onTap: () => _setTextColor('#9370DB', dialogContext), isSelected: currentColor == '#9370DB'), // Medium purple
            _ColorOption(color: const Color(0xFFFF69B4), onTap: () => _setTextColor('#FF69B4', dialogContext), isSelected: currentColor == '#FF69B4'), // Hot pink
            _ColorOption(color: const Color(0xFF87CEEB), onTap: () => _setTextColor('#87CEEB', dialogContext), isSelected: currentColor == '#87CEEB'), // Sky blue
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
    // Check current background color
    final currentStyle = widget.controller.getSelectionStyle();
    final currentBgColor = currentStyle[Attribute.background.key] as String?;

    showDialog(
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
            _ColorOption(color: const Color(0xFFFFFF00), onTap: () => _setMarkerColor('#FFFF00', dialogContext), isSelected: currentBgColor == '#FFFF00'), // Yellow
            _ColorOption(color: const Color(0xFFFFA500), onTap: () => _setMarkerColor('#FFA500', dialogContext), isSelected: currentBgColor == '#FFA500'), // Orange
            _ColorOption(color: const Color(0xFFFFC0CB), onTap: () => _setMarkerColor('#FFC0CB', dialogContext), isSelected: currentBgColor == '#FFC0CB'), // Pink
            _ColorOption(color: const Color(0xFF00FFFF), onTap: () => _setMarkerColor('#00FFFF', dialogContext), isSelected: currentBgColor == '#00FFFF'), // Cyan
            _ColorOption(color: const Color(0xFF90EE90), onTap: () => _setMarkerColor('#90EE90', dialogContext), isSelected: currentBgColor == '#90EE90'), // Light green
            _ColorOption(color: const Color(0xFFFFB6C1), onTap: () => _setMarkerColor('#FFB6C1', dialogContext), isSelected: currentBgColor == '#FFB6C1'), // Light pink
            _ColorOption(color: const Color(0xFFFFD700), onTap: () => _setMarkerColor('#FFD700', dialogContext), isSelected: currentBgColor == '#FFD700'), // Gold
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
      // Remove color attribute by formatting with the attribute without a value
      final selection = widget.controller.selection;
      if (selection.isValid && !selection.isCollapsed) {
        // For selected text, format to remove the attribute
        widget.controller.document.format(
          selection.start,
          selection.end - selection.start,
          Attribute.color,
        );
      } else if (selection.isValid) {
        // For collapsed selection, just format at cursor
        widget.controller.document.format(
          selection.start,
          0,
          Attribute.color,
        );
      }
    } else {
      // ColorAttribute constructor takes a String value (hex color)
      widget.controller.formatSelection(ColorAttribute(colorHex));
    }
  }

  void _setMarkerColor(String? colorHex, BuildContext dialogContext) {
    Navigator.pop(dialogContext);
    if (colorHex == null) {
      // Remove background attribute by formatting with the attribute without a value
      final selection = widget.controller.selection;
      if (selection.isValid && !selection.isCollapsed) {
        // For selected text, format to remove the attribute
        widget.controller.document.format(
          selection.start,
          selection.end - selection.start,
          Attribute.background,
        );
      } else if (selection.isValid) {
        // For collapsed selection, just format at cursor
        widget.controller.document.format(
          selection.start,
          0,
          Attribute.background,
        );
      }
    } else {
      // BackgroundAttribute constructor takes a String value (hex color)
      widget.controller.formatSelection(BackgroundAttribute(colorHex));
    }
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
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected 
                    ? Theme.of(context).colorScheme.primary 
                    : Colors.grey,
                width: isSelected ? 3 : 1,
              ),
            ),
            child: color == Colors.transparent
                ? const Icon(Icons.clear, size: 20)
                : null,
          ),
          if (label != null) ...[
            const SizedBox(height: 4),
            Text(
              label!,
              style: TextStyle(
                fontSize: 10,
                color: isSelected 
                    ? Theme.of(context).colorScheme.primary 
                    : Colors.grey,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
