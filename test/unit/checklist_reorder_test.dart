import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/features/editor/utils/checklist_reorder.dart';

void main() {
  Delta checklistDocument() {
    return Delta()
      ..insert('First\n', {
        'list': Attribute.unchecked.value,
        'typesync-checklist-created-at': 'first-created',
      })
      ..insert('Second\n', {
        'list': Attribute.checked.value,
        'typesync-checklist-created-at': 'second-created',
        'typesync-checklist-checked-at': 'second-checked',
      })
      ..insert('Third\n', {
        'list': Attribute.unchecked.value,
        'typesync-checklist-created-at': 'third-created',
      });
  }

  Delta apply(Delta document, Delta change) {
    final result = Document.fromDelta(document);
    result.compose(change, ChangeSource.local);
    return result.toDelta();
  }

  test('moves a checklist item up without losing its block attributes', () {
    final document = checklistDocument();
    final plan = ChecklistReorder.buildPlan(
      document: document,
      selectionStart: 6,
      selectionEnd: 6,
      selectionIsCollapsed: true,
      direction: -1,
    );

    expect(plan, isNotNull);
    expect(plan!.selectionOffsetDelta, -6);
    expect(
      apply(document, plan.change).toJson(),
      checklistDocument()
          .slice(6, 13)
          .concat(checklistDocument().slice(0, 6))
          .concat(checklistDocument().slice(13))
          .toJson(),
    );
  });

  test('moves a selected group of checklist items down together', () {
    final document = checklistDocument();
    final plan = ChecklistReorder.buildPlan(
      document: document,
      selectionStart: 0,
      selectionEnd: 13,
      selectionIsCollapsed: false,
      direction: 1,
    );

    expect(plan, isNotNull);
    expect(plan!.selectionOffsetDelta, 6);
    expect(
      apply(document, plan.change).toJson(),
      checklistDocument()
          .slice(13)
          .concat(checklistDocument().slice(0, 13))
          .toJson(),
    );
  });

  test('uses UTF-16 offsets so checklist items with emoji move correctly', () {
    final document = Delta()
      ..insert('😀\n', {'list': Attribute.unchecked.value})
      ..insert('Task\n', {'list': Attribute.checked.value});
    final plan = ChecklistReorder.buildPlan(
      document: document,
      selectionStart: 3,
      selectionEnd: 3,
      selectionIsCollapsed: true,
      direction: -1,
    );

    expect(plan, isNotNull);
    expect(plan!.selectionOffsetDelta, -3);
    expect(
      apply(document, plan.change).toJson(),
      document.slice(3).concat(document.slice(0, 3)).toJson(),
    );
  });

  test('does not move checklist items across non-checklist lines', () {
    final document = Delta()
      ..insert('Task\n', {'list': Attribute.unchecked.value})
      ..insert('Heading\n')
      ..insert('Another task\n', {'list': Attribute.unchecked.value});

    expect(
      ChecklistReorder.buildPlan(
        document: document,
        selectionStart: 0,
        selectionEnd: 0,
        selectionIsCollapsed: true,
        direction: 1,
      ),
      isNull,
    );
  });
}
