/// Synced attachment display preferences.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sync_service.dart';

/// The attachment UI choices associated with one note.
class AttachmentPreferences {
  const AttachmentPreferences({
    this.expanded = false,
    this.previewHidden = false,
  });

  final bool expanded;
  final bool previewHidden;

  Map<String, bool> toJson() => {
        'expanded': expanded,
        'previewHidden': previewHidden,
      };

  factory AttachmentPreferences.fromJson(Map<dynamic, dynamic> json) {
    return AttachmentPreferences(
      expanded: json['expanded'] as bool? ?? false,
      previewHidden: json['previewHidden'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AttachmentPreferences &&
      other.expanded == expanded &&
      other.previewHidden == previewHidden;

  @override
  int get hashCode => Object.hash(expanded, previewHidden);
}

/// Stores attachment display choices locally and in the user's synced settings.
class AttachmentPreferencesService extends ChangeNotifier {
  static const _storageKey = 'typesync_attachment_preferences_v1';
  static const _legacyExpandedPrefix = 'typesync_editor_attachments_expanded_';
  static const _legacyPreviewHiddenPrefix =
      'typesync_editor_attachments_preview_hidden_';
  static const _cloudKey = 'attachmentPreferences';

  final Map<String, AttachmentPreferences> _preferences = {};
  Future<void>? _loadFuture;
  SyncService? _syncService;

  void setSyncService(SyncService? service) {
    _syncService = service;
  }

  AttachmentPreferences preferencesFor(String? noteId) {
    if (noteId == null || noteId.isEmpty) {
      return const AttachmentPreferences();
    }
    return _preferences[noteId] ?? const AttachmentPreferences();
  }

  Future<void> load() => _loadFuture ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null || stored.isEmpty) return;

      final decoded = jsonDecode(stored);
      if (decoded is! Map) return;

      for (final entry in decoded.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        // A cloud update may arrive before local loading finishes. Keep that
        // newer value rather than letting the cache overwrite it.
        _preferences.putIfAbsent(
          entry.key as String,
          () => AttachmentPreferences.fromJson(entry.value as Map),
        );
      }
      notifyListeners();
    } catch (error) {
      debugPrint('Failed to load attachment preferences: $error');
    }
  }

  /// Imports a note's old device-only values the first time it is opened.
  Future<void> migrateLegacyPreferences(String noteId) async {
    await load();
    if (_preferences.containsKey(noteId)) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final expanded = prefs.getBool('$_legacyExpandedPrefix$noteId');
      final previewHidden = prefs.getBool('$_legacyPreviewHiddenPrefix$noteId');
      if (expanded == null && previewHidden == null) return;

      await update(
        noteId,
        AttachmentPreferences(
          expanded: expanded ?? false,
          previewHidden: previewHidden ?? false,
        ),
      );
    } catch (error) {
      debugPrint('Failed to migrate attachment preferences: $error');
    }
  }

  Future<void> update(String noteId, AttachmentPreferences preferences) async {
    await load();
    if (_preferences[noteId] == preferences) return;

    _preferences[noteId] = preferences;
    await _saveLocal();
    notifyListeners();
    await _syncToCloud();
  }

  /// Applies the complete cloud snapshot received through [SyncService].
  void handleCloudSettings(Map<String, dynamic> settings) {
    final rawPreferences = settings[_cloudKey];
    if (rawPreferences is! Map) return;

    final incoming = <String, AttachmentPreferences>{};
    for (final entry in rawPreferences.entries) {
      if (entry.key is! String || entry.value is! Map) continue;
      incoming[entry.key as String] =
          AttachmentPreferences.fromJson(entry.value as Map);
    }

    if (mapEquals(_preferences, incoming)) return;
    _preferences
      ..clear()
      ..addAll(incoming);
    unawaited(_saveLocal());
    notifyListeners();
  }

  Future<void> _saveLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode(
          _preferences.map(
            (noteId, preference) => MapEntry(
              noteId,
              preference.toJson(),
            ),
          ),
        ),
      );
    } catch (error) {
      debugPrint('Failed to save attachment preferences: $error');
    }
  }

  Future<void> _syncToCloud() async {
    final syncService = _syncService;
    if (syncService == null) return;

    await syncService.syncSettings({
      _cloudKey: _preferences.map(
        (noteId, preference) => MapEntry(noteId, preference.toJson()),
      ),
    });
  }
}
