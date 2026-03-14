// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

class RemotePdfEmbed extends StatefulWidget {
  const RemotePdfEmbed({
    required this.url,
    super.key,
  });

  final String url;

  @override
  State<RemotePdfEmbed> createState() => _RemotePdfEmbedState();
}

class _RemotePdfEmbedState extends State<RemotePdfEmbed> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType =
        'remote-pdf-${DateTime.now().microsecondsSinceEpoch}-${widget.url.hashCode}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (viewId) {
      final frame = html.IFrameElement()
        ..src = widget.url
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%';
      return frame;
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
