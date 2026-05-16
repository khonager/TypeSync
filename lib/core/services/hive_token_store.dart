import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:firedart/firedart.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A TokenStore implementation for Firedart using Hive
///
/// This provides persistent storage for Firedart authentication tokens
/// across app restarts on platforms like Linux.
class HiveTokenStore extends TokenStore {
  static const String _boxName = 'firedart_token_box';
  static const String _key = 'token_key';

  final Box<dynamic> _box;

  HiveTokenStore._(this._box) : super();

  /// Initialize and open the Hive box before returning the store
  ///
  /// Returns a [HiveTokenStore] if successful, or a [MemoryTokenStore]
  /// if Hive initialization fails (e.g. lock file error).
  static Future<TokenStore> create() async {
    try {
      final box = await Hive.openBox<dynamic>(_boxName);
      return HiveTokenStore._(box);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'HiveTokenStore initialization failed; falling back to SharedPreferences token store: $e',
        );
      }
      return SharedPreferencesTokenStore.create();
    }
  }

  @override
  Token? read() {
    final dynamic map = _box.get(_key);
    if (map != null) {
      try {
        final stringMap =
            Map<String, dynamic>.from(map as Map<dynamic, dynamic>);
        return Token.fromMap(stringMap);
      } catch (e) {
        // If the token format is invalid, disregard it
        return null;
      }
    }
    return null;
  }

  @override
  void write(Token? token) {
    if (token != null) {
      _box.put(_key, token.toMap());
    } else {
      _box.delete(_key);
    }
  }

  @override
  void delete() {
    _box.delete(_key);
  }
}

/// A fallback TokenStore that keeps tokens in memory only.
///
/// Used when persistent storage fails (e.g. Hive lock error).
class MemoryTokenStore extends TokenStore {
  Token? _token;

  @override
  Token? read() => _token;

  @override
  void write(Token? token) => _token = token;

  @override
  void delete() => _token = null;
}

/// A multi-process-friendly TokenStore backed by SharedPreferences.
///
/// Hive boxes can be file-locked by another TypeSync process on Linux, which
/// would otherwise force a volatile memory-only token store and show users as
/// signed out in secondary instances.
class SharedPreferencesTokenStore extends TokenStore {
  static const String _prefsKey = 'firedart_token_json';

  final SharedPreferences _prefs;

  SharedPreferencesTokenStore._(this._prefs);

  static Future<SharedPreferencesTokenStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SharedPreferencesTokenStore._(prefs);
  }

  @override
  Token? read() {
    final raw = _prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = _decodeTokenJson(raw);
      if (decoded == null) {
        return null;
      }
      return Token.fromMap(decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  void write(Token? token) {
    if (token == null) {
      _prefs.remove(_prefsKey);
      return;
    }
    final json = _encodeTokenJson(token.toMap());
    if (json == null) {
      return;
    }
    _prefs.setString(_prefsKey, json);
  }

  @override
  void delete() {
    _prefs.remove(_prefsKey);
  }

  Map<String, dynamic>? _decodeTokenJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return Map<String, dynamic>.from(decoded as Map);
    } catch (_) {
      return null;
    }
  }

  String? _encodeTokenJson(Map<String, dynamic> data) {
    try {
      return jsonEncode(data);
    } catch (_) {
      return null;
    }
  }
}
