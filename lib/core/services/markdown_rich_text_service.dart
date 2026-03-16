/// Markdown to rich text conversion helpers for imports.
// ignore_for_file: deprecated_member_use
library;

import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/markdown_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:markdown/markdown.dart' as md;

class ConvertedMarkdownNote {
  final String title;
  final String markdownBody;
  final String quillContentJson;

  const ConvertedMarkdownNote({
    required this.title,
    required this.markdownBody,
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
    final delta = _markdownToDelta(rewrittenMarkdown);

    return ConvertedMarkdownNote(
      title: extracted.title,
      markdownBody: rewrittenMarkdown,
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

  Delta _markdownToDelta(String markdown) {
    final document = md.Document(
      encodeHtml: false,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      blockSyntaxes: const [EmbeddableTableSyntax()],
    );

    final converter = MarkdownToDelta(
      markdownDocument: document,
      customElementToInlineAttribute: {
        'mark': (_) => const [BackgroundAttribute('FFFFFF00')],
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
