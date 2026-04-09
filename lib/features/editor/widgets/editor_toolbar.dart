/// Editor Toolbar Widget
///
/// Floating draggable toolbar with magnetic edge anchoring.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../../core/utils/color_utils.dart';

enum _ToolbarAnchorEdge { top, bottom, left, right }

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

  const EditorToolbar({
    required this.controller,
    required this.onInsertPdf,
    required this.onInsertTable,
    required this.onInsertKanban,
    super.key,
  });

  @override
  State<EditorToolbar> createState() => _EditorToolbarState();
}

class _EditorToolbarState extends State<EditorToolbar> {
  static const double _collapsedSize = 50;
  static const double _edgePadding = 8;
  static const double _panelPadding = 8;
  static const double _horizontalPanelHeight = 56;
  static const double _horizontalPanelWidth = 340;
  static const double _verticalPanelWidth = 56;

  Offset _position = const Offset(16, 100);
  _ToolbarAnchorEdge _anchor = _ToolbarAnchorEdge.bottom;
  bool _isExpanded = false;
  bool _isDragging = false;
  bool _sideSnapToBottom = true;

  bool get _isSideAnchor =>
      _anchor == _ToolbarAnchorEdge.left || _anchor == _ToolbarAnchorEdge.right;

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

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  void _onPanStart() {
    if (_isExpanded) return;
    setState(() {
      _isDragging = true;
    });
  }

  void _onPanUpdate(DragUpdateDetails details, Size areaSize) {
    if (_isExpanded) return;

    final maxCollapsedX = _maxCollapsedX(areaSize.width);
    final maxCollapsedY = _maxCollapsedY(areaSize.height);

    final nextX = (_position.dx + details.delta.dx).clamp(
      _edgePadding,
      maxCollapsedX,
    );
    final nextY = (_position.dy + details.delta.dy).clamp(
      _edgePadding,
      maxCollapsedY,
    );

    setState(() {
      _position = Offset(nextX.toDouble(), nextY.toDouble());
    });
  }

  void _onPanEnd(Size areaSize) {
    if (_isExpanded) return;

    setState(() {
      _isDragging = false;
      _snapToNearestEdge(areaSize);
    });
  }

  double _maxCollapsedX(double areaWidth) {
    return math.max(_edgePadding, areaWidth - _collapsedSize - _edgePadding);
  }

  double _maxCollapsedY(double areaHeight) {
    return math.max(_edgePadding, areaHeight - _collapsedSize - _edgePadding);
  }

  void _snapToNearestEdge(Size areaSize) {
    final maxCollapsedX = _maxCollapsedX(areaSize.width);
    final maxCollapsedY = _maxCollapsedY(areaSize.height);

    final clamped = Offset(
      _position.dx.clamp(_edgePadding, maxCollapsedX).toDouble(),
      _position.dy.clamp(_edgePadding, maxCollapsedY).toDouble(),
    );

    final leftDistance = clamped.dx - _edgePadding;
    final rightDistance = maxCollapsedX - clamped.dx;
    final topDistance = clamped.dy - _edgePadding;
    final bottomDistance = maxCollapsedY - clamped.dy;
    final minDistance = math.min(
      math.min(leftDistance, rightDistance),
      math.min(topDistance, bottomDistance),
    );

    if (minDistance == topDistance) {
      _anchor = _ToolbarAnchorEdge.top;
      _position = Offset(clamped.dx, _edgePadding);
      return;
    }

    if (minDistance == bottomDistance) {
      _anchor = _ToolbarAnchorEdge.bottom;
      _position = Offset(clamped.dx, maxCollapsedY);
      return;
    }

    _sideSnapToBottom =
        clamped.dy + (_collapsedSize / 2) >= areaSize.height / 2;
    final sideY = _sideSnapToBottom ? maxCollapsedY : _edgePadding;

    if (minDistance == leftDistance) {
      _anchor = _ToolbarAnchorEdge.left;
      _position = Offset(_edgePadding, sideY);
      return;
    }

    _anchor = _ToolbarAnchorEdge.right;
    _position = Offset(maxCollapsedX, sideY);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final areaSize = constraints.biggest;
        if (!areaSize.isFinite || areaSize.width <= 0 || areaSize.height <= 0) {
          return const SizedBox.shrink();
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (_isExpanded)
              if (_isSideAnchor)
                _buildExpandedVertical(areaSize)
              else
                _buildExpandedHorizontal(areaSize)
            else
              _buildCollapsedPen(areaSize),
          ],
        );
      },
    );
  }

  Widget _buildCollapsedPen(Size areaSize) {
    final maxCollapsedX = _maxCollapsedX(areaSize.width);
    final maxCollapsedY = _maxCollapsedY(areaSize.height);

    final freeX = _position.dx.clamp(_edgePadding, maxCollapsedX).toDouble();
    final freeY = _position.dy.clamp(_edgePadding, maxCollapsedY).toDouble();

    final snappedX = switch (_anchor) {
      _ToolbarAnchorEdge.left => _edgePadding,
      _ToolbarAnchorEdge.right => maxCollapsedX,
      _ToolbarAnchorEdge.top || _ToolbarAnchorEdge.bottom => freeX,
    };
    final snappedY = switch (_anchor) {
      _ToolbarAnchorEdge.top => _edgePadding,
      _ToolbarAnchorEdge.bottom => maxCollapsedY,
      _ToolbarAnchorEdge.left ||
      _ToolbarAnchorEdge.right =>
        _sideSnapToBottom ? maxCollapsedY : _edgePadding,
    };

    final displayX = _isDragging ? freeX : snappedX;
    final displayY = _isDragging ? freeY : snappedY;

    return Positioned(
      left: displayX,
      top: displayY,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => _onPanStart(),
        onPanUpdate: (details) => _onPanUpdate(details, areaSize),
        onPanEnd: (_) => _onPanEnd(areaSize),
        child: Material(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
          elevation: 8,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _toggleExpanded,
            child: const SizedBox(
              width: _collapsedSize,
              height: _collapsedSize,
              child: Icon(Icons.edit, size: 20),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedHorizontal(Size areaSize) {
    final maxCollapsedX = _maxCollapsedX(areaSize.width);
    final panelWidth = math.min(
      _horizontalPanelWidth,
      math.max(_collapsedSize, areaSize.width - (_edgePadding * 2)),
    );
    final maxLeft =
        math.max(_edgePadding, areaSize.width - panelWidth - _edgePadding);

    final freeX = _position.dx.clamp(_edgePadding, maxCollapsedX).toDouble();
    final panelLeft = freeX.clamp(_edgePadding, maxLeft).toDouble();
    final panelTop = _anchor == _ToolbarAnchorEdge.top
        ? _edgePadding
        : math.max(
            _edgePadding,
            areaSize.height - _horizontalPanelHeight - _edgePadding,
          );

    return Positioned(
      left: panelLeft,
      top: panelTop,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: panelWidth,
          height: _horizontalPanelHeight,
          decoration: _panelDecoration(context),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(_panelPadding),
            child: Row(
              children: _buildToolbarItems(Axis.horizontal),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedVertical(Size areaSize) {
    final maxCollapsedX = _maxCollapsedX(areaSize.width);
    final panelLeft =
        _anchor == _ToolbarAnchorEdge.left ? _edgePadding : maxCollapsedX;
    final maxPanelHeight = math.max(
      120.0,
      areaSize.height - (_edgePadding * 2),
    );

    return Positioned(
      left: panelLeft,
      top: _sideSnapToBottom ? null : _edgePadding,
      bottom: _sideSnapToBottom ? _edgePadding : null,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: _verticalPanelWidth,
          constraints: BoxConstraints(maxHeight: maxPanelHeight),
          decoration: _panelDecoration(context),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(_panelPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _buildToolbarItems(Axis.vertical),
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _panelDecoration(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: colors.surface.withValues(alpha: 0.97),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: colors.primary.withValues(alpha: 0.18)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.14),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  List<Widget> _buildToolbarItems(Axis axis) {
    final divider = _ToolbarDivider(axis: axis);

    return [
      _ToolbarButton(
        icon: Icons.close,
        tooltip: 'Collapse',
        onTap: _toggleExpanded,
      ),
      divider,
      _ToolbarButton(
        icon: Icons.format_bold,
        tooltip: 'Bold',
        isActive: _hasFormat(Attribute.bold),
        onTap: () => widget.controller.formatSelection(Attribute.bold),
      ),
      _ToolbarButton(
        icon: Icons.format_italic,
        tooltip: 'Italic',
        isActive: _hasFormat(Attribute.italic),
        onTap: () => widget.controller.formatSelection(Attribute.italic),
      ),
      _ToolbarButton(
        icon: Icons.format_underlined,
        tooltip: 'Underline',
        isActive: _hasFormat(Attribute.underline),
        onTap: () => widget.controller.formatSelection(Attribute.underline),
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
      divider,
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
      divider,
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
      divider,
      _ToolbarButton(
        icon: Icons.check_box,
        tooltip: 'Checklist',
        isActive: _hasFormat(Attribute.checked),
        onTap: () => widget.controller.formatSelection(Attribute.checked),
      ),
      _ToolbarButton(
        icon: Icons.format_list_numbered,
        tooltip: 'Numbered list',
        isActive: _hasFormat(Attribute.ol),
        onTap: () => widget.controller.formatSelection(Attribute.ol),
      ),
      _ToolbarButton(
        icon: Icons.code,
        tooltip: 'Code block',
        isActive: _hasFormat(Attribute.codeBlock),
        onTap: _toggleCodeBlock,
      ),
    ];
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
      padding: const EdgeInsets.all(2),
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
  final Axis axis;

  const _ToolbarDivider({required this.axis});

  @override
  Widget build(BuildContext context) {
    final color =
        Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.65);
    if (axis == Axis.vertical) {
      return Container(
        width: 28,
        height: 1,
        margin: const EdgeInsets.symmetric(vertical: 6),
        color: color,
      );
    }

    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: color,
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
