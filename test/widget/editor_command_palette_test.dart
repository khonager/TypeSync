import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/core/models/editor_command.dart';
import 'package:typesync/features/editor/utils/editor_command_expansion.dart';
import 'package:typesync/features/editor/widgets/editor_command_palette.dart';

void main() {
  const commands = [
    EditorCommand(trigger: '/daily', template: 'Daily template preview'),
    EditorCommand(trigger: '/date', template: 'Date template preview'),
  ];

  testWidgets('shows filtered commands and a template preview', (tester) async {
    EditorCommand? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: EditorCommandPalette(
              state: const EditorCommandMenuState(
                start: 0,
                length: 3,
                query: '/da',
                matches: commands,
              ),
              onSelected: (command) => selected = command,
            ),
          ),
        ),
      ),
    );

    expect(find.text('/daily'), findsOneWidget);
    expect(find.text('/date'), findsOneWidget);
    expect(find.text('Daily template preview'), findsOneWidget);
    expect(find.text('Template preview'), findsOneWidget);

    await tester.tap(find.text('/date'));
    expect(selected?.trigger, '/date');
  });

  testWidgets('explains that enter inserts an exact match', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorCommandPalette(
            state: const EditorCommandMenuState(
              start: 0,
              length: 5,
              query: '/daily',
              matches: [
                EditorCommand(
                  trigger: '/daily',
                  template: 'Daily template preview',
                ),
              ],
            ),
            onSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Press Enter to insert'), findsOneWidget);
    expect(find.text('Daily template preview'), findsOneWidget);
  });
}
