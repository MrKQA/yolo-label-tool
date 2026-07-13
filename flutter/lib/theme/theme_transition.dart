import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/app_runtime.dart';

class AppThemeRippleTransition extends StatefulWidget {
  const AppThemeRippleTransition({super.key, required this.child});

  final Widget child;

  @override
  State<AppThemeRippleTransition> createState() =>
      _AppThemeRippleTransitionState();
}

class _AppThemeRippleTransitionState extends State<AppThemeRippleTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  AppThemeTransitionSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    )..addStatusListener(_handleAnimationStatus);
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );
    appThemeTransitionSnapshotNotifier.addListener(_handleSnapshotChanged);
  }

  @override
  void dispose() {
    appThemeTransitionSnapshotNotifier.removeListener(_handleSnapshotChanged);
    _controller
      ..removeStatusListener(_handleAnimationStatus)
      ..dispose();
    final snapshot = _snapshot;
    if (snapshot != null) {
      completeAppThemeTransition(snapshot);
    }
    super.dispose();
  }

  void _handleSnapshotChanged() {
    final snapshot = appThemeTransitionSnapshotNotifier.value;
    if (snapshot == null || identical(snapshot, _snapshot)) {
      return;
    }
    final previous = _snapshot;
    if (previous != null) {
      completeAppThemeTransition(previous);
    }
    setState(() => _snapshot = snapshot);
    _controller.forward(from: 0);
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) {
      return;
    }
    final snapshot = _snapshot;
    if (snapshot == null) {
      return;
    }
    setState(() => _snapshot = null);
    completeAppThemeTransition(snapshot);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(key: appThemeCaptureBoundaryKey, child: widget.child),
        if (snapshot != null)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _animation,
                builder: (context, _) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final size = constraints.biggest;
                      final maxRadius = math.sqrt(
                        size.width * size.width + size.height * size.height,
                      );
                      final radius = maxRadius * _animation.value;
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipPath(
                            clipper: _OutsideRippleClipper(radius),
                            child: RawImage(
                              image: snapshot.image,
                              scale: snapshot.pixelRatio,
                              fit: BoxFit.fill,
                              filterQuality: FilterQuality.low,
                            ),
                          ),
                          CustomPaint(
                            painter: _RippleRingPainter(
                              radius: radius,
                              progress: _animation.value,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _OutsideRippleClipper extends CustomClipper<Path> {
  const _OutsideRippleClipper(this.radius);

  final double radius;

  @override
  Path getClip(Size size) {
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: Offset.zero, radius: radius));
  }

  @override
  bool shouldReclip(covariant _OutsideRippleClipper oldClipper) =>
      oldClipper.radius != radius;
}

class _RippleRingPainter extends CustomPainter {
  const _RippleRingPainter({
    required this.radius,
    required this.progress,
    required this.color,
  });

  final double radius;
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final opacity = math.sin(progress * math.pi).clamp(0.0, 1.0);
    if (opacity <= 0) {
      return;
    }
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: opacity * 0.34),
    );
    canvas.drawCircle(
      Offset.zero,
      math.max(0, radius - 12),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: opacity * 0.16),
    );
  }

  @override
  bool shouldRepaint(covariant _RippleRingPainter oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.progress != progress ||
      oldDelegate.color != color;
}
