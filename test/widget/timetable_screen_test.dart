import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:typesync/core/providers/timetable_provider.dart';
import 'package:typesync/core/services/auth_service.dart';
import 'package:typesync/core/services/sync_service.dart';
import 'package:typesync/features/timetable/screens/timetable_screen.dart';

class _SignedOutAuthService extends AuthService {
  @override
  String? get storageUserId => null;

  @override
  String? get userId => null;

  @override
  bool get effectiveSyncEnabled => false;
}

class _LocalAuthService extends _SignedOutAuthService {
  @override
  String? get storageUserId => 'widget-user';
}

class _TestTimetableProvider extends TimetableProvider {
  @override
  Future<void> initialize(String userId) async {}
}

void main() {
  Future<void> pumpTimetable(WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => TimetableProvider()),
          ChangeNotifierProvider<AuthService>(
            create: (_) => _SignedOutAuthService(),
          ),
          ChangeNotifierProvider(create: (_) => SyncService()),
        ],
        child: const MaterialApp(home: TimetableScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('selected classes fill their time in a constrained editor', (
    tester,
  ) async {
    await pumpTimetable(tester);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.tap(
      find
          .ancestor(
            of: find.text('Select one or more classes to set the time'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, '2'));
    await tester.tap(find.widgetWithText(FilterChip, '3'));
    await tester.tap(find.widgetWithText(FilterChip, '4'));
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(find.text('1, 2, 3, 4'), findsOneWidget);
    expect(find.text('Starts 08:00'), findsOneWidget);
    expect(find.text('Ends 11:15'), findsOneWidget);
  });

  testWidgets('tapping outside closes the editor', (tester) async {
    await pumpTimetable(tester);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('Add Class'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Add Class'), findsNothing);
  });

  testWidgets('dragging down closes the editor', (tester) async {
    await pumpTimetable(tester);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.drag(find.text('Add Class'), const Offset(0, 500));
    await tester.pumpAndSettle();

    expect(find.text('Add Class'), findsNothing);
  });

  testWidgets('tapping outside flushes the latest live edit', (tester) async {
    tester.view.physicalSize = const Size(500, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = _TestTimetableProvider();
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TimetableProvider>.value(value: provider),
          ChangeNotifierProvider<AuthService>(
            create: (_) => _LocalAuthService(),
          ),
          ChangeNotifierProvider(create: (_) => SyncService()),
        ],
        child: const MaterialApp(home: TimetableScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Biology');

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(provider.entries.single.subject, 'Biology');
    expect(provider.entries.single.classSlot, 1);
    expect(provider.entries.single.startTimeFormatted, '08:00');
    expect(provider.entries.single.endTimeFormatted, '08:45');
  });
}
