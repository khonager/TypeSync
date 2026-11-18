import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/core/models/typesync_table_embed.dart';
import 'package:typesync/features/editor/utils/editable_embed_builder.dart';
import 'package:typesync/features/editor/widgets/typesync_table_embed_builder.dart';

void main() {
  testWidgets('repeated edits affect only the bottom identical table',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final table = TypeSyncTableEmbed.toBlockEmbed(TypeSyncTableData.empty());
    final controller = QuillController(
      document: Document.fromDelta(
        Delta()
          ..insert(table.toJson())
          ..insert('\nbetween\n')
          ..insert(table.toJson())
          ..insert('\n'),
      ),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final focus = FocusNode();
    final scroll = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuillEditor(
            controller: controller,
            focusNode: focus,
            scrollController: scroll,
            configurations: const QuillEditorConfigurations(
              embedBuilders: [TypeSyncTableEmbedBuilder()],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit table').last);
    await tester.pumpAndSettle();
    for (final text in ['first edit', 'second edit', 'final edit']) {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump();
      final inserts = controller.document.toDelta().toJson();
      expect(
        inserts.first['insert'],
        table.toJson(),
      );
      expect(inserts[1]['insert'], '\nbetween\n');
      final custom = CustomBlockEmbed.fromJsonString(
        (inserts[2]['insert'] as Map)['custom'] as String,
      );
      expect(
        TypeSyncTableEmbed.parseData(custom.data as String).rows[0][0],
        text,
      );
    }
    await tester.tap(find.byTooltip('Add row'));
    await tester.pump();
    expect(
      controller.document.toDelta().toJson().first['insert'],
      table.toJson(),
    );
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('final edit'), findsOneWidget);
  });

  group('shared editing target for any custom block type', () {
    late QuillController controller;
    late EmbedEditTarget target;
    final original =
        BlockEmbed.custom(const CustomBlockEmbed('future-type', 'same'));
    setUp(() {
      controller = QuillController(
        document: Document.fromDelta(
          Delta()
            ..insert(original.toJson())
            ..insert('\ntext\n')
            ..insert(original.toJson())
            ..insert('\n'),
        ),
        selection: const TextSelection.collapsed(offset: 0),
      );
      target = EmbedEditTarget(
        controller,
        controller.document.querySegmentLeafNode(7).leaf as Embed,
      );
    });
    tearDown(() => controller.dispose());

    test('follows shifts and replacement nodes across repeated saves', () {
      controller.replaceText(2, 0, 'prefix', null);
      for (final content in ['one', 'two']) {
        final next =
            BlockEmbed.custom(CustomBlockEmbed('future-type', content));
        expect(target.replace(next), isTrue);
        expect(
          controller.document.toDelta().toJson().first['insert'],
          original.toJson(),
        );
        expect(
          controller.document
              .querySegmentLeafNode(13)
              .leaf!
              .toDelta()
              .first
              .data,
          next.toJson(),
        );
      }
    });

    test('does not overwrite another block after deletion', () {
      controller.replaceText(7, 1, '', null);
      final before = controller.document.toDelta().toJson();
      expect(target.replace(original), isFalse);
      expect(controller.document.toDelta().toJson(), before);
    });

    test('does not write into a replacement document', () {
      controller.document = Document.fromDelta(controller.document.toDelta());
      final before = controller.document.toDelta().toJson();
      expect(target.replace(original), isFalse);
      expect(controller.document.toDelta().toJson(), before);
    });
  });
}
