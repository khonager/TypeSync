import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/features/editor/utils/shift_click_selection.dart';

void main() {
  group('extendSelectionFromShiftClick', () {
    test('keeps the anchor of a forward selection', () {
      final result = extendSelectionFromShiftClick(
        selection: const TextSelection(baseOffset: 4, extentOffset: 10),
        targetOffset: 18,
      );

      expect(result.baseOffset, 4);
      expect(result.extentOffset, 18);
      expect(result.start, 4);
      expect(result.end, 18);
    });

    test('keeps the anchor of a reverse selection', () {
      final result = extendSelectionFromShiftClick(
        selection: const TextSelection(baseOffset: 10, extentOffset: 4),
        targetOffset: 1,
      );

      expect(result.baseOffset, 10);
      expect(result.extentOffset, 1);
      expect(result.start, 1);
      expect(result.end, 10);
    });
  });
}
