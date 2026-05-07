import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/features/editor/widgets/editor_toolbar.dart';

void main() {
  group('EditorToolbar', () {
    Future<void> pumpToolbar(
      WidgetTester tester,
      QuillController controller,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorToolbar(
              controller: controller,
              onInsertPdf: () {},
              onInsertTable: () {},
              onInsertKanban: () {},
              placement: EditorToolbarPlacement.top,
              onPlacementChanged: (_) {},
              initialPosition: Offset.zero,
              onPositionChanged: (_) {},
            ),
          ),
        ),
      );
    }

    testWidgets('toggles bold on and back off at a collapsed cursor', (
      tester,
    ) async {
      final controller = QuillController.basic();
      controller.updateSelection(
        const TextSelection.collapsed(offset: 0),
        ChangeSource.local,
      );

      await pumpToolbar(tester, controller);

      await tester.tap(find.byIcon(Icons.format_bold));
      await tester.pump();
      expect(
        controller
            .getSelectionStyle()
            .attributes
            .containsKey(Attribute.bold.key),
        isTrue,
      );

      await tester.tap(find.byIcon(Icons.format_bold));
      await tester.pump();
      expect(
        controller
            .getSelectionStyle()
            .attributes
            .containsKey(Attribute.bold.key),
        isFalse,
      );
    });

    testWidgets('list buttons switch formats and can return to normal', (
      tester,
    ) async {
      final controller = QuillController.basic();
      controller.updateSelection(
        const TextSelection.collapsed(offset: 0),
        ChangeSource.local,
      );

      await pumpToolbar(tester, controller);

      await tester.tap(find.byIcon(Icons.check_box));
      await tester.pump();
      expect(
        controller.getSelectionStyle().attributes[Attribute.list.key]?.value,
        Attribute.checked.value,
      );

      await tester.tap(find.byIcon(Icons.format_list_numbered));
      await tester.pump();
      expect(
        controller.getSelectionStyle().attributes[Attribute.list.key]?.value,
        Attribute.ol.value,
      );

      await tester.tap(find.byIcon(Icons.format_list_numbered));
      await tester.pump();
      expect(
        controller
            .getSelectionStyle()
            .attributes
            .containsKey(Attribute.list.key),
        isFalse,
      );
    });

    testWidgets('toggles strikethrough on and back off at a collapsed cursor', (
      tester,
    ) async {
      final controller = QuillController.basic();
      controller.updateSelection(
        const TextSelection.collapsed(offset: 0),
        ChangeSource.local,
      );

      await pumpToolbar(tester, controller);

      await tester.tap(find.byIcon(Icons.format_strikethrough));
      await tester.pump();
      expect(
        controller
            .getSelectionStyle()
            .attributes
            .containsKey(Attribute.strikeThrough.key),
        isTrue,
      );

      await tester.tap(find.byIcon(Icons.format_strikethrough));
      await tester.pump();
      expect(
        controller
            .getSelectionStyle()
            .attributes
            .containsKey(Attribute.strikeThrough.key),
        isFalse,
      );
    });
  });
}
