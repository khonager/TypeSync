/// Interactive kanban embed builder for Quill notes.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../../core/models/typesync_kanban_embed.dart';

class TypeSyncKanbanEmbedBuilder extends EmbedBuilder {
  const TypeSyncKanbanEmbedBuilder();

  @override
  String get key => TypeSyncKanbanEmbed.kanbanType;

  @override
  String toPlainText(Embed node) {
    final data = node.value.data;
    if (data is! String) {
      return '\n';
    }
    return '${TypeSyncKanbanEmbed.parseData(data).toPlainText()}\n';
  }

  @override
  Widget build(
    BuildContext context,
    QuillController controller,
    Embed node,
    bool readOnly,
    bool inline,
    TextStyle textStyle,
  ) {
    final data = node.value.data;
    final board = data is String
        ? TypeSyncKanbanEmbed.parseData(data)
        : TypeSyncKanbanData.empty();

    return _TypeSyncKanbanEmbedWidget(
      controller: controller,
      node: node,
      readOnly: readOnly,
      board: board,
    );
  }
}

class _TypeSyncKanbanEmbedWidget extends StatelessWidget {
  final QuillController controller;
  final Embed node;
  final bool readOnly;
  final TypeSyncKanbanData board;

  const _TypeSyncKanbanEmbedWidget({
    required this.controller,
    required this.node,
    required this.readOnly,
    required this.board,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title =
        board.title.trim().isEmpty ? 'Kanban board' : board.title.trim();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${board.columnCount} columns • ${board.cardCount} cards',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (!readOnly)
                TextButton.icon(
                  onPressed: () => _editBoard(context),
                  icon: const Icon(Icons.view_kanban_outlined, size: 18),
                  label: const Text('Edit board'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _KanbanBoardPreview(board: board),
        ],
      ),
    );
  }

  Future<void> _editBoard(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _TypeSyncKanbanEditorDialog(
        initialBoard: board,
        onBoardChanged: _persistBoard,
      ),
    );
  }

  void _persistBoard(TypeSyncKanbanData nextBoard) {
    final offset = node.documentOffset;
    controller.replaceText(
      offset,
      1,
      TypeSyncKanbanEmbed.toBlockEmbed(nextBoard),
      TextSelection.collapsed(offset: offset + 1),
    );
  }
}

class _KanbanBoardPreview extends StatelessWidget {
  final TypeSyncKanbanData board;

  const _KanbanBoardPreview({
    required this.board,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final column in board.columns)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _KanbanColumnPreview(column: column),
            ),
        ],
      ),
    );
  }
}

class _KanbanColumnPreview extends StatelessWidget {
  final TypeSyncKanbanColumnData column;

  const _KanbanColumnPreview({
    required this.column,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final visibleCards = column.cards.take(4).toList();
    final remainingCards = column.cards.length - visibleCards.length;

    return Container(
      width: 240,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  column.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${column.cards.length}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (visibleCards.isEmpty)
            Text(
              'No cards yet',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            )
          else
            ...visibleCards.map(
              (card) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _KanbanCardPreview(card: card),
              ),
            ),
          if (remainingCards > 0)
            Text(
              '+$remainingCards more',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
        ],
      ),
    );
  }
}

class _KanbanCardPreview extends StatelessWidget {
  final TypeSyncKanbanCardData card;

  const _KanbanCardPreview({
    required this.card,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final description = card.description.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            card.title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _TypeSyncKanbanEditorDialog extends StatefulWidget {
  final TypeSyncKanbanData initialBoard;
  final ValueChanged<TypeSyncKanbanData> onBoardChanged;

  const _TypeSyncKanbanEditorDialog({
    required this.initialBoard,
    required this.onBoardChanged,
  });

  @override
  State<_TypeSyncKanbanEditorDialog> createState() =>
      _TypeSyncKanbanEditorDialogState();
}

class _TypeSyncKanbanEditorDialogState
    extends State<_TypeSyncKanbanEditorDialog> {
  late TypeSyncKanbanData _board;
  late TextEditingController _titleController;

  @override
  void initState() {
    super.initState();
    _board = widget.initialBoard;
    _titleController = TextEditingController(text: _board.title);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final dialogWidth = math.min(mediaQuery.size.width * 0.94, 1220.0);
    final dialogHeight = math.min(mediaQuery.size.height * 0.86, 820.0);

    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Edit kanban board')),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Board title',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => _commitBoard(_board.copyWith(title: value)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _addColumn,
                  icon: const Icon(Icons.add),
                  label: const Text('Add column'),
                ),
                Text(
                  '${_board.columnCount} columns • ${_board.cardCount} cards',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                Text(
                  'Long-press a card to drag it to another column',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                Text(
                  'Changes save and sync automatically',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List<Widget>.generate(
                        _board.columns.length,
                        (columnIndex) => Padding(
                          padding: EdgeInsets.only(
                            right: columnIndex == _board.columns.length - 1
                                ? 0
                                : 12,
                          ),
                          child: SizedBox(
                            width: 300,
                            height: constraints.maxHeight,
                            child: _buildEditableColumn(context, columnIndex),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _commitBoard(TypeSyncKanbanData nextBoard) {
    setState(() {
      _board = nextBoard;
    });
    widget.onBoardChanged(nextBoard);
  }

  Widget _buildEditableColumn(BuildContext context, int columnIndex) {
    final column = _board.columns[columnIndex];
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.24)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey(column.id),
                  initialValue: column.title,
                  decoration: const InputDecoration(
                    labelText: 'Column',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) => _updateColumnTitle(columnIndex, value),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Move column left',
                onPressed:
                    columnIndex > 0 ? () => _moveColumn(columnIndex, -1) : null,
                icon: const Icon(Icons.arrow_back),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Move column right',
                onPressed: columnIndex < _board.columns.length - 1
                    ? () => _moveColumn(columnIndex, 1)
                    : null,
                icon: const Icon(Icons.arrow_forward),
              ),
              PopupMenuButton<String>(
                tooltip: 'Column options',
                onSelected: (value) {
                  if (value == 'delete') {
                    _deleteColumn(columnIndex);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    value: 'delete',
                    enabled: _board.columns.length > 1,
                    child: const Text('Delete column'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${column.cards.length} cards',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: DragTarget<_DraggedKanbanCard>(
              onWillAcceptWithDetails: (_) => true,
              onAcceptWithDetails: (details) {
                _moveDraggedCardToColumn(
                  cardId: details.data.cardId,
                  targetColumnIndex: columnIndex,
                );
              },
              builder: (context, candidateData, rejectedData) {
                final isActiveTarget = candidateData.isNotEmpty;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: BoxDecoration(
                    color: isActiveTarget
                        ? colorScheme.primary.withValues(alpha: 0.08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isActiveTarget
                          ? colorScheme.primary.withValues(alpha: 0.35)
                          : colorScheme.outline.withValues(alpha: 0.18),
                    ),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: column.cards.isEmpty
                      ? Center(
                          child: Text(
                            isActiveTarget ? 'Drop card here' : 'No cards yet',
                            textAlign: TextAlign.center,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: column.cards.length,
                          itemBuilder: (context, cardIndex) =>
                              _buildEditableCard(
                            context,
                            columnIndex,
                            cardIndex,
                          ),
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                        ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _showCardEditor(columnIndex: columnIndex),
            icon: const Icon(Icons.add),
            label: const Text('Add card'),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableCard(
    BuildContext context,
    int columnIndex,
    int cardIndex,
  ) {
    final card = _board.columns[columnIndex].cards[cardIndex];
    final colorScheme = Theme.of(context).colorScheme;
    final description = card.description.trim();
    final canMoveLeft = columnIndex > 0;
    final canMoveRight = columnIndex < _board.columns.length - 1;

    final cardBody = Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showCardEditor(
          columnIndex: columnIndex,
          cardIndex: cardIndex,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                card.title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Move to previous column',
                    onPressed: canMoveLeft
                        ? () =>
                            _moveCardAcrossColumns(columnIndex, cardIndex, -1)
                        : null,
                    icon: const Icon(Icons.arrow_back, size: 18),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Move to next column',
                    onPressed: canMoveRight
                        ? () =>
                            _moveCardAcrossColumns(columnIndex, cardIndex, 1)
                        : null,
                    icon: const Icon(Icons.arrow_forward, size: 18),
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    tooltip: 'Card options',
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          _showCardEditor(
                            columnIndex: columnIndex,
                            cardIndex: cardIndex,
                          );
                          return;
                        case 'up':
                          _moveCardWithinColumn(columnIndex, cardIndex, -1);
                          return;
                        case 'down':
                          _moveCardWithinColumn(columnIndex, cardIndex, 1);
                          return;
                        case 'delete':
                          _deleteCard(columnIndex, cardIndex);
                          return;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem<String>(
                        value: 'edit',
                        child: Text('Edit card'),
                      ),
                      PopupMenuItem<String>(
                        value: 'up',
                        enabled: cardIndex > 0,
                        child: const Text('Move up'),
                      ),
                      PopupMenuItem<String>(
                        value: 'down',
                        enabled: cardIndex <
                            _board.columns[columnIndex].cards.length - 1,
                        child: const Text('Move down'),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: Text('Delete card'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return LongPressDraggable<_DraggedKanbanCard>(
      data: _DraggedKanbanCard(cardId: card.id),
      feedback: Material(
        elevation: 8,
        color: Colors.transparent,
        child: SizedBox(
          width: 260,
          child: cardBody,
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.45,
        child: cardBody,
      ),
      child: cardBody,
    );
  }

  void _addColumn() {
    _commitBoard(
      _board.copyWith(
        columns: [
          ..._board.columns,
          TypeSyncKanbanColumnData.create(
            title: 'Column ${_board.columns.length + 1}',
          ),
        ],
      ),
    );
  }

  void _updateColumnTitle(int columnIndex, String value) {
    final columns = List<TypeSyncKanbanColumnData>.from(_board.columns);
    columns[columnIndex] = columns[columnIndex].copyWith(title: value);
    _commitBoard(_board.copyWith(columns: columns));
  }

  void _moveColumn(int columnIndex, int delta) {
    final targetIndex = columnIndex + delta;
    if (targetIndex < 0 || targetIndex >= _board.columns.length) {
      return;
    }

    final columns = List<TypeSyncKanbanColumnData>.from(_board.columns);
    final column = columns.removeAt(columnIndex);
    columns.insert(targetIndex, column);

    _commitBoard(_board.copyWith(columns: columns));
  }

  void _deleteColumn(int columnIndex) {
    if (_board.columns.length <= 1) {
      return;
    }

    final columns = List<TypeSyncKanbanColumnData>.from(_board.columns)
      ..removeAt(columnIndex);
    _commitBoard(_board.copyWith(columns: columns));
  }

  Future<void> _showCardEditor({
    required int columnIndex,
    int? cardIndex,
  }) async {
    final existingCard =
        cardIndex == null ? null : _board.columns[columnIndex].cards[cardIndex];
    final draftCardId = existingCard?.id ?? TypeSyncKanbanCardData.create().id;
    final titleController =
        TextEditingController(text: existingCard?.title ?? '');
    final descriptionController = TextEditingController(
      text: existingCard?.description ?? '',
    );

    void syncCardFromControllers() {
      final rawTitle = titleController.text;
      final rawDescription = descriptionController.text;
      final trimmedTitle = rawTitle.trim();
      final trimmedDescription = rawDescription.trim();

      if (existingCard == null &&
          trimmedTitle.isEmpty &&
          trimmedDescription.isEmpty) {
        return;
      }

      final nextCard = TypeSyncKanbanCardData(
        id: draftCardId,
        title: trimmedTitle.isEmpty ? 'Untitled card' : trimmedTitle,
        description: trimmedDescription,
      );

      _upsertCard(
        columnIndex: columnIndex,
        cardId: draftCardId,
        nextCard: nextCard,
      );
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Expanded(
              child: Text(existingCard == null ? 'Add card' : 'Edit card'),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.pop(dialogContext),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Changes save and sync when you close this dialog',
                  style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                        color: Theme.of(dialogContext).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    syncCardFromControllers();
    titleController.dispose();
    descriptionController.dispose();
  }

  void _deleteCard(int columnIndex, int cardIndex) {
    final columns = List<TypeSyncKanbanColumnData>.from(_board.columns);
    final cards = List<TypeSyncKanbanCardData>.from(columns[columnIndex].cards)
      ..removeAt(cardIndex);
    columns[columnIndex] = columns[columnIndex].copyWith(cards: cards);

    _commitBoard(_board.copyWith(columns: columns));
  }

  void _moveCardWithinColumn(int columnIndex, int cardIndex, int delta) {
    final cards =
        List<TypeSyncKanbanCardData>.from(_board.columns[columnIndex].cards);
    final targetIndex = cardIndex + delta;
    if (targetIndex < 0 || targetIndex >= cards.length) {
      return;
    }

    final card = cards.removeAt(cardIndex);
    cards.insert(targetIndex, card);

    final columns = List<TypeSyncKanbanColumnData>.from(_board.columns);
    columns[columnIndex] = columns[columnIndex].copyWith(cards: cards);

    _commitBoard(_board.copyWith(columns: columns));
  }

  void _moveCardAcrossColumns(int columnIndex, int cardIndex, int delta) {
    final targetColumnIndex = columnIndex + delta;
    if (targetColumnIndex < 0 || targetColumnIndex >= _board.columns.length) {
      return;
    }

    final columns = List<TypeSyncKanbanColumnData>.from(_board.columns);
    final sourceCards =
        List<TypeSyncKanbanCardData>.from(columns[columnIndex].cards);
    final targetCards = List<TypeSyncKanbanCardData>.from(
      columns[targetColumnIndex].cards,
    );
    final card = sourceCards.removeAt(cardIndex);
    targetCards.add(card);

    columns[columnIndex] = columns[columnIndex].copyWith(cards: sourceCards);
    columns[targetColumnIndex] = columns[targetColumnIndex].copyWith(
      cards: targetCards,
    );

    _commitBoard(_board.copyWith(columns: columns));
  }

  void _moveDraggedCardToColumn({
    required String cardId,
    required int targetColumnIndex,
  }) {
    final sourceLocation = _findCardLocation(cardId);
    if (sourceLocation == null) {
      return;
    }

    final sourceColumnIndex = sourceLocation.columnIndex;
    final sourceCardIndex = sourceLocation.cardIndex;
    if (sourceColumnIndex == targetColumnIndex) {
      return;
    }

    final columns = List<TypeSyncKanbanColumnData>.from(_board.columns);
    final sourceCards = List<TypeSyncKanbanCardData>.from(
      columns[sourceColumnIndex].cards,
    );
    final targetCards = List<TypeSyncKanbanCardData>.from(
      columns[targetColumnIndex].cards,
    );

    final card = sourceCards.removeAt(sourceCardIndex);
    targetCards.add(card);

    columns[sourceColumnIndex] = columns[sourceColumnIndex].copyWith(
      cards: sourceCards,
    );
    columns[targetColumnIndex] = columns[targetColumnIndex].copyWith(
      cards: targetCards,
    );

    _commitBoard(_board.copyWith(columns: columns));
  }

  void _upsertCard({
    required int columnIndex,
    required String cardId,
    required TypeSyncKanbanCardData nextCard,
  }) {
    final columns = List<TypeSyncKanbanColumnData>.from(_board.columns);
    final cards = List<TypeSyncKanbanCardData>.from(columns[columnIndex].cards);
    final existingIndex = cards.indexWhere((card) => card.id == cardId);

    if (existingIndex >= 0) {
      cards[existingIndex] = nextCard;
    } else {
      cards.add(nextCard);
    }

    columns[columnIndex] = columns[columnIndex].copyWith(cards: cards);
    _commitBoard(_board.copyWith(columns: columns));
  }

  _KanbanCardLocation? _findCardLocation(String cardId) {
    for (var columnIndex = 0;
        columnIndex < _board.columns.length;
        columnIndex++) {
      final cards = _board.columns[columnIndex].cards;
      for (var cardIndex = 0; cardIndex < cards.length; cardIndex++) {
        if (cards[cardIndex].id == cardId) {
          return _KanbanCardLocation(
            columnIndex: columnIndex,
            cardIndex: cardIndex,
          );
        }
      }
    }
    return null;
  }
}

class _DraggedKanbanCard {
  final String cardId;

  const _DraggedKanbanCard({
    required this.cardId,
  });
}

class _KanbanCardLocation {
  final int columnIndex;
  final int cardIndex;

  const _KanbanCardLocation({
    required this.columnIndex,
    required this.cardIndex,
  });
}
