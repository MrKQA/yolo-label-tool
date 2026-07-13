import '../models/collaboration.dart';
import '../services/annotation_database_codec.dart';
import '../services/app_runtime.dart';
import '../services/logger.dart';
import '../services/path_utils.dart';
import 'collaboration_controller.dart';
import 'collaboration_sync_controller.dart';
import 'project_controller.dart';
import 'project_persistence_controller.dart';

/// Coordinates annotation database serialization, persistence, and loading.
class AnnotationDatabaseController {
  AnnotationDatabaseController({
    required this.project,
    required this.collaboration,
    required this.collaborationSync,
    ProjectPersistenceController? persistence,
  }) : _persistence = persistence ?? ProjectPersistenceController();

  final ProjectController project;
  final CollaborationController collaboration;
  final CollaborationSyncController collaborationSync;
  final ProjectPersistenceController _persistence;
  bool _disposed = false;

  String get projectKey => annotationDatabaseProjectKey(
    importedDataset: project.importedDataset,
    images: project.images,
  );

  String payload({bool includeClasses = true, bool includeAnnotations = true}) {
    return buildAnnotationDatabasePayload(
      images: project.images,
      labelClasses: project.labelClasses,
      annotationsByImage: project.annotationsByImage,
      imageSplits: project.imageSplits,
      imageDisplaySizes: project.imageDisplaySizes,
      importedDataset: project.importedDataset,
      collaborationMode: collaboration.mode,
      collaborationSelfPermissions: collaboration.selfPermissions,
      collaborationAuthorId: collaboration.authorId,
      currentAnnotatorName: collaboration.annotatorName,
      currentAnnotatorColorValue: collaboration.annotatorColorValue,
      collaborationStartIndex: collaboration.assignmentStart,
      collaborationEndIndex: collaboration.assignmentEnd,
      collaborationPeers: collaboration.peers,
      includeClasses: includeClasses,
      includeAnnotations: includeAnnotations,
    );
  }

  void scheduleSave() {
    if (_disposed || _persistence.applying || project.images.isEmpty) {
      return;
    }
    _persistence.scheduleSave(saveNow);
  }

  void cancelScheduledSave() {
    _persistence.cancelScheduledSave();
  }

  Future<void> saveNow() async {
    if (_disposed || _persistence.applying || project.images.isEmpty) {
      return;
    }
    if (collaboration.mode == CollaborationMode.client) {
      if (!collaboration.applyingAnnotationSnapshot) {
        collaborationSync.publishCurrentAnnotations();
      }
      return;
    }
    try {
      final result = await _persistence.save(payload());
      if (_disposed) {
        return;
      }
      logApp(
        'DB',
        'Label database saved: images=${result['images'] ?? '-'}, classes=${result['classes'] ?? '-'}, annotations=${result['annotations'] ?? '-'}',
        level: AppLogLevel.debug,
      );
      if (!collaboration.applyingAnnotationSnapshot) {
        collaborationSync.publishCurrentAnnotations();
      }
    } on Object catch (error) {
      if (_disposed) {
        return;
      }
      logApp(
        'DB',
        'Label database save failed: $error',
        level: AppLogLevel.error,
      );
    }
  }

  Future<void> saveCollaborationNow(String reason) async {
    if (_disposed ||
        project.images.isEmpty ||
        collaboration.mode == CollaborationMode.client) {
      return;
    }
    final previousApplying = collaboration.applyingAnnotationSnapshot;
    collaboration.applyingAnnotationSnapshot = true;
    try {
      final result = await _persistence.save(payload());
      if (_disposed) {
        return;
      }
      logApp(
        'COLLAB',
        'Collaboration data saved: reason=$reason, images=${result['images'] ?? '-'}, classes=${result['classes'] ?? '-'}, annotations=${result['annotations'] ?? '-'}',
        level: AppLogLevel.debug,
      );
    } on Object catch (error) {
      if (_disposed) {
        return;
      }
      logApp(
        'COLLAB',
        'Collaboration data save failed: reason=$reason, error=$error',
        level: AppLogLevel.error,
      );
    } finally {
      collaboration.applyingAnnotationSnapshot = previousApplying;
    }
  }

  Future<void> loadForCurrentImages() async {
    if (_disposed || project.images.isEmpty) {
      return;
    }
    await _persistence.runApplying(() async {
      try {
        final result = await _persistence.load(
          payload(includeClasses: false, includeAnnotations: false),
        );
        if (_disposed) {
          return;
        }
        final loadedClasses = labelClassesFromDatabase(result['classes']);
        final loadedAnnotations = annotationsFromDatabase(
          result['annotations'],
          {for (final image in project.images) pathKey(image.path)},
        );
        project.applyLoadedAnnotations(
          classes: loadedClasses,
          loadedAnnotations: loadedAnnotations,
        );
        final count = loadedAnnotations.values.fold<int>(
          0,
          (sum, annotations) => sum + annotations.length,
        );
        logApp(
          'DB',
          'Label database loaded: classes=${loadedClasses.length}, annotations=$count',
          level: AppLogLevel.debug,
        );
      } on Object catch (error) {
        if (_disposed) {
          return;
        }
        logApp(
          'DB',
          'Label database load failed: $error',
          level: AppLogLevel.error,
        );
      }
    });
  }

  void dispose() {
    _disposed = true;
    _persistence.dispose();
  }
}
