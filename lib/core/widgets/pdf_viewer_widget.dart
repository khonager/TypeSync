/// PDF Viewer Widget
///
/// A custom PDF viewer that works on all platforms by rendering
/// PDF pages as images using the pdf package.

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

/// Custom PDF viewer widget
class PdfViewerWidget extends StatefulWidget {
  final File pdfFile;

  const PdfViewerWidget({
    super.key,
    required this.pdfFile,
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

  Future<void> _loadPdf() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      // Read PDF file
      final bytes = await widget.pdfFile.readAsBytes();

      // PDF loaded successfully
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
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
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

    // Use Printing's PDF preview which works cross-platform
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
          child: _pdfBytes != null
              ? PdfPreview(
                  build: (format) => _pdfBytes!,
                  allowPrinting: true,
                  allowSharing: true,
                  canChangeOrientation: false,
                  canChangePageFormat: false,
                  canDebug: false,
                )
              : const Center(child: CircularProgressIndicator()),
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
        await Process.run('start', [widget.pdfFile.absolute.path],
            runInShell: true);
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
