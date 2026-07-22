import 'package:flutter/widgets.dart' show TextSelection;

/// Extends a selection from its original anchor to a Shift-clicked position.
///
/// Keeping the selection's base offset intact is important: it is the anchor,
/// while normalized start/end offsets lose the direction in which the user
/// created the selection.
TextSelection extendSelectionFromShiftClick({
  required TextSelection selection,
  required int targetOffset,
}) {
  return selection.copyWith(extentOffset: targetOffset);
}
