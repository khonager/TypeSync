library;

import 'dart:typed_data';

import 'package:flutter_quill/flutter_quill_internal.dart'
    show ClipboardService;

/// Skips rich clipboard probing so Quill can fall back to plain-text paste.
///
/// On Linux, the default Quill clipboard service shells out to `xclip` several
/// times to inspect HTML, file, and image clipboard formats before it reads
/// plain text. That overhead is noticeable even when pasting a single
/// character, so we opt into the fast plain-text path for TypeSync.
class PlainTextQuillClipboardService extends ClipboardService {
  @override
  Future<String?> getHtmlText() async => null;

  @override
  Future<String?> getHtmlFile() async => null;

  @override
  Future<String?> getMarkdownFile() async => null;

  @override
  Future<Uint8List?> getImageFile() async => null;

  @override
  Future<Uint8List?> getGifFile() async => null;

  @override
  Future<void> copyImage(Uint8List imageBytes) async {}
}
