import 'dart:ui';

import '../models/annotation.dart';
import '../models/export.dart';
import '../models/imported_dataset.dart';
import '../services/app_runtime.dart';
import '../services/export_dataset.dart';
import '../services/logger.dart';
import 'project_controller.dart';

typedef ExportTrainingLauncher = Future<bool> Function(String dataYamlPath);
typedef NewDatasetExporter =
    Future<DatasetExportResult?> Function({
      required DatasetExportConfig config,
      required String exportRoot,
      required List<ImageItem> images,
      required List<LabelClass> labelClasses,
      required Map<String, List<AnnotationRegion>> annotationsByImage,
      required Map<String, String> imageSplits,
      required Size? Function(String imagePath) displaySizeForImagePath,
      required Future<Size> Function(String imagePath)
      ensureDisplaySizeForImagePath,
    });
typedef ImportedDatasetExporter =
    Future<DatasetExportResult?> Function({
      required DatasetExportConfig config,
      required ImportedDataset dataset,
      required List<ImageItem> images,
      required List<LabelClass> labelClasses,
      required Map<String, List<AnnotationRegion>> annotationsByImage,
      required Map<String, String> imageSplits,
      required Size? Function(String imagePath) displaySizeForImagePath,
      required Future<Size> Function(String imagePath)
      ensureDisplaySizeForImagePath,
    });

enum DatasetExportMode { newDataset, overwriteImported }

class DatasetExportWorkflowResult {
  const DatasetExportWorkflowResult({required this.mode, required this.result});

  final DatasetExportMode mode;
  final DatasetExportResult? result;
}

/// Public export facade for dataset export and optional post-export training.
class ExportController {
  ExportController({
    required this.project,
    this.trainingLauncher,
    NewDatasetExporter? newDatasetExporter,
    ImportedDatasetExporter? importedDatasetExporter,
  }) : _newDatasetExporter =
           newDatasetExporter ?? exportAnnotationsToNewDataset,
       _importedDatasetExporter =
           importedDatasetExporter ?? overwriteImportedDatasetExport;

  final ProjectController project;
  final ExportTrainingLauncher? trainingLauncher;
  final NewDatasetExporter _newDatasetExporter;
  final ImportedDatasetExporter _importedDatasetExporter;

  Future<DatasetExportWorkflowResult> exportDataset({
    required DatasetExportConfig config,
    required String exportRoot,
    required bool overwriteImported,
    required Size? Function(String imagePath) displaySizeForImagePath,
    required Future<Size> Function(String imagePath)
    ensureDisplaySizeForImagePath,
  }) async {
    final dataset = project.importedDataset;
    final mode = overwriteImported && dataset != null
        ? DatasetExportMode.overwriteImported
        : DatasetExportMode.newDataset;
    try {
      final DatasetExportResult? result;
      if (mode == DatasetExportMode.overwriteImported) {
        logApp(
          'EXPORT',
          'Overwrite imported dataset started: yaml=${dataset!.dataYamlPath}, redistribute=${config.redistribute}',
        );
        result = await _importedDatasetExporter(
          config: config,
          dataset: dataset,
          images: project.images,
          labelClasses: project.labelClasses,
          annotationsByImage: project.annotationsByImage,
          imageSplits: project.imageSplits,
          displaySizeForImagePath: displaySizeForImagePath,
          ensureDisplaySizeForImagePath: ensureDisplaySizeForImagePath,
        );
      } else {
        logApp(
          'EXPORT',
          'Export started: ${config.folderName} (redistribute=${config.redistribute}, train=${config.trainRatio.toStringAsFixed(0)}% val=${config.valRatio.toStringAsFixed(0)}% test=${config.testRatio.toStringAsFixed(0)}%)',
        );
        result = await _newDatasetExporter(
          config: config,
          exportRoot: exportRoot,
          images: project.images,
          labelClasses: project.labelClasses,
          annotationsByImage: project.annotationsByImage,
          imageSplits: project.imageSplits,
          displaySizeForImagePath: displaySizeForImagePath,
          ensureDisplaySizeForImagePath: ensureDisplaySizeForImagePath,
        );
      }
      _logExportResult(mode, result);
      return DatasetExportWorkflowResult(mode: mode, result: result);
    } on Object catch (error) {
      logApp(
        'EXPORT',
        'Dataset export failed: mode=${mode.name}, error=$error',
        level: AppLogLevel.error,
      );
      rethrow;
    }
  }

  Future<bool> startTrainingAfterExport(String dataYamlPath) async {
    logApp('EXPORT', 'Export auto training requested: data_yaml=$dataYamlPath');
    final launcher = trainingLauncher;
    if (launcher == null) {
      return false;
    }
    final started = await launcher(dataYamlPath);
    if (!started) {
      logApp(
        'EXPORT',
        'Export auto training skipped: training page is not ready',
        level: AppLogLevel.warning,
      );
    }
    return started;
  }

  void _logExportResult(DatasetExportMode mode, DatasetExportResult? result) {
    if (result == null) {
      logApp(
        'EXPORT',
        mode == DatasetExportMode.overwriteImported
            ? 'Overwrite imported dataset skipped: no data'
            : 'Export skipped: no images or annotations to export',
        level: AppLogLevel.warning,
      );
      return;
    }
    if (mode == DatasetExportMode.overwriteImported) {
      logApp(
        'EXPORT',
        'Overwrite imported dataset completed: yaml=${result.dataYamlPath}, images=${result.imageCount}, annotations=${result.annotationCount}, train=${result.trainCount}, val=${result.valCount}, test=${result.testCount}, exportImages=${result.exportImages}, skipEmpty=${result.skipEmpty}',
      );
      return;
    }
    logApp(
      'EXPORT',
      'Export completed: path=${result.outputPath}, images=${result.imageCount}, annotations=${result.annotationCount}, train=${result.trainCount}, val=${result.valCount}, test=${result.testCount}, exportImages=${result.exportImages}, skipEmpty=${result.skipEmpty}',
    );
  }
}
