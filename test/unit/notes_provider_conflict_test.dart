import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typesync/core/models/note.dart';
import 'package:typesync/core/providers/notes_provider.dart';

String _content(String text) => jsonEncode(<Map<String, dynamic>>[
      <String, dynamic>{'insert': '$text\n'},
    ]);

void main() {
  late Directory hiveDirectory;
  late NotesProvider provider;
  const userId = 'conflict-provider-test-user';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    hiveDirectory = await Directory.systemTemp.createTemp(
      'typesync-conflict-provider-',
    );
    Hive.init(hiveDirectory.path);
  });

  setUp(() async {
    provider = NotesProvider();
    await provider.initialize(userId);
  });

  tearDown(() async {
    await Hive.box<Note>('notes_$userId').clear();
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('keeps post-conflict typing and rejects a stale cloud resolution',
      () async {
    final original = await provider.createNote(
      userId: userId,
      content: _content('locally saved'),
    );
    expect(original, isNotNull);

    final firstCloudContent = _content('first cloud edit');
    provider.handleSingleCloudNoteUpdate(
      original!.copyWith(
        content: firstCloudContent,
        updatedAt: original.updatedAt.add(const Duration(minutes: 1)),
        isDirty: false,
      ),
    );
    expect(provider.getNoteById(original.id)?.hasConflict, isTrue);

    final latestLocalContent = _content('typed after the banner appeared');
    await provider.saveConflictedNoteDraft(
      noteId: original.id,
      content: latestLocalContent,
      characterCount: 31,
      lineCount: 1,
    );

    final savedDraft = provider.getNoteById(original.id)!;
    expect(savedDraft.content, latestLocalContent);
    expect(savedDraft.conflictContent, firstCloudContent);
    expect(savedDraft.hasConflict, isTrue);

    final newerCloudContent = _content('newer cloud edit');
    provider.handleSingleCloudNoteUpdate(
      original.copyWith(
        content: newerCloudContent,
        updatedAt: DateTime.now().add(const Duration(minutes: 2)),
        isDirty: false,
      ),
    );

    final staleResolutionApplied = await provider.resolveConflictWithContent(
      noteId: original.id,
      resolvedContent: latestLocalContent,
      expectedCloudContent: firstCloudContent,
    );
    expect(staleResolutionApplied, isFalse);
    expect(provider.getNoteById(original.id)?.hasConflict, isTrue);
    expect(provider.getNoteById(original.id)?.content, latestLocalContent);
    expect(
      provider.getNoteById(original.id)?.conflictContent,
      newerCloudContent,
    );

    final currentResolutionApplied = await provider.resolveConflictWithContent(
      noteId: original.id,
      resolvedContent: latestLocalContent,
      expectedCloudContent: newerCloudContent,
    );
    expect(currentResolutionApplied, isTrue);
    expect(provider.getNoteById(original.id)?.hasConflict, isFalse);
    expect(provider.getNoteById(original.id)?.content, latestLocalContent);
  });
}
