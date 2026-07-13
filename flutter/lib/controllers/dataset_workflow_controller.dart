import 'dart:ui';

import '../models/export.dart';
import '../services/app_runtime.dart';
import '../services/import_dataset.dart';
import '../services/logger.dart';
import 'export_controller.dart';
import 'project_controller.dart';

export 'export_controller.dart'
    show
        DatasetExportMode,
        DatasetExportWorkflowResult,
        ImportedDatasetExporter,
        NewDatasetExporter;

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

/// Coordinates YOLO dataset import/export with the active project state.
class DatasetWorkflowController {
  DatasetWorkflowController({
    required this.project,
    ImportedProjectLoader? importLoader,
    NewDatasetExporter? newDatasetExporter,
    ImportedDatasetExporter? importedDatasetExporter,
  }) : _importLoader = importLoader ?? loadImportedYoloProject,
       _exportController = ExportController(
         project: project,
         newDatasetExporter: newDatasetExporter,
         importedDatasetExporter: importedDatasetExporter,
       );

  final ProjectController project;
  final ImportedProjectLoader _importLoader;
  final ExportController _exportController;

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

  Future<DatasetExportWorkflowResult> exportDataset({
    required DatasetExportConfig config,
    required String exportRoot,
    required bool overwriteImported,
    required Size? Function(String imagePath) displaySizeForImagePath,
    required Future<Size> Function(String imagePath)
    ensureDisplaySizeForImagePath,
  }) {
    return _exportController.exportDataset(
      config: config,
      exportRoot: exportRoot,
      overwriteImported: overwriteImported,
      displaySizeForImagePath: displaySizeForImagePath,
      ensureDisplaySizeForImagePath: ensureDisplaySizeForImagePath,
    );
  }
}
