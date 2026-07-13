// =============================================================================
// export_dataset.dart - YOLO Dataset Export / YOLO 数据集导出
// =============================================================================
// Exports annotations to YOLO label format with class-balanced train/val/test
// split, optional image copying, and data.yaml generation in the output directory.
//
// 将标注导出为 YOLO 标签格式：类别均衡的 train/val/test 划分、图片复制和 data.yaml。
// =============================================================================

import 'dart:io';
import 'dart:ui' show Size;

import '../models/annotation.dart';
import '../models/export.dart';
import '../models/imported_dataset.dart';
import 'import_dataset.dart';
import 'path_utils.dart';

class _ExportEntry {
  const _ExportEntry(this.path, this.annotations);

  final String path;
  final List<AnnotationRegion> annotations;
}

Future<DatasetExportResult?> exportAnnotationsToNewDataset({
  required DatasetExportConfig config,
  required String exportRoot,
  required List<ImageItem> images,
  required List<LabelClass> labelClasses,
  required Map<String, List<AnnotationRegion>> annotationsByImage,
  required Size? Function(String imagePath) displaySizeForImagePath,
  required Future<Size> Function(String imagePath) ensureDisplaySizeForImagePath,
}) async {
  final baseDir = Directory('$exportRoot\\${config.folderName}');
  if (baseDir.existsSync()) {
    baseDir.deleteSync(recursive: true);
  }

  final entries = <_ExportEntry>[];
  for (final image in images) {
    final annotations = _exportAnnotationsForPath(
      annotationsByImage,
      image.path,
    );
    entries.add(_ExportEntry(image.path, annotations.toList()));
    if (displaySizeForImagePath(image.path) == null) {
      await ensureDisplaySizeForImagePath(image.path);
    }
  }
  if (entries.isEmpty) {
    return null;
  }

  final splitPlan = _buildClassBalancedExportSplit(entries, config);
  final splitDirs = _createExportSplitDirectories(baseDir, splitPlan);
  final pathToEntry = {for (final entry in entries) entry.path: entry};

  _writeExportLabels(
    paths: splitPlan.trainSet,
    split: 'train',
    pathToEntry: pathToEntry,
    splitDirs: splitDirs,
    labelClasses: labelClasses,
    displaySizeForImagePath: displaySizeForImagePath,
    skipEmpty: config.skipEmpty,
  );
  _writeExportLabels(
    paths: splitPlan.valSet,
    split: 'val',
    pathToEntry: pathToEntry,
    splitDirs: splitDirs,
    labelClasses: labelClasses,
    displaySizeForImagePath: displaySizeForImagePath,
    skipEmpty: config.skipEmpty,
  );
  _writeExportLabels(
    paths: splitPlan.testSet,
    split: 'test',
    pathToEntry: pathToEntry,
    splitDirs: splitDirs,
    labelClasses: labelClasses,
    displaySizeForImagePath: displaySizeForImagePath,
    skipEmpty: config.skipEmpty,
  );

  final dataYamlPath = '${baseDir.path}\\data.yaml';
  File(dataYamlPath).writeAsStringSync(
    '${_newDatasetYamlContent(baseDir, splitPlan, labelClasses)}\n',
  );

  if (config.exportImages) {
    _copyExportImages(
      paths: splitPlan.trainSet,
      split: 'train',
      splitDirs: splitDirs,
    );
    _copyExportImages(
      paths: splitPlan.valSet,
      split: 'val',
      splitDirs: splitDirs,
    );
    _copyExportImages(
      paths: splitPlan.testSet,
      split: 'test',
      splitDirs: splitDirs,
    );
  }

  return DatasetExportResult(
    dataYamlPath: dataYamlPath,
    outputPath: baseDir.path,
    imageCount: entries.length,
    annotationCount: _annotationCount(entries),
    trainCount: splitPlan.trainSet.length,
    valCount: splitPlan.valSet.length,
    testCount: splitPlan.testSet.length,
    exportImages: config.exportImages,
    skipEmpty: config.skipEmpty,
  );
}

Future<DatasetExportResult?> overwriteImportedDatasetExport({
  required DatasetExportConfig config,
  required ImportedDataset dataset,
  required List<ImageItem> images,
  required List<LabelClass> labelClasses,
  required Map<String, List<AnnotationRegion>> annotationsByImage,
  required Map<String, String> imageSplits,
  required Size? Function(String imagePath) displaySizeForImagePath,
  required Future<Size> Function(String imagePath) ensureDisplaySizeForImagePath,
}) async {
  final entries = <_ExportEntry>[
    for (final image in images)
      _ExportEntry(
        image.path,
        _exportAnnotationsForPath(annotationsByImage, image.path).toList(),
      ),
  ];
  if (entries.isEmpty) {
    return null;
  }

  for (final entry in entries) {
    if (displaySizeForImagePath(entry.path) == null) {
      await ensureDisplaySizeForImagePath(entry.path);
    }
  }

  final grouped = <String, Set<String>>{
    for (final split in datasetSplits) split: <String>{},
  };
  for (final entry in entries) {
    final split = imageSplits[pathKey(entry.path)] ?? 'train';
    grouped[datasetSplits.contains(split) ? split : 'train']!.add(entry.path);
  }

  final pathToEntry = {for (final entry in entries) entry.path: entry};
  for (final split in datasetSplits) {
    _writeImportedDatasetLabels(
      paths: grouped[split]!,
      split: split,
      dataset: dataset,
      pathToEntry: pathToEntry,
      labelClasses: labelClasses,
      displaySizeForImagePath: displaySizeForImagePath,
      skipEmpty: config.skipEmpty,
    );
  }

  if (config.exportImages) {
    _copyImportedDatasetImages(dataset, grouped);
  }

  File(dataset.dataYamlPath).writeAsStringSync(
    '${datasetYamlContent(dataset, grouped, labelClasses)}\n',
  );

  return DatasetExportResult(
    dataYamlPath: dataset.dataYamlPath,
    outputPath: dataset.rootPath,
    imageCount: entries.length,
    annotationCount: _annotationCount(entries),
    trainCount: grouped['train']?.length ?? 0,
    valCount: grouped['val']?.length ?? 0,
    testCount: grouped['test']?.length ?? 0,
    exportImages: config.exportImages,
    skipEmpty: config.skipEmpty,
  );
}

List<AnnotationRegion> _exportAnnotationsForPath(
  Map<String, List<AnnotationRegion>> annotationsByImage,
  String path,
) {
  return annotationsByImage[pathKey(path)] ?? const [];
}

int _annotationCount(List<_ExportEntry> entries) {
  return entries.fold<int>(0, (sum, entry) => sum + entry.annotations.length);
}

class _ExportSplitPlan {
  const _ExportSplitPlan({
    required this.trainSet,
    required this.valSet,
    required this.testSet,
  });

  final Set<String> trainSet;
  final Set<String> valSet;
  final Set<String> testSet;
}

_ExportSplitPlan _buildClassBalancedExportSplit(
  List<_ExportEntry> entries,
  DatasetExportConfig config,
) {
  final assigned = <String>{};
  final trainSet = <String>{};
  final valSet = <String>{};
  final testSet = <String>{};
  final allClassIds = <int>{};

  for (final entry in entries) {
    for (final annotation in entry.annotations) {
      allClassIds.add(annotation.classId);
    }
  }

  for (final classId in allClassIds) {
    final classImages = entries
        .where((entry) => entry.annotations.any((a) => a.classId == classId))
        .toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    final total = classImages.length;
    final valCount = (total * config.valRatio).round();
    final testCount = (total * config.testRatio).round();

    for (var i = 0; i < classImages.length; i++) {
      final path = classImages[i].path;
      if (assigned.contains(path)) {
        continue;
      }
      if (i < total - valCount - testCount) {
        trainSet.add(path);
      } else if (i < total - testCount) {
        valSet.add(path);
      } else {
        testSet.add(path);
      }
      assigned.add(path);
    }
  }

  for (final entry in entries) {
    if (!assigned.contains(entry.path)) {
      trainSet.add(entry.path);
    }
  }

  return _ExportSplitPlan(
    trainSet: trainSet,
    valSet: valSet,
    testSet: testSet,
  );
}

Map<String, Directory> _createExportSplitDirectories(
  Directory baseDir,
  _ExportSplitPlan splitPlan,
) {
  final splitDirs = <String, Directory>{};

  void makeDirs(String split) {
    splitDirs['${split}_images'] = Directory('${baseDir.path}\\$split\\images')
      ..createSync(recursive: true);
    splitDirs['${split}_labels'] = Directory('${baseDir.path}\\$split\\labels')
      ..createSync(recursive: true);
  }

  makeDirs('train');
  makeDirs('val');
  if (splitPlan.testSet.isNotEmpty) {
    makeDirs('test');
  }
  return splitDirs;
}

void _writeExportLabels({
  required Set<String> paths,
  required String split,
  required Map<String, _ExportEntry> pathToEntry,
  required Map<String, Directory> splitDirs,
  required List<LabelClass> labelClasses,
  required Size? Function(String imagePath) displaySizeForImagePath,
  required bool skipEmpty,
}) {
  final labelDir = splitDirs['${split}_labels'];
  if (labelDir == null) {
    return;
  }

  for (final path in paths) {
    final entry = pathToEntry[path]!;
    final baseName = fileName(path).replaceAll(RegExp(r'\.[^.]+$'), '');
    _writeYoloLabelFile(
      path: path,
      labelFile: File('${labelDir.path}\\$baseName.txt'),
      annotations: entry.annotations,
      labelClasses: labelClasses,
      displaySizeForImagePath: displaySizeForImagePath,
      skipEmpty: skipEmpty,
    );
  }
}

void _writeImportedDatasetLabels({
  required Set<String> paths,
  required String split,
  required ImportedDataset dataset,
  required Map<String, _ExportEntry> pathToEntry,
  required List<LabelClass> labelClasses,
  required Size? Function(String imagePath) displaySizeForImagePath,
  required bool skipEmpty,
}) {
  final labelDir = Directory(dataset.labelDirForSplit(split))
    ..createSync(recursive: true);
  for (final path in paths) {
    final entry = pathToEntry[path]!;
    _writeYoloLabelFile(
      path: path,
      labelFile: File(
        '${labelDir.path}\\${baseNameWithoutExtension(path)}.txt',
      ),
      annotations: entry.annotations,
      labelClasses: labelClasses,
      displaySizeForImagePath: displaySizeForImagePath,
      skipEmpty: skipEmpty,
    );
  }
}

void _writeYoloLabelFile({
  required String path,
  required File labelFile,
  required List<AnnotationRegion> annotations,
  required List<LabelClass> labelClasses,
  required Size? Function(String imagePath) displaySizeForImagePath,
  required bool skipEmpty,
}) {
  final lines = <String>[];
  for (final annotation in annotations) {
    final classIndex = labelClasses.indexWhere(
      (labelClass) => labelClass.id == annotation.classId,
    );
    if (classIndex < 0) {
      continue;
    }
    lines.add(
      annotation.toUltralyticsLabelLine(
        classIndex: classIndex,
        imageSize: displaySizeForImagePath(path) ?? const Size(1, 1),
      ),
    );
  }
  if (lines.isNotEmpty || !skipEmpty) {
    labelFile.writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
  } else if (labelFile.existsSync()) {
    labelFile.deleteSync();
  }
}

String _newDatasetYamlContent(
  Directory baseDir,
  _ExportSplitPlan splitPlan,
  List<LabelClass> labelClasses,
) {
  final lines = <String>[
    'path: ${baseDir.path.replaceAll('\\', '/')}',
    'train: train/images',
    'val: val/images',
    if (splitPlan.testSet.isNotEmpty) 'test: test/images',
    '',
    'nc: ${labelClasses.length}',
    'names:',
    for (var i = 0; i < labelClasses.length; i++)
      '  $i: ${labelClasses[i].name}',
  ];
  return lines.join('\n');
}

void _copyExportImages({
  required Set<String> paths,
  required String split,
  required Map<String, Directory> splitDirs,
}) {
  final imageDir = splitDirs['${split}_images'];
  if (imageDir == null) {
    return;
  }
  for (final path in paths) {
    copyFileOverwrite(path, '${imageDir.path}\\${fileName(path)}');
  }
}

void _copyImportedDatasetImages(
  ImportedDataset dataset,
  Map<String, Set<String>> grouped,
) {
  for (final split in datasetSplits) {
    final imageDir = Directory(dataset.imageDirForSplit(split))
      ..createSync(recursive: true);
    for (final path in grouped[split]!) {
      final target = '${imageDir.path}\\${fileName(path)}';
      if (pathKey(path) != pathKey(target)) {
        copyFileOverwrite(path, target);
      }
    }
  }
}
