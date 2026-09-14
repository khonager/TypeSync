import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter/services.dart' show TextSelection;
import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/features/editor/utils/editor_format_retention.dart';

void main() {
  group('inlineFormatKeysToClearAfterDeletion', () {
    test('clears inline formatting when the last line character is erased', () {
      final document = Document.fromDelta(
        Delta()
          ..insert('formatted', {'bold': true, 'color': '#ff0000'})
          ..insert('\n'),
      );

      final keys = inlineFormatKeysToClearAfterDeletion(
        document: document,
        selectionStyle: document.collectStyle(8, 0),
        index: 0,
        length: 9,
        data: '',
      );

      expect(
        keys,
        containsAll(<String>[Attribute.bold.key, Attribute.color.key]),
      );
    });

    test('keeps inline formatting while text remains on the line', () {
      final document = Document.fromDelta(
        Delta()
          ..insert('formatted', {'bold': true})
          ..insert('\n'),
      );

      final keys = inlineFormatKeysToClearAfterDeletion(
        document: document,
        selectionStyle: document.collectStyle(9, 0),
        index: 8,
        length: 1,
        data: '',
      );

      expect(keys, isEmpty);
    });

    test('clears carried inline formatting when blank lines are removed', () {
      final document = Document.fromDelta(
        Delta()
          ..insert('formatted', {'italic': true})
          ..insert('\n\n\n'),
      );

      final keys = inlineFormatKeysToClearAfterDeletion(
        document: document,
        selectionStyle: document.collectStyle(11, 0),
        index: 10,
        length: 1,
        data: '',
      );

      expect(keys, contains(Attribute.italic.key));
    });

    test('does not clear block formatting from an empty list item', () {
      final document = Document.fromDelta(
        Delta()
          ..insert('item', {'bold': true})
          ..insert('\n', {'list': 'bullet'})
          ..insert('\n', {'list': 'bullet'}),
      );
      final selectionStyle = document.collectStyle(5, 0);

      final keys = inlineFormatKeysToClearAfterDeletion(
        document: document,
        selectionStyle: selectionStyle,
        index: 5,
        length: 1,
        data: '',
      );

      expect(keys, isNot(contains(Attribute.list.key)));
    });

    test('ignores replacements that insert text', () {
      final document = Document.fromDelta(
        Delta()
          ..insert('x', {'bold': true})
          ..insert('\n'),
      );

      final keys = inlineFormatKeysToClearAfterDeletion(
        document: document,
        selectionStyle: document.collectStyle(1, 0),
        index: 0,
        length: 1,
        data: 'y',
      );

      expect(keys, isEmpty);
    });

    test('makes the next inserted character plain', () {
      final controller = QuillController(
        document: Document(),
        selection: const TextSelection.collapsed(offset: 0),
      );
      addTearDown(controller.dispose);
      controller.forceToggledStyle(const Style().put(Attribute.bold));

      clearCarriedInlineFormats(controller, <String>[Attribute.bold.key]);
      controller.replaceText(
        0,
        0,
        'plain',
        const TextSelection.collapsed(offset: 5),
      );

      expect(
        controller.document.toDelta(),
        Delta()..insert('plain\n'),
      );
    });
  });
}
