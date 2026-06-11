/// Editor Toolbar Widget
///
/// Floating draggable toolbar with magnetic edge anchoring.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../../core/utils/color_utils.dart';

enum EditorToolbarPlacement { floating, top, bottom, left, right }

enum _ToolbarAnchorEdge { floating, top, bottom, left, right }

/// Rich text editing toolbar
///
/// Provides quick access to common formatting options:
/// - Text formatting (bold, italic, underline, strikethrough)
/// - Text color and marker
/// - Alignment
/// - Lists (checklist, numbered with auto-detection)
/// - Code blocks
class EditorToolbar extends StatefulWidget {
  final QuillController controller;
  final VoidCallback onInsertPdf;
  final VoidCallback onInsertTable;
  final VoidCallback onInsertKanban;
  final VoidCallback onToggleChecklist;
  final EditorToolbarPlacement placement;
  final ValueChanged<EditorToolbarPlacement> onPlacementChanged;
  final Offset initialPosition;
  final ValueChanged<Offset> onPositionChanged;

  const EditorToolbar({
    required this.controller,
    required this.onInsertPdf,
    required this.onInsertTable,
    required this.onInsertKanban,
    required this.onToggleChecklist,
    required this.placement,
    required this.onPlacementChanged,
    required this.initialPosition,
    required this.onPositionChanged,
    super.key,
  });

  @override
  State<EditorToolbar> createState() => _EditorToolbarState();
}

class _EditorToolbarState extends State<EditorToolbar> {
  static const double _collapsedSize = 50;
  static const double _edgePadding = 8;
  static const double _snapDistance = 42;
  static const double _panelPadding = 8;
  static const double _horizontalPanelHeight = 56;
  static const double _horizontalPanelWidth = 340;
  static const double _verticalPanelWidth = 56;
  static const double _floatingPanelWidth = 260;
  static const double _floatingPanelMaxHeight = 260;

  Offset _position = const Offset(16, 100);
  _ToolbarAnchorEdge _anchor = _ToolbarAnchorEdge.floating;
  bool _isExpanded = false;
  bool _isDragging = false;
  bool _sideSnapToBottom = true;

  bool get _isSideAnchor =>
      _anchor == _ToolbarAnchorEdge.left || _anchor == _ToolbarAnchorEdge.right;

  _ToolbarAnchorEdge _edgeFromPlacement(EditorToolbarPlacement placement) {
    return switch (placement) {
      EditorToolbarPlacement.floating => _ToolbarAnchorEdge.floating,
      EditorToolbarPlacement.top => _ToolbarAnchorEdge.top,
      EditorToolbarPlacement.bottom => _ToolbarAnchorEdge.bottom,
      EditorToolbarPlacement.left => _ToolbarAnchorEdge.left,
      EditorToolbarPlacement.right => _ToolbarAnchorEdge.right,
    };
  }

  EditorToolbarPlacement _placementFromEdge(_ToolbarAnchorEdge edge) {
    return switch (edge) {
      _ToolbarAnchorEdge.floating => EditorToolbarPlacement.floating,
      _ToolbarAnchorEdge.top => EditorToolbarPlacement.top,
      _ToolbarAnchorEdge.bottom => EditorToolbarPlacement.bottom,
      _ToolbarAnchorEdge.left => EditorToolbarPlacement.left,
      _ToolbarAnchorEdge.right => EditorToolbarPlacement.right,
    };
  }

  void _notifyPlacementChanged(_ToolbarAnchorEdge edge) {
    final placement = _placementFromEdge(edge);
    if (widget.placement == placement) return;
    widget.onPlacementChanged(placement);
  }

  void _notifyPositionChanged(Offset position) {
    widget.onPositionChanged(position);
  }

  void _setAnchor(_ToolbarAnchorEdge edge, {bool notify = true}) {
    _anchor = edge;
    if (notify) {
      _notifyPlacementChanged(edge);
    }
  }

  void _setPosition(Offset position, {bool notify = true}) {
    _position = position;
    if (notify) {
      _notifyPositionChanged(position);
    }
  }

  @override
  void initState() {
    super.initState();
    _anchor = _edgeFromPlacement(widget.placement);
    _position = widget.initialPosition;
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant EditorToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
    if (oldWidget.placement != widget.placement) {
      _setAnchor(_edgeFromPlacement(widget.placement), notify: false);
    }
    if (!_isDragging && oldWidget.initialPosition != widget.initialPosition) {
      _setPosition(widget.initialPosition, notify: false);
    }
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
      _setPosition(Offset(nextX.toDouble(), nextY.toDouble()));
    });
  }

  void _onPanEnd(Size areaSize) {
    if (_isExpanded) return;

    setState(() {
      _isDragging = false;
      _snapToNearestEdge(areaSize);
    });
  }

  void _undockFromDock() {
    setState(() {
      _setAnchor(_ToolbarAnchorEdge.floating);
      _isExpanded = false;
      _isDragging = false;
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

    if (minDistance > _snapDistance) {
      _setAnchor(_ToolbarAnchorEdge.floating);
      _setPosition(clamped);
      return;
    }

    if (minDistance == topDistance) {
      _setAnchor(_ToolbarAnchorEdge.top);
      _setPosition(Offset(clamped.dx, _edgePadding));
      return;
    }

    if (minDistance == bottomDistance) {
      _setAnchor(_ToolbarAnchorEdge.bottom);
      _setPosition(Offset(clamped.dx, maxCollapsedY));
      return;
    }

    _sideSnapToBottom =
        clamped.dy + (_collapsedSize / 2) >= areaSize.height / 2;
    final sideY = _sideSnapToBottom ? maxCollapsedY : _edgePadding;

    if (minDistance == leftDistance) {
      _setAnchor(_ToolbarAnchorEdge.left);
      _setPosition(Offset(_edgePadding, sideY));
      return;
    }

    _setAnchor(_ToolbarAnchorEdge.right);
    _setPosition(Offset(maxCollapsedX, sideY));
  }

  @override
  Widget build(BuildContext context) {
    if (_anchor == _ToolbarAnchorEdge.top ||
        _anchor == _ToolbarAnchorEdge.bottom) {
      return _buildDockedHorizontal();
    }

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
              else if (_anchor == _ToolbarAnchorEdge.floating)
                _buildExpandedFloating(areaSize)
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
      _ToolbarAnchorEdge.floating => freeX,
      _ToolbarAnchorEdge.left => _edgePadding,
      _ToolbarAnchorEdge.right => maxCollapsedX,
      _ToolbarAnchorEdge.top || _ToolbarAnchorEdge.bottom => freeX,
    };
    final snappedY = switch (_anchor) {
      _ToolbarAnchorEdge.floating => freeY,
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

  Widget _buildDockedHorizontal() {
    final isBottom = _anchor == _ToolbarAnchorEdge.bottom;
    final scrollItems = _buildToolbarItems(Axis.horizontal);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        isBottom ? 8 : 12,
        12,
        isBottom ? 12 : 8,
      ),
      child: Material(
        color: Colors.transparent,
        child: Container(
          height: _horizontalPanelHeight,
          decoration: _panelDecoration(context),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(_panelPadding),
            child: Row(
              children: [
                _ToolbarButton(
                  icon: Icons.open_with,
                  tooltip: 'Undock',
                  onTap: _undockFromDock,
                ),
                const _ToolbarDivider(axis: Axis.horizontal),
                ...scrollItems.skip(2),
              ],
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

  Widget _buildExpandedFloating(Size areaSize) {
    final maxCollapsedX = _maxCollapsedX(areaSize.width);
    final maxCollapsedY = _maxCollapsedY(areaSize.height);
    final freeX = _position.dx.clamp(_edgePadding, maxCollapsedX).toDouble();
    final freeY = _position.dy.clamp(_edgePadding, maxCollapsedY).toDouble();

    final panelWidth = math
        .min(
          _floatingPanelWidth,
          math.max(180, areaSize.width - (_edgePadding * 2)),
        )
        .toDouble();
    final maxLeft =
        math.max(_edgePadding, areaSize.width - panelWidth - _edgePadding);
    final panelLeft = freeX.clamp(_edgePadding, maxLeft).toDouble();

    final panelMaxHeight = math
        .min(
          _floatingPanelMaxHeight,
          math.max(120.0, areaSize.height - (_edgePadding * 2)),
        )
        .toDouble();
    final maxTop =
        math.max(_edgePadding, areaSize.height - panelMaxHeight - _edgePadding);
    final panelTop = freeY.clamp(_edgePadding, maxTop).toDouble();

    return Positioned(
      left: panelLeft,
      top: panelTop,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: panelWidth,
          constraints: BoxConstraints(maxHeight: panelMaxHeight),
          decoration: _panelDecoration(context),
          child: Padding(
            padding: const EdgeInsets.all(_panelPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Format',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    _ToolbarButton(
                      icon: Icons.close,
                      tooltip: 'Collapse',
                      onTap: _toggleExpanded,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Flexible(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: _buildFloatingToolbarItems(),
                    ),
                  ),
                ),
              ],
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
        onTap: () => _toggleAttribute(Attribute.bold),
      ),
      _ToolbarButton(
        icon: Icons.format_italic,
        tooltip: 'Italic',
        isActive: _hasFormat(Attribute.italic),
        onTap: () => _toggleAttribute(Attribute.italic),
      ),
      _ToolbarButton(
        icon: Icons.format_underlined,
        tooltip: 'Underline',
        isActive: _hasFormat(Attribute.underline),
        onTap: () => _toggleAttribute(Attribute.underline),
      ),
      _ToolbarButton(
        icon: Icons.format_strikethrough,
        tooltip: 'Strikethrough',
        isActive: _hasFormat(Attribute.strikeThrough),
        onTap: () => _toggleAttribute(Attribute.strikeThrough),
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
        onTap: widget.onToggleChecklist,
      ),
      _ToolbarButton(
        icon: Icons.format_list_numbered,
        tooltip: 'Numbered list',
        isActive: _hasFormat(Attribute.ol),
        onTap: () => _toggleAttribute(Attribute.ol),
      ),
      _ToolbarButton(
        icon: Icons.code,
        tooltip: 'Code block',
        isActive: _hasFormat(Attribute.codeBlock),
        onTap: _toggleCodeBlock,
      ),
    ];
  }

  List<Widget> _buildFloatingToolbarItems() {
    return [
      _ToolbarButton(
        icon: Icons.format_bold,
        tooltip: 'Bold',
        isActive: _hasFormat(Attribute.bold),
        onTap: () => _toggleAttribute(Attribute.bold),
      ),
      _ToolbarButton(
        icon: Icons.format_italic,
        tooltip: 'Italic',
        isActive: _hasFormat(Attribute.italic),
        onTap: () => _toggleAttribute(Attribute.italic),
      ),
      _ToolbarButton(
        icon: Icons.format_underlined,
        tooltip: 'Underline',
        isActive: _hasFormat(Attribute.underline),
        onTap: () => _toggleAttribute(Attribute.underline),
      ),
      _ToolbarButton(
        icon: Icons.format_strikethrough,
        tooltip: 'Strikethrough',
        isActive: _hasFormat(Attribute.strikeThrough),
        onTap: () => _toggleAttribute(Attribute.strikeThrough),
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
      _ToolbarButton(
        icon: Icons.check_box,
        tooltip: 'Checklist',
        isActive: _hasFormat(Attribute.checked),
        onTap: widget.onToggleChecklist,
      ),
      _ToolbarButton(
        icon: Icons.format_list_numbered,
        tooltip: 'Numbered list',
        isActive: _hasFormat(Attribute.ol),
        onTap: () => _toggleAttribute(Attribute.ol),
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
      final attributes = widget.controller.getSelectionStyle().attributes;
      final current = attributes[attribute.key];
      if (current == null) return false;

      if (attribute.key == Attribute.list.key ||
          attribute.key == Attribute.header.key ||
          attribute.key == Attribute.script.key ||
          attribute.key == Attribute.align.key) {
        return current.value == attribute.value;
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  void _toggleAttribute(Attribute<dynamic> attribute) {
    widget.controller.skipRequestKeyboard = !attribute.isInline;
    widget.controller.formatSelection(
      _hasFormat(attribute) ? Attribute.clone(attribute, null) : attribute,
    );
  }

  void _toggleCodeBlock() {
    _toggleAttribute(Attribute.codeBlock);
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
