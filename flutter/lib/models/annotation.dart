// =============================================================================
// AnnotationModels.dart - Annotation Data Models / 标注数据模型
// =============================================================================
// HBB/OBB/SEG annotation region model with hit-testing, coordinate
// transforms, YOLO-format export, and image item representation.
//
// HBB/OBB/SEG 标注区域数据模型：命中检测、坐标变换、YOLO 格式导出、
// 图像文件条目。
// =============================================================================

// ignore_for_file: file_names

import 'dart:math' as math;
import 'dart:ui';

import '../services/path_utils.dart';

/// 标注模式，分别对应 YOLO HBB、OBB 和实例分割。
/// Annotation mode for YOLO HBB, OBB, and instance segmentation.
enum AnnotationMode { hbb, obb, seg }

extension AnnotationModeLabel on AnnotationMode {
  String get label => switch (this) {
    AnnotationMode.hbb => 'HBB',
    AnnotationMode.obb => 'OBB',
    AnnotationMode.seg => 'SEG',
  };
}

/// 图片列表中的文件条目。
/// Image file item used by the preview list.
class ImageItem {
  const ImageItem({required this.path, required this.name});

  factory ImageItem.fromPath(String path) {
    return ImageItem(path: path, name: fileName(path));
  }

  final String path;
  final String name;
}

/// 标注类别，颜色以整数保存，方便后续写入 JSON/SQLite。
/// Label class. The color is stored as an integer for JSON/SQLite persistence.
class LabelClass {
  const LabelClass({
    required this.id,
    required this.name,
    required this.colorValue,
  });

  final int id;
  final String name;
  final int colorValue;

  Color get color => Color(colorValue);

  LabelClass copyWith({String? name, int? colorValue}) {
    return LabelClass(
      id: id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
    );
  }
}

/// 单个标注区域。HBB/OBB 用 rect 表示，SEG 额外保留多边形节点。
/// One annotation region. HBB/OBB use rect; SEG also keeps polygon points.
class AnnotationRegion {
  const AnnotationRegion({
    required this.id,
    required this.mode,
    required this.rect,
    required this.classId,
    this.rotationDegrees = 0,
    this.points = const [],
    this.authorId = '',
    this.authorName = '',
    this.authorColorValue = 0,
  });

  factory AnnotationRegion.fromRect({
    required String id,
    required AnnotationMode mode,
    required Rect rect,
    required int classId,
    String authorId = '',
    String authorName = '',
    int authorColorValue = 0,
  }) {
    final normalized = normalizeRect(rect);
    return AnnotationRegion(
      id: id,
      mode: mode,
      rect: normalized,
      classId: classId,
      points: mode == AnnotationMode.seg
          ? rectToPoints(normalized)
          : const [],
      authorId: authorId,
      authorName: authorName,
      authorColorValue: authorColorValue,
    );
  }

  final String id;
  final AnnotationMode mode;
  final Rect rect;
  final int classId;
  final double rotationDegrees;
  final List<Offset> points;
  final String authorId;
  final String authorName;
  final int authorColorValue;

  AnnotationRegion copyWith({
    Rect? rect,
    int? classId,
    double? rotationDegrees,
    List<Offset>? points,
    String? authorId,
    String? authorName,
    int? authorColorValue,
  }) {
    return AnnotationRegion(
      id: id,
      mode: mode,
      rect: rect ?? this.rect,
      classId: classId ?? this.classId,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      points: points ?? this.points,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      authorColorValue: authorColorValue ?? this.authorColorValue,
    );
  }

  AnnotationRegion translated(Offset delta) {
    return copyWith(
      rect: rect.shift(delta),
      points: [for (final point in points) point + delta],
    );
  }

  AnnotationRegion clampedTo(Rect bounds) {
    final shiftedRect = _shiftRectIntoBounds(rect, bounds);
    final delta = shiftedRect.topLeft - rect.topLeft;
    return copyWith(
      rect: shiftedRect,
      points: [for (final point in points) clampOffset(point + delta, bounds)],
    );
  }

  AnnotationRegion rotated(double deltaDegrees) {
    return copyWith(rotationDegrees: rotationDegrees + deltaDegrees);
  }

  AnnotationRegion clampObbToImage(Size imageSize) {
    if (mode != AnnotationMode.obb) {
      return clampedTo(Rect.fromLTWH(0, 0, imageSize.width, imageSize.height));
    }
    var result = clampedTo(
      Rect.fromLTWH(0, 0, imageSize.width, imageSize.height),
    );
    final corners = rotatedCorners(result.rect, result.rotationDegrees);
    var dx = 0.0;
    var dy = 0.0;
    double minX = corners[0].dx, maxX = corners[0].dx;
    double minY = corners[0].dy, maxY = corners[0].dy;
    for (final c in corners) {
      if (c.dx < minX) minX = c.dx;
      if (c.dx > maxX) maxX = c.dx;
      if (c.dy < minY) minY = c.dy;
      if (c.dy > maxY) maxY = c.dy;
    }
    if (minX < 0) dx = -minX;
    if (maxX > imageSize.width) dx = imageSize.width - maxX;
    if (minY < 0) dy = -minY;
    if (maxY > imageSize.height) dy = imageSize.height - maxY;
    if (dx != 0 || dy != 0) {
      result = result.copyWith(rect: result.rect.shift(Offset(dx, dy)));
    }
    return result;
  }

  AnnotationRegion duplicate(String newId) {
    return AnnotationRegion(
      id: newId,
      mode: mode,
      rect: rect.shift(const Offset(18, 18)),
      classId: classId,
      rotationDegrees: rotationDegrees,
      points: [for (final point in points) point + const Offset(18, 18)],
      authorId: authorId,
      authorName: authorName,
      authorColorValue: authorColorValue,
    );
  }

  bool hitTest(Offset point) {
    if (mode == AnnotationMode.seg && points.length >= 3) {
      final path = Path()..addPolygon(points, true);
      if (path.contains(point)) {
        return true;
      }
    }
    return rect.inflate(6).contains(point);
  }

  String toUltralyticsLabelLine({
    required int classIndex,
    required Size imageSize,
  }) {
    final values = switch (mode) {
      AnnotationMode.hbb => _hbbValues(imageSize),
      AnnotationMode.obb => _obbValues(imageSize),
      AnnotationMode.seg => _segValues(imageSize),
    };
    return '$classIndex ${values.map(_formatYoloValue).join(' ')}';
  }

  List<double> _hbbValues(Size imageSize) {
    final w = imageSize.width;
    final h = imageSize.height;
    if (w <= 0 || h <= 0) {
      return const [0, 0, 0, 0];
    }
    return [
      (rect.center.dx / w).clamp(0.0, 1.0),
      (rect.center.dy / h).clamp(0.0, 1.0),
      (rect.width / w).clamp(0.0, 1.0),
      (rect.height / h).clamp(0.0, 1.0),
    ];
  }

  List<double> _obbValues(Size imageSize) {
    final w = imageSize.width;
    final h = imageSize.height;
    if (w <= 0 || h <= 0) {
      return List.filled(8, 0.0);
    }
    final corners = rotatedCorners(rect, rotationDegrees);
    return [
      for (final point in corners) ...[
        (point.dx / w).clamp(0.0, 1.0),
        (point.dy / h).clamp(0.0, 1.0),
      ],
    ];
  }

  List<double> _segValues(Size imageSize) {
    final w = imageSize.width;
    final h = imageSize.height;
    if (w <= 0 || h <= 0) {
      return [];
    }
    final polygon = points.length >= 3 ? points : rectToPoints(rect);
    return [
      for (final point in polygon) ...[
        (point.dx / w).clamp(0.0, 1.0),
        (point.dy / h).clamp(0.0, 1.0),
      ],
    ];
  }
}

Rect normalizeRect(Rect rect) {
  return Rect.fromLTRB(
    rect.left < rect.right ? rect.left : rect.right,
    rect.top < rect.bottom ? rect.top : rect.bottom,
    rect.left < rect.right ? rect.right : rect.left,
    rect.top < rect.bottom ? rect.bottom : rect.top,
  );
}

List<Offset> rectToPoints(Rect rect) {
  return [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft];
}

Rect _shiftRectIntoBounds(Rect rect, Rect bounds) {
  var dx = 0.0;
  var dy = 0.0;
  if (rect.left < bounds.left) {
    dx = bounds.left - rect.left;
  } else if (rect.right > bounds.right) {
    dx = bounds.right - rect.right;
  }
  if (rect.top < bounds.top) {
    dy = bounds.top - rect.top;
  } else if (rect.bottom > bounds.bottom) {
    dy = bounds.bottom - rect.bottom;
  }
  final shifted = rect.shift(Offset(dx, dy));
  return shifted.intersect(bounds);
}

Offset clampOffset(Offset point, Rect bounds) {
  return Offset(
    point.dx.clamp(bounds.left, bounds.right).toDouble(),
    point.dy.clamp(bounds.top, bounds.bottom).toDouble(),
  );
}

List<Offset> rotatedCorners(Rect rect, double degrees) {
  final radians = degrees * math.pi / 180;
  final center = rect.center;
  return [
    rect.topLeft,
    rect.topRight,
    rect.bottomRight,
    rect.bottomLeft,
  ].map((point) => rotatePoint(point, center, radians)).toList();
}

Offset rotatePoint(Offset point, Offset center, double radians) {
  final dx = point.dx - center.dx;
  final dy = point.dy - center.dy;
  final cosValue = math.cos(radians);
  final sinValue = math.sin(radians);
  return Offset(
    center.dx + dx * cosValue - dy * sinValue,
    center.dy + dx * sinValue + dy * cosValue,
  );
}

String _formatYoloValue(double value) {
  return value.clamp(0.0, 1.0).toStringAsFixed(6);
}
