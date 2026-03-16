/// Markdown to rich text conversion helpers for imports.
// ignore_for_file: deprecated_member_use
library;

import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/markdown_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:markdown/markdown.dart' as md;

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
    final document = md.Document(
      encodeHtml: false,
      extensionSet: md.ExtensionSet.gitHubFlavored,
    );

    final converter = MarkdownToDelta(
      markdownDocument: document,
      customElementToInlineAttribute: {
        'mark': (_) => const [BackgroundAttribute('FFFFFF00')],
        'u': (_) => const [Attribute.underline],
        'span': _attributesForStyledSpan,
        'font': _attributesForStyledSpan,
      },
    );

    return converter.convert(markdown);
  }

  List<Attribute<dynamic>> _attributesForStyledSpan(md.Element element) {
    final attributes = <Attribute<dynamic>>[];
    final directColor = element.attributes['color'];
    final style = element.attributes['style'] ?? '';

    final colorValue = directColor ?? _cssDeclaration(style, 'color');
    final backgroundValue = _cssDeclaration(style, 'background-color');

    final quillColor = _quillColorFromCss(colorValue);
    if (quillColor != null) {
      attributes.add(ColorAttribute(quillColor));
    }

    final quillBackground = _quillColorFromCss(backgroundValue);
    if (quillBackground != null) {
      attributes.add(BackgroundAttribute(quillBackground));
    }

    final textDecoration = _cssDeclaration(style, 'text-decoration');
    if (textDecoration != null &&
        textDecoration.toLowerCase().contains('underline')) {
      attributes.add(Attribute.underline);
    }

    return attributes;
  }

  static String _stripInlineMarkdown(String input) {
    return input
        .replaceAll(RegExp(r'[*_`~]'), '')
        .replaceAll(RegExp(r'\[(.*?)\]\((.*?)\)'), r'$1')
        .trim();
  }

  static String? _cssDeclaration(String style, String name) {
    final match = RegExp(
      '$name\\s*:\\s*([^;]+)',
      caseSensitive: false,
    ).firstMatch(style);
    return match?.group(1)?.trim();
  }

  static String? _quillColorFromCss(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final normalized = value.trim().toLowerCase();
    const named = <String, String>{
      'black': 'FF000000',
      'white': 'FFFFFFFF',
      'red': 'FFFF0000',
      'green': 'FF008000',
      'blue': 'FF0000FF',
      'yellow': 'FFFFFF00',
      'orange': 'FFFFA500',
      'amber': 'FFFFC107',
      'pink': 'FFFFC0CB',
      'purple': 'FF800080',
      'teal': 'FF008080',
      'cyan': 'FF00BCD4',
      'sky': 'FF87CEEB',
      'grey': 'FF9E9E9E',
      'gray': 'FF9E9E9E',
    };

    if (named.containsKey(normalized)) {
      return named[normalized];
    }

    if (normalized.startsWith('#')) {
      final hex = normalized.substring(1);
      if (hex.length == 3) {
        final expanded = hex.split('').map((char) => '$char$char').join();
        return 'FF${expanded.toUpperCase()}';
      }
      if (hex.length == 6) {
        return 'FF${hex.toUpperCase()}';
      }
      if (hex.length == 8) {
        return hex.toUpperCase();
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
      return _argbHex(alpha, red, green, blue);
    }

    return null;
  }

  static String _argbHex(int alpha, int red, int green, int blue) {
    String hex(int value) =>
        value.clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '${hex(alpha)}${hex(red)}${hex(green)}${hex(blue)}'.toUpperCase();
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
          if (trimmed.isEmpty || !_looksLikeTableRow(trimmed)) {
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

  static bool _looksLikeTableDivider(String line) {
    return RegExp(
      r'^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$',
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
