import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typesync/core/routes/app_router.dart';
import 'package:typesync/core/services/navigation_state_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('restores an editor destination only for its workspace', () async {
    final service = NavigationStateService.instance;
    await service.activate('workspace-a');
    service.recordRoute(
      const RouteSettings(
        name: AppRouter.editor,
        arguments: <String, dynamic>{
          'noteId': 'note-42',
          'folderId': 'folder-7',
        },
      ),
    );

    final otherWorkspace = await service.activate('workspace-b');
    expect(otherWorkspace.routeName, AppRouter.home);

    final restored = await service.activate('workspace-a');
    expect(restored.routeName, AppRouter.editor);
    expect(restored.noteId, 'note-42');
    expect(restored.folderId, 'folder-7');
  });

  test('home state can return from a folder to the root', () async {
    final service = NavigationStateService.instance;
    await service.activate('workspace-home');
    service.recordHomeState(tab: 'profile', folderId: 'folder-7');
    await service.activate('flush-one');
    expect(
      (await service.activate('workspace-home')).homeFolderId,
      'folder-7',
    );

    service.recordHomeState(tab: 'files');
    await service.activate('flush-two');
    final restored = await service.activate('workspace-home');
    expect(restored.routeName, AppRouter.home);
    expect(restored.homeFolderId, isNull);
    expect(restored.homeTab, 'files');
  });
}
