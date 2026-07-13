// =============================================================================
// canvas_grid_painter.dart - Canvas Grid Background / 画布网格背景
// =============================================================================
// CustomPainter that draws a subtle grid pattern on the annotation canvas
// background to help users gauge scale and alignment.
//
// 自定义绘制器，在标注画布背景上绘制细微网格，帮助用户判断比例和对齐。
// =============================================================================

import 'package:flutter/material.dart';

import '../../theme/colors.dart';

class CanvasGridPainter extends CustomPainter {
  const CanvasGridPainter(this.darkMode);

  final bool darkMode;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = darkMode
          ? appDarkLevel6.withValues(alpha: 0.72)
          : appLightLevel6.withValues(alpha: 0.76)
      ..strokeWidth = 1;

    const step = 32.0;
    for (double x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CanvasGridPainter oldDelegate) =>
      oldDelegate.darkMode != darkMode;
}
