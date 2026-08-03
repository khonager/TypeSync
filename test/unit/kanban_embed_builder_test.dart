import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/core/models/typesync_kanban_embed.dart';
import 'package:typesync/features/editor/widgets/typesync_kanban_embed_builder.dart';

void main() {
  testWidgets('title edits do not replace the document while typing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const board = TypeSyncKanbanData(
      id: 'board-1',
      title: 'Original board',
      columns: [
        TypeSyncKanbanColumnData(
          id: 'column-1',
          title: 'Original column',
          cards: [],
        ),
      ],
    );
    final controller = QuillController(
      document: Document.fromDelta(
        Delta()
          ..insert(TypeSyncKanbanEmbed.toBlockEmbed(board).toJson())
          ..insert('\n'),
      ),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final editorFocusNode = FocusNode();
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(editorFocusNode.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuillEditor(
            controller: controller,
            focusNode: editorFocusNode,
            scrollController: scrollController,
            configurations: const QuillEditorConfigurations(
              embedBuilders: [TypeSyncKanbanEmbedBuilder()],
            ),
          ),
        ),
      ),
    );

    final originalDocument = controller.document.toDelta().toJson();
    await tester.tap(find.text('Edit board'));
    await tester.pumpAndSettle();

    final boardTitleField = find.widgetWithText(TextField, 'Board title');
    await tester.enterText(boardTitleField, 'Renamed board');
    await tester.pump();
    expect(boardTitleField.evaluate().single, isNotNull);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: boardTitleField,
              matching: find.byType(EditableText),
            ),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
    expect(controller.document.toDelta().toJson(), originalDocument);

    final columnTitleField = find.widgetWithText(TextFormField, 'Column').first;
    await tester.enterText(columnTitleField, 'Renamed column');
    await tester.pump();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: columnTitleField,
              matching: find.byType(EditableText),
            ),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
    expect(controller.document.toDelta().toJson(), originalDocument);

    await tester.tap(find.byTooltip('Save and close'));
    await tester.pumpAndSettle();

    expect(find.text('Renamed board'), findsOneWidget);
    expect(find.text('Renamed column'), findsOneWidget);
    expect(find.text('Original board'), findsNothing);
    expect(find.text('Original column'), findsNothing);
  });
}
