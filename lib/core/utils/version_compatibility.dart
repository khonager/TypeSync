/// Helpers for semantic version compatibility checks.
library;

/// Current app version used for note compatibility checks.
///
/// Override with `--dart-define=TYPESYNC_APP_VERSION=x.y.z` in CI/release
/// pipelines. The default should match `pubspec.yaml`.
const String kCurrentAppVersion = String.fromEnvironment(
  'TYPESYNC_APP_VERSION',
  defaultValue: '1.1.0',
);

/// Utilities for semantic version comparisons.
class VersionCompatibility {
  /// Returns:
  /// - `< 0` when [left] is older than [right]
  /// - `0` when equal
  /// - `> 0` when [left] is newer than [right]
  static int compare(String left, String right) {
    final leftParts = _parse(left);
    final rightParts = _parse(right);
    final maxLength = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;

    for (var i = 0; i < maxLength; i++) {
      final leftValue = i < leftParts.length ? leftParts[i] : 0;
      final rightValue = i < rightParts.length ? rightParts[i] : 0;
      if (leftValue != rightValue) {
        return leftValue.compareTo(rightValue);
      }
    }
    return 0;
  }

  static bool isAtLeast({
    required String current,
    required String minimum,
  }) {
    return compare(current, minimum) >= 0;
  }

  static String normalize(String raw) {
    final parts = _parse(raw);
    final major = parts.isNotEmpty ? parts[0] : 0;
    final minor = parts.length > 1 ? parts[1] : 0;
    final patch = parts.length > 2 ? parts[2] : 0;
    return '$major.$minor.$patch';
  }

  static List<int> _parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const [0, 0, 0];
    }

    final core = trimmed.split('+').first.split('-').first;
    final segments = core.split('.');
    final parsed = <int>[];

    for (final segment in segments) {
      final match = RegExp(r'\d+').stringMatch(segment);
      parsed.add(int.tryParse(match ?? '') ?? 0);
    }

    while (parsed.length < 3) {
      parsed.add(0);
    }

    return parsed;
  }
}
