import 'dart:ui';

import '../models/annotation.dart';
import '../theme/colors.dart' as colors;
import 'path_utils.dart';

List<LabelClass> collaborationClassesFromJson(Object? value) {
  final rawClasses = value;
  if (rawClasses is! List) {
    return const [];
  }
  final classes = <LabelClass>[];
  final seenIds = <int>{};
  for (final rawClass in rawClasses) {
    final labelClass = collaborationMap(rawClass);
    final classId = collaborationInt(
      labelClass,
      'id',
      fallback: classes.length,
    );
    if (!seenIds.add(classId)) {
      continue;
    }
    classes.add(
      LabelClass(
        id: classId,
        name: collaborationString(labelClass, 'name').trim().isEmpty
            ? 'class_${classes.length}'
            : collaborationString(labelClass, 'name'),
        colorValue: collaborationInt(
          labelClass,
          'color',
          fallback: colors
              .labelColorPalette[classes.length % colors.labelColorPalette.length]
              .toARGB32(),
        ),
      ),
    );
  }
  return classes;
}

int nextClassSerialFor(Iterable<LabelClass> classes) {
  var next = 1;
  for (final labelClass in classes) {
    if (labelClass.id >= next) {
      next = labelClass.id + 1;
    }
  }
  return next;
}

String collaborationCacheFileName(String remotePath, String name) {
  final rawName = name.trim().isEmpty ? fileName(remotePath) : name.trim();
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

AnnotationRegion? collaborationAnnotationFromJson(Object? value) {
  final data = collaborationMap(value);
  final id = collaborationString(data, 'id');
  if (id.isEmpty) {
    return null;
  }
  final mode = _collaborationAnnotationModeFromJson(
    collaborationString(data, 'mode'),
  );
  final points = <Offset>[];
  final rawPoints = data['points'];
  if (rawPoints is List) {
    for (final rawPoint in rawPoints) {
      final point = collaborationMap(rawPoint);
      points.add(
        Offset(
          collaborationDouble(point, 'x'),
          collaborationDouble(point, 'y'),
        ),
      );
    }
  }
  return AnnotationRegion(
    id: id,
    mode: mode,
    rect: Rect.fromLTRB(
      collaborationDouble(data, 'left'),
      collaborationDouble(data, 'top'),
      collaborationDouble(data, 'right'),
      collaborationDouble(data, 'bottom'),
    ),
    classId: collaborationInt(data, 'classId', fallback: 0),
    rotationDegrees: collaborationDouble(data, 'rotation'),
    points: points,
    authorId: collaborationString(data, 'authorId'),
    authorName: collaborationString(data, 'authorName'),
    authorColorValue: collaborationInt(data, 'authorColor', fallback: 0),
  );
}

Map<String, dynamic> collaborationMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
}

String collaborationString(Map<String, dynamic> map, String key) =>
    '${map[key] ?? ''}';

int collaborationInt(
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

bool collaborationBool(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is bool) {
    return value;
  }
  return '$value'.toLowerCase() == 'true' || '$value' == '1';
}

double collaborationDouble(
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

AnnotationMode _collaborationAnnotationModeFromJson(String raw) {
  return switch (raw.toLowerCase()) {
    'obb' => AnnotationMode.obb,
    'seg' => AnnotationMode.seg,
    _ => AnnotationMode.hbb,
  };
}
