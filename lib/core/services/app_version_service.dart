/// Runtime app version lookup with compile-time fallback.
library;

import 'package:package_info_plus/package_info_plus.dart';

import '../utils/version_compatibility.dart';

class AppVersionInfo {
  final String version;
  final String buildNumber;

  const AppVersionInfo({
    required this.version,
    required this.buildNumber,
  });

  String get normalizedVersion => VersionCompatibility.normalize(version);

  String get displayLabel => '$version ($buildNumber)';
}

class AppVersionService {
  static const AppVersionService instance = AppVersionService._();

  const AppVersionService._();

  Future<AppVersionInfo> load() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final version = packageInfo.version.trim().isEmpty
          ? kCurrentAppVersion
          : packageInfo.version.trim();
      final buildNumber = packageInfo.buildNumber.trim().isEmpty
          ? kCurrentBuildNumber
          : packageInfo.buildNumber.trim();
      return AppVersionInfo(
        version: version,
        buildNumber: buildNumber,
      );
    } catch (_) {
      return const AppVersionInfo(
        version: kCurrentAppVersion,
        buildNumber: kCurrentBuildNumber,
      );
    }
  }
}
