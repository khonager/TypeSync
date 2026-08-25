/// Supported custom embeds that may be persisted in rich-text notes.
library;

import '../models/typesync_code_embed.dart';
import '../models/typesync_kanban_embed.dart';
import '../models/typesync_table_embed.dart';

bool isSupportedRichTextEmbedType(String embedType) {
  return embedType == TypeSyncKanbanEmbed.kanbanType ||
      embedType == TypeSyncTableEmbed.tableType ||
      embedType == TypeSyncCodeEmbed.codeType ||
      embedType == 'x-embed-table';
}
