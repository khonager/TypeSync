library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// A small, persistent audit trail for diagnosing native Firebase Auth session
/// restoration across full process restarts.
///
/// This intentionally stores only a Firebase UID marker, app metadata, and
/// state transitions. Passwords, ID tokens, refresh tokens, and API keys are
/// never recorded.
class AuthPersistenceDiagnostics extends ChangeNotifier {
  AuthPersistenceDiagnostics._({
    String Function()? installationIdFactory,
  }) : _installationIdFactory =
            installationIdFactory ?? (() => const Uuid().v4());

  static final AuthPersistenceDiagnostics instance =
      AuthPersistenceDiagnostics._();

  @visibleForTesting
  factory AuthPersistenceDiagnostics.forTesting({
    String Function()? installationIdFactory,
  }) {
    return AuthPersistenceDiagnostics._(
      installationIdFactory: installationIdFactory,
    );
  }

  static const String _eventsKey = 'auth_persistence_diagnostics_events_v1';
  static const String _installationIdKey =
      'auth_persistence_diagnostics_installation_id_v1';
  static const String _launchCountKey =
      'auth_persistence_diagnostics_launch_count_v1';
  static const String _expectedUserIdKey =
      'auth_persistence_expected_user_id_v1';
  static const int _maxEvents = 80;

  final String Function() _installationIdFactory;
  final List<String> _events = [];

  SharedPreferences? _preferences;
  Future<void> _writeQueue = Future<void>.value();
  String? _installationId;
  String? _expectedUserId;
  String? _initialNativeUserId;
  int _launchCount = 0;
  bool _initialNativeAuthStateRecorded = false;
  bool _initialized = false;

  bool get isInitialized => _initialized;
  int get launchCount => _launchCount;

  /// True when ordinary app storage survived the restart but native Firebase
  /// Auth returned no user even though the previous session was signed in.
  bool get suspectedUnexpectedSignOut =>
      _initialNativeAuthStateRecorded &&
      _initialNativeUserId == null &&
      _expectedUserId != null;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final preferences = await SharedPreferences.getInstance();
      _preferences = preferences;
      _events
        ..clear()
        ..addAll(preferences.getStringList(_eventsKey) ?? const []);

      _installationId = preferences.getString(_installationIdKey);
      if (_installationId == null || _installationId!.isEmpty) {
        _installationId = _installationIdFactory();
        await preferences.setString(_installationIdKey, _installationId!);
      }

      _launchCount = (preferences.getInt(_launchCountKey) ?? 0) + 1;
      await preferences.setInt(_launchCountKey, _launchCount);
      _expectedUserId = preferences.getString(_expectedUserIdKey);
      _initialized = true;

      PackageInfo? packageInfo;
      try {
        packageInfo = await PackageInfo.fromPlatform();
      } catch (error) {
        _append('Package metadata unavailable: $error');
      }

      _append(
        'PROCESS_START launch=$_launchCount '
        'install=${_shortValue(_installationId)} '
        'package=${packageInfo?.packageName ?? 'unknown'} '
        'version=${packageInfo?.version ?? 'unknown'}+'
        '${packageInfo?.buildNumber ?? 'unknown'} '
        'platform=${defaultTargetPlatform.name} '
        'expectedUser=${_userLabel(_expectedUserId)}',
      );
    } catch (error) {
      _initialized = true;
      _append('Diagnostics initialization failed: $error');
    }
  }

  void recordFirebaseInitialization({
    required bool succeeded,
    String? appName,
    String? appId,
    String? projectId,
    Object? error,
  }) {
    _append(
      'FIREBASE_INIT success=$succeeded '
      'app=${appName ?? 'none'} '
      'appId=${appId ?? 'none'} '
      'project=${projectId ?? 'none'}'
      '${error == null ? '' : ' error=$error'}',
    );
  }

  /// Records only the first native Auth state observed in this process. Later
  /// state changes remain in the event trail but do not affect startup-loss
  /// detection.
  void recordNativeAuthState(String? userId) {
    if (!_initialNativeAuthStateRecorded) {
      _initialNativeAuthStateRecorded = true;
      _initialNativeUserId = userId;
      _append(
        'NATIVE_AUTH_INITIAL user=${_userLabel(userId)} '
        'expectedUser=${_userLabel(_expectedUserId)} '
        'storageSurvived=${_launchCount > 1}',
      );

      if (suspectedUnexpectedSignOut) {
        _append(
          'UNEXPECTED_SIGN_OUT native Firebase user is null while the '
          'persisted signed-in marker and ordinary app storage survived',
        );
      }
      return;
    }

    _append('NATIVE_AUTH_CHANGED user=${_userLabel(userId)}');
  }

  Future<void> markSignedIn(String userId) async {
    _expectedUserId = userId;
    try {
      final preferences = _preferences ?? await SharedPreferences.getInstance();
      _preferences = preferences;
      await preferences.setString(_expectedUserIdKey, userId);
    } catch (error) {
      _append('Failed to persist signed-in marker: $error');
    }
    _append('SESSION_EXPECTED user=${_userLabel(userId)}');
    notifyListeners();
  }

  Future<void> markExplicitlySignedOut({required String reason}) async {
    final previousUserId = _expectedUserId;
    _expectedUserId = null;
    try {
      final preferences = _preferences ?? await SharedPreferences.getInstance();
      _preferences = preferences;
      await preferences.remove(_expectedUserIdKey);
    } catch (error) {
      _append('Failed to clear signed-in marker: $error');
    }
    _append(
      'SESSION_CLEARED reason=$reason '
      'previousUser=${_userLabel(previousUserId)}',
    );
    notifyListeners();
  }

  String exportText() {
    final summary = [
      'TypeSync authentication persistence report',
      'launchCount=$_launchCount',
      'install=${_shortValue(_installationId)}',
      'expectedUser=${_userLabel(_expectedUserId)}',
      'initialNativeUser=${_userLabel(_initialNativeUserId)}',
      'suspectedUnexpectedSignOut=$suspectedUnexpectedSignOut',
      '',
    ];

    return [...summary, ..._events].join('\n');
  }

  void _append(String message) {
    final line = '[${DateTime.now().toIso8601String()}] $message';
    _events.add(line);
    if (_events.length > _maxEvents) {
      _events.removeRange(0, _events.length - _maxEvents);
    }

    debugPrint('[AUTH_PERSISTENCE] $message');
    notifyListeners();

    final preferences = _preferences;
    if (preferences != null) {
      final snapshot = List<String>.of(_events);
      _writeQueue = _writeQueue.then(
        (_) async {
          await preferences.setStringList(_eventsKey, snapshot);
        },
      ).catchError((Object error, StackTrace stackTrace) {
        debugPrint(
          '[AUTH_PERSISTENCE] Failed to persist diagnostics: $error',
        );
      });
    }
  }

  String _userLabel(String? userId) {
    if (userId == null || userId.isEmpty) return 'none';
    return _shortValue(userId);
  }

  String _shortValue(String? value) {
    if (value == null || value.isEmpty) return 'none';
    if (value.length <= 8) return value;
    return '...${value.substring(value.length - 8)}';
  }
}
