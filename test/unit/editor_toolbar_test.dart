import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/features/editor/widgets/editor_toolbar.dart';

void main() {
  group('EditorToolbar', () {
    Future<void> pumpToolbar(
      WidgetTester tester,
      QuillController controller, {
      EditorToolbarPlacement placement = EditorToolbarPlacement.top,
      VoidCallback? onInsertCode,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorToolbar(
              controller: controller,
              onInsertPdf: () {},
              onInsertTable: () {},
              onInsertKanban: () {},
              onToggleChecklist: () {
                final hasChecklist = controller
                    .getSelectionStyle()
                    .attributes
                    .containsKey(Attribute.list.key);
                controller.formatSelection(
                  hasChecklist
                      ? Attribute.clone(Attribute.checked, null)
                      : Attribute.checked,
                );
              },
              placement: placement,
              onPlacementChanged: (_) {},
              initialPosition: Offset.zero,
              onPositionChanged: (_) {},
              onSetAlignment: (Attribute<String?> value) {},
              onInsertCode: onInsertCode ?? () {},
            ),
          ),
        ),
      );
    }

    testWidgets(
      'floating rectangle has three reversed six-item rows',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final controller = QuillController.basic();
        addTearDown(controller.dispose);
        var codeInsertions = 0;

        await pumpToolbar(
          tester,
          controller,
          placement: EditorToolbarPlacement.floating,
          onInsertCode: () => codeInsertions++,
        );
        await tester.tap(find.byIcon(Icons.edit));
        await tester.pumpAndSettle();

        expect(find.byTooltip('Bullet list'), findsOneWidget);
        expect(find.byTooltip('Insert code block'), findsOneWidget);
        expect(find.text('Format'), findsNothing);
        for (var index = 0; index < 2; index++) {
          final divider = find.byKey(
            ValueKey('floating-toolbar-divider-$index'),
          );
          expect(divider, findsOneWidget);
          final dividerSize = tester.getSize(divider);
          expect(dividerSize.height, 28);
          expect(dividerSize.height, greaterThan(dividerSize.width));
        }
        expect(
          find.byKey(const ValueKey('floating-toolbar-divider-2')),
          findsNothing,
        );

        final rows = [
          [
            'Collapse',
            'Reset text style',
            'Insert PDF',
            'Insert table',
            'Insert kanban',
            'Insert code block',
          ],
          [
            'Checklist',
            'Numbered list',
            'Bullet list',
            'Align left',
            'Align center',
            'Align right',
          ],
          [
            'Bold',
            'Italic',
            'Underline',
            'Strikethrough',
            'Text color',
            'Highlight',
          ],
        ];
        final rowCenters = <List<Offset>>[];
        for (final row in rows) {
          final centers = row
              .map((tooltip) => tester.getCenter(find.byTooltip(tooltip)))
              .toList();
          expect(centers.map((center) => center.dy).toSet(), hasLength(1));
          for (var index = 1; index < centers.length; index++) {
            expect(centers[index - 1].dx, lessThan(centers[index].dx));
          }
          rowCenters.add(centers);
        }
        expect(rowCenters[0].first.dy, lessThan(rowCenters[1].first.dy));
        expect(rowCenters[1].first.dy, lessThan(rowCenters[2].first.dy));

        final topDividerCenter = tester.getCenter(
          find.byKey(const ValueKey('floating-toolbar-divider-0')),
        );
        expect(topDividerCenter.dx, greaterThan(rowCenters[0][1].dx));
        expect(topDividerCenter.dx, lessThan(rowCenters[0][2].dx));
        final middleDividerCenter = tester.getCenter(
          find.byKey(const ValueKey('floating-toolbar-divider-1')),
        );
        expect(middleDividerCenter.dx, greaterThan(rowCenters[1][2].dx));
        expect(middleDividerCenter.dx, lessThan(rowCenters[1][3].dx));

        await tester.tap(find.byTooltip('Bullet list'));
        await tester.pump();
        expect(
          controller.getSelectionStyle().attributes[Attribute.list.key]?.value,
          Attribute.ul.value,
        );

        await tester.tap(find.byTooltip('Insert code block'));
        expect(codeInsertions, 1);
      },
    );

    testWidgets('hides a tooltip when the pointer leaves its toolbar button', (
      tester,
    ) async {
      final controller = QuillController.basic();
      addTearDown(controller.dispose);

      await pumpToolbar(tester, controller);

      final button = find.byTooltip('Bold');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(button));
      await tester.pump(const Duration(seconds: 1));

      final tooltipLabel = find.text('Bold');
      expect(tooltipLabel, findsOneWidget);

      await mouse.moveTo(tester.getCenter(tooltipLabel));
      await tester.pump();

      expect(tooltipLabel, findsNothing);
    });

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

    testWidgets('resets text styling to the defaults at a collapsed cursor', (
      tester,
    ) async {
      final controller = QuillController.basic();
      controller.updateSelection(
        const TextSelection.collapsed(offset: 0),
        ChangeSource.local,
      );
      controller.formatSelection(Attribute.bold);
      controller.formatSelection(const ColorAttribute('#64D2FF'));
      controller.formatSelection(const BackgroundAttribute('#FFF59D'));
      controller.formatSelection(Attribute.checked);

      await pumpToolbar(tester, controller);

      await tester.tap(find.byTooltip('Reset text style'));
      await tester.pump();

      final attributes = controller.getSelectionStyle().attributes;
      expect(attributes.containsKey(Attribute.bold.key), isFalse);
      expect(attributes.containsKey(Attribute.color.key), isFalse);
      expect(attributes.containsKey(Attribute.background.key), isFalse);
      expect(attributes[Attribute.list.key]?.value, Attribute.checked.value);
    });

    testWidgets('does not reset a code block', (tester) async {
      final controller = QuillController.basic();
      controller.updateSelection(
        const TextSelection.collapsed(offset: 0),
        ChangeSource.local,
      );
      controller.formatSelection(Attribute.codeBlock);
      controller.formatSelection(Attribute.bold);

      await pumpToolbar(tester, controller);

      await tester.tap(find.byTooltip('Reset text style'));
      await tester.pump();

      final attributes = controller.getSelectionStyle().attributes;
      expect(attributes.containsKey(Attribute.bold.key), isFalse);
      expect(
        attributes[Attribute.codeBlock.key]?.value,
        Attribute.codeBlock.value,
      );
    });
  });
}
