library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

const double kDesktopWindowHeaderHeight = 38;

bool get supportsCustomDesktopWindowFrame {
  if (kIsWeb) return false;
  return switch (defaultTargetPlatform) {
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows =>
      true,
    _ => false,
  };
}

Future<void> configureDesktopWindowFrame() async {
  if (!supportsCustomDesktopWindowFrame) return;

  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1280, 720),
    minimumSize: Size(900, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    title: 'typesync',
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

Widget? desktopWindowDragArea() {
  if (!supportsCustomDesktopWindowFrame) return null;
  return const DragToMoveArea(
    child: SizedBox.expand(),
  );
}

List<Widget> withDesktopWindowControls(
  List<Widget> actions, {
  bool enabled = true,
}) {
  if (!enabled || !supportsCustomDesktopWindowFrame) {
    return actions;
  }

  return [
    ...actions,
    const SizedBox(width: 8),
    const DesktopWindowControls(),
  ];
}

class DesktopWindowFrameShell extends StatelessWidget {
  final Widget child;

  const DesktopWindowFrameShell({
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (!supportsCustomDesktopWindowFrame) {
      return child;
    }

    return VirtualWindowFrame(
      child: child,
    );
  }
}

class DesktopWindowControls extends StatefulWidget {
  const DesktopWindowControls({super.key});

  @override
  State<DesktopWindowControls> createState() => _DesktopWindowControlsState();
}

class _DesktopWindowControlsState extends State<DesktopWindowControls>
    with WindowListener {
  bool _isMaximized = false;
  bool _isFullScreen = false;

  bool get _showOnLeadingEdge => defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();
    if (!supportsCustomDesktopWindowFrame) return;
    windowManager.addListener(this);
    _loadInitialWindowState();
  }

  Future<void> _loadInitialWindowState() async {
    _isMaximized = await windowManager.isMaximized();
    _isFullScreen = await windowManager.isFullScreen();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    if (supportsCustomDesktopWindowFrame) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  List<Widget> _buildButtons(Brightness brightness) {
    final maximizeButton = _isMaximized
        ? WindowCaptionButton.unmaximize(
            brightness: brightness,
            onPressed: windowManager.unmaximize,
          )
        : WindowCaptionButton.maximize(
            brightness: brightness,
            onPressed: windowManager.maximize,
          );

    final leadingButtons = <Widget>[
      WindowCaptionButton.close(
        brightness: brightness,
        onPressed: windowManager.close,
      ),
      WindowCaptionButton.minimize(
        brightness: brightness,
        onPressed: windowManager.minimize,
      ),
      maximizeButton,
    ];

    final trailingButtons = <Widget>[
      WindowCaptionButton.minimize(
        brightness: brightness,
        onPressed: windowManager.minimize,
      ),
      maximizeButton,
      WindowCaptionButton.close(
        brightness: brightness,
        onPressed: windowManager.close,
      ),
    ];

    return _showOnLeadingEdge ? leadingButtons : trailingButtons;
  }

  @override
  Widget build(BuildContext context) {
    if (!supportsCustomDesktopWindowFrame || _isFullScreen) {
      return const SizedBox.shrink();
    }

    final buttons = _buildButtons(Theme.of(context).brightness);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: buttons,
    );
  }

  @override
  void onWindowEnterFullScreen() {
    if (!mounted) return;
    setState(() {
      _isFullScreen = true;
    });
  }

  @override
  void onWindowLeaveFullScreen() {
    if (!mounted) return;
    setState(() {
      _isFullScreen = false;
    });
  }

  @override
  void onWindowMaximize() {
    if (!mounted) return;
    setState(() {
      _isMaximized = true;
    });
  }

  @override
  void onWindowUnmaximize() {
    if (!mounted) return;
    setState(() {
      _isMaximized = false;
    });
  }
}

class DesktopWindowHeader extends StatelessWidget
    implements PreferredSizeWidget {
  final Widget title;
  final List<Widget> actions;
  final Widget? leading;

  const DesktopWindowHeader({
    required this.title,
    this.actions = const <Widget>[],
    this.leading,
    super.key,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kDesktopWindowHeaderHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const controls = DesktopWindowControls();

    return Material(
      color: theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface,
      child: SizedBox(
        height: kDesktopWindowHeaderHeight,
        child: Row(
          children: [
            if (supportsCustomDesktopWindowFrame &&
                defaultTargetPlatform == TargetPlatform.macOS) ...[
              const SizedBox(width: 8),
              controls,
              const SizedBox(width: 8),
            ],
            if (leading != null) leading!,
            Expanded(
              child: DragToMoveArea(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DefaultTextStyle(
                    style: theme.textTheme.titleSmall ??
                        const TextStyle(fontSize: 14),
                    child: title,
                  ),
                ),
              ),
            ),
            ...actions,
            if (supportsCustomDesktopWindowFrame &&
                defaultTargetPlatform != TargetPlatform.macOS) ...[
              const SizedBox(width: 8),
              controls,
            ],
          ],
        ),
      ),
    );
  }
}
