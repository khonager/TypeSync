/// Markdown to rich text conversion helpers for imports.
// ignore_for_file: deprecated_member_use
library;

import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as path;

import '../models/typesync_kanban_embed.dart';
import '../models/typesync_table_embed.dart';

class ConvertedMarkdownNote {
  final String title;
  final String quillContentJson;

  const ConvertedMarkdownNote({
    required this.title,
    required this.quillContentJson,
  });
}

class MarkdownRichTextService {
  const MarkdownRichTextService();

  static const MarkdownRichTextService instance = MarkdownRichTextService();

  ConvertedMarkdownNote convertAnytypeMarkdown({
    required String rawMarkdown,
    required String fallbackTitle,
    Map<String, String> pathReplacements = const {},
  }) {
    final extracted = extractAnytypeBodyAndTitle(
      rawMarkdown: rawMarkdown,
      fallbackTitle: fallbackTitle,
    );
    final rewrittenMarkdown = _rewriteMarkdownTargets(
      extracted.body,
      pathReplacements,
    );
    final inferredMarkdown = _inferUnderlinedLabels(rewrittenMarkdown);
    final delta = _convertMarkdownDocument(inferredMarkdown);

    return ConvertedMarkdownNote(
      title: extracted.title,
      quillContentJson: jsonEncode(delta.toJson()),
    );
  }

  static ({String title, String body}) extractAnytypeBodyAndTitle({
    required String rawMarkdown,
    required String fallbackTitle,
  }) {
    final normalized = rawMarkdown.replaceAll('\r\n', '\n');
    var body = normalized.trimLeft();

    final frontMatter = RegExp(r'^\ufeff?---\s*\n[\s\S]*?\n---\s*(?:\n|$)');
    body = body.replaceFirst(frontMatter, '');
    body = body.trimLeft();

    var title = fallbackTitle;
    final lines = body.split('\n');
    if (lines.isNotEmpty) {
      final headingMatch = RegExp(r'^#\s+(.+?)\s*$').firstMatch(lines.first);
      if (headingMatch != null) {
        final headingTitle = _stripInlineMarkdown(headingMatch.group(1)!);
        if (headingTitle.isNotEmpty) {
          title = headingTitle;
        }
        lines.removeAt(0);
        while (lines.isNotEmpty && lines.first.trim().isEmpty) {
          lines.removeAt(0);
        }
        body = lines.join('\n');
      }
    }

    return (
      title: title.trim().isEmpty ? fallbackTitle : title.trim(),
      body: body.trimRight(),
    );
  }

  static String? extractAnytypeFrontMatterValue({
    required String rawMarkdown,
    required String key,
  }) {
    final values = extractAnytypeFrontMatterValues(rawMarkdown: rawMarkdown);
    for (final entry in values.entries) {
      if (entry.key.toLowerCase() != key.toLowerCase()) {
        continue;
      }
      for (final value in entry.value) {
        if (value.trim().isNotEmpty) {
          return value.trim();
        }
      }
      return null;
    }
    return null;
  }

  static Map<String, List<String>> extractAnytypeFrontMatterValues({
    required String rawMarkdown,
  }) {
    final frontMatter = _extractAnytypeFrontMatter(rawMarkdown);
    if (frontMatter == null) {
      return <String, List<String>>{};
    }

    final values = <String, List<String>>{};
    String? currentKey;

    for (final rawLine in frontMatter.split('\n')) {
      final line = rawLine.trimRight();
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }

      final keyMatch =
          RegExp(r'^([^:\n][^:\n]*?):(?:\s*(.*))?$').firstMatch(trimmed);
      if (keyMatch != null && !trimmed.startsWith('- ')) {
        currentKey = keyMatch.group(1)!.trim();
        final inlineValue = keyMatch.group(2)?.trim() ?? '';
        if (currentKey.isEmpty) {
          currentKey = null;
          continue;
        }

        values.putIfAbsent(currentKey, () => <String>[]);
        if (inlineValue.isNotEmpty) {
          values[currentKey]!.add(_unquoteYamlScalar(inlineValue));
          currentKey = null;
        }
        continue;
      }

      if (currentKey == null) {
        continue;
      }

      final listMatch = RegExp(r'^-\s+(.+?)\s*$').firstMatch(trimmed);
      if (listMatch != null) {
        values[currentKey]!.add(_unquoteYamlScalar(listMatch.group(1)!));
        continue;
      }

      if (!RegExp(r'^\S.*:\s*').hasMatch(line)) {
        values[currentKey]!.add(_unquoteYamlScalar(trimmed));
        currentKey = null;
      }
    }

    values.removeWhere((_, entries) {
      entries.removeWhere((entry) => entry.trim().isEmpty);
      return entries.isEmpty;
    });
    return values;
  }

  Delta _convertMarkdownDocument(String markdown) {
    final blocks = _splitIntoBlocks(markdown);
    var delta = Delta();

    for (final block in blocks) {
      switch (block) {
        case _MarkdownTextBlock():
          if (block.markdown.trim().isEmpty) {
            continue;
          }
          delta = delta.concat(_markdownToDelta(block.markdown));
        case _MarkdownTableBlock():
          final table = TypeSyncTableData.fromMarkdownTable(block.markdown);
          delta.insert(TypeSyncTableEmbed.toBlockEmbed(table).toJson());
          delta.insert('\n');
      }
    }

    if (delta.isEmpty) {
      delta.insert('\n');
    } else {
      final last = delta.last.value;
      if (last is! String || !last.endsWith('\n')) {
        delta.insert('\n');
      }
    }

    return delta;
  }

  Delta _markdownToDelta(String markdown) {
    final html = md.markdownToHtml(
      markdown,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    );
    final delta = HtmlToDelta().convert(
      html,
      transformTableAsEmbed: false,
    );
    return _flattenUnsupportedEmbeds(_normalizeColorAttributes(delta));
  }

  static String _stripInlineMarkdown(String input) {
    return input
        .replaceAll(RegExp(r'[*_`~]'), '')
        .replaceAll(RegExp(r'\[(.*?)\]\((.*?)\)'), r'$1')
        .trim();
  }

  static Delta _normalizeColorAttributes(Delta delta) {
    final normalized = Delta();

    for (final operation in delta.toList()) {
      final rawAttributes = operation.attributes;
      if (rawAttributes == null || rawAttributes.isEmpty) {
        normalized.push(operation);
        continue;
      }

      final attributes = Map<String, dynamic>.from(rawAttributes);
      final color = _quillColorFromCss(attributes['color'] as String?);
      if (color != null) {
        attributes['color'] = color;
      }

      final background =
          _quillColorFromCss(attributes['background'] as String?);
      if (background != null) {
        attributes['background'] = background;
      }

      normalized.insert(operation.data, attributes.isEmpty ? null : attributes);
    }

    return normalized;
  }

  static Delta _flattenUnsupportedEmbeds(Delta delta) {
    final normalized = Delta();

    for (final operation in delta.toList()) {
      final data = operation.data;
      if (data is! Map) {
        normalized.push(operation);
        continue;
      }

      final resolved = _resolveEmbed(data);
      if (resolved == null) {
        normalized.insert('[Unsupported content]\n');
        continue;
      }
      if (_isSupportedEmbedType(resolved.type)) {
        normalized.push(operation);
        continue;
      }

      normalized.insert(_unsupportedEmbedText(resolved.type, resolved.value));
    }

    return normalized;
  }

  static ({String type, Object? value})? _resolveEmbed(
    Map<dynamic, dynamic> data,
  ) {
    final embedKeys = data.keys.toList(growable: false);
    if (embedKeys.isEmpty) {
      return null;
    }

    final embedType = '${embedKeys.first}';
    final embedValue = data[embedKeys.first];
    if (embedType != BlockEmbed.customType || embedValue is! String) {
      return (type: embedType, value: embedValue);
    }

    try {
      final decoded = jsonDecode(embedValue);
      if (decoded is! Map) {
        return (type: embedType, value: embedValue);
      }
      final customKeys = decoded.keys.toList(growable: false);
      if (customKeys.isEmpty) {
        return (type: embedType, value: embedValue);
      }
      final customType = '${customKeys.first}';
      return (type: customType, value: decoded[customKeys.first]);
    } catch (_) {
      return (type: embedType, value: embedValue);
    }
  }

  static bool _isSupportedEmbedType(String embedType) {
    return embedType == TypeSyncKanbanEmbed.kanbanType ||
        embedType == TypeSyncTableEmbed.tableType ||
        embedType == 'x-embed-table';
  }

  static String _unsupportedEmbedText(String embedType, Object? embedValue) {
    final rawValue = embedValue?.toString().trim() ?? '';
    final label = rawValue.isEmpty
        ? ''
        : path.basename(Uri.tryParse(rawValue)?.path ?? rawValue).trim();

    return switch (embedType) {
      BlockEmbed.imageType =>
        label.isEmpty ? '[Image attachment]\n' : '[Image attachment: $label]\n',
      BlockEmbed.videoType =>
        label.isEmpty ? '[Video attachment]\n' : '[Video attachment: $label]\n',
      BlockEmbed.formulaType =>
        rawValue.isEmpty ? '[Formula]\n' : '$rawValue\n',
      _ => '[Unsupported content]\n',
    };
  }

  static String? _extractAnytypeFrontMatter(String rawMarkdown) {
    final normalized = rawMarkdown.replaceAll('\r\n', '\n');
    final match = RegExp(r'^\ufeff?---\s*\n([\s\S]*?)\n---\s*(?:\n|$)')
        .firstMatch(normalized);
    return match?.group(1);
  }

  static String _unquoteYamlScalar(String value) {
    final trimmed = value.trim();
    if (trimmed.length >= 2) {
      final first = trimmed[0];
      final last = trimmed[trimmed.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        return trimmed.substring(1, trimmed.length - 1);
      }
    }
    return trimmed;
  }

  static String? _quillColorFromCss(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final normalized = value.trim().toLowerCase();
    const named = <String, String>{
      'black': '#000000',
      'white': '#FFFFFF',
      'red': '#FF0000',
      'green': '#008000',
      'blue': '#0000FF',
      'yellow': '#FFFF00',
      'lime': '#CDFFCC',
      'orange': '#FFA500',
      'amber': '#FFC107',
      'pink': '#FFC0CB',
      'purple': '#800080',
      'teal': '#008080',
      'cyan': '#00BCD4',
      'sky': '#87CEEB',
      'ice': '#D8F6FF',
      'grey': '#9E9E9E',
      'gray': '#9E9E9E',
    };

    if (named.containsKey(normalized)) {
      return named[normalized];
    }

    if (normalized.startsWith('#')) {
      final hex = normalized.substring(1);
      if (hex.length == 3) {
        final expanded = hex.split('').map((char) => '$char$char').join();
        return '#${expanded.toUpperCase()}';
      }
      if (hex.length == 6) {
        return '#${hex.toUpperCase()}';
      }
      if (hex.length == 8) {
        return '#${hex.toUpperCase()}';
      }
    }

    final rgbMatch = RegExp(
      r'rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})(?:\s*,\s*([0-9.]+))?\s*\)',
    ).firstMatch(normalized);
    if (rgbMatch != null) {
      final red = int.parse(rgbMatch.group(1)!);
      final green = int.parse(rgbMatch.group(2)!);
      final blue = int.parse(rgbMatch.group(3)!);
      final alphaGroup = rgbMatch.group(4);
      final alpha = alphaGroup == null
          ? 255
          : (double.parse(alphaGroup).clamp(0, 1) * 255).round();
      return _hexColor(alpha, red, green, blue);
    }

    return null;
  }

  static String _hexColor(int alpha, int red, int green, int blue) {
    String hex(int value) =>
        value.clamp(0, 255).toRadixString(16).padLeft(2, '0').toUpperCase();
    if (alpha >= 255) {
      return '#${hex(red)}${hex(green)}${hex(blue)}';
    }
    return '#${hex(alpha)}${hex(red)}${hex(green)}${hex(blue)}';
  }

  static String _rewriteMarkdownTargets(
    String markdown,
    Map<String, String> replacements,
  ) {
    if (replacements.isEmpty) {
      return markdown;
    }

    return markdown.replaceAllMapped(
      RegExp(r'(!?\[[^\]]*\]\()([^)]+)(\))'),
      (match) {
        final prefix = match.group(1)!;
        final originalTarget = match.group(2)!;
        final suffix = match.group(3)!;
        final normalizedTarget =
            _normalizeMarkdownTarget(originalTarget) ?? originalTarget;
        final replacement = replacements[normalizedTarget];
        if (replacement == null) {
          return match.group(0)!;
        }
        return '$prefix$replacement$suffix';
      },
    );
  }

  static String? normalizeMarkdownTargetForReplacement(String rawTarget) {
    return _normalizeMarkdownTarget(rawTarget);
  }

  static String? quillColorFromCss(String? value) {
    return _quillColorFromCss(value);
  }

  static String _inferUnderlinedLabels(String markdown) {
    final lines = markdown.split('\n');
    final output = <String>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = _trimLooseIndent(line);
      if (_shouldUnderlineLabel(lines, i, trimmed)) {
        final leading = line.substring(0, line.length - line.trimLeft().length);
        output.add('$leading<u>$trimmed</u>');
      } else {
        output.add(line);
      }
    }

    return output.join('\n');
  }

  static bool _shouldUnderlineLabel(
    List<String> lines,
    int index,
    String trimmed,
  ) {
    if (trimmed.isEmpty ||
        !trimmed.endsWith(':') ||
        trimmed.startsWith('#') ||
        trimmed.startsWith('- ') ||
        trimmed.startsWith('* ') ||
        trimmed.startsWith('|') ||
        trimmed.startsWith('<u>')) {
      return false;
    }

    for (int i = index + 1; i < lines.length; i++) {
      final next = lines[i];
      final nextTrimmed = _trimLooseIndent(next);
      if (nextTrimmed.isEmpty) {
        continue;
      }
      return next != nextTrimmed ||
          nextTrimmed.startsWith('|') ||
          nextTrimmed.startsWith('- ') ||
          RegExp(r'^\d+\.\s').hasMatch(nextTrimmed);
    }

    return false;
  }

  static List<_MarkdownBlock> _splitIntoBlocks(String markdown) {
    final lines = markdown.split('\n');
    final blocks = <_MarkdownBlock>[];
    final buffer = <String>[];

    int index = 0;
    while (index < lines.length) {
      if (_isMarkdownTableStart(lines, index)) {
        if (buffer.isNotEmpty) {
          blocks.add(_MarkdownTextBlock(buffer.join('\n')));
          buffer.clear();
        }

        final tableLines = <String>[];
        tableLines.add(_trimLooseIndent(lines[index]));
        tableLines.add(_trimLooseIndent(lines[index + 1]));
        index += 2;

        while (index < lines.length) {
          final trimmed = _trimLooseIndent(lines[index]);
          if (trimmed.isEmpty || !_looksLikeMarkdownTableBodyRow(trimmed)) {
            break;
          }
          tableLines.add(trimmed);
          index++;
        }

        blocks.add(_MarkdownTableBlock(tableLines.join('\n')));
        continue;
      }

      buffer.add(lines[index]);
      index++;
    }

    if (buffer.isNotEmpty) {
      blocks.add(_MarkdownTextBlock(buffer.join('\n')));
    }

    return blocks;
  }

  static bool _isMarkdownTableStart(List<String> lines, int index) {
    if (index + 1 >= lines.length) {
      return false;
    }
    final header = _trimLooseIndent(lines[index]);
    final divider = _trimLooseIndent(lines[index + 1]);
    return _looksLikeTableRow(header) && _looksLikeTableDivider(divider);
  }

  static bool _looksLikeTableRow(String line) {
    return line.contains('|') && line.replaceAll('|', '').trim().isNotEmpty;
  }

  static bool _looksLikeMarkdownTableBodyRow(String line) {
    if (!line.contains('|')) {
      return false;
    }
    final trimmed = line.trim();
    return trimmed.startsWith('|') || trimmed.endsWith('|');
  }

  static bool _looksLikeTableDivider(String line) {
    return RegExp(
      r'^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)+\|?$',
    ).hasMatch(line);
  }

  static String _trimLooseIndent(String value) {
    return value.replaceAll(
      RegExp(
        r'^[\s\u2000-\u200A\u202F\u205F\u3000]+|[\s\u2000-\u200A\u202F\u205F\u3000]+$',
      ),
      '',
    );
  }

  static String? _normalizeMarkdownTarget(String? rawTarget) {
    if (rawTarget == null) {
      return null;
    }

    var target = rawTarget.trim();
    if (target.isEmpty) {
      return null;
    }

    if (target.startsWith('<') && target.endsWith('>')) {
      target = target.substring(1, target.length - 1).trim();
    }

    if (target.startsWith('#') ||
        target.startsWith('data:') ||
        target.startsWith('mailto:')) {
      return null;
    }

    final uri = Uri.tryParse(target);
    if (uri?.hasScheme == true) {
      return null;
    }

    return Uri.decodeFull(target);
  }
}

sealed class _MarkdownBlock {
  const _MarkdownBlock();
}

class _MarkdownTextBlock extends _MarkdownBlock {
  final String markdown;

  const _MarkdownTextBlock(this.markdown);
}

class _MarkdownTableBlock extends _MarkdownBlock {
  final String markdown;

  const _MarkdownTableBlock(this.markdown);
}
