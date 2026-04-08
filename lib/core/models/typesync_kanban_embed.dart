/// Structured kanban embed used inside rich text notes.
library;

import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart';
import 'package:uuid/uuid.dart';

class TypeSyncKanbanCardData {
  static const Uuid _uuid = Uuid();

  final String id;
  final String title;
  final String description;

  const TypeSyncKanbanCardData({
    required this.id,
    required this.title,
    this.description = '',
  });

  factory TypeSyncKanbanCardData.create({
    String title = 'Untitled card',
    String description = '',
  }) {
    return TypeSyncKanbanCardData(
      id: _uuid.v4(),
      title: title,
      description: description,
    );
  }

  factory TypeSyncKanbanCardData.fromJson(Map<String, dynamic> json) {
    return TypeSyncKanbanCardData(
      id: json['id'] as String? ?? _uuid.v4(),
      title: json['title'] as String? ?? 'Untitled card',
      description: json['description'] as String? ?? '',
    );
  }

  TypeSyncKanbanCardData copyWith({
    String? id,
    String? title,
    String? description,
  }) {
    return TypeSyncKanbanCardData(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
    };
  }

  String toPlainText() {
    final descriptionText = description.trim();
    if (descriptionText.isEmpty) {
      return title;
    }
    return '$title\n$descriptionText';
  }
}

class TypeSyncKanbanColumnData {
  static const Uuid _uuid = Uuid();

  final String id;
  final String title;
  final List<TypeSyncKanbanCardData> cards;

  const TypeSyncKanbanColumnData({
    required this.id,
    required this.title,
    required this.cards,
  });

  factory TypeSyncKanbanColumnData.create({
    String title = 'New column',
    List<TypeSyncKanbanCardData> cards = const <TypeSyncKanbanCardData>[],
  }) {
    return TypeSyncKanbanColumnData(
      id: _uuid.v4(),
      title: title,
      cards: List<TypeSyncKanbanCardData>.from(cards),
    );
  }

  factory TypeSyncKanbanColumnData.fromJson(Map<String, dynamic> json) {
    return TypeSyncKanbanColumnData(
      id: json['id'] as String? ?? _uuid.v4(),
      title: json['title'] as String? ?? 'New column',
      cards: (json['cards'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (card) => TypeSyncKanbanCardData.fromJson(
              Map<String, dynamic>.from(card),
            ),
          )
          .toList(),
    );
  }

  TypeSyncKanbanColumnData copyWith({
    String? id,
    String? title,
    List<TypeSyncKanbanCardData>? cards,
  }) {
    return TypeSyncKanbanColumnData(
      id: id ?? this.id,
      title: title ?? this.title,
      cards: cards ?? this.cards,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'cards': cards.map((card) => card.toJson()).toList(),
    };
  }

  String toPlainText() {
    final buffer = StringBuffer()..writeln(title);
    for (final card in cards) {
      buffer.writeln(card.toPlainText());
    }
    return buffer.toString().trimRight();
  }
}

class TypeSyncKanbanData {
  static const Uuid _uuid = Uuid();

  final String id;
  final String title;
  final List<TypeSyncKanbanColumnData> columns;

  const TypeSyncKanbanData({
    required this.id,
    required this.title,
    required this.columns,
  });

  factory TypeSyncKanbanData.empty({
    String title = 'Kanban board',
    List<String> columnTitles = const ['To Do', 'Doing', 'Done'],
  }) {
    return TypeSyncKanbanData(
      id: _uuid.v4(),
      title: title,
      columns: columnTitles
          .map(
            (columnTitle) => TypeSyncKanbanColumnData.create(
              title: columnTitle,
            ),
          )
          .toList(),
    );
  }

  factory TypeSyncKanbanData.fromJson(Map<String, dynamic> json) {
    final columns = (json['columns'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (column) => TypeSyncKanbanColumnData.fromJson(
            Map<String, dynamic>.from(column),
          ),
        )
        .toList();

    return TypeSyncKanbanData(
      id: json['id'] as String? ?? _uuid.v4(),
      title: json['title'] as String? ?? 'Kanban board',
      columns: columns.isEmpty ? TypeSyncKanbanData.empty().columns : columns,
    );
  }

  factory TypeSyncKanbanData.fromEmbedData(String embedData) {
    return TypeSyncKanbanData.fromJson(
      jsonDecode(embedData) as Map<String, dynamic>,
    );
  }

  int get columnCount => columns.length;

  int get cardCount =>
      columns.fold<int>(0, (sum, column) => sum + column.cards.length);

  TypeSyncKanbanData copyWith({
    String? id,
    String? title,
    List<TypeSyncKanbanColumnData>? columns,
  }) {
    return TypeSyncKanbanData(
      id: id ?? this.id,
      title: title ?? this.title,
      columns: columns ?? this.columns,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'columns': columns.map((column) => column.toJson()).toList(),
    };
  }

  String toEmbedData() => jsonEncode(toJson());

  String toPlainText() {
    final buffer = StringBuffer();
    if (title.trim().isNotEmpty) {
      buffer.writeln(title.trim());
    }
    for (final column in columns) {
      final columnText = column.toPlainText().trim();
      if (columnText.isEmpty) {
        continue;
      }
      if (buffer.isNotEmpty) {
        buffer.writeln();
      }
      buffer.write(columnText);
    }
    return buffer.toString().trimRight();
  }
}

class TypeSyncKanbanEmbed extends CustomBlockEmbed {
  const TypeSyncKanbanEmbed(String data) : super(kanbanType, data);

  static const String kanbanType = 'typesync_kanban';
  static const String minimumSupportedAppVersion = '1.1.0';

  static TypeSyncKanbanEmbed fromBoard(TypeSyncKanbanData board) {
    return TypeSyncKanbanEmbed(board.toEmbedData());
  }

  static TypeSyncKanbanData parseData(String data) {
    return TypeSyncKanbanData.fromEmbedData(data);
  }

  static BlockEmbed toBlockEmbed(TypeSyncKanbanData board) {
    return BlockEmbed.custom(fromBoard(board));
  }
}
