import 'dart:math' as math;
import 'dart:ui';

class AiOrientedRect {
  const AiOrientedRect({required this.rect, required this.rotationDegrees});

  final Rect rect;
  final double rotationDegrees;
}

List<Offset> scaleAiPoints(
  List<Offset> points, {
  required Size sourceSize,
  required Size displaySize,
}) {
  if (sourceSize.width <= 0 || sourceSize.height <= 0) {
    return const [];
  }
  return [
    for (final point in points)
      Offset(
        point.dx / sourceSize.width * displaySize.width,
        point.dy / sourceSize.height * displaySize.height,
      ),
  ];
}

Rect pointsBounds(List<Offset> points) {
  if (points.isEmpty) {
    return Rect.zero;
  }
  var minX = points.first.dx;
  var minY = points.first.dy;
  var maxX = points.first.dx;
  var maxY = points.first.dy;
  for (final point in points.skip(1)) {
    minX = math.min(minX, point.dx);
    minY = math.min(minY, point.dy);
    maxX = math.max(maxX, point.dx);
    maxY = math.max(maxY, point.dy);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

AiOrientedRect minimumAreaRect(List<Offset> points) {
  if (points.length < 3) {
    return AiOrientedRect(rect: pointsBounds(points), rotationDegrees: 0);
  }
  final hull = _convexHull(points);
  if (hull.length < 3) {
    return AiOrientedRect(rect: pointsBounds(points), rotationDegrees: 0);
  }
  var bestArea = double.infinity;
  Rect bestRect = pointsBounds(points);
  var bestAngle = 0.0;
  for (var i = 0; i < hull.length; i++) {
    final current = hull[i];
    final next = hull[(i + 1) % hull.length];
    final angle = math.atan2(next.dy - current.dy, next.dx - current.dx);
    final rotated = [for (final point in hull) _rotateOffset(point, -angle)];
    final rect = pointsBounds(rotated);
    final area = rect.width * rect.height;
    if (area >= bestArea) {
      continue;
    }
    bestArea = area;
    bestAngle = angle;
    final center = _rotateOffset(rect.center, angle);
    bestRect = Rect.fromCenter(
      center: center,
      width: rect.width,
      height: rect.height,
    );
  }
  return AiOrientedRect(
    rect: bestRect,
    rotationDegrees: bestAngle * 180 / math.pi,
  );
}

List<Offset> _convexHull(List<Offset> points) {
  final sorted = List<Offset>.of(points)
    ..sort((a, b) {
      final x = a.dx.compareTo(b.dx);
      return x != 0 ? x : a.dy.compareTo(b.dy);
    });
  if (sorted.length <= 1) {
    return sorted;
  }
  final lower = <Offset>[];
  for (final point in sorted) {
    while (lower.length >= 2 &&
        _cross(lower[lower.length - 2], lower.last, point) <= 0) {
      lower.removeLast();
    }
    lower.add(point);
  }
  final upper = <Offset>[];
  for (final point in sorted.reversed) {
    while (upper.length >= 2 &&
        _cross(upper[upper.length - 2], upper.last, point) <= 0) {
      upper.removeLast();
    }
    upper.add(point);
  }
  lower.removeLast();
  upper.removeLast();
  return [...lower, ...upper];
}

double _cross(Offset origin, Offset a, Offset b) {
  return (a.dx - origin.dx) * (b.dy - origin.dy) -
      (a.dy - origin.dy) * (b.dx - origin.dx);
}

Offset _rotateOffset(Offset point, double radians) {
  final cos = math.cos(radians);
  final sin = math.sin(radians);
  return Offset(
    point.dx * cos - point.dy * sin,
    point.dx * sin + point.dy * cos,
  );
}
