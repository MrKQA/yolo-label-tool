// ignore_for_file: file_names

part of 'main.dart';

/// 标注模式，分别对应 YOLO HBB、OBB 和实例分割。
/// Annotation mode for YOLO HBB, OBB, and instance segmentation.
enum _AnnotationMode { hbb, obb, seg }

extension _AnnotationModeLabel on _AnnotationMode {
  String get label => switch (this) {
    _AnnotationMode.hbb => 'HBB',
    _AnnotationMode.obb => 'OBB',
    _AnnotationMode.seg => 'SEG',
  };
}

/// 图片列表中的文件条目。
/// Image file item used by the preview list.
class _ImageItem {
  const _ImageItem({required this.path, required this.name});

  factory _ImageItem.fromPath(String path) {
    return _ImageItem(path: path, name: _fileName(path));
  }

  final String path;
  final String name;
}

/// 标注类别，颜色以整数保存，方便后续写入 JSON/SQLite。
/// Label class. The color is stored as an integer for JSON/SQLite persistence.
class _LabelClass {
  const _LabelClass({
    required this.id,
    required this.name,
    required this.colorValue,
  });

  final int id;
  final String name;
  final int colorValue;

  Color get color => Color(colorValue);

  _LabelClass copyWith({String? name, int? colorValue}) {
    return _LabelClass(
      id: id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
    );
  }
}

/// 单个标注区域。HBB/OBB 用 rect 表示，SEG 额外保留多边形节点。
/// One annotation region. HBB/OBB use rect; SEG also keeps polygon points.
class _AnnotationRegion {
  const _AnnotationRegion({
    required this.id,
    required this.mode,
    required this.rect,
    required this.classId,
    this.rotationDegrees = 0,
    this.points = const [],
  });

  factory _AnnotationRegion.fromRect({
    required String id,
    required _AnnotationMode mode,
    required Rect rect,
    required int classId,
  }) {
    final normalized = _normalizeRect(rect);
    return _AnnotationRegion(
      id: id,
      mode: mode,
      rect: normalized,
      classId: classId,
      points: mode == _AnnotationMode.seg
          ? _rectToPoints(normalized)
          : const [],
    );
  }

  final String id;
  final _AnnotationMode mode;
  final Rect rect;
  final int classId;
  final double rotationDegrees;
  final List<Offset> points;

  _AnnotationRegion copyWith({
    Rect? rect,
    int? classId,
    double? rotationDegrees,
    List<Offset>? points,
  }) {
    return _AnnotationRegion(
      id: id,
      mode: mode,
      rect: rect ?? this.rect,
      classId: classId ?? this.classId,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      points: points ?? this.points,
    );
  }

  _AnnotationRegion translated(Offset delta) {
    return copyWith(
      rect: rect.shift(delta),
      points: [for (final point in points) point + delta],
    );
  }

  _AnnotationRegion clampedTo(Rect bounds) {
    final shiftedRect = _shiftRectIntoBounds(rect, bounds);
    final delta = shiftedRect.topLeft - rect.topLeft;
    return copyWith(
      rect: shiftedRect,
      points: [for (final point in points) _clampOffset(point + delta, bounds)],
    );
  }

  _AnnotationRegion rotated(double deltaDegrees) {
    return copyWith(rotationDegrees: rotationDegrees + deltaDegrees);
  }

  _AnnotationRegion duplicate(String newId) {
    return _AnnotationRegion(
      id: newId,
      mode: mode,
      rect: rect.shift(const Offset(18, 18)),
      classId: classId,
      rotationDegrees: rotationDegrees,
      points: [for (final point in points) point + const Offset(18, 18)],
    );
  }

  bool hitTest(Offset point) {
    if (mode == _AnnotationMode.seg && points.length >= 3) {
      final path = Path()..addPolygon(points, true);
      if (path.contains(point)) {
        return true;
      }
    }
    return rect.inflate(6).contains(point);
  }

  String toUltralyticsLabelLine({
    required int classIndex,
    required Rect imageRect,
  }) {
    final values = switch (mode) {
      _AnnotationMode.hbb => _hbbValues(imageRect),
      _AnnotationMode.obb => _obbValues(imageRect),
      _AnnotationMode.seg => _segValues(imageRect),
    };
    return '$classIndex ${values.map(_formatYoloValue).join(' ')}';
  }

  List<double> _hbbValues(Rect imageRect) {
    final clipped = rect.intersect(imageRect);
    if (clipped.isEmpty) {
      return const [0, 0, 0, 0];
    }
    return [
      _normalizeX(clipped.center.dx, imageRect),
      _normalizeY(clipped.center.dy, imageRect),
      _normalizeWidth(clipped.width, imageRect),
      _normalizeHeight(clipped.height, imageRect),
    ];
  }

  List<double> _obbValues(Rect imageRect) {
    final corners = _rotatedCorners(rect, rotationDegrees);
    return [
      for (final point in corners) ...[
        _normalizeX(point.dx, imageRect),
        _normalizeY(point.dy, imageRect),
      ],
    ];
  }

  List<double> _segValues(Rect imageRect) {
    final polygon = points.length >= 3 ? points : _rectToPoints(rect);
    return [
      for (final point in polygon) ...[
        _normalizeX(point.dx, imageRect),
        _normalizeY(point.dy, imageRect),
      ],
    ];
  }
}

Rect _normalizeRect(Rect rect) {
  return Rect.fromLTRB(
    rect.left < rect.right ? rect.left : rect.right,
    rect.top < rect.bottom ? rect.top : rect.bottom,
    rect.left < rect.right ? rect.right : rect.left,
    rect.top < rect.bottom ? rect.bottom : rect.top,
  );
}

List<Offset> _rectToPoints(Rect rect) {
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

Offset _clampOffset(Offset point, Rect bounds) {
  return Offset(
    point.dx.clamp(bounds.left, bounds.right).toDouble(),
    point.dy.clamp(bounds.top, bounds.bottom).toDouble(),
  );
}

List<Offset> _rotatedCorners(Rect rect, double degrees) {
  final radians = degrees * math.pi / 180;
  final center = rect.center;
  return [
    rect.topLeft,
    rect.topRight,
    rect.bottomRight,
    rect.bottomLeft,
  ].map((point) => _rotatePoint(point, center, radians)).toList();
}

Offset _rotatePoint(Offset point, Offset center, double radians) {
  final dx = point.dx - center.dx;
  final dy = point.dy - center.dy;
  final cosValue = math.cos(radians);
  final sinValue = math.sin(radians);
  return Offset(
    center.dx + dx * cosValue - dy * sinValue,
    center.dy + dx * sinValue + dy * cosValue,
  );
}

double _normalizeX(double x, Rect imageRect) {
  return ((x - imageRect.left) / imageRect.width).clamp(0.0, 1.0).toDouble();
}

double _normalizeY(double y, Rect imageRect) {
  return ((y - imageRect.top) / imageRect.height).clamp(0.0, 1.0).toDouble();
}

double _normalizeWidth(double width, Rect imageRect) {
  return (width / imageRect.width).clamp(0.0, 1.0).toDouble();
}

double _normalizeHeight(double height, Rect imageRect) {
  return (height / imageRect.height).clamp(0.0, 1.0).toDouble();
}

String _formatYoloValue(double value) {
  return value.clamp(0.0, 1.0).toStringAsFixed(6);
}
