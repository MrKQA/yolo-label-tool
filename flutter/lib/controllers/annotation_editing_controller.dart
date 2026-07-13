import 'dart:math' as math;
import 'dart:ui';

import '../models/annotation.dart';
import '../models/collaboration.dart';
import '../services/app_runtime.dart';
import '../services/logger.dart';
import 'collaboration_controller.dart';
import 'collaboration_sync_controller.dart';
import 'project_controller.dart';

enum AnnotationEditResult { changed, ignored, permissionDenied }

enum AnnotationModifyAction { edit, delete, changeClass }

/// Applies annotation and class edits with collaboration permission checks.
class AnnotationEditingController {
  const AnnotationEditingController({
    required this.project,
    required this.collaboration,
    required this.collaborationSync,
    required this.onChanged,
  });

  final ProjectController project;
  final CollaborationController collaboration;
  final CollaborationSyncController collaborationSync;
  final VoidCallback onChanged;

  bool get selectedImageAuthorized => collaboration.isImageIndexAuthorized(
    project.selectedImageIndex,
    project.images.length,
  );

  bool canModify(AnnotationRegion annotation, AnnotationModifyAction action) {
    if (collaboration.mode != CollaborationMode.client ||
        annotation.authorId == collaboration.authorId) {
      return true;
    }
    return switch (action) {
      AnnotationModifyAction.edit =>
        collaboration.selfPermissions.canEditOthers,
      AnnotationModifyAction.delete =>
        collaboration.selfPermissions.canDeleteOthers,
      AnnotationModifyAction.changeClass =>
        collaboration.selfPermissions.canChangeClass,
    };
  }

  AnnotationRegion? createRect({
    required Rect rect,
    required int classId,
    required AnnotationMode mode,
  }) {
    if (project.selectedImageKey == null ||
        !selectedImageAuthorized ||
        rect.width.abs() < 4 ||
        rect.height.abs() < 4) {
      return null;
    }
    project.pushAnnotationSnapshot();
    final annotation = AnnotationRegion.fromRect(
      id: project.nextAnnotationId(),
      mode: mode,
      rect: rect,
      classId: classId,
      authorId: collaboration.authorId,
      authorName: collaboration.annotatorName,
      authorColorValue: collaboration.annotatorColorValue,
    );
    project.addAnnotation(annotation);
    project.selectAnnotation(null);
    onChanged();
    return annotation;
  }

  AnnotationRegion? createSeg({
    required List<Offset> points,
    required int classId,
  }) {
    if (project.selectedImageKey == null ||
        !selectedImageAuthorized ||
        points.length < 3) {
      return null;
    }
    project.pushAnnotationSnapshot();
    final annotation = AnnotationRegion(
      id: project.nextAnnotationId(),
      mode: AnnotationMode.seg,
      rect: Rect.fromLTRB(
        points.map((point) => point.dx).reduce(math.min),
        points.map((point) => point.dy).reduce(math.min),
        points.map((point) => point.dx).reduce(math.max),
        points.map((point) => point.dy).reduce(math.max),
      ),
      classId: classId,
      points: List<Offset>.of(points),
      authorId: collaboration.authorId,
      authorName: collaboration.annotatorName,
      authorColorValue: collaboration.annotatorColorValue,
    );
    project.addAnnotation(annotation);
    project.selectAnnotation(null);
    onChanged();
    return annotation;
  }

  void selectAnnotation(String? id) {
    project.selectAnnotation(selectedImageAuthorized ? id : null);
  }

  AnnotationEditResult updateAnnotation(AnnotationRegion annotation) {
    if (project.selectedImageKey == null || !selectedImageAuthorized) {
      return AnnotationEditResult.ignored;
    }
    final existing = project.annotationById(annotation.id);
    if (existing != null && !canModify(existing, AnnotationModifyAction.edit)) {
      return AnnotationEditResult.permissionDenied;
    }
    if (!project.updateAnnotation(annotation)) {
      return AnnotationEditResult.ignored;
    }
    onChanged();
    return AnnotationEditResult.changed;
  }

  AnnotationEditResult changeAnnotationClass(String annotationId, int classId) {
    if (project.selectedImageKey == null || !selectedImageAuthorized) {
      return AnnotationEditResult.ignored;
    }
    final existing = project.annotationById(annotationId);
    if (existing != null &&
        !canModify(existing, AnnotationModifyAction.changeClass)) {
      return AnnotationEditResult.permissionDenied;
    }
    project.pushAnnotationSnapshot();
    if (!project.changeAnnotationClass(annotationId, classId)) {
      return AnnotationEditResult.ignored;
    }
    logApp(
      'ANNOTATION',
      'Class changed: annotation=$annotationId, classId=$classId',
      level: AppLogLevel.debug,
    );
    onChanged();
    return AnnotationEditResult.changed;
  }

  AnnotationEditResult deleteAnnotation(String id) {
    if (project.selectedImageKey == null || !selectedImageAuthorized) {
      return AnnotationEditResult.ignored;
    }
    final existing = project.annotationById(id);
    if (existing != null &&
        !canModify(existing, AnnotationModifyAction.delete)) {
      return AnnotationEditResult.permissionDenied;
    }
    project.pushAnnotationSnapshot();
    if (project.deleteAnnotation(id) == null) {
      return AnnotationEditResult.ignored;
    }
    logApp('ANNOTATION', 'Deleted annotation: $id', level: AppLogLevel.debug);
    onChanged();
    return AnnotationEditResult.changed;
  }

  AnnotationRegion? copySelectedAnnotation() {
    return project.copySelectedAnnotation();
  }

  AnnotationRegion? pasteAnnotation() {
    final copied = project.copiedAnnotation;
    if (project.selectedImageKey == null ||
        copied == null ||
        !selectedImageAuthorized) {
      return null;
    }
    project.pushAnnotationSnapshot();
    final pasted = project.pasteCopiedAnnotation(
      authorId: collaboration.authorId,
      authorName: collaboration.annotatorName,
      authorColorValue: collaboration.annotatorColorValue,
    );
    if (pasted == null) {
      return null;
    }
    logApp(
      'ANNOTATION',
      'Pasted annotation: source=${copied.id}, pasted=${pasted.id}',
      level: AppLogLevel.debug,
    );
    onChanged();
    return pasted;
  }

  AnnotationEditResult rotateSelectedAnnotation(
    double deltaDegrees, {
    Size? imageSize,
  }) {
    if (!selectedImageAuthorized) {
      return AnnotationEditResult.ignored;
    }
    final selectedId = project.selectedAnnotationId;
    final selected = selectedId == null
        ? null
        : project.annotationById(selectedId);
    if (selected == null || selected.mode != AnnotationMode.obb) {
      return AnnotationEditResult.ignored;
    }
    if (!canModify(selected, AnnotationModifyAction.edit)) {
      return AnnotationEditResult.permissionDenied;
    }
    project.pushAnnotationSnapshot();
    final rotated = selected.rotated(deltaDegrees);
    final next = imageSize != null && imageSize != Size.zero
        ? rotated.clampObbToImage(imageSize)
        : rotated;
    if (!project.updateAnnotation(next)) {
      return AnnotationEditResult.ignored;
    }
    onChanged();
    return AnnotationEditResult.changed;
  }

  int addLabelClass({required String name, required int colorValue}) {
    final id = project.classSerial++;
    project.addLabelClass(
      LabelClass(id: id, name: name.trim(), colorValue: colorValue),
    );
    collaborationSync.broadcastClassSnapshot('class added');
    onChanged();
    return id;
  }

  bool updateLabelClass(LabelClass labelClass, {required String reason}) {
    if (!project.updateLabelClass(labelClass)) {
      return false;
    }
    collaborationSync.broadcastClassSnapshot(reason);
    onChanged();
    return true;
  }

  bool deleteLabelClass(int classId) {
    project.pushAnnotationSnapshot();
    if (!project.deleteLabelClass(classId)) {
      return false;
    }
    collaborationSync.broadcastClassSnapshot('class deleted');
    collaborationSync.broadcastAllAnnotations('class deleted');
    onChanged();
    return true;
  }

  bool reorderLabelClass(int oldIndex, int newIndex) {
    if (!project.reorderLabelClass(oldIndex, newIndex)) {
      return false;
    }
    collaborationSync.broadcastClassSnapshot('class reordered');
    onChanged();
    return true;
  }
}
