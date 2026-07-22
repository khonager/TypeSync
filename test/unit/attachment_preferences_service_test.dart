import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typesync/core/services/attachment_preferences_service.dart';

void main() {
  group('AttachmentPreferencesService', () {
    test('migrates legacy device-only attachment preferences', () async {
      SharedPreferences.setMockInitialValues({
        'typesync_editor_attachments_expanded_note-1': true,
        'typesync_editor_attachments_preview_hidden_note-1': true,
      });
      final service = AttachmentPreferencesService();

      await service.migrateLegacyPreferences('note-1');

      expect(service.preferencesFor('note-1').expanded, isTrue);
      expect(service.preferencesFor('note-1').previewHidden, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('typesync_attachment_preferences_v1'),
        contains('note-1'),
      );
    });

    test('applies attachment preferences received from cloud settings',
        () async {
      SharedPreferences.setMockInitialValues({});
      final service = AttachmentPreferencesService();

      service.handleCloudSettings({
        'attachmentPreferences': {
          'note-1': {'expanded': true, 'previewHidden': false},
        },
      });

      expect(service.preferencesFor('note-1').expanded, isTrue);
      expect(service.preferencesFor('note-1').previewHidden, isFalse);
    });

    test('does not let a late local cache load overwrite cloud settings',
        () async {
      SharedPreferences.setMockInitialValues({
        'typesync_attachment_preferences_v1':
            '{"note-1":{"expanded":false,"previewHidden":true}}',
      });
      final service = AttachmentPreferencesService();

      service.handleCloudSettings({
        'attachmentPreferences': {
          'note-1': {'expanded': true, 'previewHidden': false},
        },
      });
      await service.load();

      expect(service.preferencesFor('note-1').expanded, isTrue);
      expect(service.preferencesFor('note-1').previewHidden, isFalse);
    });
  });
}
