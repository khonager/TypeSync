/// Changelog loader for in-app release notes.
library;

import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/app_changelog.dart';
import '../utils/version_compatibility.dart';

class ChangelogService {
  static const String _assetPath = 'assets/data/changelog.json';

  const ChangelogService();

  Future<AppChangelog> load() async {
    try {
      final jsonString = await rootBundle.loadString(_assetPath);
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      final parsed = AppChangelog.fromJson(decoded);
      if (parsed.releases.isEmpty) {
        return AppChangelog.fallback(kCurrentAppVersion);
      }
      return parsed;
    } catch (_) {
      return AppChangelog.fallback(kCurrentAppVersion);
    }
  }
}
