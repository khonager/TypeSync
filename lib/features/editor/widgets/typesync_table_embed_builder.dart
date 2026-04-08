/// Interactive table embed builder for Quill notes.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../../core/models/typesync_table_embed.dart';

class TypeSyncTableEmbedBuilder extends EmbedBuilder {
  const TypeSyncTableEmbedBuilder();

  @override
  String get key => TypeSyncTableEmbed.tableType;

  @override
  String toPlainText(Embed node) {
    final data = node.value.data;
    if (data is! String) {
      return '\n';
    }
    return '${TypeSyncTableEmbed.parseData(data).toPlainText()}\n';
  }

  @override
  Widget build(
    BuildContext context,
    QuillController controller,
    Embed node,
    bool readOnly,
    bool inline,
    TextStyle textStyle,
  ) {
    final data = node.value.data;
    final table = data is String
        ? TypeSyncTableEmbed.parseData(data)
        : TypeSyncTableData.empty();

    return _TypeSyncTableEmbedWidget(
      controller: controller,
      node: node,
      readOnly: readOnly,
      table: table,
    );
  }
}

class _TypeSyncTableEmbedWidget extends StatelessWidget {
  final QuillController controller;
  final Embed node;
  final bool readOnly;
  final TypeSyncTableData table;

  const _TypeSyncTableEmbedWidget({
    required this.controller,
    required this.node,
    required this.readOnly,
    required this.table,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${table.rowCount}x${table.columnCount} table',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const Spacer(),
              if (!readOnly)
                TextButton.icon(
                  onPressed: () => _editTable(context),
                  icon: const Icon(Icons.table_chart_outlined, size: 18),
                  label: const Text('Edit table'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _TablePreview(table: table),
        ],
      ),
    );
  }

  Future<void> _editTable(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _TypeSyncTableEditorDialog(
        initialTable: table,
        onTableChanged: _persistTable,
      ),
    );
  }

  void _persistTable(TypeSyncTableData nextTable) {
    final offset = node.documentOffset;
    controller.replaceText(
      offset,
      1,
      TypeSyncTableEmbed.toBlockEmbed(nextTable),
      TextSelection.collapsed(offset: offset + 1),
    );
  }
}

class _TablePreview extends StatelessWidget {
  final TypeSyncTableData table;

  const _TablePreview({
    required this.table,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: {
          for (int i = 0; i < table.columnCount; i++)
            i: FixedColumnWidth(table.columnWidths[i]),
        },
        border: TableBorder.all(
          color: colorScheme.outline.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8),
        ),
        children: List<TableRow>.generate(
          table.rowCount,
          (rowIndex) => TableRow(
            children: List<Widget>.generate(
              table.columnCount,
              (columnIndex) => _TablePreviewCell(
                text: table.rows[rowIndex][columnIndex],
                isHeader: rowIndex < table.headerRowCount,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TablePreviewCell extends StatelessWidget {
  final String text;
  final bool isHeader;

  const _TablePreviewCell({
    required this.text,
    required this.isHeader,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: isHeader ? colorScheme.surfaceContainerHigh : Colors.transparent,
      child: Text(
        text.isEmpty ? ' ' : text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: isHeader ? FontWeight.w600 : FontWeight.w400,
            ),
      ),
    );
  }
}

class _TypeSyncTableEditorDialog extends StatefulWidget {
  final TypeSyncTableData initialTable;
  final ValueChanged<TypeSyncTableData> onTableChanged;

  const _TypeSyncTableEditorDialog({
    required this.initialTable,
    required this.onTableChanged,
  });

  @override
  State<_TypeSyncTableEditorDialog> createState() =>
      _TypeSyncTableEditorDialogState();
}

class _TypeSyncTableEditorDialogState
    extends State<_TypeSyncTableEditorDialog> {
  late TypeSyncTableData _table;
  late TextEditingController _cellController;
  int _selectedRow = 0;
  int _selectedColumn = 0;
  bool _isSyncingCellText = false;

  @override
  void initState() {
    super.initState();
    _table = widget.initialTable;
    _cellController = TextEditingController(
      text: _table.rows[_selectedRow][_selectedColumn],
    );
  }

  @override
  void dispose() {
    _cellController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final dialogWidth = math.min(mediaQuery.size.width * 0.9, 980.0);
    final dialogHeight = math.min(mediaQuery.size.height * 0.8, 720.0);

    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Edit table')),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildControls(context),
            const SizedBox(height: 12),
            Text(
              'Changes save and sync automatically',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _cellController,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                labelText:
                    'Cell ${_selectedRow + 1}:${_selectedColumn + 1} content',
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                if (_isSyncingCellText) {
                  return;
                }
                _updateSelectedCell(value);
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: 0.25),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Table(
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      columnWidths: {
                        for (int i = 0; i < _table.columnCount; i++)
                          i: FixedColumnWidth(_table.columnWidths[i]),
                      },
                      border: TableBorder.all(
                        color: Theme.of(context)
                            .colorScheme
                            .outline
                            .withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      children: List<TableRow>.generate(
                        _table.rowCount,
                        (rowIndex) => TableRow(
                          children: List<Widget>.generate(
                            _table.columnCount,
                            (columnIndex) => _buildEditableCell(
                              context,
                              rowIndex,
                              columnIndex,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _commitTable(TypeSyncTableData nextTable) {
    setState(() {
      _table = nextTable;
    });
    widget.onTableChanged(nextTable);
  }

  Widget _buildControls(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Selected ${_selectedRow + 1}:${_selectedColumn + 1}',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        _iconButton(
          icon: Icons.playlist_add,
          tooltip: 'Add row',
          onTap: _addRow,
        ),
        _iconButton(
          icon: Icons.add_box_outlined,
          tooltip: 'Add column',
          onTap: _addColumn,
        ),
        _iconButton(
          icon: Icons.delete_outline,
          tooltip: 'Delete row',
          onTap: _table.rowCount > 1 ? _deleteRow : null,
        ),
        _iconButton(
          icon: Icons.view_week_outlined,
          tooltip: 'Delete column',
          onTap: _table.columnCount > 1 ? _deleteColumn : null,
        ),
        _iconButton(
          icon: Icons.arrow_upward,
          tooltip: 'Move row up',
          onTap: _selectedRow > 0 ? () => _moveRow(-1) : null,
        ),
        _iconButton(
          icon: Icons.arrow_downward,
          tooltip: 'Move row down',
          onTap: _selectedRow < _table.rowCount - 1 ? () => _moveRow(1) : null,
        ),
        _iconButton(
          icon: Icons.arrow_back,
          tooltip: 'Move column left',
          onTap: _selectedColumn > 0 ? () => _moveColumn(-1) : null,
        ),
        _iconButton(
          icon: Icons.arrow_forward,
          tooltip: 'Move column right',
          onTap: _selectedColumn < _table.columnCount - 1
              ? () => _moveColumn(1)
              : null,
        ),
        _iconButton(
          icon: Icons.width_normal,
          tooltip: 'Narrower column',
          onTap: () => _resizeColumn(-24),
        ),
        _iconButton(
          icon: Icons.width_full,
          tooltip: 'Wider column',
          onTap: () => _resizeColumn(24),
        ),
      ],
    );
  }

  Widget _iconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon),
    );
  }

  Widget _buildEditableCell(
    BuildContext context,
    int rowIndex,
    int columnIndex,
  ) {
    final isHeader = rowIndex < _table.headerRowCount;
    final isSelected =
        rowIndex == _selectedRow && columnIndex == _selectedColumn;
    final colorScheme = Theme.of(context).colorScheme;
    final cellText = _table.rows[rowIndex][columnIndex];

    return InkWell(
      onTap: () => _selectCell(rowIndex, columnIndex),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: isSelected
            ? colorScheme.primary.withValues(alpha: 0.16)
            : isHeader
                ? colorScheme.surfaceContainerHigh
                : Colors.transparent,
        child: Text(
          cellText.isEmpty ? ' ' : cellText,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: isHeader ? FontWeight.w600 : FontWeight.w400,
              ),
        ),
      ),
    );
  }

  void _selectCell(int rowIndex, int columnIndex) {
    setState(() {
      _selectedRow = rowIndex;
      _selectedColumn = columnIndex;
      _syncSelectedCellText();
    });
  }

  void _updateSelectedCell(String value) {
    if (_table.rows[_selectedRow][_selectedColumn] == value) {
      return;
    }
    final rows = _cloneRows();
    rows[_selectedRow][_selectedColumn] = value;
    _commitTable(_table.copyWith(rows: rows));
  }

  void _addRow() {
    final rows = _cloneRows();
    rows.insert(
      _selectedRow + 1,
      List<String>.filled(_table.columnCount, ''),
    );
    final nextTable = _table.copyWith(rows: rows);
    setState(() {
      _selectedRow += 1;
      _syncCellController('');
    });
    _commitTable(nextTable);
  }

  void _addColumn() {
    final rows = _cloneRows();
    for (final row in rows) {
      row.insert(_selectedColumn + 1, '');
    }
    final widths = List<double>.from(_table.columnWidths)
      ..insert(_selectedColumn + 1, 180);
    final nextTable = _table.copyWith(rows: rows, columnWidths: widths);
    setState(() {
      _selectedColumn += 1;
      _syncCellController('');
    });
    _commitTable(nextTable);
  }

  void _deleteRow() {
    final rows = _cloneRows()..removeAt(_selectedRow);
    final nextRow = _selectedRow.clamp(0, rows.length - 1);
    final nextTable = _table.copyWith(rows: rows);
    setState(() {
      _selectedRow = nextRow;
      _syncCellController(rows[nextRow][_selectedColumn]);
    });
    _commitTable(nextTable);
  }

  void _deleteColumn() {
    final rows = _cloneRows();
    for (final row in rows) {
      row.removeAt(_selectedColumn);
    }
    final widths = List<double>.from(_table.columnWidths)
      ..removeAt(_selectedColumn);
    final nextColumn = _selectedColumn.clamp(0, widths.length - 1);
    final nextTable = _table.copyWith(rows: rows, columnWidths: widths);
    setState(() {
      _selectedColumn = nextColumn;
      _syncCellController(rows[_selectedRow][nextColumn]);
    });
    _commitTable(nextTable);
  }

  void _moveRow(int delta) {
    final target = _selectedRow + delta;
    if (target < 0 || target >= _table.rowCount) {
      return;
    }
    final rows = _cloneRows();
    final row = rows.removeAt(_selectedRow);
    rows.insert(target, row);
    final nextTable = _table.copyWith(rows: rows);
    setState(() {
      _selectedRow = target;
      _syncCellController(rows[target][_selectedColumn]);
    });
    _commitTable(nextTable);
  }

  void _moveColumn(int delta) {
    final target = _selectedColumn + delta;
    if (target < 0 || target >= _table.columnCount) {
      return;
    }
    final rows = _cloneRows();
    for (final row in rows) {
      final cell = row.removeAt(_selectedColumn);
      row.insert(target, cell);
    }
    final widths = List<double>.from(_table.columnWidths);
    final width = widths.removeAt(_selectedColumn);
    widths.insert(target, width);
    final nextTable = _table.copyWith(rows: rows, columnWidths: widths);
    setState(() {
      _selectedColumn = target;
      _syncCellController(rows[_selectedRow][target]);
    });
    _commitTable(nextTable);
  }

  void _resizeColumn(double delta) {
    final widths = List<double>.from(_table.columnWidths);
    widths[_selectedColumn] =
        (widths[_selectedColumn] + delta).clamp(96, 420).toDouble();
    _commitTable(_table.copyWith(columnWidths: widths));
  }

  List<List<String>> _cloneRows() {
    return _table.rows.map((row) => List<String>.from(row)).toList();
  }

  void _syncSelectedCellText() {
    _syncCellController(_table.rows[_selectedRow][_selectedColumn]);
  }

  void _syncCellController(String value) {
    _isSyncingCellText = true;
    _cellController.text = value;
    _cellController.selection = TextSelection.collapsed(
      offset: _cellController.text.length,
    );
    _isSyncingCellText = false;
  }
}
