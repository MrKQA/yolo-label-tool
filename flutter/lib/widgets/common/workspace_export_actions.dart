part of '../../main.dart';

extension _WorkspaceShellExportActions on _WorkspaceShellState {
  Future<void> _showExportDialog() async {
    final config = await showDialog<DatasetExportConfig>(
      context: context,
      builder: (context) => ExportDialog(exportPath: _appSettings.exportPath),
    );
    if (config == null || !mounted) return;
    final importedDataset = _importedDataset;
    String? dataYamlPath;
    if (importedDataset != null) {
      final overwrite = await _confirmOverwriteImportedDataset();
      if (overwrite == null || !mounted) {
        return;
      }
      if (overwrite) {
        dataYamlPath = await _exportImportedDataset(config, importedDataset);
      } else {
        dataYamlPath = await _exportAnnotations(config);
      }
    } else {
      dataYamlPath = await _exportAnnotations(config);
    }
    if (config.trainAfterExport && dataYamlPath != null && mounted) {
      await _trainFromExportedDataset(dataYamlPath);
    }
  }

  Future<void> _trainFromExportedDataset(String dataYamlPath) async {
    _log('EXPORT', 'Export auto training requested: data_yaml=$dataYamlPath');
    setState(() => _activeSection = 'train');
    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return;
    }
    final trainPage = _trainPageKey.currentState;
    if (trainPage == null) {
      _log(
        'EXPORT',
        'Export auto training skipped: training page is not ready',
        level: _LogLevel.warning,
      );
      return;
    }
    await trainPage._loadExportedDatasetAndStartTraining(dataYamlPath);
  }

  Future<bool?> _confirmOverwriteImportedDataset() async {
    return showOverwriteImportedDatasetDialog(context);
  }

  Future<Size> _computeImageDisplaySize(String imagePath) async {
    final displaySize = await computeImageDisplaySizeForPath(
      imagePath,
      onDecodeError: (path, error) {
        _log(
          'LABEL',
          'Image size decode failed: $path, error=$error',
          level: _LogLevel.warning,
        );
      },
    );
    _imageDisplaySizes[pathKey(imagePath)] = displaySize;
    return displaySize;
  }

  Future<String?> _exportAnnotations(DatasetExportConfig config) async {
    _log(
      'EXPORT',
      'Export started: ${config.folderName} (train=${config.trainRatio.toStringAsFixed(0)}% val=${config.valRatio.toStringAsFixed(0)}% test=${config.testRatio.toStringAsFixed(0)}%)',
    );
    final result = await exportAnnotationsToNewDataset(
      config: config,
      exportRoot: _appSettings.exportPath,
      images: _images,
      labelClasses: _labelClasses,
      annotationsByImage: _annotationsByImage,
      displaySizeForImagePath: _displaySizeForImagePath,
      ensureDisplaySizeForImagePath: _computeImageDisplaySize,
    );
    if (result == null) {
      _log(
        'EXPORT',
        'Export skipped: no images or annotations to export',
        level: _LogLevel.warning,
      );
      _showFloatingMessage(t('export.noData'));
      return null;
    }
    _log(
      'EXPORT',
      'Export completed: path=${result.outputPath}, images=${result.imageCount}, annotations=${result.annotationCount}, train=${result.trainCount}, val=${result.valCount}, test=${result.testCount}, exportImages=${result.exportImages}, skipEmpty=${result.skipEmpty}',
    );
    _showFloatingMessage(
      '${t('export.done')} (${t('export.folderName')}: ${config.folderName})',
    );
    return result.dataYamlPath;
  }

  Future<String?> _exportImportedDataset(
    DatasetExportConfig config,
    ImportedDataset dataset,
  ) async {
    _log(
      'EXPORT',
      'Overwrite imported dataset started: yaml=${dataset.dataYamlPath}',
    );
    final result = await overwriteImportedDatasetExport(
      config: config,
      dataset: dataset,
      images: _images,
      labelClasses: _labelClasses,
      annotationsByImage: _annotationsByImage,
      imageSplits: _imageSplits,
      displaySizeForImagePath: _displaySizeForImagePath,
      ensureDisplaySizeForImagePath: _computeImageDisplaySize,
    );
    if (result == null) {
      _log(
        'EXPORT',
        'Overwrite imported dataset skipped: no data',
        level: _LogLevel.warning,
      );
      _showFloatingMessage(t('export.noData'));
      return null;
    }
    _log(
      'EXPORT',
      'Overwrite imported dataset completed: yaml=${result.dataYamlPath}, images=${result.imageCount}, annotations=${result.annotationCount}, train=${result.trainCount}, val=${result.valCount}, test=${result.testCount}, exportImages=${result.exportImages}, skipEmpty=${result.skipEmpty}',
    );
    _showFloatingMessage(t('export.done'));
    return result.dataYamlPath;
  }
}
