/// Search query parser and normalized filter model.
library;

/// Parsed search query with Discord-style filter syntax.
///
/// Supported operators:
/// - `is:folder`, `is:file`
/// - `in:text`, `in:title`, `in:attachment`, `in:pdf`, `in:txt`, `in:markdown`
/// - `has:attachment`, `has:image`, `has:pdf`, `has:table`, `has:kanban`
/// - `tag:name` — filter notes by tag name
class SearchQuery {
  final String raw;
  final List<String> textTokens;
  final Set<String> inFilters;
  final Set<String> isFilters;
  final Set<String> hasFilters;
  final List<String> tagFilters;

  const SearchQuery({
    required this.raw,
    required this.textTokens,
    required this.inFilters,
    required this.isFilters,
    required this.hasFilters,
    this.tagFilters = const [],
  });

  bool get hasText => textTokens.isNotEmpty;
  bool get hasAnyFilter =>
      inFilters.isNotEmpty ||
      isFilters.isNotEmpty ||
      hasFilters.isNotEmpty ||
      tagFilters.isNotEmpty;
  bool get isActive => hasText || hasAnyFilter;

  String get plainTextQuery => textTokens.join(' ');

  bool get includeFolders {
    if (isFilters.contains('folder')) return true;
    if (isFilters.contains('file')) return false;
    if (inFilters.isNotEmpty || hasFilters.isNotEmpty) return false;
    return true;
  }

  bool get includeFiles {
    if (isFilters.contains('folder')) return false;
    if (isFilters.contains('file')) return true;
    return true;
  }

  static SearchQuery parse(String input) {
    final inFilters = <String>{};
    final isFilters = <String>{};
    final hasFilters = <String>{};
    final tagFilters = <String>[];
    final textTokens = <String>[];

    final matches = RegExp(r'"([^"]+)"|(\S+)').allMatches(input);
    for (final match in matches) {
      final token = (match.group(1) ?? match.group(2) ?? '').trim();
      if (token.isEmpty) continue;

      final separatorIndex = token.indexOf(':');
      if (separatorIndex <= 0 || separatorIndex == token.length - 1) {
        textTokens.add(token.toLowerCase());
        continue;
      }

      final prefix = token.substring(0, separatorIndex).toLowerCase();
      final rawValue = token.substring(separatorIndex + 1).trim();
      final value = _normalizeTokenValue(rawValue);
      if (value.isEmpty) {
        textTokens.add(token.toLowerCase());
        continue;
      }

      if (prefix == 'in') {
        final normalized = _normalizeInFilter(value);
        if (normalized != null) {
          inFilters.add(normalized);
          continue;
        }
      } else if (prefix == 'is') {
        final normalized = _normalizeIsFilter(value);
        if (normalized != null) {
          isFilters.add(normalized);
          continue;
        }
      } else if (prefix == 'has') {
        final normalized = _normalizeHasFilter(value);
        if (normalized != null) {
          hasFilters.add(normalized);
          continue;
        }
      } else if (prefix == 'tag') {
        tagFilters.add(value);
        continue;
      }

      textTokens.add(token.toLowerCase());
    }

    return SearchQuery(
      raw: input,
      textTokens: textTokens,
      inFilters: inFilters,
      isFilters: isFilters,
      hasFilters: hasFilters,
      tagFilters: tagFilters,
    );
  }

  static String _normalizeTokenValue(String value) {
    var normalized = value.trim().toLowerCase();
    if (normalized.startsWith('"') && normalized.endsWith('"')) {
      normalized = normalized.substring(1, normalized.length - 1);
    }
    return normalized.trim();
  }

  static String? _normalizeInFilter(String value) {
    switch (value) {
      case 'text':
      case 'content':
      case 'body':
        return 'text';
      case 'title':
      case 'name':
        return 'title';
      case 'attachment':
      case 'attachments':
      case 'file':
      case 'files':
        return 'attachment';
      case 'pdf':
        return 'pdf';
      case 'txt':
      case 'textfile':
        return 'txt';
      case 'md':
      case 'markdown':
        return 'markdown';
      default:
        return null;
    }
  }

  static String? _normalizeIsFilter(String value) {
    switch (value) {
      case 'folder':
      case 'folders':
        return 'folder';
      case 'file':
      case 'files':
      case 'note':
      case 'notes':
        return 'file';
      default:
        return null;
    }
  }

  static String? _normalizeHasFilter(String value) {
    switch (value) {
      case 'attachment':
      case 'attachments':
      case 'file':
      case 'files':
        return 'attachment';
      case 'image':
      case 'images':
      case 'img':
      case 'photo':
      case 'picture':
        return 'image';
      case 'pdf':
        return 'pdf';
      case 'table':
      case 'tables':
        return 'table';
      case 'kanban':
      case 'board':
      case 'boards':
        return 'kanban';
      default:
        return null;
    }
  }
}
