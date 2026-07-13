// =============================================================================
// collaboration_codec.dart - Collaboration Network Codec / 协作网络编解码
// =============================================================================
// Encodes/decodes collaboration class lists, annotation snapshots, and
// permission records into JSON-compatible maps for UDP/TCP transport.
//
// 将协作类别列表、标注快照和权限记录编解码为网络传输用的 JSON 兼容 Map。
// =============================================================================

import 'dart:ui';

import '../models/annotation.dart';
import '../models/collaboration.dart';
import '../theme/colors.dart' as colors;
import 'collaboration_identity.dart';
import 'path_utils.dart';

typedef CollaborationLocalImageResolver =
    String Function(String remotePath, String name, String bytesBase64);

class CollaborationProjectSnapshot {
  const CollaborationProjectSnapshot({
    required this.images,
    required this.splits,
    required this.displaySizes,
    required this.classes,
    required this.annotations,
    required this.assignmentStart,
    required this.assignmentEnd,
    required this.nextClassSerial,
    required this.nextAnnotationSerial,
  });

  final List<ImageItem> images;
  final Map<String, String> splits;
  final Map<String, Size> displaySizes;
  final List<LabelClass> classes;
  final Map<String, List<AnnotationRegion>> annotations;
  final int assignmentStart;
  final int assignmentEnd;
  final int nextClassSerial;
  final int nextAnnotationSerial;
}

class CollaborationAnnotationSnapshot {
  const CollaborationAnnotationSnapshot({
    required this.imageIndex,
    required this.classes,
    required this.hasClassPayload,
    required this.annotations,
    required this.authoritative,
    required this.scopedAuthors,
  });

  final int imageIndex;
  final List<LabelClass> classes;
  final bool hasClassPayload;
  final List<AnnotationRegion> annotations;
  final bool authoritative;
  final Set<String> scopedAuthors;
}

List<Map<String, Object?>> collaborationClassesToJson(
  Iterable<LabelClass> classes,
) {
  return [
    for (final labelClass in classes)
      {
        'id': labelClass.id,
        'name': labelClass.name,
        'color': labelClass.colorValue,
      },
  ];
}

Map<String, Object?> collaborationAnnotationToJson(
  AnnotationRegion annotation, {
  required String fallbackAuthorId,
  required String fallbackAuthorName,
  required int fallbackAuthorColorValue,
}) {
  final rect = annotation.rect;
  return {
    'id': annotation.id,
    'mode': annotation.mode.name,
    'classId': annotation.classId,
    'left': rect.left,
    'top': rect.top,
    'right': rect.right,
    'bottom': rect.bottom,
    'rotation': annotation.rotationDegrees,
    'points': [
      for (final point in annotation.points) {'x': point.dx, 'y': point.dy},
    ],
    'authorId': annotation.authorId.trim().isEmpty
        ? fallbackAuthorId
        : annotation.authorId,
    'authorName': annotation.authorName.trim().isEmpty
        ? fallbackAuthorName
        : annotation.authorName,
    'authorColor': annotation.authorColorValue == 0
        ? fallbackAuthorColorValue
        : annotation.authorColorValue,
  };
}

Map<String, Object?> collaborationClassSnapshotToJson(
  Iterable<LabelClass> classes,
) {
  return {
    'type': 'class_snapshot',
    'classes': collaborationClassesToJson(classes),
  };
}

Map<String, Object?> collaborationProjectSnapshotToJson({
  required String projectKey,
  required List<ImageItem> images,
  required Map<String, String> imageSplits,
  required Map<String, Size> imageDisplaySizes,
  required List<LabelClass> classes,
  required Map<String, List<AnnotationRegion>> annotationsByImage,
  required int assignmentStart,
  required int assignmentEnd,
  required String fallbackAuthorId,
  required String fallbackAuthorName,
  required int fallbackAuthorColorValue,
  required String Function(String path) imageBytesBase64,
}) {
  Map<String, Object?> annotationToJson(AnnotationRegion annotation) {
    return collaborationAnnotationToJson(
      annotation,
      fallbackAuthorId: fallbackAuthorId,
      fallbackAuthorName: fallbackAuthorName,
      fallbackAuthorColorValue: fallbackAuthorColorValue,
    );
  }

  return {
    'type': 'project_snapshot',
    'projectKey': projectKey,
    'assignmentStart': assignmentStart,
    'assignmentEnd': assignmentEnd,
    'images': [
      for (var index = 0; index < images.length; index++)
        {
          'path': images[index].path,
          'name': images[index].name,
          'split': imageSplits[pathKey(images[index].path)] ?? 'train',
          'width':
              (imageDisplaySizes[pathKey(images[index].path)] ??
                      imageDisplaySizes[images[index].path] ??
                      Size.zero)
                  .width,
          'height':
              (imageDisplaySizes[pathKey(images[index].path)] ??
                      imageDisplaySizes[images[index].path] ??
                      Size.zero)
                  .height,
          'index': index + 1,
          if (index + 1 >= assignmentStart && index + 1 <= assignmentEnd)
            'bytesBase64': imageBytesBase64(images[index].path),
        },
    ],
    'classes': collaborationClassesToJson(classes),
    'annotationsByImage': [
      for (var index = 0; index < images.length; index++)
        if (index + 1 >= assignmentStart && index + 1 <= assignmentEnd)
          {
            'imageIndex': index + 1,
            'imagePath': images[index].path,
            'annotations': [
              for (final annotation
                  in annotationsByImage[pathKey(images[index].path)] ??
                      const <AnnotationRegion>[])
                annotationToJson(annotation),
            ],
          },
    ],
  };
}

CollaborationProjectSnapshot? collaborationProjectSnapshotFromJson(
  Map<String, dynamic> message, {
  required CollaborationLocalImageResolver resolveLocalImage,
  required int fallbackAssignmentStart,
  required int fallbackAssignmentEnd,
  required int currentAnnotationSerial,
}) {
  final rawImages = message['images'];
  if (rawImages is! List) {
    return null;
  }
  final images = <ImageItem>[];
  final splits = <String, String>{};
  final displaySizes = <String, Size>{};
  final remoteToLocalPath = <String, String>{};
  for (final rawImage in rawImages) {
    final image = collaborationMap(rawImage);
    final remotePath = collaborationString(image, 'path');
    if (remotePath.isEmpty) {
      continue;
    }
    final rawName = collaborationString(image, 'name').trim();
    final name = rawName.isEmpty ? fileName(remotePath) : rawName;
    final localPath = resolveLocalImage(
      remotePath,
      name,
      collaborationString(image, 'bytesBase64'),
    );
    final key = pathKey(localPath);
    remoteToLocalPath[pathKey(remotePath)] = localPath;
    images.add(ImageItem(path: localPath, name: name));
    final split = collaborationString(image, 'split').trim();
    splits[key] = split.isEmpty ? 'train' : split;
    displaySizes[key] = Size(
      collaborationDouble(image, 'width'),
      collaborationDouble(image, 'height'),
    );
  }
  if (images.isEmpty) {
    return null;
  }

  final classes = collaborationClassesFromJson(message['classes']);
  final annotations = <String, List<AnnotationRegion>>{};
  var nextAnnotationSerial = currentAnnotationSerial;
  final rawAnnotationsByImage = message['annotationsByImage'];
  if (rawAnnotationsByImage is List) {
    for (final rawEntry in rawAnnotationsByImage) {
      final entry = collaborationMap(rawEntry);
      final imagePath = collaborationString(entry, 'imagePath');
      final imageIndex = collaborationInt(entry, 'imageIndex', fallback: 0) - 1;
      final localPath = imageIndex >= 0 && imageIndex < images.length
          ? images[imageIndex].path
          : remoteToLocalPath[pathKey(imagePath)] ?? imagePath;
      if (localPath.isEmpty || entry['annotations'] is! List) {
        continue;
      }
      final decoded = (entry['annotations'] as List)
          .map(collaborationAnnotationFromJson)
          .whereType<AnnotationRegion>()
          .toList();
      for (final annotation in decoded) {
        final serial = _annotationSerialFromId(annotation.id);
        if (serial != null && serial >= nextAnnotationSerial) {
          nextAnnotationSerial = serial + 1;
        }
      }
      annotations[pathKey(localPath)] = decoded;
    }
  }
  return CollaborationProjectSnapshot(
    images: images,
    splits: splits,
    displaySizes: displaySizes,
    classes: classes,
    annotations: annotations,
    assignmentStart: collaborationInt(
      message,
      'assignmentStart',
      fallback: fallbackAssignmentStart,
    ),
    assignmentEnd: collaborationInt(
      message,
      'assignmentEnd',
      fallback: fallbackAssignmentEnd,
    ),
    nextClassSerial: nextClassSerialFor(classes),
    nextAnnotationSerial: nextAnnotationSerial,
  );
}

CollaborationAnnotationSnapshot? collaborationAnnotationSnapshotFromJson(
  Map<String, dynamic> message, {
  required String fromUserId,
  required String selfUserId,
  required String selfUserName,
  required int selfUserColorValue,
  required Iterable<CollaborationPeer> peers,
}) {
  final rawAnnotations = message['annotations'];
  if (rawAnnotations is! List) {
    return null;
  }
  final sourceUserId = fromUserId.trim().isNotEmpty
      ? fromUserId.trim()
      : collaborationString(message, 'sourceUserId').trim();
  final incoming = rawAnnotations
      .map(collaborationAnnotationFromJson)
      .whereType<AnnotationRegion>()
      .map(
        (annotation) => collaborationAnnotationWithAuthorFallback(
          annotation,
          fallbackUserId: sourceUserId,
          selfUserId: selfUserId,
          selfUserName: selfUserName,
          selfUserColorValue: selfUserColorValue,
          peers: peers,
        ),
      )
      .toList(growable: false);
  final authorScope = collaborationString(message, 'authorScope').trim();
  return CollaborationAnnotationSnapshot(
    imageIndex: collaborationInt(message, 'imageIndex', fallback: 0) - 1,
    classes: collaborationClassesFromJson(message['classes']),
    hasClassPayload: message['classes'] is List,
    annotations: incoming,
    authoritative: collaborationBool(message, 'authoritative'),
    scopedAuthors: {
      for (final annotation in incoming)
        if (annotation.authorId.isNotEmpty) annotation.authorId,
      if (authorScope.isNotEmpty) authorScope,
      if (authorScope.isEmpty && sourceUserId.isNotEmpty) sourceUserId,
    },
  );
}

AnnotationRegion collaborationAnnotationWithAuthorFallback(
  AnnotationRegion annotation, {
  required String fallbackUserId,
  required String selfUserId,
  required String selfUserName,
  required int selfUserColorValue,
  required Iterable<CollaborationPeer> peers,
}) {
  final userId = annotation.authorId.trim().isEmpty
      ? fallbackUserId.trim()
      : annotation.authorId;
  if (userId.isEmpty) {
    return annotation;
  }
  CollaborationPeer? peer;
  for (final item in peers) {
    if (item.userId == userId) {
      peer = item;
      break;
    }
  }
  final peerName = peer?.userName.trim() ?? '';
  final authorName = annotation.authorName.trim().isEmpty
      ? userId == selfUserId
            ? selfUserName
            : (peerName.isNotEmpty ? peerName : 'User')
      : annotation.authorName;
  final authorColor = annotation.authorColorValue == 0
      ? userId == selfUserId
            ? selfUserColorValue
            : (peer?.colorValue ?? collaborationColorForId(userId).toARGB32())
      : annotation.authorColorValue;
  return annotation.copyWith(
    authorId: userId,
    authorName: authorName,
    authorColorValue: authorColor,
  );
}

int? _annotationSerialFromId(String id) {
  final match = RegExp(r'^ann_(\d+)$').firstMatch(id);
  return match == null ? null : int.tryParse(match.group(1) ?? '');
}

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
              .labelColorPalette[classes.length %
                  colors.labelColorPalette.length]
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
