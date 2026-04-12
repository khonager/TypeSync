/// PDF Viewer Widget
///
/// A custom PDF viewer that works on all platforms by rendering
/// PDF pages as images using the pdf package.
library;

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'inline_pdf_preview.dart';

/// Custom PDF viewer widget
class PdfViewerWidget extends StatefulWidget {
  final File pdfFile;

  const PdfViewerWidget({
    required this.pdfFile,
    super.key,
  });

  @override
  State<PdfViewerWidget> createState() => _PdfViewerWidgetState();
}

class _PdfViewerWidgetState extends State<PdfViewerWidget> {
  Uint8List? _pdfBytes;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  @override
  void didUpdateWidget(covariant PdfViewerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pdfFile.path != widget.pdfFile.path) {
      _loadPdf();
    }
  }

  Future<void> _loadPdf() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final bytes = await widget.pdfFile.readAsBytes();

      setState(() {
        _pdfBytes = bytes;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Failed to load PDF: $e');
      setState(() {
        _errorMessage = 'Failed to load PDF: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null || !widget.pdfFile.existsSync()) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Failed to load PDF: file not found',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _openInExternalViewer(),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open in external viewer'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).appBarTheme.backgroundColor,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.open_in_new),
                onPressed: () => _openInExternalViewer(),
                tooltip: 'Open in external viewer',
              ),
            ],
          ),
        ),

        // PDF Preview
        Expanded(
          child: _pdfBytes == null
              ? const Center(child: CircularProgressIndicator())
              : InlinePdfPreview(pdfBytes: _pdfBytes!),
        ),
      ],
    );
  }

  Future<void> _openInExternalViewer() async {
    try {
      final uri = Uri.file(widget.pdfFile.absolute.path);

      if (Platform.isLinux) {
        // Use xdg-open on Linux
        await Process.run('xdg-open', [widget.pdfFile.absolute.path]);
      } else if (Platform.isMacOS) {
        // Use open on macOS
        await Process.run('open', [widget.pdfFile.absolute.path]);
      } else if (Platform.isWindows) {
        // Use start on Windows
        await Process.run(
          'start',
          [widget.pdfFile.absolute.path],
          runInShell: true,
        );
      } else {
        // Try url_launcher for mobile
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open PDF: $e')),
        );
      }
    }
  }
}
