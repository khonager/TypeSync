library;

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typesync/core/services/auth_persistence_diagnostics.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    PackageInfo.setMockInitialValues(
      appName: 'TypeSync',
      packageName: 'de.khonager.typesync',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: 'test',
    );
  });

  test('detects native session loss while ordinary app storage survives',
      () async {
    final firstLaunch = AuthPersistenceDiagnostics.forTesting(
      installationIdFactory: () => 'installation-1',
    );
    await firstLaunch.initialize();
    await firstLaunch.markSignedIn('firebase-user-12345678');

    final coldRestart = AuthPersistenceDiagnostics.forTesting(
      installationIdFactory: () => 'must-not-be-used',
    );
    await coldRestart.initialize();
    coldRestart.recordNativeAuthState(null);

    expect(coldRestart.launchCount, 2);
    expect(coldRestart.suspectedUnexpectedSignOut, isTrue);
    expect(
      coldRestart.exportText(),
      contains('UNEXPECTED_SIGN_OUT'),
    );
    expect(
      coldRestart.exportText(),
      contains('storageSurvived=true'),
    );
  });

  test('does not report session loss when Firebase restores the expected user',
      () async {
    final diagnostics = AuthPersistenceDiagnostics.forTesting(
      installationIdFactory: () => 'installation-1',
    );
    await diagnostics.initialize();
    await diagnostics.markSignedIn('firebase-user-12345678');
    diagnostics.recordNativeAuthState('firebase-user-12345678');

    expect(diagnostics.suspectedUnexpectedSignOut, isFalse);

    await diagnostics.markExplicitlySignedOut(reason: 'test');
    expect(diagnostics.suspectedUnexpectedSignOut, isFalse);
  });
}
