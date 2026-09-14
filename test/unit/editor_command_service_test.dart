import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typesync/core/services/editor_command_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('normalizes, saves, and resolves a custom command', () async {
    final service = EditorCommandService();
    await Future<void>.delayed(Duration.zero);

    final error = await service.saveCommand(
      trigger: 'LIST',
      template: 'One\nTwo',
    );

    expect(error, isNull);
    expect(service.commands.single.trigger, '/list');
    expect(service.commandForTrigger('/LIST')?.template, 'One\nTwo');
  });

  test('rejects invalid and duplicate triggers', () async {
    final service = EditorCommandService();
    await Future<void>.delayed(Duration.zero);

    expect(
      await service.saveCommand(trigger: 'bad name', template: 'Text'),
      isNotNull,
    );
    expect(
      await service.saveCommand(trigger: '/valid', template: 'Text'),
      isNull,
    );
    expect(
      await service.saveCommand(trigger: 'VALID', template: 'Other'),
      'That command already exists.',
    );
  });
}
