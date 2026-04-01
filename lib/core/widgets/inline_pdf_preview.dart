library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

class InlinePdfPreview extends StatefulWidget {
  final Uint8List pdfBytes;
  final double dpi;

  const InlinePdfPreview({
    required this.pdfBytes,
    this.dpi = 144,
    super.key,
  });

  @override
  State<InlinePdfPreview> createState() => _InlinePdfPreviewState();
}

class _InlinePdfPreviewState extends State<InlinePdfPreview> {
  final List<_RasterizedPdfPage> _pages = [];
  bool _isLoading = true;
  Object? _error;
  int _rasterSession = 0;

  @override
  void initState() {
    super.initState();
    _rasterizeDocument();
  }

  @override
  void didUpdateWidget(covariant InlinePdfPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameBytes(oldWidget.pdfBytes, widget.pdfBytes) ||
        oldWidget.dpi != widget.dpi) {
      _rasterizeDocument();
    }
  }

  @override
  void dispose() {
    _disposePages();
    super.dispose();
  }

  Future<void> _rasterizeDocument() async {
    final session = ++_rasterSession;
    _disposePages();
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await for (final page
          in Printing.raster(widget.pdfBytes, dpi: widget.dpi)) {
        if (!mounted || session != _rasterSession) {
          return;
        }

        final pngBytes = await page.toPng();
        if (!mounted || session != _rasterSession) {
          return;
        }

        setState(() {
          _pages.add(
            _RasterizedPdfPage(
              image: MemoryImage(pngBytes),
              width: page.width.toDouble(),
              height: page.height.toDouble(),
            ),
          );
        });
      }

      if (!mounted || session != _rasterSession) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || session != _rasterSession) {
        return;
      }
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  void _disposePages() {
    for (final page in _pages) {
      page.image.evict();
    }
    _pages.clear();
  }

  bool _sameBytes(Uint8List left, Uint8List right) {
    if (identical(left, right)) return true;
    if (left.lengthInBytes != right.lengthInBytes) return false;
    for (var i = 0; i < left.lengthInBytes; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Unable to render PDF: $_error',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_pages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _pages.length + (_isLoading ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        if (index >= _pages.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final page = _pages[index];
        return _ZoomablePdfPage(
          page: page,
          pageNumber: index + 1,
        );
      },
    );
  }
}

class _ZoomablePdfPage extends StatefulWidget {
  final _RasterizedPdfPage page;
  final int pageNumber;

  const _ZoomablePdfPage({
    required this.page,
    required this.pageNumber,
  });

  @override
  State<_ZoomablePdfPage> createState() => _ZoomablePdfPageState();
}

class _ZoomablePdfPageState extends State<_ZoomablePdfPage> {
  final TransformationController _transformationController =
      TransformationController();
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_handleTransformChanged);
  }

  @override
  void dispose() {
    _transformationController.removeListener(_handleTransformChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _handleTransformChanged() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final isZoomed = scale > 1.01;
    if (isZoomed != _isZoomed) {
      setState(() {
        _isZoomed = isZoomed;
      });
    }
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final aspectRatio = widget.page.width / widget.page.height;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.18),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: 1,
              maxScale: 5,
              panEnabled: _isZoomed,
              clipBehavior: Clip.hardEdge,
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: Image(
                  image: widget.page.image,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${widget.pageNumber}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            if (_isZoomed) ...[
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: _resetZoom,
                icon: const Icon(Icons.center_focus_strong, size: 16),
                label: const Text('Reset zoom'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _RasterizedPdfPage {
  final MemoryImage image;
  final double width;
  final double height;

  const _RasterizedPdfPage({
    required this.image,
    required this.width,
    required this.height,
  });
}
