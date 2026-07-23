import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typesync/firebase_options.dart';

const String _expectedUserKey = 'auth_persistence_probe_expected_user';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var status = 'FAIL';
  var detail = 'Probe did not run';

  try {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw StateError('This probe must run on an Android emulator.');
    }

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    final auth = FirebaseAuth.instance;
    await auth.useAuthEmulator('10.0.2.2', 9099);

    final preferences = await SharedPreferences.getInstance();
    final expectedUserId = preferences.getString(_expectedUserKey);
    final restoredUserId = auth.currentUser?.uid;

    if (expectedUserId == null) {
      if (auth.currentUser != null) {
        await auth.signOut();
      }
      final credential = await auth.signInAnonymously();
      final userId = credential.user?.uid;
      if (userId == null) {
        throw StateError('The Auth emulator returned no user.');
      }

      await preferences.setString(_expectedUserKey, userId);
      status = 'READY';
      detail = 'Signed in; force-stop and relaunch the process';
      debugPrint('AUTH_PERSISTENCE_PROBE:READY uid=$userId');
    } else if (restoredUserId == expectedUserId) {
      status = 'PASS';
      detail = 'Firebase restored the same user after a cold process restart';
      debugPrint('AUTH_PERSISTENCE_PROBE:PASS uid=$restoredUserId');
    } else {
      status = 'FAIL';
      detail = 'Expected $expectedUserId but Firebase restored $restoredUserId';
      debugPrint(
        'AUTH_PERSISTENCE_PROBE:FAIL '
        'expected=$expectedUserId actual=$restoredUserId',
      );
    }
  } catch (error, stackTrace) {
    detail = error.toString();
    debugPrint('AUTH_PERSISTENCE_PROBE:FAIL error=$error');
    debugPrintStack(stackTrace: stackTrace);
  }

  runApp(_ProbeApp(status: status, detail: detail));
}

class _ProbeApp extends StatelessWidget {
  const _ProbeApp({
    required this.status,
    required this.detail,
  });

  final String status;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final passed = status == 'PASS';
    final ready = status == 'READY';

    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  passed
                      ? Icons.check_circle
                      : ready
                          ? Icons.restart_alt
                          : Icons.error,
                  size: 72,
                  color: passed
                      ? Colors.green
                      : ready
                          ? Colors.blue
                          : Colors.red,
                ),
                const SizedBox(height: 16),
                Text(
                  'AUTH PERSISTENCE $status',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(detail, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
