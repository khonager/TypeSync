import 'dart:convert';

/// The notes and folders carried by a drag operation in the home browser.
class HomeDragData {
  static const _prefix = 'typesync-items:';

  final Set<String> noteIds;
  final Set<String> folderIds;

  const HomeDragData({
    this.noteIds = const {},
    this.folderIds = const {},
  });

  bool get isEmpty => noteIds.isEmpty && folderIds.isEmpty;

  String encode() =>
      _prefix +
      base64UrlEncode(
        utf8.encode(
          jsonEncode({
            'notes': noteIds.toList(),
            'folders': folderIds.toList(),
          }),
        ),
      );

  static HomeDragData? tryParse(String data) {
    // Keep accepting the original single-item payloads so existing drags and
    // any platform drag integrations remain compatible.
    if (data.startsWith('note:')) {
      return HomeDragData(noteIds: {data.substring(5)});
    }
    if (data.startsWith('folder:')) {
      return HomeDragData(folderIds: {data.substring(7)});
    }
    if (!data.startsWith(_prefix)) return null;

    try {
      final value = jsonDecode(
        utf8.decode(base64Url.decode(data.substring(_prefix.length))),
      ) as Map<String, dynamic>;
      return HomeDragData(
        noteIds: (value['notes'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toSet(),
        folderIds: (value['folders'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toSet(),
      );
    } catch (_) {
      return null;
    }
  }
}
