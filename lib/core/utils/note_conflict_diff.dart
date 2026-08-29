/// Line-based conflict detection and rich-text-safe resolution for notes.
library;

import 'dart:convert';

enum NoteConflictChoice { local, cloud }

class NoteConflictSection {
  const NoteConflictSection({
    required this.isConflict,
    required this.localLines,
    required this.cloudLines,
    required this.localStartLine,
    required this.cloudStartLine,
  });

  final bool isConflict;
  final List<NoteConflictLine> localLines;
  final List<NoteConflictLine> cloudLines;
  final int localStartLine;
  final int cloudStartLine;
}

class NoteConflictLine {
  const NoteConflictLine({
    required this.operations,
    required this.text,
    required this.signature,
  });

  final List<Map<String, dynamic>> operations;
  final String text;
  final String signature;
}

class NoteConflictDiff {
  NoteConflictDiff._({
    required this.sections,
  });

  factory NoteConflictDiff.fromContents({
    required String localContent,
    required String cloudContent,
  }) {
    final localLines = _parseLines(localContent);
    final cloudLines = _parseLines(cloudContent);
    return NoteConflictDiff._(
      sections: _buildSections(localLines, cloudLines),
    );
  }

  final List<NoteConflictSection> sections;

  int get conflictCount =>
      sections.where((section) => section.isConflict).length;

  /// Whether two stored note documents render and format identically.
  ///
  /// Quill may split the same text into a different number of adjacent insert
  /// operations while typing. Comparing the raw JSON would incorrectly treat
  /// those storage-only differences as a conflict.
  static bool contentsEquivalent(String first, String second) {
    final firstLines = _parseLines(first);
    final secondLines = _parseLines(second);
    if (firstLines.length != secondLines.length) return false;
    for (var index = 0; index < firstLines.length; index++) {
      if (firstLines[index].signature != secondLines[index].signature) {
        return false;
      }
    }
    return true;
  }

  String resolve(List<NoteConflictChoice> choices) {
    if (choices.length != conflictCount) {
      throw ArgumentError.value(
        choices.length,
        'choices',
        'Expected one choice for each of the $conflictCount conflicts.',
      );
    }

    final operations = <Map<String, dynamic>>[];
    var choiceIndex = 0;
    for (final section in sections) {
      final selectedLines = section.isConflict
          ? (choices[choiceIndex++] == NoteConflictChoice.local
              ? section.localLines
              : section.cloudLines)
          : section.localLines;
      for (final line in selectedLines) {
        operations.addAll(
          line.operations
              .map((operation) => Map<String, dynamic>.from(operation)),
        );
      }
    }

    if (operations.isEmpty) {
      operations.add(<String, dynamic>{'insert': '\n'});
    } else if (!_endsWithNewline(operations)) {
      operations.add(<String, dynamic>{'insert': '\n'});
    }

    return jsonEncode(operations);
  }
}

enum _LineDiffKind { equal, local, cloud }

class _LineDiffEntry {
  const _LineDiffEntry(this.kind, {this.localLine, this.cloudLine});

  final _LineDiffKind kind;
  final NoteConflictLine? localLine;
  final NoteConflictLine? cloudLine;
}

List<NoteConflictSection> _buildSections(
  List<NoteConflictLine> localLines,
  List<NoteConflictLine> cloudLines,
) {
  final entries = _lineDiff(localLines, cloudLines);
  final sections = <NoteConflictSection>[];
  var localLineNumber = 1;
  var cloudLineNumber = 1;
  var index = 0;

  while (index < entries.length) {
    final isConflict = entries[index].kind != _LineDiffKind.equal;
    final localStartLine = localLineNumber;
    final cloudStartLine = cloudLineNumber;
    final localSectionLines = <NoteConflictLine>[];
    final cloudSectionLines = <NoteConflictLine>[];

    while (index < entries.length &&
        (entries[index].kind != _LineDiffKind.equal) == isConflict) {
      final entry = entries[index++];
      if (entry.localLine != null) {
        localSectionLines.add(entry.localLine!);
        localLineNumber++;
      }
      if (entry.cloudLine != null) {
        cloudSectionLines.add(entry.cloudLine!);
        cloudLineNumber++;
      }
    }

    sections.add(
      NoteConflictSection(
        isConflict: isConflict,
        localLines: localSectionLines,
        cloudLines: cloudSectionLines,
        localStartLine: localStartLine,
        cloudStartLine: cloudStartLine,
      ),
    );
  }

  return sections;
}

List<_LineDiffEntry> _lineDiff(
  List<NoteConflictLine> localLines,
  List<NoteConflictLine> cloudLines,
) {
  final localLength = localLines.length;
  final cloudLength = cloudLines.length;

  // Avoid allocating an unbounded LCS matrix for unusually large notes. The
  // changed middle remains one selectable hunk while common edges stay visible.
  if (localLength * cloudLength > 250000) {
    return _largeDocumentDiff(localLines, cloudLines);
  }

  final lcs = List.generate(
    localLength + 1,
    (_) => List<int>.filled(cloudLength + 1, 0),
  );
  for (var localIndex = localLength - 1; localIndex >= 0; localIndex--) {
    for (var cloudIndex = cloudLength - 1; cloudIndex >= 0; cloudIndex--) {
      lcs[localIndex][cloudIndex] = localLines[localIndex].signature ==
              cloudLines[cloudIndex].signature
          ? lcs[localIndex + 1][cloudIndex + 1] + 1
          : (lcs[localIndex + 1][cloudIndex] >= lcs[localIndex][cloudIndex + 1]
              ? lcs[localIndex + 1][cloudIndex]
              : lcs[localIndex][cloudIndex + 1]);
    }
  }

  final result = <_LineDiffEntry>[];
  var localIndex = 0;
  var cloudIndex = 0;
  while (localIndex < localLength && cloudIndex < cloudLength) {
    final localLine = localLines[localIndex];
    final cloudLine = cloudLines[cloudIndex];
    if (localLine.signature == cloudLine.signature) {
      result.add(
        _LineDiffEntry(
          _LineDiffKind.equal,
          localLine: localLine,
          cloudLine: cloudLine,
        ),
      );
      localIndex++;
      cloudIndex++;
    } else if (lcs[localIndex + 1][cloudIndex] >=
        lcs[localIndex][cloudIndex + 1]) {
      result.add(
        _LineDiffEntry(_LineDiffKind.local, localLine: localLine),
      );
      localIndex++;
    } else {
      result.add(
        _LineDiffEntry(_LineDiffKind.cloud, cloudLine: cloudLine),
      );
      cloudIndex++;
    }
  }
  while (localIndex < localLength) {
    result.add(
      _LineDiffEntry(
        _LineDiffKind.local,
        localLine: localLines[localIndex++],
      ),
    );
  }
  while (cloudIndex < cloudLength) {
    result.add(
      _LineDiffEntry(
        _LineDiffKind.cloud,
        cloudLine: cloudLines[cloudIndex++],
      ),
    );
  }
  return result;
}

List<_LineDiffEntry> _largeDocumentDiff(
  List<NoteConflictLine> localLines,
  List<NoteConflictLine> cloudLines,
) {
  final result = <_LineDiffEntry>[];
  var prefix = 0;
  while (prefix < localLines.length &&
      prefix < cloudLines.length &&
      localLines[prefix].signature == cloudLines[prefix].signature) {
    result.add(
      _LineDiffEntry(
        _LineDiffKind.equal,
        localLine: localLines[prefix],
        cloudLine: cloudLines[prefix],
      ),
    );
    prefix++;
  }

  var localSuffix = localLines.length - 1;
  var cloudSuffix = cloudLines.length - 1;
  while (localSuffix >= prefix &&
      cloudSuffix >= prefix &&
      localLines[localSuffix].signature == cloudLines[cloudSuffix].signature) {
    localSuffix--;
    cloudSuffix--;
  }

  for (var index = prefix; index <= localSuffix; index++) {
    result.add(
      _LineDiffEntry(_LineDiffKind.local, localLine: localLines[index]),
    );
  }
  for (var index = prefix; index <= cloudSuffix; index++) {
    result.add(
      _LineDiffEntry(_LineDiffKind.cloud, cloudLine: cloudLines[index]),
    );
  }
  for (var offset = localSuffix + 1; offset < localLines.length; offset++) {
    final cloudOffset = cloudSuffix + 1 + (offset - localSuffix - 1);
    result.add(
      _LineDiffEntry(
        _LineDiffKind.equal,
        localLine: localLines[offset],
        cloudLine: cloudLines[cloudOffset],
      ),
    );
  }
  return result;
}

List<NoteConflictLine> _parseLines(String content) {
  final operations = _decodeOperations(content);
  final lines = <NoteConflictLine>[];
  var currentOperations = <Map<String, dynamic>>[];
  final currentText = StringBuffer();

  void finishLine() {
    final copiedOperations = currentOperations
        .map((operation) => Map<String, dynamic>.from(operation))
        .toList(growable: false);
    lines.add(
      NoteConflictLine(
        operations: copiedOperations,
        text: currentText.toString(),
        signature: _canonicalOperationsSignature(copiedOperations),
      ),
    );
    currentOperations = <Map<String, dynamic>>[];
    currentText.clear();
  }

  for (final rawOperation in operations) {
    final operation = Map<String, dynamic>.from(rawOperation);
    final insert = operation['insert'];
    if (insert is! String) {
      currentOperations.add(operation);
      currentText.write(_embedLabel(insert));
      continue;
    }

    var start = 0;
    for (var index = 0; index < insert.length; index++) {
      if (insert.codeUnitAt(index) != 10) continue;
      if (index > start) {
        currentOperations.add(
          _operationWithInsert(operation, insert.substring(start, index)),
        );
        currentText.write(insert.substring(start, index));
      }
      currentOperations.add(_operationWithInsert(operation, '\n'));
      finishLine();
      start = index + 1;
    }
    if (start < insert.length) {
      currentOperations.add(
        _operationWithInsert(operation, insert.substring(start)),
      );
      currentText.write(insert.substring(start));
    }
  }

  if (currentOperations.isNotEmpty) {
    finishLine();
  }
  if (lines.isEmpty) {
    const emptyOperation = <String, dynamic>{'insert': '\n'};
    lines.add(
      NoteConflictLine(
        operations: const <Map<String, dynamic>>[emptyOperation],
        text: '',
        signature: _canonicalOperationsSignature(
          const <Map<String, dynamic>>[emptyOperation],
        ),
      ),
    );
  }
  return lines;
}

String _canonicalOperationsSignature(
  List<Map<String, dynamic>> operations,
) {
  final canonicalOperations = <Map<String, dynamic>>[];
  String? previousMetadata;

  for (final operation in operations) {
    final canonical = _canonicalMap(operation);
    final insert = canonical['insert'];
    if (insert is String && insert.isEmpty) continue;
    final attributes = canonical['attributes'];
    if (attributes == null ||
        (attributes is Map<Object?, Object?> && attributes.isEmpty)) {
      canonical.remove('attributes');
    }
    final metadata = Map<String, dynamic>.from(canonical)..remove('insert');
    final metadataSignature = jsonEncode(metadata);

    if (insert is String &&
        canonicalOperations.isNotEmpty &&
        canonicalOperations.last['insert'] is String &&
        previousMetadata == metadataSignature) {
      canonicalOperations.last['insert'] =
          '${canonicalOperations.last['insert']}$insert';
    } else {
      canonicalOperations.add(Map<String, dynamic>.from(canonical));
    }
    previousMetadata = metadataSignature;
  }

  return jsonEncode(canonicalOperations);
}

Map<String, dynamic> _canonicalMap(Map<Object?, Object?> value) {
  final keys = value.keys.map((key) => '$key').toList()..sort();
  return <String, dynamic>{
    for (final key in keys) key: _canonicalValue(value[key]),
  };
}

Object? _canonicalValue(Object? value) {
  if (value is Map<Object?, Object?>) return _canonicalMap(value);
  if (value is List<Object?>) return value.map(_canonicalValue).toList();
  return value;
}

List<Map<String, dynamic>> _decodeOperations(String content) {
  try {
    final decoded = jsonDecode(content);
    final rawOperations = decoded is List<dynamic>
        ? decoded
        : decoded is Map<String, dynamic> && decoded['ops'] is List<dynamic>
            ? decoded['ops'] as List<dynamic>
            : null;
    if (rawOperations != null) {
      return rawOperations
          .whereType<Map<Object?, Object?>>()
          .map((operation) => Map<String, dynamic>.from(operation))
          .toList();
    }
  } catch (_) {
    // Legacy notes are converted to a plain-text Delta below.
  }
  return <Map<String, dynamic>>[
    <String, dynamic>{
      'insert': content.endsWith('\n') ? content : '$content\n',
    },
  ];
}

Map<String, dynamic> _operationWithInsert(
  Map<String, dynamic> operation,
  String insert,
) {
  return <String, dynamic>{...operation, 'insert': insert};
}

String _embedLabel(Object? insert) {
  if (insert is Map && insert.isNotEmpty) {
    final type = '${insert.keys.first}';
    return '[${type == 'custom' ? 'embedded content' : type}]';
  }
  return '[embedded content]';
}

bool _endsWithNewline(List<Map<String, dynamic>> operations) {
  final insert = operations.last['insert'];
  return insert is String && insert.endsWith('\n');
}
