import 'package:flutter_quill/flutter_quill.dart';

/// Returns the inline formats that should be explicitly disabled after an
/// erase operation leaves the caret on an empty line.
///
/// Flutter Quill normally remembers the formatting of backspaced text. That
/// is useful while correcting a word, but surprising after erasing everything
/// typed on a newly formatted line.
Set<String> inlineFormatKeysToClearAfterDeletion({
  required Document document,
  required Style selectionStyle,
  required int index,
  required int length,
  required Object? data,
}) {
  if (data != '' || length <= 0 || index < 0) {
    return const <String>{};
  }

  final text = document.toPlainText();
  if (index > text.length || index + length > text.length) {
    return const <String>{};
  }

  final textAfterDeletion = text.replaceRange(index, index + length, '');
  final caretOffset = index.clamp(0, textAfterDeletion.length);
  final lineStart = caretOffset == 0
      ? 0
      : textAfterDeletion.lastIndexOf('\n', caretOffset - 1) + 1;
  final nextNewline = textAfterDeletion.indexOf('\n', caretOffset);
  final lineEnd = nextNewline == -1 ? textAfterDeletion.length : nextNewline;

  if (textAfterDeletion.substring(lineStart, lineEnd).trim().isNotEmpty) {
    return const <String>{};
  }

  return selectionStyle.values
      .where(
        (attribute) =>
            attribute.scope == AttributeScope.inline && attribute.value != null,
      )
      .map((attribute) => attribute.key)
      .toSet();
}

/// Explicitly disables the carried inline formats for the controller's next
/// insertion while leaving any block-level formatting untouched.
void clearCarriedInlineFormats(
  QuillController controller,
  Iterable<String> formatKeys,
) {
  var style = controller.toggledStyle;
  for (final key in formatKeys) {
    style = style.put(Attribute<Object?>(key, AttributeScope.inline, null));
  }
  controller.forceToggledStyle(style);
}
