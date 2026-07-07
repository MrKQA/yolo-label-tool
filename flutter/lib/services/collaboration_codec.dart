part of '../main.dart';

List<_LabelClass> _collaborationClassesFromJson(Object? value) {
  final rawClasses = value;
  if (rawClasses is! List) {
    return const [];
  }
  final classes = <_LabelClass>[];
  final seenIds = <int>{};
  for (final rawClass in rawClasses) {
    final labelClass = _collaborationMap(rawClass);
    final classId = _collaborationInt(
      labelClass,
      'id',
      fallback: classes.length,
    );
    if (!seenIds.add(classId)) {
      continue;
    }
    classes.add(
      _LabelClass(
        id: classId,
        name: _collaborationString(labelClass, 'name').trim().isEmpty
            ? 'class_${classes.length}'
            : _collaborationString(labelClass, 'name'),
        colorValue: _collaborationInt(
          labelClass,
          'color',
          fallback:
              _labelColorPalette[classes.length % _labelColorPalette.length]
                  .toARGB32(),
        ),
      ),
    );
  }
  return classes;
}

int _nextClassSerialFor(Iterable<_LabelClass> classes) {
  var next = 1;
  for (final labelClass in classes) {
    if (labelClass.id >= next) {
      next = labelClass.id + 1;
    }
  }
  return next;
}

String _collaborationCacheFileName(String remotePath, String name) {
  final rawName = name.trim().isEmpty ? _fileName(remotePath) : name.trim();
  final safeName = rawName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
  final displayName = safeName.isEmpty ? 'image' : safeName;
  return '${_stableCollaborationHash(remotePath)}_$displayName';
}

String _stableCollaborationHash(String value) {
  var hash = 2166136261;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 16777619) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

_AnnotationRegion? _collaborationAnnotationFromJson(Object? value) {
  final data = _collaborationMap(value);
  final id = _collaborationString(data, 'id');
  if (id.isEmpty) {
    return null;
  }
  final mode = _annotationModeFromDatabase(_collaborationString(data, 'mode'));
  final points = <Offset>[];
  final rawPoints = data['points'];
  if (rawPoints is List) {
    for (final rawPoint in rawPoints) {
      final point = _collaborationMap(rawPoint);
      points.add(
        Offset(
          _collaborationDouble(point, 'x'),
          _collaborationDouble(point, 'y'),
        ),
      );
    }
  }
  return _AnnotationRegion(
    id: id,
    mode: mode,
    rect: Rect.fromLTRB(
      _collaborationDouble(data, 'left'),
      _collaborationDouble(data, 'top'),
      _collaborationDouble(data, 'right'),
      _collaborationDouble(data, 'bottom'),
    ),
    classId: _collaborationInt(data, 'classId', fallback: 0),
    rotationDegrees: _collaborationDouble(data, 'rotation'),
    points: points,
    authorId: _collaborationString(data, 'authorId'),
    authorName: _collaborationString(data, 'authorName'),
    authorColorValue: _collaborationInt(data, 'authorColor', fallback: 0),
  );
}

Map<String, dynamic> _collaborationMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
}

String _collaborationString(Map<String, dynamic> map, String key) =>
    '${map[key] ?? ''}';

int _collaborationInt(
  Map<String, dynamic> map,
  String key, {
  required int fallback,
}) {
  final value = map[key];
  if (value is num) {
    return value.round();
  }
  return int.tryParse('$value') ?? fallback;
}

bool _collaborationBool(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is bool) {
    return value;
  }
  return '$value'.toLowerCase() == 'true' || '$value' == '1';
}

double _collaborationDouble(
  Map<String, dynamic> map,
  String key, {
  double fallback = 0,
}) {
  final value = map[key];
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse('$value') ?? fallback;
}
