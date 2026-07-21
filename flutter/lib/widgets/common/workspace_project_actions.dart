import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../controllers/ai_annotation_controller.dart';
import '../../controllers/annotation_database_controller.dart';
import '../../controllers/collaboration_controller.dart';
import '../../controllers/collaboration_sync_controller.dart';
import '../../controllers/dataset_import_controller.dart';
import '../../controllers/project_controller.dart';
import '../../controllers/workspace_navigation_controller.dart';
import '../../controllers/workspace_viewport_controller.dart';
import '../../dialogs/clear_project_items_dialog.dart';
import '../../models/annotation.dart';
import '../../models/imported_dataset.dart';
import '../../services/app_runtime.dart';
import '../../services/i18n.dart';
import '../../services/logger.dart';
import '../../services/path_utils.dart';
import '../label/image_filter_dropdown.dart';

const _imageTypeGroup = XTypeGroup(
  label: 'Images',
  extensions: ['jpg', 'jpeg', 'png', 'bmp', 'webp'],
);
const _yamlTypeGroup = XTypeGroup(label: 'YAML', extensions: ['yaml', 'yml']);

/// Coordinates project file operations and dataset import UI flows.
class WorkspaceProjectActions extends ChangeNotifier {
  WorkspaceProjectActions({
    required this.project,
    required this.database,
    required this.datasetImport,
    required this.ai,
    required this.collaboration,
    required this.collaborationSync,
    required this.navigation,
    required this.viewport,
    required this.context,
    required this.mounted,
    required this.showMessage,
  });

  final ProjectController project;
  final AnnotationDatabaseController database;
  final DatasetImportController datasetImport;
  final AiAnnotationController ai;
  final CollaborationController collaboration;
  final CollaborationSyncController collaborationSync;
  final WorkspaceNavigationController navigation;
  final WorkspaceViewportController viewport;
  final BuildContext Function() context;
  final bool Function() mounted;
  final ValueChanged<String> showMessage;

  bool importingDataset = false;

  bool get selectedImageAuthorized => collaboration.isImageIndexAuthorized(
    project.selectedImageIndex,
    project.images.length,
  );

  bool guardProjectChangeBlocked() {
    if (!collaboration.projectLocked) return false;
    showMessage(t('collab.disconnectFirst'));
    return true;
  }

  void clearCurrentProject() {
    project.cancelResumeSave();
    project.clear();
    ai.clearProject();
    viewport.forceReset();
    navigation.activeSection = 'label';
  }

  void scheduleResumeSave() {
    project.scheduleResumeSave(
      projectKey: database.projectKey,
      enabled: !collaboration.clientMode,
    );
  }

  void saveResumePositionNow() {
    project.saveResumePosition(
      projectKey: database.projectKey,
      enabled: !collaboration.clientMode,
    );
  }

  void restoreResumePosition() {
    final index = project.restoreResumePosition(
      projectKey: database.projectKey,
      enabled: !collaboration.clientMode,
    );
    if (index != null) {
      logApp(
        'LABEL',
        'Restored image position: ${index + 1}/${project.images.length}',
        level: AppLogLevel.debug,
      );
    }
  }

  void selectImage(int index) {
    if (project.selectImage(index)) scheduleResumeSave();
  }

  bool selectPreviousImage({int step = 1}) {
    if (project.images.isEmpty) return false;
    final index = (project.selectedImageIndex - step).clamp(
      0,
      project.images.length - 1,
    );
    if (index == project.selectedImageIndex) return false;
    selectImage(index);
    return true;
  }

  bool selectNextImage({int step = 1}) {
    if (project.images.isEmpty) return false;
    final index = (project.selectedImageIndex + step).clamp(
      0,
      project.images.length - 1,
    );
    if (index == project.selectedImageIndex) return false;
    selectImage(index);
    return true;
  }

  Future<void> openImageFile({int? insertAfterIndex}) async {
    if (guardProjectChangeBlocked()) return;
    final file = await openFile(acceptedTypeGroups: [_imageTypeGroup]);
    if (file == null) return;
    logApp('LABEL', 'Open image file: ${file.path}');
    if (insertAfterIndex != null) {
      final existingIndex = project.imageIndexOfPath(file.path);
      if (existingIndex >= 0) {
        project.touchRecentFile(file.path);
        selectImage(existingIndex);
        return;
      }
      project.touchRecentFile(file.path);
      project.importedDataset = null;
      insertImages([file.path], insertAfterIndex: insertAfterIndex);
      await database.loadForCurrentImages();
      return;
    }
    await openSingleImageProject(file.path);
  }

  Future<void> openSingleImageProject(String path) async {
    clearCurrentProject();
    project.openSingleImage(path);
    logApp('LABEL', 'Single image project opened: $path');
    await database.loadForCurrentImages();
    scheduleResumeSave();
  }

  Future<void> openImageFolder([String? path]) async {
    if (guardProjectChangeBlocked()) return;
    final folderPath = path ?? await getDirectoryPath();
    if (folderPath == null) return;
    final files = project.openImageFolder(folderPath);
    logApp(
      'LABEL',
      'Open image folder: $folderPath, images=${files.length}',
      level: files.isEmpty ? AppLogLevel.warning : AppLogLevel.info,
    );
    navigation.activeSection = 'label';
    await database.loadForCurrentImages();
    restoreResumePosition();
  }

  Future<void> openRecentFolder(String path) async {
    if (guardProjectChangeBlocked()) return;
    if (!Directory(path).existsSync()) {
      project.removeRecentFolder(path);
      logApp(
        'HISTORY',
        'Removed missing recent folder: $path',
        level: AppLogLevel.warning,
      );
      showMessage(t('recent.missingFolder'));
      return;
    }
    await openImageFolder(path);
  }

  Future<void> openRecentFile(String path) async {
    if (guardProjectChangeBlocked()) return;
    logApp('LABEL', 'Open recent file: $path');
    if (!File(path).existsSync()) {
      project.removeRecentFile(path);
      logApp(
        'HISTORY',
        'Removed missing recent file: $path',
        level: AppLogLevel.warning,
      );
      showMessage(t('recent.missingFile'));
      return;
    }
    await openSingleImageProject(path);
  }

  void insertImages(List<String> paths, {int? insertAfterIndex}) {
    if (guardProjectChangeBlocked()) return;
    final inserted = project.insertImages(
      paths,
      insertAfterIndex: insertAfterIndex,
    );
    if (inserted == 0) return;
    navigation.activeSection = 'label';
    logApp(
      'LABEL',
      'Images inserted: count=$inserted, total=${project.images.length}',
    );
    collaborationSync.broadcastProjectSnapshot('images inserted');
    scheduleResumeSave();
    database.scheduleSave();
  }

  void deleteImage(int index) {
    if (guardProjectChangeBlocked() ||
        index < 0 ||
        index >= project.images.length) {
      return;
    }
    final path = project.images[index].path;
    final removed = project.deleteImage(index);
    if (removed == null) return;
    ai.clearImage(removed.path);
    logApp('LABEL', 'Image removed: $path, total=${project.images.length}');
    collaborationSync.broadcastProjectSnapshot('image deleted');
    scheduleResumeSave();
    database.scheduleSave();
  }

  Future<void> showClearProjectItems() async {
    if (guardProjectChangeBlocked()) return;
    final request = await showClearProjectItemsDialog(
      context: context(),
      images: project.images,
      labelClasses: project.labelClasses,
      annotationsByImage: project.annotationsByImage,
    );
    if (request == null || !mounted()) return;
    final confirmed = await showClearProjectItemsConfirmation(
      context: context(),
      request: request,
    );
    if (!confirmed || !mounted()) return;

    if (request.removeImages) {
      await _removeFilteredImages(request);
    } else if (request.clearAnnotations) {
      _clearFilteredAnnotations(request);
    }
  }

  Future<void> _removeFilteredImages(ClearProjectItemsRequest request) async {
    final candidates = project.images
        .where(
          (image) => imageMatchesFilter(
            image: image,
            filterValue: request.filterValue,
            annotationsByImage: project.annotationsByImage,
          ),
        )
        .toList(growable: false);
    final selected = _selectRandomItems(candidates, request.quantity);
    if (selected.isEmpty) return;
    final previousProjectKey = database.projectKey;
    final removed = project.deleteImagesByPaths({
      for (final image in selected) image.path,
    });
    if (removed.isEmpty) return;
    for (final image in removed) {
      ai.clearImage(image.path);
    }
    if (project.images.isEmpty) ai.clearProject();
    logApp(
      'LABEL',
      'Filtered images cleared: count=${removed.length}, filter=${request.filterValue}',
    );
    collaborationSync.broadcastProjectSnapshot('filtered images cleared');
    if (project.images.isEmpty) {
      await database.saveNow(
        projectKeyOverride: previousProjectKey,
        allowEmptyProject: true,
      );
    } else {
      scheduleResumeSave();
      database.scheduleSave();
    }
    showMessage('${t('label.clearImagesDone')} ${removed.length}');
  }

  void _clearFilteredAnnotations(ClearProjectItemsRequest request) {
    final classId = imageFilterClassId(request.filterValue);
    final candidates = <AnnotationRegion>[];
    for (final image in project.images) {
      final annotations =
          project.annotationsByImage[pathKey(image.path)] ??
          const <AnnotationRegion>[];
      if (request.filterValue == imageFilterAllValue) {
        candidates.addAll(annotations);
      } else if (classId != null) {
        candidates.addAll(
          annotations.where((annotation) => annotation.classId == classId),
        );
      }
    }
    final selected = _selectRandomItems(candidates, request.quantity);
    final removedCount = project.deleteAnnotationsByIds({
      for (final annotation in selected) annotation.id,
    });
    if (removedCount == 0) return;
    logApp(
      'ANNOTATION',
      'Filtered annotations cleared: count=$removedCount, filter=${request.filterValue}',
    );
    collaborationSync.broadcastAllAnnotations('filtered annotations cleared');
    database.scheduleSave();
    showMessage('${t('label.clearAnnotationsDone')} $removedCount');
  }

  List<T> _selectRandomItems<T>(List<T> candidates, int quantity) {
    final count = quantity.clamp(0, candidates.length);
    if (count == 0) return const [];
    if (count == candidates.length) return candidates;
    final shuffled = List<T>.of(candidates)..shuffle(math.Random());
    return shuffled.take(count).toList(growable: false);
  }

  void setSelectedImageSplit(String split) {
    if (project.setSelectedImageSplit(split, datasetSplits.toSet())) {
      database.scheduleSave();
    }
  }

  void updateSelectedImageDisplaySize(Size size) {
    project.updateSelectedImageDisplaySize(size);
    if (project.selectedImageKey != null && size != Size.zero) {
      database.scheduleSave();
    }
  }

  Future<void> showImageContextMenu(TapDownDetails details, int? index) async {
    if (guardProjectChangeBlocked()) return;
    final overlay =
        Overlay.of(context()).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(details.globalPosition, details.globalPosition),
      Offset.zero & overlay.size,
    );
    final action = await showMenu<String>(
      context: context(),
      position: position,
      items: [
        PopupMenuItem(value: 'add', child: Text(t('context.addImage'))),
        PopupMenuItem(value: 'delete', child: Text(t('context.deleteImage'))),
      ],
    );
    if (action == 'add') {
      await openImageFile(insertAfterIndex: index);
    } else if (action == 'delete' && index != null) {
      deleteImage(index);
    }
  }

  Future<void> importYoloDataset() async {
    if (importingDataset || guardProjectChangeBlocked()) return;
    final file = await openFile(acceptedTypeGroups: [_yamlTypeGroup]);
    if (file == null || !mounted()) return;
    importingDataset = true;
    notifyListeners();
    await WidgetsBinding.instance.endOfFrame;
    try {
      final result = await datasetImport.importDataset(
        yamlPath: file.path,
        ensureImageDisplaySize: project.ensureDisplaySizeForPath,
      );
      if (!mounted()) return;
      switch (result.status) {
        case DatasetImportStatus.imported:
          navigation.activeSection = 'label';
          restoreResumePosition();
          unawaited(database.saveNow());
          showMessage('${t('import.done')} (${result.imageCount})');
        case DatasetImportStatus.noImages:
          showMessage(t('import.noImages'));
        case DatasetImportStatus.failed:
          showMessage(t('import.failed'));
      }
    } finally {
      importingDataset = false;
      notifyListeners();
    }
  }
}
