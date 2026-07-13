// =============================================================================
// annotation_database_codec.dart - Annotation Database Codec / 标注数据库编解码
// =============================================================================
// Serializes/deserializes annotation project data (images, classes, annotations,
// splits, display sizes, collaboration metadata) to/from JSON payloads used
// by the Rust SQLite backend.
//
// 将标注项目数据序列化/反序列化为 JSON，供 Rust SQLite 后端存取。
// =============================================================================

import 'dart:ui' show Offset, Rect, Size;

import '../models/annotation.dart';
import '../models/collaboration.dart';
import '../models/imported_dataset.dart';
import 'path_utils.dart';

String buildAnnotationDatabasePayload({
  required List<ImageItem> images,
  required List<LabelClass> labelClasses,
  required Map<String, List<AnnotationRegion>> annotationsByImage,
  required Map<String, String> imageSplits,
  required Map<String, Size> imageDisplaySizes,
  required ImportedDataset? importedDataset,
  required CollaborationMode collaborationMode,
  required CollaborationPermissions collaborationSelfPermissions,
  required String collaborationAuthorId,
  required String currentAnnotatorName,
  required int currentAnnotatorColorValue,
  required int collaborationStartIndex,
  required int collaborationEndIndex,
  required List<CollaborationPeer> collaborationPeers,
  bool includeClasses = true,
  bool includeAnnotations = true,
}) {
  final lines = <String>[
    'PROJECT\t${_databaseField(annotationDatabaseProjectKey(importedDataset: importedDataset, images: images))}',
  ];
  if (includeClasses) {
    for (final labelClass in labelClasses) {
      lines.add(
        [
          'CLASS',
          labelClass.id,
          labelClass.name,
          labelClass.colorValue,
        ].map(_databaseField).join('\t'),
      );
    }
  }

  for (var index = 0; index < images.length; index++) {
    final image = images[index];
    final imageKey = pathKey(image.path);
    final size = _imageDisplaySizeForDatabase(imageDisplaySizes, image.path);
    lines.add(
      [
        'IMAGE',
        image.path,
        image.name,
        imageSplits[imageKey] ?? 'train',
        _databaseNumber(size.width),
        _databaseNumber(size.height),
        index,
      ].map(_databaseField).join('\t'),
    );
  }

  if (includeAnnotations) {
    for (final image in images) {
      final imageKey = pathKey(image.path);
      final annotations = annotationsByImage[imageKey] ?? const [];
      for (final annotation in annotations) {
        final rect = annotation.rect;
        lines.add(
          [
            'ANNOTATION',
            image.path,
            annotation.id,
            annotation.mode.name,
            annotation.classId,
            _databaseNumber(rect.left),
            _databaseNumber(rect.top),
            _databaseNumber(rect.right),
            _databaseNumber(rect.bottom),
            _databaseNumber(annotation.rotationDegrees),
            _annotationPointsForDatabase(annotation),
            annotation.authorId.isEmpty ? 'manual' : 'collab',
            '0',
            annotation.authorId,
            annotation.authorName,
            annotation.authorColorValue,
          ].map(_databaseField).join('\t'),
        );
      }
    }
  }

  final selfPermissions = collaborationMode == CollaborationMode.client
      ? collaborationSelfPermissions
      : const CollaborationPermissions(
          canEditOthers: true,
          canDeleteOthers: true,
          canChangeClass: true,
        );
  lines.add(
    [
      'COLLAB_USER',
      collaborationAuthorId,
      currentAnnotatorName,
      currentAnnotatorColorValue,
      selfPermissions.canEditOthers ? '1' : '0',
      selfPermissions.canDeleteOthers ? '1' : '0',
      selfPermissions.canChangeClass ? '1' : '0',
      collaborationStartIndex,
      collaborationEndIndex,
    ].map(_databaseField).join('\t'),
  );
  for (final peer in collaborationPeers) {
    if (peer.userId == collaborationAuthorId) {
      continue;
    }
    final permissions = peer.permissions;
    lines.add(
      [
        'COLLAB_USER',
        peer.userId,
        peer.userName,
        peer.colorValue,
        permissions.canEditOthers ? '1' : '0',
        permissions.canDeleteOthers ? '1' : '0',
        permissions.canChangeClass ? '1' : '0',
        peer.assignmentStart,
        peer.assignmentEnd,
      ].map(_databaseField).join('\t'),
    );
  }
  return lines.join('\n');
}

String annotationDatabaseProjectKey({
  required ImportedDataset? importedDataset,
  required List<ImageItem> images,
}) {
  final imported = importedDataset;
  if (imported != null) {
    return 'dataset:${pathKey(imported.dataYamlPath)}';
  }
  if (images.isEmpty) {
    return 'default';
  }
  final directories = {
    for (final image in images) pathKey(directoryName(image.path)),
  }.toList()..sort();
  if (directories.length == 1) {
    return 'folder:${directories.first}';
  }
  return 'workspace:${directories.join('|')}';
}

Size _imageDisplaySizeForDatabase(
  Map<String, Size> imageDisplaySizes,
  String path,
) {
  final key = pathKey(path);
  return imageDisplaySizes[key] ?? imageDisplaySizes[path] ?? Size.zero;
}

String _databaseField(Object? value) {
  return '${value ?? ''}'
      .replaceAll('\t', ' ')
      .replaceAll('\r', ' ')
      .replaceAll('\n', ' ');
}

String _databaseNumber(num value) {
  if (!value.isFinite) {
    return '0';
  }
  return value.toStringAsFixed(6);
}

String _annotationPointsForDatabase(AnnotationRegion annotation) {
  final points = annotation.mode == AnnotationMode.seg
      ? annotation.points
      : const <Offset>[];
  return points
      .map(
        (point) => '${_databaseNumber(point.dx)},${_databaseNumber(point.dy)}',
      )
      .join(';');
}

List<Offset> _annotationPointsFromDatabase(String raw) {
  final points = <Offset>[];
  for (final token in raw.split(';')) {
    final parts = token.split(',');
    if (parts.length != 2) {
      continue;
    }
    final x = double.tryParse(parts[0]);
    final y = double.tryParse(parts[1]);
    if (x != null && y != null) {
      points.add(Offset(x, y));
    }
  }
  return points;
}

AnnotationMode _annotationModeFromDatabase(String raw) {
  return switch (raw.toLowerCase()) {
    'obb' => AnnotationMode.obb,
    'seg' => AnnotationMode.seg,
    _ => AnnotationMode.hbb,
  };
}

List<LabelClass> labelClassesFromDatabase(Object? raw) {
  if (raw is! List) {
    return const [];
  }
  final classes = <LabelClass>[];
  for (final item in raw) {
    if (item is! Map) {
      continue;
    }
    final id = (item['id'] as num?)?.toInt();
    final name = '${item['name'] ?? ''}'.trim();
    final color = (item['color'] as num?)?.toInt();
    if (id == null || name.isEmpty || color == null) {
      continue;
    }
    classes.add(LabelClass(id: id, name: name, colorValue: color));
  }
  classes.sort((a, b) => a.id.compareTo(b.id));
  return classes;
}

Map<String, List<AnnotationRegion>> annotationsFromDatabase(
  Object? raw,
  Set<String> openImageKeys,
) {
  final result = <String, List<AnnotationRegion>>{};
  if (raw is! List) {
    return result;
  }
  for (final item in raw) {
    if (item is! Map) {
      continue;
    }
    final imagePath = '${item['imagePath'] ?? ''}';
    final imageKey = pathKey(imagePath);
    if (!openImageKeys.contains(imageKey)) {
      continue;
    }
    final id = '${item['id'] ?? ''}';
    final classId = (item['classId'] as num?)?.toInt();
    if (id.isEmpty || classId == null) {
      continue;
    }
    final mode = _annotationModeFromDatabase('${item['kind'] ?? ''}');
    final rect = Rect.fromLTRB(
      ((item['left'] as num?) ?? 0).toDouble(),
      ((item['top'] as num?) ?? 0).toDouble(),
      ((item['right'] as num?) ?? 0).toDouble(),
      ((item['bottom'] as num?) ?? 0).toDouble(),
    );
    final points = mode == AnnotationMode.seg
        ? _annotationPointsFromDatabase('${item['points'] ?? ''}')
        : const <Offset>[];
    result
        .putIfAbsent(imageKey, () => [])
        .add(
          AnnotationRegion(
            id: id,
            mode: mode,
            rect: normalizeRect(rect),
            classId: classId,
            rotationDegrees: ((item['rotation'] as num?) ?? 0).toDouble(),
            points: points,
            authorId: '${item['authorId'] ?? ''}',
            authorName: '${item['authorName'] ?? ''}',
            authorColorValue: (item['authorColor'] as num?)?.toInt() ?? 0,
          ),
        );
  }
  return result;
}

int nextAnnotationSerialFor(
  Map<String, List<AnnotationRegion>> annotationsByImage,
) {
  var next = 1;
  final pattern = RegExp(r'^ann_(\d+)$');
  for (final annotations in annotationsByImage.values) {
    for (final annotation in annotations) {
      final match = pattern.firstMatch(annotation.id);
      if (match == null) {
        next += 1;
        continue;
      }
      final value = int.tryParse(match.group(1) ?? '');
      if (value != null && value >= next) {
        next = value + 1;
      }
    }
  }
  return next;
}
