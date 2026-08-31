import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/core/utils/note_conflict_diff.dart';
import 'package:typesync/features/editor/widgets/note_conflict_resolver_dialog.dart';

void main() {
  testWidgets('requires a decision and applies the selected conflict side',
      (tester) async {
    String? resolvedContent;
    final diff = NoteConflictDiff.fromContents(
      localContent: jsonEncode(<Map<String, dynamic>>[
        <String, dynamic>{'insert': 'Local wording\n'},
      ]),
      cloudContent: jsonEncode(<Map<String, dynamic>>[
        <String, dynamic>{'insert': 'Cloud wording\n'},
      ]),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                resolvedContent = await showDialog<String>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => NoteConflictResolverDialog(diff: diff),
                );
              },
              child: const Text('Open resolver'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open resolver'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('note-conflict-resolver')), findsOneWidget);
    expect(find.text('KEEP LOCAL'), findsOneWidget);
    expect(find.text('KEEP CLOUD'), findsOneWidget);
    expect(find.text('Change 1'), findsOneWidget);
    expect(find.textContaining('@@'), findsNothing);
    expect(find.text('0 of 1 choices made'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('apply-conflict-resolution')),
          )
          .onPressed,
      isNull,
    );

    final notePreview =
        tester.widgetList<RichText>(find.byType(RichText)).firstWhere(
              (widget) => widget.text.toPlainText().contains('Local wording'),
            );
    expect(notePreview.text.style?.fontFamily, isNot('monospace'));
    expect(
      (notePreview.text as TextSpan)
          .children
          ?.whereType<TextSpan>()
          .any((span) => span.style?.backgroundColor != null),
      isTrue,
    );

    await tester.tap(find.text('KEEP CLOUD'));
    await tester.pump();
    expect(find.text('1 of 1 choices made'), findsOneWidget);

    await tester.tap(find.byKey(const Key('apply-conflict-resolution')));
    await tester.pumpAndSettle();

    expect(resolvedContent, contains('Cloud wording'));
    expect(resolvedContent, isNot(contains('Local wording')));
  });
}
