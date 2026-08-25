/// Editor Toolbar Widget
///
/// Floating draggable toolbar with magnetic edge anchoring.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';

import '../../../core/services/editor_color_palette_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/color_utils.dart';

enum EditorToolbarPlacement { floating, top, bottom, left, right }

enum _ToolbarAnchorEdge { floating, top, bottom, left, right }

enum _EditorColorPaletteType { text, marker }

/// Rich text editing toolbar
///
/// Provides quick access to common formatting options:
/// - Text formatting (bold, italic, underline, strikethrough)
/// - Text color and marker
/// - Alignment
/// - Lists (checklist, numbered, and bulleted)
/// - Code blocks
class EditorToolbar extends StatefulWidget {
  final QuillController controller;
  final VoidCallback onInsertPdf;
  final VoidCallback onInsertTable;
  final VoidCallback onInsertKanban;
  final VoidCallback onInsertCode;
  final VoidCallback onToggleChecklist;
  final ValueChanged<Attribute<String?>> onSetAlignment;
  final EditorToolbarPlacement placement;
  final ValueChanged<EditorToolbarPlacement> onPlacementChanged;
  final Offset initialPosition;
  final ValueChanged<Offset> onPositionChanged;
  final Color defaultTextColor;
  final Color previewSurfaceColor;

  const EditorToolbar({
    required this.controller,
    required this.onInsertPdf,
    required this.onInsertTable,
    required this.onInsertKanban,
    required this.onInsertCode,
    required this.onToggleChecklist,
    required this.onSetAlignment,
    required this.placement,
    required this.onPlacementChanged,
    required this.initialPosition,
    required this.onPositionChanged,
    this.defaultTextColor = Colors.white,
    this.previewSurfaceColor = AppTheme.darkTertiary,
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
  static const double _floatingPanelWidth = 320;
  static const double _floatingPanelMaxHeight = 160;

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
                ...scrollItems.skip(1),
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
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _buildFloatingToolbarRows(),
              ),
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
    final activeTextColor = _currentPaletteColor(_EditorColorPaletteType.text);
    final activeMarkerColor =
        _currentPaletteColor(_EditorColorPaletteType.marker);

    return [
      _ToolbarButton(
        icon: Icons.close,
        tooltip: 'Collapse',
        onTap: _toggleExpanded,
      ),
      _ToolbarButton(
        icon: Icons.format_clear,
        tooltip: 'Reset text style',
        onTap: _resetTextStyle,
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
        activeIconColor: activeTextColor,
        onTap: _showColorPicker,
      ),
      _ToolbarButton(
        icon: Icons.border_color,
        tooltip: 'Highlight',
        activeFillColor: activeMarkerColor,
        activeIconColor: activeMarkerColor == null
            ? null
            : AppColorPalette.getContrastingTextColor(activeMarkerColor),
        onTap: _showMarkerColorPicker,
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
        icon: Icons.format_list_bulleted,
        tooltip: 'Bullet list',
        isActive: _hasFormat(Attribute.ul),
        onTap: () => _toggleAttribute(Attribute.ul),
      ),
      divider,
      _ToolbarButton(
        icon: Icons.format_align_left,
        tooltip: 'Align left',
        isActive: _isAlignmentActive(Attribute.leftAlignment),
        onTap: () => _setAlignment(Attribute.leftAlignment),
      ),
      _ToolbarButton(
        icon: Icons.format_align_center,
        tooltip: 'Align center',
        isActive: _isAlignmentActive(Attribute.centerAlignment),
        onTap: () => _setAlignment(Attribute.centerAlignment),
      ),
      _ToolbarButton(
        icon: Icons.format_align_right,
        tooltip: 'Align right',
        isActive: _isAlignmentActive(Attribute.rightAlignment),
        onTap: () => _setAlignment(Attribute.rightAlignment),
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
      _ToolbarButton(
        icon: Icons.code,
        tooltip: 'Insert code block',
        onTap: widget.onInsertCode,
      ),
    ];
  }

  List<Widget> _buildFloatingToolbarRows() {
    final activeTextColor = _currentPaletteColor(_EditorColorPaletteType.text);
    final activeMarkerColor =
        _currentPaletteColor(_EditorColorPaletteType.marker);

    final rows = <List<Widget>>[
      [
        _ToolbarButton(
          icon: Icons.close,
          tooltip: 'Collapse',
          onTap: _toggleExpanded,
        ),
        _ToolbarButton(
          icon: Icons.format_clear,
          tooltip: 'Reset text style',
          onTap: _resetTextStyle,
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
          icon: Icons.code,
          tooltip: 'Insert code block',
          onTap: widget.onInsertCode,
        ),
      ],
      [
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
          icon: Icons.format_list_bulleted,
          tooltip: 'Bullet list',
          isActive: _hasFormat(Attribute.ul),
          onTap: () => _toggleAttribute(Attribute.ul),
        ),
        _ToolbarButton(
          icon: Icons.format_align_left,
          tooltip: 'Align left',
          isActive: _isAlignmentActive(Attribute.leftAlignment),
          onTap: () => _setAlignment(Attribute.leftAlignment),
        ),
        _ToolbarButton(
          icon: Icons.format_align_center,
          tooltip: 'Align center',
          isActive: _isAlignmentActive(Attribute.centerAlignment),
          onTap: () => _setAlignment(Attribute.centerAlignment),
        ),
        _ToolbarButton(
          icon: Icons.format_align_right,
          tooltip: 'Align right',
          isActive: _isAlignmentActive(Attribute.rightAlignment),
          onTap: () => _setAlignment(Attribute.rightAlignment),
        ),
      ],
      [
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
          activeIconColor: activeTextColor,
          onTap: _showColorPicker,
        ),
        _ToolbarButton(
          icon: Icons.border_color,
          tooltip: 'Highlight',
          activeFillColor: activeMarkerColor,
          activeIconColor: activeMarkerColor == null
              ? null
              : AppColorPalette.getContrastingTextColor(activeMarkerColor),
          onTap: _showMarkerColorPicker,
        ),
      ],
    ];

    const dividerAfterByRow = <int?>[2, 3, null];
    return [
      for (var index = 0; index < rows.length; index++)
        _buildFloatingToolbarRow(
          rows[index],
          dividerIndex: index,
          dividerAfter: dividerAfterByRow[index],
        ),
    ];
  }

  Widget _buildFloatingToolbarRow(
    List<Widget> items, {
    required int dividerIndex,
    required int? dividerAfter,
  }) {
    assert(items.length == 6);
    return Row(
      children: [
        for (var itemIndex = 0; itemIndex < items.length; itemIndex++) ...[
          if (itemIndex == dividerAfter)
            _FloatingToolbarDivider(index: dividerIndex),
          Expanded(
            child: Center(child: items[itemIndex]),
          ),
        ],
      ],
    );
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

  bool _isAlignmentActive(Attribute<String?> attribute) {
    try {
      final currentAlignment =
          widget.controller.getSelectionStyle().attributes[Attribute.align.key];
      if (attribute == Attribute.leftAlignment) {
        return currentAlignment == null ||
            currentAlignment.value == Attribute.leftAlignment.value;
      }

      return currentAlignment?.value == attribute.value;
    } catch (_) {
      return attribute == Attribute.leftAlignment;
    }
  }

  void _toggleAttribute(Attribute<dynamic> attribute) {
    widget.controller.skipRequestKeyboard = !attribute.isInline;
    widget.controller.formatSelection(
      _hasFormat(attribute) ? Attribute.clone(attribute, null) : attribute,
    );
  }

  void _resetTextStyle() {
    const textStyleAttributes = <Attribute<dynamic>>[
      Attribute.bold,
      Attribute.italic,
      Attribute.underline,
      Attribute.strikeThrough,
      Attribute.color,
      Attribute.background,
    ];
    for (final attribute in textStyleAttributes) {
      widget.controller.formatSelection(Attribute.clone(attribute, null));
    }
  }

  void _setAlignment(Attribute<String?> alignment) {
    widget.onSetAlignment(alignment);
  }

  void _showColorPicker() {
    _showPalettePicker(_EditorColorPaletteType.text);
  }

  void _showMarkerColorPicker() {
    _showPalettePicker(_EditorColorPaletteType.marker);
  }

  void _showPalettePicker(_EditorColorPaletteType type) {
    final currentColorHex = _currentPaletteHex(type);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => Consumer<EditorColorPaletteService>(
        builder: (context, paletteService, _) {
          final colors = type == _EditorColorPaletteType.text
              ? paletteService.textColors
              : paletteService.markerColors;

          return AlertDialog(
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    type == _EditorColorPaletteType.text
                        ? 'Text Color'
                        : 'Marker Color',
                  ),
                ),
                IconButton(
                  tooltip: 'Edit palette',
                  onPressed: () => _openPaletteEditor(dialogContext, type),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _usageHintForPalette(type),
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _ColorOption(
                          onTap: () => type == _EditorColorPaletteType.text
                              ? _setTextColor(null, dialogContext)
                              : _setMarkerColor(null, dialogContext),
                          isSelected: currentColorHex == null,
                          tooltip: type == _EditorColorPaletteType.text
                              ? 'Default\nNormal text'
                              : 'None\nRemove the highlight',
                          paletteType: type,
                          previewLabel: type == _EditorColorPaletteType.text
                              ? 'Default'
                              : 'None',
                          defaultTextColor: type == _EditorColorPaletteType.text
                              ? widget.defaultTextColor
                              : AppColorPalette.getContrastingTextColor(
                                  widget.previewSurfaceColor,
                                ),
                          previewSurfaceColor: widget.previewSurfaceColor,
                        ),
                        ...colors.map(
                          (colorOption) => _ColorOption(
                            onTap: () => type == _EditorColorPaletteType.text
                                ? _setTextColor(colorOption.hex, dialogContext)
                                : _setMarkerColor(
                                    colorOption.hex,
                                    dialogContext,
                                  ),
                            isSelected: currentColorHex == colorOption.hex,
                            tooltip: _buildColorTooltip(colorOption),
                            paletteType: type,
                            colorOption: colorOption,
                            defaultTextColor: widget.defaultTextColor,
                            previewSurfaceColor: widget.previewSurfaceColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
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

  String? _currentPaletteHex(_EditorColorPaletteType type) {
    final attributes = widget.controller.getSelectionStyle().attributes;
    final color = switch (type) {
      _EditorColorPaletteType.text =>
        attributes[Attribute.color.key]?.value as String?,
      _EditorColorPaletteType.marker =>
        attributes[Attribute.background.key]?.value as String?,
    };
    // Earlier dark-editor documents stored white as their explicit default.
    // On a light note canvas it means the same thing as Default, not a custom
    // text color, so expose it that way in the picker.
    if (type == _EditorColorPaletteType.text && _isLegacyDefaultWhite(color)) {
      return null;
    }
    return color;
  }

  bool _isLegacyDefaultWhite(String? hex) {
    if (hex == null) return false;
    final normalized = hex.replaceAll('#', '').toUpperCase();
    return normalized == 'FFFFFF' || normalized == 'FFFFFFFF';
  }

  Color? _currentPaletteColor(_EditorColorPaletteType type) {
    final hex = _currentPaletteHex(type);
    if (hex == null || hex.isEmpty) {
      return null;
    }

    try {
      final normalized = hex.replaceFirst('#', '');
      if (normalized.length != 6) {
        return null;
      }
      return Color(int.parse('FF$normalized', radix: 16));
    } catch (_) {
      return null;
    }
  }

  String _buildColorTooltip(ColorOption colorOption) {
    if (colorOption.meaning == null || colorOption.meaning!.isEmpty) {
      return colorOption.name;
    }
    return '${colorOption.name}\n${colorOption.meaning!}';
  }

  String _usageHintForPalette(_EditorColorPaletteType type) {
    return type == _EditorColorPaletteType.text
        ? 'Use text color for text you wrote yourself, even if someone else dictated it.'
        : 'Use highlighters for text that was not written by you, like copied text from a book or website.';
  }

  Future<void> _openPaletteEditor(
    BuildContext dialogContext,
    _EditorColorPaletteType type,
  ) async {
    Navigator.pop(dialogContext);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;

    final paletteService = context.read<EditorColorPaletteService>();
    final editedColors = await showDialog<List<ColorOption>>(
      context: context,
      builder: (context) => _PaletteEditorDialog(
        paletteType: type,
        initialColors: type == _EditorColorPaletteType.text
            ? paletteService.textColors
            : paletteService.markerColors,
      ),
    );

    if (editedColors == null) return;

    if (type == _EditorColorPaletteType.text) {
      await paletteService.setTextColors(editedColors);
    } else {
      await paletteService.setMarkerColors(editedColors);
    }
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isActive;
  final String tooltip;
  final Color? activeFillColor;
  final Color? activeIconColor;

  const _ToolbarButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.isActive = false,
    this.activeFillColor,
    this.activeIconColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasColorPreview = activeFillColor != null || activeIconColor != null;
    final buttonColor = activeFillColor ??
        (isActive
            ? colors.primary.withValues(alpha: 0.14)
            : Colors.transparent);
    final iconColor = activeIconColor ??
        (isActive ? colors.primary : Theme.of(context).iconTheme.color);

    return Padding(
      padding: const EdgeInsets.all(2),
      child: _DismissOnExitTooltip(
        message: tooltip,
        child: Material(
          color: buttonColor,
          shape: RoundedRectangleBorder(
            side: hasColorPreview && activeFillColor == null
                ? BorderSide(
                    color: (activeIconColor ?? colors.primary).withValues(
                      alpha: 0.35,
                    ),
                  )
                : BorderSide.none,
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                icon,
                size: 20,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Prevents a toolbar tooltip from staying open when the pointer moves from
/// its button onto the tooltip overlay.
class _DismissOnExitTooltip extends StatefulWidget {
  final String message;
  final Widget child;

  const _DismissOnExitTooltip({
    required this.message,
    required this.child,
  });

  @override
  State<_DismissOnExitTooltip> createState() => _DismissOnExitTooltipState();
}

class _DismissOnExitTooltipState extends State<_DismissOnExitTooltip> {
  bool _temporarilyHidden = false;

  void _handleExit(PointerExitEvent event) {
    setState(() => _temporarilyHidden = true);

    // Re-enable the tooltip after its current overlay has been removed. Since
    // the pointer is no longer over the button, it will remain hidden until
    // the button is hovered again. Re-enabling also preserves touch tooltips.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _temporarilyHidden = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onExit: _handleExit,
      child: TooltipVisibility(
        visible: !_temporarilyHidden,
        child: Tooltip(
          message: widget.message,
          child: widget.child,
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

class _FloatingToolbarDivider extends StatelessWidget {
  final int index;

  const _FloatingToolbarDivider({required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('floating-toolbar-divider-$index'),
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Theme.of(
        context,
      ).colorScheme.outlineVariant.withValues(alpha: 0.65),
    );
  }
}

/// Color option widget
class _ColorOption extends StatelessWidget {
  final VoidCallback onTap;
  final bool isSelected;
  final ColorOption? colorOption;
  final String? previewLabel;
  final String? tooltip;
  final Color? defaultTextColor;
  final Color previewSurfaceColor;
  final _EditorColorPaletteType paletteType;
  final bool enabled;

  const _ColorOption({
    required this.onTap,
    required this.paletteType,
    this.isSelected = false,
    this.colorOption,
    this.previewLabel,
    this.tooltip,
    this.defaultTextColor,
    this.previewSurfaceColor = AppTheme.darkTertiary,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).dividerColor;

    final preview = Container(
      width: 88,
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: previewSurfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
      ),
      child: _ColorPreview(
        paletteType: paletteType,
        colorOption: colorOption,
        fallbackLabel: previewLabel,
        defaultTextColor: defaultTextColor,
      ),
    );

    final option = enabled
        ? InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: preview,
          )
        : preview;

    if (!enabled || tooltip == null || tooltip!.isEmpty) {
      return option;
    }

    return Tooltip(
      message: tooltip!,
      waitDuration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.darkTertiary),
      ),
      textStyle: const TextStyle(
        color: AppTheme.darkTextPrimary,
        fontSize: 14,
        height: 1.35,
      ),
      child: option,
    );
  }
}

class _ColorPreview extends StatelessWidget {
  final _EditorColorPaletteType paletteType;
  final ColorOption? colorOption;
  final String? fallbackLabel;
  final Color? defaultTextColor;

  const _ColorPreview({
    required this.paletteType,
    this.colorOption,
    this.fallbackLabel,
    this.defaultTextColor,
  });

  @override
  Widget build(BuildContext context) {
    final label = fallbackLabel ?? colorOption?.name ?? 'Color';
    if (colorOption == null) {
      return Center(
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: defaultTextColor ?? AppTheme.darkTextPrimary,
                fontWeight: FontWeight.w600,
              ),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (paletteType == _EditorColorPaletteType.marker) {
      final background = colorOption!.color;
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Marked',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: defaultTextColor ??
                      AppColorPalette.getContrastingTextColor(background),
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      );
    }

    return Center(
      child: Text(
        colorOption!.name,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colorOption!.color,
              fontWeight: FontWeight.w700,
            ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _PaletteEditorDialog extends StatefulWidget {
  final _EditorColorPaletteType paletteType;
  final List<ColorOption> initialColors;

  const _PaletteEditorDialog({
    required this.paletteType,
    required this.initialColors,
  });

  @override
  State<_PaletteEditorDialog> createState() => _PaletteEditorDialogState();
}

class _PaletteEditorDialogState extends State<_PaletteEditorDialog> {
  late final List<ColorOption> _colors;

  @override
  void initState() {
    super.initState();
    _colors = widget.initialColors
        .map((color) => color.copyWith())
        .toList(growable: true);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.paletteType == _EditorColorPaletteType.text
        ? 'Edit Text Colors'
        : 'Edit Marker Colors';

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 760,
        height: 640,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: _addColor,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _colors.isEmpty
                    ? Center(
                        child: Text(
                          'No colors yet. Add one to start.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      )
                    : ListView.separated(
                        itemCount: _colors.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final color = _colors[index];
                          return Container(
                            key: ValueKey(color.id),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color:
                                  AppTheme.darkTertiary.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppTheme.darkTertiary,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _ColorOption(
                                  onTap: () {},
                                  paletteType: widget.paletteType,
                                  colorOption: color,
                                  tooltip: null,
                                  enabled: false,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        color.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        color.hex,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: AppTheme.darkTextSecondary,
                                            ),
                                      ),
                                      if ((color.meaning ?? '')
                                          .trim()
                                          .isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          color.meaning!,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      onPressed: index == 0
                                          ? null
                                          : () => _move(index, -1),
                                      icon: const Icon(Icons.keyboard_arrow_up),
                                    ),
                                    IconButton(
                                      onPressed: index == _colors.length - 1
                                          ? null
                                          : () => _move(index, 1),
                                      icon:
                                          const Icon(Icons.keyboard_arrow_down),
                                    ),
                                  ],
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      onPressed: () => _editColor(index),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    IconButton(
                                      onPressed: () => _deleteColor(index),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, _colors),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addColor() async {
    final color = await showDialog<ColorOption>(
      context: context,
      builder: (context) => _PaletteEntryEditorDialog(
        paletteType: widget.paletteType,
      ),
    );
    if (color == null) return;
    setState(() {
      _colors.add(color);
    });
  }

  Future<void> _editColor(int index) async {
    final updated = await showDialog<ColorOption>(
      context: context,
      builder: (context) => _PaletteEntryEditorDialog(
        paletteType: widget.paletteType,
        initialColor: _colors[index],
      ),
    );
    if (updated == null) return;
    setState(() {
      _colors[index] = updated;
    });
  }

  void _deleteColor(int index) {
    setState(() {
      _colors.removeAt(index);
    });
  }

  void _move(int index, int direction) {
    final targetIndex = index + direction;
    if (targetIndex < 0 || targetIndex >= _colors.length) return;
    setState(() {
      final color = _colors.removeAt(index);
      _colors.insert(targetIndex, color);
    });
  }
}

class _PaletteEntryEditorDialog extends StatefulWidget {
  final _EditorColorPaletteType paletteType;
  final ColorOption? initialColor;

  const _PaletteEntryEditorDialog({
    required this.paletteType,
    this.initialColor,
  });

  @override
  State<_PaletteEntryEditorDialog> createState() =>
      _PaletteEntryEditorDialogState();
}

class _PaletteEntryEditorDialogState extends State<_PaletteEntryEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _meaningController;
  late final TextEditingController _hexController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialColor?.name ?? '',
    );
    _meaningController = TextEditingController(
      text: widget.initialColor?.meaning ?? '',
    );
    _hexController = TextEditingController(
      text: widget.initialColor?.hex ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _meaningController.dispose();
    _hexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final previewColor = _tryParsePreviewColor(_hexController.text);
    final previewOption = previewColor == null
        ? null
        : ColorOption(
            id: widget.initialColor?.id ?? 'preview',
            name:
                _nameController.text.isEmpty ? 'Preview' : _nameController.text,
            color: previewColor,
            hex: AppColorPalette.normalizeHex(_hexController.text),
            isLight: AppColorPalette.isLightColorHex(_hexController.text),
            opacity: widget.initialColor?.opacity ??
                (widget.paletteType == _EditorColorPaletteType.marker
                    ? 0.45
                    : null),
            meaning: _meaningController.text,
          );

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 420,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.initialColor == null ? 'Add Color' : 'Edit Color',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                _ColorOption(
                  onTap: () {},
                  paletteType: widget.paletteType,
                  colorOption: previewOption,
                  previewLabel: previewOption == null ? 'Preview' : null,
                  tooltip: null,
                  enabled: false,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _meaningController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Meaning'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _hexController,
                  decoration: const InputDecoration(
                    labelText: 'Hex color',
                    hintText: '#64D2FF',
                  ),
                  onChanged: (_) => setState(() {
                    _error = null;
                  }),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: _save,
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color? _tryParsePreviewColor(String value) {
    try {
      return AppColorPalette.parseHexColor(value);
    } catch (_) {
      return null;
    }
  }

  void _save() {
    final name = _nameController.text.trim();
    final meaning = _meaningController.text.trim();
    final hexInput = _hexController.text.trim();

    if (name.isEmpty) {
      setState(() {
        _error = 'Please enter a name.';
      });
      return;
    }

    String normalizedHex;
    try {
      normalizedHex = AppColorPalette.normalizeHex(hexInput);
    } catch (_) {
      setState(() {
        _error = 'Please enter a valid hex color like #64D2FF.';
      });
      return;
    }

    Navigator.pop(
      context,
      ColorOption(
        id: widget.initialColor?.id ??
            'custom-${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        color: AppColorPalette.parseHexColor(normalizedHex),
        hex: normalizedHex,
        isLight: AppColorPalette.isLightColorHex(normalizedHex),
        opacity: widget.initialColor?.opacity ??
            (widget.paletteType == _EditorColorPaletteType.marker
                ? 0.45
                : null),
        meaning: meaning.isEmpty ? null : meaning,
      ),
    );
  }
}
