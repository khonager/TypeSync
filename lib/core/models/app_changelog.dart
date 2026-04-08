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
          notes: const <String>[
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
  final List<String> important;
  final List<String> newFeatures;
  final List<String> fixesImprovements;
  final List<String> notes;

  const ChangelogRelease({
    required this.version,
    required this.date,
    required this.title,
    this.important = const <String>[],
    this.newFeatures = const <String>[],
    this.fixesImprovements = const <String>[],
    this.notes = const <String>[],
  });

  factory ChangelogRelease.fromJson(Map<String, dynamic> json) {
    final legacyChanges =
        (json['changes'] as List<dynamic>? ?? const <dynamic>[])
            .map((change) => change.toString())
            .where((change) => change.trim().isNotEmpty)
            .toList();

    return ChangelogRelease(
      version: json['version'] as String? ?? '',
      date: json['date'] as String? ?? '',
      title: json['title'] as String? ?? '',
      important: (json['important'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(),
      newFeatures: (json['newFeatures'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(),
      fixesImprovements:
          (json['fixesImprovements'] as List<dynamic>? ?? const <dynamic>[])
              .map((change) => change.toString())
              .where((change) => change.trim().isNotEmpty)
              .toList()
            ..addAll(legacyChanges),
      notes: (json['notes'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(),
    );
  }
}
