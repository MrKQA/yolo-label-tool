import 'dart:async';

import '../models/collaboration.dart';
import '../services/annotation_database_codec.dart';
import '../services/app_runtime.dart';
import '../services/logger.dart';
import '../services/path_utils.dart';
import '../services/rust_backend.dart';
import 'collaboration_controller.dart';
import 'collaboration_sync_controller.dart';
import 'project_controller.dart';

typedef ProjectDatabaseRunner =
    Future<Map<String, dynamic>> Function(String payload);

/// Coordinates annotation database serialization, persistence, and loading.
class AnnotationDatabaseController {
  AnnotationDatabaseController({
    required this.project,
    required this.collaboration,
    required this.collaborationSync,
    ProjectDatabaseRunner? saveRunner,
    ProjectDatabaseRunner? loadRunner,
    this.saveDelay = const Duration(milliseconds: 700),
  }) : _saveRunner = saveRunner ?? _save,
       _loadRunner = loadRunner ?? _load;

  final ProjectController project;
  final CollaborationController collaboration;
  final CollaborationSyncController collaborationSync;
  final ProjectDatabaseRunner _saveRunner;
  final ProjectDatabaseRunner _loadRunner;
  final Duration saveDelay;
  Timer? _saveTimer;
  bool _applying = false;
  bool _disposed = false;

  String get projectKey => annotationDatabaseProjectKey(
    importedDataset: project.importedDataset,
    images: project.images,
  );

  String payload({
    bool includeClasses = true,
    bool includeAnnotations = true,
    String? projectKeyOverride,
  }) {
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
      projectKeyOverride: projectKeyOverride,
      includeClasses: includeClasses,
      includeAnnotations: includeAnnotations,
    );
  }

  void scheduleSave() {
    if (_disposed || _applying || project.images.isEmpty) {
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, () => unawaited(saveNow()));
  }

  void cancelScheduledSave() {
    _saveTimer?.cancel();
    _saveTimer = null;
  }

  Future<void> saveNow({
    String? projectKeyOverride,
    bool allowEmptyProject = false,
  }) async {
    if (_disposed ||
        _applying ||
        (!allowEmptyProject && project.images.isEmpty)) {
      return;
    }
    if (collaboration.mode == CollaborationMode.client) {
      if (!collaboration.applyingAnnotationSnapshot) {
        collaborationSync.publishCurrentAnnotations();
      }
      return;
    }
    try {
      final result = await _saveRunner(
        payload(projectKeyOverride: projectKeyOverride),
      );
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
      final result = await _saveRunner(payload());
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
    await _runApplying(() async {
      try {
        final result = await _loadRunner(
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
    cancelScheduledSave();
  }

  Future<T> _runApplying<T>(Future<T> Function() action) async {
    cancelScheduledSave();
    _applying = true;
    try {
      return await action();
    } finally {
      _applying = false;
    }
  }

  static Future<Map<String, dynamic>> _save(String payload) {
    return RustBackend.saveLabelDatabase(payload: payload);
  }

  static Future<Map<String, dynamic>> _load(String payload) {
    return RustBackend.loadLabelDatabase(payload: payload);
  }
}
