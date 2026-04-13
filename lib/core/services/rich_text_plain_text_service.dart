/// Extracts plain text from TypeSync rich note JSON content.
library;

import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart';

import '../models/typesync_kanban_embed.dart';
import '../models/typesync_table_embed.dart';

class RichTextPlainTextService {
  const RichTextPlainTextService();

  static const RichTextPlainTextService instance = RichTextPlainTextService();

  static String extractPlainText(String content) {
    return instance.fromContent(content);
  }

  static String extractPlainTextFromDelta(List<dynamic> operations) {
    return instance.fromOperations(operations);
  }

  String fromContent(String content) {
    if (content.isEmpty) {
      return '';
    }

    final trimmed = content.trimLeft();
    if (!trimmed.startsWith('[') && !trimmed.startsWith('{')) {
      return content;
    }

    try {
      final decoded = jsonDecode(content);
      if (decoded is List<dynamic>) {
        return fromOperations(decoded);
      }
      if (decoded is Map<String, dynamic> && decoded['ops'] is List<dynamic>) {
        return fromOperations(decoded['ops'] as List<dynamic>);
      }
    } catch (_) {
      return content;
    }

    return content;
  }

  String fromOperations(List<dynamic> operations) {
    final buffer = StringBuffer();

    for (final operation in operations) {
      if (operation is! Map) {
        continue;
      }

      final insertValue = operation['insert'];
      if (insertValue is String) {
        buffer.write(insertValue);
        continue;
      }

      if (insertValue is Map) {
        for (final entry in insertValue.entries) {
          final key = '${entry.key}';
          final value = entry.value;
          if (value is! String) {
            continue;
          }

          final extractedText = _extractEmbedText(key, value);
          if (extractedText.trim().isEmpty) {
            continue;
          }

          if (buffer.isNotEmpty) {
            buffer.write(' ');
          }
          buffer.write(extractedText);
        }
      }
    }

    return buffer.toString();
  }

  String _extractEmbedText(String key, String value) {
    try {
      if (key == BlockEmbed.customType) {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic> && decoded.length == 1) {
          final nestedKey = decoded.keys.first;
          final nestedValue = decoded[nestedKey];
          if (nestedValue is String) {
            return _extractEmbedText(nestedKey, nestedValue);
          }
        }
      }
      if (key == TypeSyncTableEmbed.tableType) {
        return TypeSyncTableEmbed.parseData(value).toPlainText();
      }
      if (key == TypeSyncKanbanEmbed.kanbanType) {
        return TypeSyncKanbanEmbed.parseData(value).toPlainText();
      }
    } catch (_) {
      return value;
    }

    return value;
  }
}
