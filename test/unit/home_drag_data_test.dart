import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/features/home/models/home_drag_data.dart';

void main() {
  test('encodes and decodes a mixed note and folder selection', () {
    const data = HomeDragData(
      noteIds: {'note-a', 'note-b'},
      folderIds: {'folder-a'},
    );

    final decoded = HomeDragData.tryParse(data.encode());

    expect(decoded?.noteIds, {'note-a', 'note-b'});
    expect(decoded?.folderIds, {'folder-a'});
  });

  test('continues to parse legacy single-item drag payloads', () {
    expect(HomeDragData.tryParse('note:note-a')?.noteIds, {'note-a'});
    expect(HomeDragData.tryParse('folder:folder-a')?.folderIds, {'folder-a'});
  });
}
