part of '../../main.dart';

class _CanvasGridPainter extends CustomPainter {
  const _CanvasGridPainter(this.darkMode);

  final bool darkMode;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = darkMode ? const Color(0xFF3B2A68) : const Color(0xFFE2E8F0)
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
  bool shouldRepaint(covariant _CanvasGridPainter oldDelegate) =>
      oldDelegate.darkMode != darkMode;
}
