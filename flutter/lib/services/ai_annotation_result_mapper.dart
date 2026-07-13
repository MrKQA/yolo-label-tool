import 'dart:ui';

import '../models/ai_assist.dart';
import '../models/annotation.dart';
import '../models/detection.dart';
import 'ai_geometry.dart';

typedef AiClassIdResolver = int Function(String className);
typedef AiAnnotationIdFactory = String Function();

class AiAnnotationAuthor {
  const AiAnnotationAuthor({
    this.id = '',
    this.name = '',
    this.colorValue = 0,
  });

  final String id;
  final String name;
  final int colorValue;
}

/// Converts backend coordinates into annotation-space regions without owning
/// project state, label classes, or persistence.
class AiAnnotationResultMapper {
  const AiAnnotationResultMapper._();

  static List<AnnotationRegion> sam3Preview({
    required AiAnnotationResult result,
    required Size displaySize,
    required int classId,
  }) {
    if (!_hasValidDimensions(result, displaySize)) {
      return const [];
    }
    final sourceSize = Size(result.width, result.height);
    final imageBounds = Offset.zero & displaySize;
    final annotations = <AnnotationRegion>[];
    for (var index = 0; index < result.masks.length; index += 1) {
      final points = scaleAiPoints(
        result.masks[index].points,
        sourceSize: sourceSize,
        displaySize: displaySize,
      );
      final bounds = _validBounds(points, imageBounds);
      if (bounds == null) {
        continue;
      }
      annotations.add(
        AnnotationRegion(
          id: 'sam3_preview_$index',
          mode: AnnotationMode.seg,
          rect: bounds,
          classId: classId,
          points: points,
        ),
      );
    }
    return annotations;
  }

  static List<AnnotationRegion> map({
    required AiAnnotationResult result,
    required Size displaySize,
    required AiAssistConfig config,
    required AiClassIdResolver resolveClassId,
    required AiAnnotationIdFactory nextAnnotationId,
    String? classNameOverride,
    AiAnnotationAuthor author = const AiAnnotationAuthor(),
  }) {
    if (!_hasValidDimensions(result, displaySize)) {
      return const [];
    }
    return config.backend == AiAssistBackend.sam3
        ? _mapSam3(
            result: result,
            displaySize: displaySize,
            outputMode: config.sam3OutputMode.annotationMode,
            resolveClassId: resolveClassId,
            nextAnnotationId: nextAnnotationId,
            classNameOverride: classNameOverride,
            author: author,
          )
        : _mapBoxes(
            result: result,
            displaySize: displaySize,
            resolveClassId: resolveClassId,
            nextAnnotationId: nextAnnotationId,
            author: author,
          );
  }

  static List<AnnotationRegion> _mapSam3({
    required AiAnnotationResult result,
    required Size displaySize,
    required AnnotationMode outputMode,
    required AiClassIdResolver resolveClassId,
    required AiAnnotationIdFactory nextAnnotationId,
    required String? classNameOverride,
    required AiAnnotationAuthor author,
  }) {
    final sourceSize = Size(result.width, result.height);
    final imageBounds = Offset.zero & displaySize;
    final override = classNameOverride?.trim();
    final annotations = <AnnotationRegion>[];
    for (final mask in result.masks) {
      final points = scaleAiPoints(
        mask.points,
        sourceSize: sourceSize,
        displaySize: displaySize,
      );
      final bounds = _validBounds(points, imageBounds);
      if (bounds == null) {
        continue;
      }
      final classId = resolveClassId(
        override?.isNotEmpty == true ? override! : mask.className,
      );
      final id = nextAnnotationId();
      if (outputMode == AnnotationMode.seg) {
        annotations.add(
          AnnotationRegion(
            id: id,
            mode: AnnotationMode.seg,
            rect: bounds,
            classId: classId,
            points: points,
            authorId: author.id,
            authorName: author.name,
            authorColorValue: author.colorValue,
          ),
        );
        continue;
      }
      if (outputMode == AnnotationMode.obb) {
        final oriented = minimumAreaRect(points);
        final rect = oriented.rect.intersect(imageBounds);
        if (rect.width < 2 || rect.height < 2) {
          continue;
        }
        annotations.add(
          AnnotationRegion.fromRect(
            id: id,
            mode: AnnotationMode.obb,
            rect: rect,
            classId: classId,
            authorId: author.id,
            authorName: author.name,
            authorColorValue: author.colorValue,
          ).copyWith(rotationDegrees: oriented.rotationDegrees),
        );
        continue;
      }
      annotations.add(
        AnnotationRegion.fromRect(
          id: id,
          mode: AnnotationMode.hbb,
          rect: bounds,
          classId: classId,
          authorId: author.id,
          authorName: author.name,
          authorColorValue: author.colorValue,
        ),
      );
    }
    return annotations;
  }

  static List<AnnotationRegion> _mapBoxes({
    required AiAnnotationResult result,
    required Size displaySize,
    required AiClassIdResolver resolveClassId,
    required AiAnnotationIdFactory nextAnnotationId,
    required AiAnnotationAuthor author,
  }) {
    final sourceSize = Size(result.width, result.height);
    final imageBounds = Offset.zero & displaySize;
    final annotations = <AnnotationRegion>[];
    for (final box in result.boxes) {
      final rect = Rect.fromLTRB(
        box.rect.left / sourceSize.width * displaySize.width,
        box.rect.top / sourceSize.height * displaySize.height,
        box.rect.right / sourceSize.width * displaySize.width,
        box.rect.bottom / sourceSize.height * displaySize.height,
      ).intersect(imageBounds);
      if (rect.width < 2 || rect.height < 2) {
        continue;
      }
      annotations.add(
        AnnotationRegion.fromRect(
          id: nextAnnotationId(),
          mode: AnnotationMode.hbb,
          rect: rect,
          classId: resolveClassId(box.className),
          authorId: author.id,
          authorName: author.name,
          authorColorValue: author.colorValue,
        ),
      );
    }
    return annotations;
  }

  static Rect? _validBounds(List<Offset> points, Rect imageBounds) {
    if (points.length < 3) {
      return null;
    }
    final bounds = pointsBounds(points).intersect(imageBounds);
    return bounds.width >= 2 && bounds.height >= 2 ? bounds : null;
  }

  static bool _hasValidDimensions(
    AiAnnotationResult result,
    Size displaySize,
  ) {
    return result.width > 0 &&
        result.height > 0 &&
        displaySize.width > 0 &&
        displaySize.height > 0;
  }
}
