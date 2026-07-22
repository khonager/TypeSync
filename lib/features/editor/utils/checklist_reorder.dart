import 'package:flutter_quill/quill_delta.dart';

/// A change that moves one or more adjacent checklist lines as a unit.
class ChecklistReorderPlan {
  const ChecklistReorderPlan({
    required this.change,
    required this.selectionOffsetDelta,
  });

  /// The document change that swaps the selected lines with their neighbour.
  final Delta change;

  /// Add this value to each selection offset after applying [change].
  final int selectionOffsetDelta;
}

/// Builds lossless Quill document changes for moving checklist items.
///
/// Only adjacent checklist items can be reordered. This keeps task groups in
/// place and ensures all block and inline attributes, including TypeSync's
/// checklist timestamps, travel with their item.
class ChecklistReorder {
  static const _listAttributeKey = 'list';
  static const _checkedListValue = 'checked';
  static const _uncheckedListValue = 'unchecked';

  /// Returns a move plan for the selected checklist lines, or `null` when the
  /// selection cannot move in [direction] (`-1` for up, `1` for down).
  static ChecklistReorderPlan? buildPlan({
    required Delta document,
    required int selectionStart,
    required int selectionEnd,
    required bool selectionIsCollapsed,
    required int direction,
  }) {
    assert(direction == -1 || direction == 1);

    final lines = _documentLines(document);
    final selectedLines = lines
        .where(
          (line) => _isLineSelected(
            line,
            selectionStart: selectionStart,
            selectionEnd: selectionEnd,
            selectionIsCollapsed: selectionIsCollapsed,
          ),
        )
        .toList(growable: false);

    if (selectedLines.isEmpty ||
        selectedLines.any((line) => !line.isChecklist)) {
      return null;
    }

    final firstSelectedIndex = lines.indexOf(selectedLines.first);
    final lastSelectedIndex = lines.indexOf(selectedLines.last);
    final neighbourIndex =
        direction < 0 ? firstSelectedIndex - 1 : lastSelectedIndex + 1;
    if (neighbourIndex < 0 || neighbourIndex >= lines.length) return null;

    final neighbour = lines[neighbourIndex];
    if (!neighbour.isChecklist) return null;

    final selectedStart = selectedLines.first.startOffset;
    final selectedEnd = selectedLines.last.endOffset + 1;
    final neighbourStart = neighbour.startOffset;
    final neighbourEnd = neighbour.endOffset + 1;
    final replacementStart = direction < 0 ? neighbourStart : selectedStart;
    final replacementEnd = direction < 0 ? selectedEnd : neighbourEnd;
    final selectedDelta = document.slice(selectedStart, selectedEnd);
    final neighbourDelta = document.slice(neighbourStart, neighbourEnd);
    final replacement = direction < 0
        ? selectedDelta.concat(neighbourDelta)
        : neighbourDelta.concat(selectedDelta);
    final change = (Delta()
          ..retain(replacementStart)
          ..delete(replacementEnd - replacementStart))
        .concat(replacement);

    return ChecklistReorderPlan(
      change: change,
      selectionOffsetDelta: direction < 0
          ? -(neighbourEnd - neighbourStart)
          : neighbourEnd - neighbourStart,
    );
  }

  static bool _isLineSelected(
    _ChecklistDocumentLine line, {
    required int selectionStart,
    required int selectionEnd,
    required bool selectionIsCollapsed,
  }) {
    final lineSelectionEnd = line.endOffset + 1;
    if (selectionIsCollapsed) {
      return selectionStart >= line.startOffset &&
          selectionStart <= line.endOffset;
    }
    return selectionStart < lineSelectionEnd && selectionEnd > line.startOffset;
  }

  static List<_ChecklistDocumentLine> _documentLines(Delta document) {
    final lines = <_ChecklistDocumentLine>[];
    var documentOffset = 0;
    var lineStartOffset = 0;

    for (final operation in document.toList()) {
      final insert = operation.data;
      final attributes = operation.attributes ?? const <String, dynamic>{};

      if (insert is String) {
        for (final codeUnit in insert.codeUnits) {
          if (codeUnit == 0x0A) {
            lines.add(
              _ChecklistDocumentLine(
                startOffset: lineStartOffset,
                endOffset: documentOffset,
                listType: attributes[_listAttributeKey] as String?,
              ),
            );
            lineStartOffset = documentOffset + 1;
          }
          documentOffset++;
        }
      } else {
        documentOffset++;
      }
    }

    return lines;
  }
}

class _ChecklistDocumentLine {
  const _ChecklistDocumentLine({
    required this.startOffset,
    required this.endOffset,
    required this.listType,
  });

  final int startOffset;
  final int endOffset;
  final String? listType;

  bool get isChecklist =>
      listType == ChecklistReorder._checkedListValue ||
      listType == ChecklistReorder._uncheckedListValue;
}
