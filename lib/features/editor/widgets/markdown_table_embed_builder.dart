/// Render Markdown tables produced during import as custom Quill embeds.
// ignore_for_file: deprecated_member_use
library;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/markdown_quill.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter_markdown/flutter_markdown.dart';

class MarkdownTableEmbedBuilder extends EmbedBuilder {
  const MarkdownTableEmbedBuilder();

  @override
  String get key => EmbeddableTable.tableType;

  @override
  String toPlainText(Embed node) {
    final data = node.value.data;
    return data is String ? '$data\n' : '\n';
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
    final markdownTable = data is String ? data : '';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: MediaQuery.sizeOf(context).width - 96,
          ),
          child: MarkdownBody(
            data: markdownTable,
            extensionSet: md.ExtensionSet.gitHubFlavored,
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
          ),
        ),
      ),
    );
  }
}
