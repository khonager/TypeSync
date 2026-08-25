import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/core/models/typesync_code_embed.dart';
import 'package:typesync/features/editor/widgets/typesync_code_embed_builder.dart';

void main() {
  group('code block highlighting', () {
    const baseColor = Color(0xFFD4D4D4);

    test('is lossless for every supported language', () {
      const source = '''line 1 <tag attr="value">
# heading or comment
**bold** `inline` \\escaped
final value = 42;
''';

      for (final language in codeBlockLanguages) {
        expect(
          highlightCode(source, language, baseColor).toPlainText(),
          source,
          reason: '$language highlighting changed the source text',
        );
      }
    });
  });

  testWidgets('Markdown is rendered until the raw source is edited', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const source = '# Release notes\n\n- **Rendered** item\n';
    const editedSource = '## Updated preview\n\n1. New item\n';
    const code = TypeSyncCodeData(
      id: 'markdown-preview-block',
      language: 'markdown',
      code: source,
    );
    final controller = QuillController(
      document: Document.fromDelta(
        Delta()
          ..insert(TypeSyncCodeData.toBlockEmbed(code).toJson())
          ..insert('\n'),
      ),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final focusNode = FocusNode();
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuillEditor(
            controller: controller,
            focusNode: focusNode,
            scrollController: scrollController,
            configurations: const QuillEditorConfigurations(
              embedBuilders: [TypeSyncCodeEmbedBuilder()],
            ),
          ),
        ),
      ),
    );

    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.byKey(const ValueKey('markdown-preview')), findsOneWidget);
    expect(find.text('Release notes'), findsOneWidget);
    expect(find.text('# Release notes'), findsNothing);

    await tester.tap(find.byTooltip('Edit code'));
    await tester.pumpAndSettle();

    final rawEditor = tester.widget<TextField>(find.byType(TextField));
    expect(rawEditor.controller!.text, source);

    await tester.enterText(find.byType(TextField), editedSource);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.text('Updated preview'), findsOneWidget);
    expect(find.text('## Updated preview'), findsNothing);
  });

  testWidgets('Markdown can be edited and saved without changing its text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const markdown = '''# Release notes

- [x] Code blocks
- [ ] More tests

Use **bold**, _italic_, [links](https://example.com), and `inline code`.

```dart
void main() => print("Markdown stays intact");
```
''';
    TypeSyncCodeData? saved;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  saved = await showDialog<TypeSyncCodeData>(
                    context: context,
                    builder: (_) => const TypeSyncCodeEditorDialog(
                      initial: TypeSyncCodeData(
                        id: 'markdown-block',
                        language: 'markdown',
                        code: 'old text',
                      ),
                    ),
                  );
                },
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    expect(find.text('Markdown'), findsOneWidget);

    await tester.enterText(find.byType(TextField), markdown);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.id, 'markdown-block');
    expect(saved!.language, 'markdown');
    expect(saved!.code, markdown);
  });
}
