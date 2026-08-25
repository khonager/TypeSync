/// VS Code-style, language-aware code block embed.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../core/models/typesync_code_embed.dart';

const codeBlockLanguages = <String>[
  'plaintext',
  'dart',
  'javascript',
  'typescript',
  'python',
  'json',
  'html',
  'css',
  'bash',
  'powershell',
  'sql',
  'java',
  'csharp',
  'cpp',
  'go',
  'rust',
  'kotlin',
  'swift',
  'yaml',
  'nix',
  'markdown',
];

class TypeSyncCodeEmbedBuilder extends EmbedBuilder {
  const TypeSyncCodeEmbedBuilder();

  @override
  String get key => TypeSyncCodeData.codeType;

  @override
  String toPlainText(Embed node) {
    final data = node.value.data;
    if (data is! String) return '\n';
    return '${TypeSyncCodeData.fromEmbedData(data).code}\n';
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
    final raw = node.value.data;
    final code = raw is String
        ? TypeSyncCodeData.fromEmbedData(raw)
        : TypeSyncCodeData.empty();
    return _CodeBlock(
      controller: controller,
      node: node,
      code: code,
      readOnly: readOnly,
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({
    required this.controller,
    required this.node,
    required this.code,
    required this.readOnly,
  });
  final QuillController controller;
  final Embed node;
  final TypeSyncCodeData code;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF1E1E1E);
    const foreground = Color(0xFFD4D4D4);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 38,
            padding: const EdgeInsets.only(left: 12, right: 4),
            color: const Color(0xFF252526),
            child: Row(
              children: [
                Text(
                  _languageLabel(code.language),
                  style: const TextStyle(
                    color: Color(0xFFB9B9B9),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Copy code',
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  color: const Color(0xFFCECECE),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code.code));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copied')),
                      );
                    }
                  },
                ),
                if (!readOnly)
                  IconButton(
                    tooltip: 'Edit code',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    color: const Color(0xFFCECECE),
                    onPressed: () => _edit(context),
                  ),
              ],
            ),
          ),
          if (code.language == 'markdown')
            Padding(
              key: const ValueKey('markdown-preview'),
              padding: const EdgeInsets.all(14),
              child: MarkdownBody(
                data: code.code,
                selectable: true,
                extensionSet: md.ExtensionSet.gitHubWeb,
                styleSheet: _markdownPreviewStyle(context, foreground),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(14),
              child: SelectableText.rich(
                highlightCode(code.code, code.language, foreground),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final result = await showDialog<TypeSyncCodeData>(
      context: context,
      builder: (_) => TypeSyncCodeEditorDialog(initial: code),
    );
    if (result == null) return;
    final offset = TypeSyncCodeData.findCodeOffset(
      controller.document.toDelta().toJson(),
      codeId: code.id,
    );
    if (offset == null) return;
    controller.replaceText(
      offset,
      1,
      TypeSyncCodeData.toBlockEmbed(result),
      TextSelection.collapsed(offset: offset + 1),
    );
  }
}

MarkdownStyleSheet _markdownPreviewStyle(
  BuildContext context,
  Color foreground,
) {
  final base = TextStyle(color: foreground, fontSize: 14, height: 1.45);
  return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    a: base.copyWith(color: const Color(0xFF4FC1FF)),
    p: base,
    code: base.copyWith(
      color: const Color(0xFFCE9178),
      fontFamily: 'monospace',
      backgroundColor: const Color(0xFF2D2D2D),
    ),
    h1: base.copyWith(fontSize: 26, fontWeight: FontWeight.w700),
    h2: base.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
    h3: base.copyWith(fontSize: 19, fontWeight: FontWeight.w600),
    h4: base.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
    h5: base.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
    h6: base.copyWith(fontWeight: FontWeight.w600),
    blockquote: base.copyWith(color: const Color(0xFFB9B9B9)),
    listBullet: base,
    tableHead: base.copyWith(fontWeight: FontWeight.w600),
    tableBody: base,
    tableBorder: TableBorder.all(color: const Color(0xFF555555)),
    blockquoteDecoration: const BoxDecoration(
      color: Color(0xFF252526),
      border: Border(left: BorderSide(color: Color(0xFF569CD6), width: 3)),
    ),
    codeblockDecoration: BoxDecoration(
      color: const Color(0xFF171717),
      borderRadius: BorderRadius.circular(6),
    ),
    horizontalRuleDecoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Color(0xFF555555))),
    ),
  );
}

class TypeSyncCodeEditorDialog extends StatefulWidget {
  const TypeSyncCodeEditorDialog({required this.initial, super.key});
  final TypeSyncCodeData initial;
  @override
  State<TypeSyncCodeEditorDialog> createState() => _CodeEditorDialogState();
}

class _CodeEditorDialogState extends State<TypeSyncCodeEditorDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial.code);
  late String _language = widget.initial.language;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Code block'),
        content: SizedBox(
          width: 720,
          height: 440,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: DropdownButton<String>(
                  value: codeBlockLanguages.contains(_language)
                      ? _language
                      : 'plaintext',
                  items: codeBlockLanguages
                      .map(
                        (l) => DropdownMenuItem(
                          value: l,
                          child: Text(_languageLabel(l)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _language = value!),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Paste or write code here',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              widget.initial
                  .copyWith(language: _language, code: _controller.text),
            ),
            child: const Text('Save'),
          ),
        ],
      );
}

String _languageLabel(String language) => switch (language) {
      'csharp' => 'C#',
      'cpp' => 'C++',
      'javascript' => 'JavaScript',
      'typescript' => 'TypeScript',
      'powershell' => 'PowerShell',
      'plaintext' => 'Plain text',
      _ => language[0].toUpperCase() + language.substring(1),
    };

/// Builds syntax-highlighted text without changing any of the source text.
///
/// This is public so the full list of code-block languages can be covered by
/// regression tests. A code block must always be lossless, even when its
/// highlighter does not recognise a token.
TextSpan highlightCode(String code, String language, Color base) {
  final keyword = switch (language) {
    'dart' =>
      r'\b(class|final|const|var|void|return|if|else|import|async|await|extends|static|new)\b',
    'python' =>
      r'\b(def|class|return|if|elif|else|import|from|for|while|in|True|False|None)\b',
    'javascript' ||
    'typescript' =>
      r'\b(const|let|var|function|return|if|else|import|export|async|await|class|interface|type|new)\b',
    'nix' => r'\b(let|in|with|rec|inherit|if|then|else|true|false|null)\b',
    'json' => r'"(?:\\.|[^"\\])*"(?=\s*:)|\b(true|false|null)\b',
    _ =>
      r'\b(class|public|private|static|void|return|if|else|for|while|SELECT|FROM|WHERE)\b',
  };
  final pattern = RegExp(
    '(?:$keyword)|(?://[^\\n]*|#[^\\n]*|/\\*[\\s\\S]*?\\*/)|(?:"(?:\\\\.|[^"\\\\])*")|(?:\\b\\d+(?:\\.\\d+)?\\b)',
    multiLine: true,
    caseSensitive: language != 'sql',
  );
  final spans = <TextSpan>[];
  var index = 0;
  for (final match in pattern.allMatches(code)) {
    if (match.start > index) {
      spans.add(TextSpan(text: code.substring(index, match.start)));
    }
    final text = match.group(0)!;
    final color =
        text.startsWith('//') || text.startsWith('#') || text.startsWith('/*')
            ? const Color(0xFF6A9955)
            : text.startsWith('"')
                ? const Color(0xFFCE9178)
                : RegExp(r'^\d').hasMatch(text)
                    ? const Color(0xFFB5CEA8)
                    : const Color(0xFF569CD6);
    spans.add(TextSpan(text: text, style: TextStyle(color: color)));
    index = match.end;
  }
  if (index < code.length) {
    spans.add(
      TextSpan(text: code.substring(index), style: TextStyle(color: base)),
    );
  }
  return TextSpan(style: TextStyle(color: base), children: spans);
}
