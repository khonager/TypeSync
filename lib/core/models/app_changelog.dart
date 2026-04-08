/// Structured changelog payload loaded from app assets.
library;

class AppChangelog {
  final int schemaVersion;
  final String latestVersion;
  final List<ChangelogRelease> releases;

  const AppChangelog({
    required this.schemaVersion,
    required this.latestVersion,
    required this.releases,
  });

  factory AppChangelog.fromJson(Map<String, dynamic> json) {
    return AppChangelog(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      latestVersion: json['latestVersion'] as String? ?? '',
      releases: (json['releases'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (release) =>
                ChangelogRelease.fromJson(Map<String, dynamic>.from(release)),
          )
          .toList(),
    );
  }

  factory AppChangelog.fallback(String version) {
    return AppChangelog(
      schemaVersion: 1,
      latestVersion: version,
      releases: <ChangelogRelease>[
        ChangelogRelease(
          version: version,
          date: '',
          title: 'Current release',
          changes: const <String>[
            'Changelog data is unavailable in this build.',
          ],
        ),
      ],
    );
  }
}

class ChangelogRelease {
  final String version;
  final String date;
  final String title;
  final List<String> changes;

  const ChangelogRelease({
    required this.version,
    required this.date,
    required this.title,
    required this.changes,
  });

  factory ChangelogRelease.fromJson(Map<String, dynamic> json) {
    return ChangelogRelease(
      version: json['version'] as String? ?? '',
      date: json['date'] as String? ?? '',
      title: json['title'] as String? ?? '',
      changes: (json['changes'] as List<dynamic>? ?? const <dynamic>[])
          .map((change) => change.toString())
          .where((change) => change.trim().isNotEmpty)
          .toList(),
    );
  }
}
