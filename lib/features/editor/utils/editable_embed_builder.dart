import 'package:flutter/foundation.dart' show nonVirtual;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
// Quill 10 unwraps custom embeds into detached nodes before calling builders.
// Keep this version-specific integration here, away from individual editors.
// ignore: implementation_imports
import 'package:flutter_quill/src/editor/widgets/text/text_line.dart';

/// Base for editable embeds. New block editors should use [EmbedEditTarget]
/// rather than saving a builder node's offset or searching by payload/ID.
abstract class EditableEmbedBuilder extends EmbedBuilder {
  const EditableEmbedBuilder();

  @override
  @nonVirtual
  Widget build(
    BuildContext context,
    QuillController controller,
    Embed node,
    bool readOnly,
    bool inline,
    TextStyle textStyle,
  ) {
    final line = context.widget is TextLine
        ? (context.widget as TextLine).line
        : context.findAncestorWidgetOfExactType<TextLine>()?.line;
    final candidates = line?.children.whereType<Embed>().where((candidate) {
      final value = candidate.value.type == BlockEmbed.customType
          ? CustomBlockEmbed.fromJsonString(candidate.value.data as String)
          : candidate.value;
      return value.type == node.value.type && value.data == node.value.data;
    }).toList();
    // Never guess when there is no unambiguous document node.
    final actual = node.parent != null
        ? node
        : candidates?.length == 1
            ? candidates!.single
            : null;
    return buildEditable(
      context,
      controller,
      node,
      actual == null ? null : EmbedEditTarget(controller, actual),
      readOnly || actual == null,
      inline,
      textStyle,
    );
  }

  Widget buildEditable(
    BuildContext context,
    QuillController controller,
    Embed node,
    EmbedEditTarget? target,
    bool readOnly,
    bool inline,
    TextStyle textStyle,
  );
}

/// Tracks one live block across saves and edits before it, even when identical
/// blocks (or pasted blocks with duplicate IDs) exist in the same document.
class EmbedEditTarget {
  EmbedEditTarget(this._controller, this._node);

  final QuillController _controller;
  Embed? _node;

  bool replace(BlockEmbed value) {
    final node = _node;
    if (node == null) return false;
    Node root = node;
    while (root.parent != null) {
      root = root.parent!;
    }
    if (!identical(root, _controller.document.root)) return false;

    final offset = node.documentOffset;
    _controller.replaceText(
      offset,
      1,
      value,
      TextSelection.collapsed(offset: offset + 1),
    );
    final replacement = _controller.document.querySegmentLeafNode(offset).leaf;
    _node = replacement is Embed ? replacement : null;
    return _node != null;
  }
}
