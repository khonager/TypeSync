/// Structured table embed used inside rich text notes.
library;

import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart';

class TypeSyncTableData {
  final List<List<String>> rows;
  final List<double> columnWidths;
  final int headerRowCount;

  const TypeSyncTableData({
    required this.rows,
    required this.columnWidths,
    this.headerRowCount = 1,
  });

  factory TypeSyncTableData.empty({
    int rowCount = 2,
    int columnCount = 2,
  }) {
    final rows = List<List<String>>.generate(
      rowCount,
      (rowIndex) => List<String>.generate(
        columnCount,
        (columnIndex) => rowIndex == 0 ? 'Header ${columnIndex + 1}' : '',
      ),
    );
    return TypeSyncTableData(
      rows: rows,
      columnWidths: List<double>.filled(columnCount, 180),
    );
  }

  factory TypeSyncTableData.fromJson(Map<String, dynamic> json) {
    final rows = (json['rows'] as List<dynamic>? ?? const <dynamic>[])
        .map(
          (row) => (row as List<dynamic>).map((cell) => '$cell').toList(),
        )
        .toList();

    final columnCount = rows.isEmpty
        ? 0
        : rows.map((row) => row.length).reduce((a, b) => a > b ? a : b);
    final rawWidths =
        (json['columnWidths'] as List<dynamic>? ?? const <dynamic>[])
            .map((width) => (width as num).toDouble())
            .toList();
    final widths = List<double>.generate(
      columnCount,
      (index) => index < rawWidths.length ? rawWidths[index] : 180,
    );

    return TypeSyncTableData(
      rows: rows.isEmpty
          ? TypeSyncTableData.empty().rows
          : rows.map((row) => _normalizeRow(row, columnCount)).toList(),
      columnWidths:
          widths.isEmpty ? TypeSyncTableData.empty().columnWidths : widths,
      headerRowCount: (json['headerRowCount'] as num?)?.toInt() ?? 1,
    );
  }

  factory TypeSyncTableData.fromEmbedData(String embedData) {
    return TypeSyncTableData.fromJson(
      jsonDecode(embedData) as Map<String, dynamic>,
    );
  }

  factory TypeSyncTableData.fromMarkdownTable(String markdownTable) {
    final lines = markdownTable
        .split('\n')
        .map(_trimTableWhitespace)
        .where((line) => line.isNotEmpty)
        .toList();

    if (lines.length < 2) {
      return TypeSyncTableData.empty();
    }

    final header = _parseMarkdownRow(lines.first);
    final body = lines.skip(2).map(_parseMarkdownRow).toList();
    final columnCount = header.length;
    final rows = <List<String>>[
      _normalizeRow(header, columnCount),
      ...body.map((row) => _normalizeRow(row, columnCount)),
    ];

    return TypeSyncTableData(
      rows: rows,
      columnWidths: List<double>.filled(columnCount, 180),
      headerRowCount: 1,
    );
  }

  int get rowCount => rows.length;
  int get columnCount => columnWidths.length;

  TypeSyncTableData copyWith({
    List<List<String>>? rows,
    List<double>? columnWidths,
    int? headerRowCount,
  }) {
    return TypeSyncTableData(
      rows: rows ?? this.rows,
      columnWidths: columnWidths ?? this.columnWidths,
      headerRowCount: headerRowCount ?? this.headerRowCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rows': rows,
      'columnWidths': columnWidths,
      'headerRowCount': headerRowCount,
    };
  }

  String toEmbedData() => jsonEncode(toJson());

  String toPlainText() {
    return rows.map((row) => row.join('\t')).join('\n');
  }

  static List<String> _parseMarkdownRow(String row) {
    var trimmed = _trimTableWhitespace(row);
    if (trimmed.startsWith('|')) {
      trimmed = trimmed.substring(1);
    }
    if (trimmed.endsWith('|')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed.split('|').map((cell) => cell.trim()).toList();
  }

  static List<String> _normalizeRow(List<String> row, int columnCount) {
    return List<String>.generate(
      columnCount,
      (index) => index < row.length ? row[index] : '',
    );
  }

  static String _trimTableWhitespace(String value) {
    return value.replaceAll(
      RegExp(
        r'^[\s\u2000-\u200A\u202F\u205F\u3000]+|[\s\u2000-\u200A\u202F\u205F\u3000]+$',
      ),
      '',
    );
  }
}

class TypeSyncTableEmbed extends CustomBlockEmbed {
  const TypeSyncTableEmbed(String data) : super(tableType, data);

  static const String tableType = 'typesync_table';

  static TypeSyncTableEmbed fromTable(TypeSyncTableData table) {
    return TypeSyncTableEmbed(table.toEmbedData());
  }

  static TypeSyncTableData parseData(String data) {
    return TypeSyncTableData.fromEmbedData(data);
  }

  static BlockEmbed toBlockEmbed(TypeSyncTableData table) {
    return BlockEmbed.custom(fromTable(table));
  }
}
