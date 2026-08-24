import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class StartupLoadingScreen extends StatefulWidget {
  const StartupLoadingScreen({super.key});

  @override
  State<StartupLoadingScreen> createState() => _StartupLoadingScreenState();
}

class _StartupLoadingScreenState extends State<StartupLoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _bounce;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _bounce = Tween<double>(begin: 0, end: -10).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return ColoredBox(
      color: color.withValues(alpha: 0.06),
      child: Center(
        child: AnimatedBuilder(
          animation: _bounce,
          child: SvgPicture.asset(
            'assets/icons/icon-transparent.svg',
            width: 100,
            height: 100,
            semanticsLabel: 'TypeSync is loading',
          ),
          builder: (context, child) => Transform.translate(
            offset: Offset(0, _bounce.value),
            child: child,
          ),
        ),
      ),
    );
  }
}
