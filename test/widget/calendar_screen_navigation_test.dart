import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:typesync/core/providers/calendar_provider.dart';
import 'package:typesync/core/services/auth_service.dart';
import 'package:typesync/core/services/sync_service.dart';
import 'package:typesync/features/calendar/screens/calendar_screen.dart';

class _SignedOutAuthService extends AuthService {
  @override
  String? get storageUserId => null;

  @override
  String? get userId => null;

  @override
  bool get effectiveSyncEnabled => false;
}

void main() {
  testWidgets('calendar route focuses and selects an event start date',
      (tester) async {
    final eventStart = DateTime(2026, 9, 29, 14, 30);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => CalendarProvider()),
          ChangeNotifierProvider<AuthService>(
            create: (_) => _SignedOutAuthService(),
          ),
          ChangeNotifierProvider(create: (_) => SyncService()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  settings: RouteSettings(
                    arguments: <String, Object>{'initialDate': eventStart},
                  ),
                  builder: (_) => const CalendarScreen(),
                ),
              ),
              child: const Text('Open event'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open event'));
    await tester.pumpAndSettle();

    expect(find.text('September 2026'), findsOneWidget);
    expect(find.text('Events on Tue, 29 Sep 2026'), findsOneWidget);
  });
}
