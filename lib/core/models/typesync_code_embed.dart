/// Structured, language-aware code block used inside rich text notes.
library;

import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart';
import 'package:uuid/uuid.dart';

class TypeSyncCodeData {
  static const String codeType = TypeSyncCodeEmbed.codeType;
  static const Uuid _uuid = Uuid();

  final String id;
  final String language;
  final String code;

  const TypeSyncCodeData({
    required this.id,
    required this.language,
    required this.code,
  });

  factory TypeSyncCodeData.empty() => TypeSyncCodeData(
        id: _uuid.v4(),
        language: 'plaintext',
        code: '',
      );

  factory TypeSyncCodeData.fromJson(Map<String, dynamic> json) =>
      TypeSyncCodeData(
        id: json['id'] as String? ?? _uuid.v4(),
        language: json['language'] as String? ?? 'plaintext',
        code: json['code'] as String? ?? '',
      );

  factory TypeSyncCodeData.fromEmbedData(String data) =>
      TypeSyncCodeData.fromJson(jsonDecode(data) as Map<String, dynamic>);

  TypeSyncCodeData copyWith({String? language, String? code}) =>
      TypeSyncCodeData(
        id: id,
        language: language ?? this.language,
        code: code ?? this.code,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'language': language,
        'code': code,
      };

  String toEmbedData() => jsonEncode(toJson());

  static BlockEmbed toBlockEmbed(TypeSyncCodeData code) =>
      BlockEmbed.custom(TypeSyncCodeEmbed(code.toEmbedData()));

  /// Resolves a code block by ID because Flutter Quill passes detached embed
  /// clones to builders, whose document offsets are not reliable.
  static int? findCodeOffset(
    Iterable<Map<String, dynamic>> operations, {
    required String codeId,
  }) {
    var offset = 0;
    for (final operation in operations) {
      final insert = operation['insert'];
      if (insert is String) {
        offset += insert.length;
        continue;
      }
      if (insert is Map) {
        final code = _codeFromInsert(insert);
        if (code?.id == codeId) return offset;
        offset += 1;
      }
    }
    return null;
  }

  static TypeSyncCodeData? _codeFromInsert(Map<dynamic, dynamic> insert) {
    Object? data = insert[codeType];
    if (data == null) {
      final customData = insert[BlockEmbed.customType];
      if (customData is String) {
        try {
          final custom = jsonDecode(customData);
          if (custom is Map) data = custom[codeType];
        } catch (_) {
          return null;
        }
      }
    }
    if (data is! String) return null;
    try {
      return TypeSyncCodeData.fromEmbedData(data);
    } catch (_) {
      return null;
    }
  }
}

class TypeSyncCodeEmbed extends CustomBlockEmbed {
  const TypeSyncCodeEmbed(String data) : super(codeType, data);

  static const String codeType = 'typesync-code';
}
