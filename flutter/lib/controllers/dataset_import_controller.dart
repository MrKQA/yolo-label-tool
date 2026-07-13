import 'dart:ui';

import '../services/app_runtime.dart';
import '../services/import_dataset.dart';
import '../services/logger.dart';
import 'project_controller.dart';

typedef ImportedProjectLoader =
    Future<ImportedYoloProject?> Function({
      required String yamlPath,
      required Future<Size> Function(String imagePath) ensureImageDisplaySize,
    });

enum DatasetImportStatus { imported, noImages, failed }

class DatasetImportWorkflowResult {
  const DatasetImportWorkflowResult({
    required this.status,
    this.imageCount = 0,
    this.error,
  });

  final DatasetImportStatus status;
  final int imageCount;
  final Object? error;
}

/// Imports YOLO datasets into the active annotation project.
class DatasetImportController {
  DatasetImportController({
    required this.project,
    ImportedProjectLoader? importLoader,
  }) : _importLoader = importLoader ?? loadImportedYoloProject;

  final ProjectController project;
  final ImportedProjectLoader _importLoader;

  Future<DatasetImportWorkflowResult> importDataset({
    required String yamlPath,
    required Future<Size> Function(String imagePath) ensureImageDisplaySize,
  }) async {
    try {
      logApp('IMPORT', 'Dataset import started: $yamlPath');
      final imported = await _importLoader(
        yamlPath: yamlPath,
        ensureImageDisplaySize: ensureImageDisplaySize,
      );
      if (imported == null) {
        logApp(
          'IMPORT',
          'Dataset import found no images: $yamlPath',
          level: AppLogLevel.warning,
        );
        return const DatasetImportWorkflowResult(
          status: DatasetImportStatus.noImages,
        );
      }
      project.applyImportedDataset(
        images: imported.images,
        classes: imported.labelClasses,
        annotations: imported.annotationsByImage,
        splits: imported.imageSplits,
        dataset: imported.dataset,
        nextClassSerial: imported.classSerial,
        nextAnnotationSerial: imported.annotationSerial,
      );
      logApp(
        'IMPORT',
        'Dataset import completed: images=${imported.images.length}, classes=${imported.labelClasses.length}, annotations=${imported.annotationCount}, yaml=$yamlPath',
      );
      return DatasetImportWorkflowResult(
        status: DatasetImportStatus.imported,
        imageCount: imported.images.length,
      );
    } on Object catch (error) {
      logApp(
        'IMPORT',
        'Dataset import failed: $yamlPath, error=$error',
        level: AppLogLevel.error,
      );
      return DatasetImportWorkflowResult(
        status: DatasetImportStatus.failed,
        error: error,
      );
    }
  }
}
