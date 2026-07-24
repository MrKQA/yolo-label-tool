// =============================================================================
// export_dataset.dart - YOLO Dataset Export / YOLO 数据集导出
// =============================================================================
// Exports annotations to YOLO label format with class-balanced train/val/test
// split, optional image copying, and data.yaml generation in the output directory.
//
// 将标注导出为 YOLO 标签格式：类别均衡的 train/val/test 划分、图片复制和 data.yaml。
// =============================================================================

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Size;

import '../models/annotation.dart';
import '../models/export.dart';
import '../models/imported_dataset.dart';
import 'import_dataset.dart';
import 'path_utils.dart';

class _ExportEntry {
  const _ExportEntry({
    required this.path,
    required this.annotations,
    required this.outputFileName,
  });

  final String path;
  final List<AnnotationRegion> annotations;
  final String outputFileName;

  String get outputBaseName {
    final dotIndex = outputFileName.lastIndexOf('.');
    return dotIndex <= 0
        ? outputFileName
        : outputFileName.substring(0, dotIndex);
  }
}

Future<DatasetExportResult?> exportAnnotationsToNewDataset({
  required DatasetExportConfig config,
  required String exportRoot,
  required List<ImageItem> images,
  required List<LabelClass> labelClasses,
  required Map<String, List<AnnotationRegion>> annotationsByImage,
  required Map<String, String> imageSplits,
  required Size? Function(String imagePath) displaySizeForImagePath,
  required Future<Size> Function(String imagePath)
  ensureDisplaySizeForImagePath,
}) async {
  final folderName = _validatedDatasetFolderName(config.folderName);
  final baseDir = Directory(joinPath(exportRoot, folderName));
  final rawEntries = <({String path, List<AnnotationRegion> annotations})>[];
  for (final image in images) {
    final annotations = _exportAnnotationsForPath(
      annotationsByImage,
      image.path,
    );
    rawEntries.add((path: image.path, annotations: annotations.toList()));
    if (displaySizeForImagePath(image.path) == null) {
      await ensureDisplaySizeForImagePath(image.path);
    }
  }
  final entries = _assignUniqueOutputNames(rawEntries);
  if (entries.isEmpty) {
    return null;
  }

  final splitPlan = config.redistribute
      ? _buildClassBalancedExportSplit(entries, config)
      : _buildSelectedExportSplit(entries, imageSplits);
  final token = _exportToken();
  final stagingDir = Directory('${baseDir.path}.rustlabel_tmp_$token');
  try {
    final splitDirs = _createExportSplitDirectories(stagingDir, splitPlan);
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

    File('${stagingDir.path}\\data.yaml').writeAsStringSync(
      '${_newDatasetYamlContent(baseDir, splitPlan, labelClasses)}\n',
    );

    if (config.exportImages) {
      _copyExportImages(
        paths: splitPlan.trainSet,
        split: 'train',
        pathToEntry: pathToEntry,
        splitDirs: splitDirs,
      );
      _copyExportImages(
        paths: splitPlan.valSet,
        split: 'val',
        pathToEntry: pathToEntry,
        splitDirs: splitDirs,
      );
      _copyExportImages(
        paths: splitPlan.testSet,
        split: 'test',
        pathToEntry: pathToEntry,
        splitDirs: splitDirs,
      );
    }
    _commitStagedDatasetDirectory(
      stagingDir: stagingDir,
      targetDir: baseDir,
      token: token,
    );
  } on Object {
    _deleteDirectoryBestEffort(stagingDir);
    rethrow;
  }

  return DatasetExportResult(
    dataYamlPath: '${baseDir.path}\\data.yaml',
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
  required Future<Size> Function(String imagePath)
  ensureDisplaySizeForImagePath,
}) async {
  final rawEntries = <({String path, List<AnnotationRegion> annotations})>[
    for (final image in images)
      (
        path: image.path,
        annotations: _exportAnnotationsForPath(
          annotationsByImage,
          image.path,
        ).toList(),
      ),
  ];
  final entries = _assignUniqueOutputNames(rawEntries);

  for (final entry in entries) {
    if (displaySizeForImagePath(entry.path) == null) {
      await ensureDisplaySizeForImagePath(entry.path);
    }
  }

  final splitPlan = config.redistribute
      ? _buildClassBalancedExportSplit(entries, config)
      : _buildSelectedExportSplit(entries, imageSplits);
  final grouped = _splitPlanAsMap(splitPlan);
  final pathToEntry = {for (final entry in entries) entry.path: entry};
  final token = _exportToken();
  final stagingRoot = Directory(
    joinPath(dataset.rootPath, '.rustlabel_overwrite_tmp_$token'),
  );
  try {
    final splitDirs = _createExportSplitDirectories(
      stagingRoot,
      splitPlan,
      createEmptyTest: true,
    );
    for (final split in datasetSplits) {
      _writeExportLabels(
        paths: grouped[split]!,
        split: split,
        pathToEntry: pathToEntry,
        splitDirs: splitDirs,
        labelClasses: labelClasses,
        displaySizeForImagePath: displaySizeForImagePath,
        skipEmpty: config.skipEmpty,
      );
      _copyExportImages(
        paths: grouped[split]!,
        split: split,
        pathToEntry: pathToEntry,
        splitDirs: splitDirs,
      );
    }
    final stagedYaml = File(joinPath(stagingRoot.path, 'data.yaml'))
      ..writeAsStringSync(
        '${datasetYamlContent(dataset, grouped, labelClasses)}\n',
      );
    _commitImportedDatasetStage(
      dataset: dataset,
      splitDirs: splitDirs,
      stagedYaml: stagedYaml,
      stagingRoot: stagingRoot,
      token: token,
    );
  } on Object {
    _deleteDirectoryBestEffort(stagingRoot);
    rethrow;
  }

  return DatasetExportResult(
    dataYamlPath: dataset.dataYamlPath,
    outputPath: dataset.rootPath,
    imageCount: entries.length,
    annotationCount: _annotationCount(entries),
    trainCount: grouped['train']?.length ?? 0,
    valCount: grouped['val']?.length ?? 0,
    testCount: grouped['test']?.length ?? 0,
    exportImages: true,
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

List<_ExportEntry> _assignUniqueOutputNames(
  List<({String path, List<AnnotationRegion> annotations})> entries,
) {
  final usedBaseNames = <String>{};
  final result = <_ExportEntry>[];
  for (final entry in entries) {
    final originalName = fileName(entry.path);
    final dotIndex = originalName.lastIndexOf('.');
    final originalBase = dotIndex <= 0
        ? originalName
        : originalName.substring(0, dotIndex);
    final extension = dotIndex <= 0 ? '' : originalName.substring(dotIndex);
    final base = originalBase.trim().isEmpty ? 'image' : originalBase;
    var outputBase = base;
    var duplicateIndex = 1;
    while (!usedBaseNames.add(outputBase.toLowerCase())) {
      outputBase = '$base($duplicateIndex)';
      duplicateIndex++;
    }
    result.add(
      _ExportEntry(
        path: entry.path,
        annotations: entry.annotations,
        outputFileName: '$outputBase$extension',
      ),
    );
  }
  return result;
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
  final random = math.Random.secure();
  final targetSizes = _proportionalCounts(
    entries.length,
    trainRatio: config.trainRatio,
    valRatio: config.valRatio,
    testRatio: config.testRatio,
  );
  final classTotals = <int, int>{};
  final entryClassCounts = <String, Map<int, int>>{};
  for (final entry in entries) {
    final counts = <int, int>{};
    for (final annotation in entry.annotations) {
      counts.update(
        annotation.classId,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      classTotals.update(
        annotation.classId,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    entryClassCounts[entry.path] = counts;
  }
  final classTargets = <int, Map<String, int>>{
    for (final entry in classTotals.entries)
      entry.key: _proportionalCounts(
        entry.value,
        trainRatio: config.trainRatio,
        valRatio: config.valRatio,
        testRatio: config.testRatio,
      ),
  };
  final randomOrder = {
    for (final entry in entries) entry.path: random.nextDouble(),
  };
  final orderedEntries = List<_ExportEntry>.of(entries)
    ..sort((left, right) {
      double rarity(_ExportEntry entry) {
        return entryClassCounts[entry.path]!.keys.fold<double>(
          0,
          (sum, classId) => sum + (1 / classTotals[classId]!),
        );
      }

      final comparison = rarity(right).compareTo(rarity(left));
      return comparison != 0
          ? comparison
          : randomOrder[left.path]!.compareTo(randomOrder[right.path]!);
    });

  final assignedPaths = {for (final split in datasetSplits) split: <String>{}};
  final assignedClassCounts = {
    for (final split in datasetSplits) split: <int, int>{},
  };
  for (final entry in orderedEntries) {
    final candidates = datasetSplits
        .where((split) => assignedPaths[split]!.length < targetSizes[split]!)
        .toList(growable: false);
    final entryCounts = entryClassCounts[entry.path]!;
    String? selectedSplit;
    var bestScore = double.negativeInfinity;
    for (final split in candidates) {
      var score = random.nextDouble() * 0.000001;
      final remainingCapacity =
          targetSizes[split]! - assignedPaths[split]!.length;
      score += remainingCapacity / math.max(1, targetSizes[split]!) * 0.25;
      for (final classEntry in entryCounts.entries) {
        final classId = classEntry.key;
        final total = classTotals[classId]!;
        final target = classTargets[classId]![split]!;
        final assigned = assignedClassCounts[split]![classId] ?? 0;
        final deficit = target - assigned;
        if (deficit > 0) {
          score +=
              (math.min(classEntry.value, deficit) / total) * 20 +
              (deficit / total) * 4;
        } else {
          score += deficit / total;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        selectedSplit = split;
      }
    }
    final split = selectedSplit ?? 'train';
    assignedPaths[split]!.add(entry.path);
    for (final classEntry in entryCounts.entries) {
      assignedClassCounts[split]!.update(
        classEntry.key,
        (value) => value + classEntry.value,
        ifAbsent: () => classEntry.value,
      );
    }
  }

  return _ExportSplitPlan(
    trainSet: assignedPaths['train']!,
    valSet: assignedPaths['val']!,
    testSet: assignedPaths['test']!,
  );
}

_ExportSplitPlan _buildSelectedExportSplit(
  List<_ExportEntry> entries,
  Map<String, String> imageSplits,
) {
  final grouped = {for (final split in datasetSplits) split: <String>{}};
  for (final entry in entries) {
    final selected = imageSplits[pathKey(entry.path)] ?? 'train';
    grouped[datasetSplits.contains(selected) ? selected : 'train']!.add(
      entry.path,
    );
  }
  return _ExportSplitPlan(
    trainSet: grouped['train']!,
    valSet: grouped['val']!,
    testSet: grouped['test']!,
  );
}

Map<String, Set<String>> _splitPlanAsMap(_ExportSplitPlan plan) => {
  'train': plan.trainSet,
  'val': plan.valSet,
  'test': plan.testSet,
};

Map<String, int> _proportionalCounts(
  int total, {
  required double trainRatio,
  required double valRatio,
  required double testRatio,
}) {
  final ratios = [
    math.max(0, trainRatio),
    math.max(0, valRatio),
    math.max(0, testRatio),
  ];
  final ratioTotal = ratios.fold<double>(0, (sum, value) => sum + value);
  if (ratioTotal <= 0) {
    return {'train': total, 'val': 0, 'test': 0};
  }
  final raw = [for (final ratio in ratios) total * ratio / ratioTotal];
  final counts = [for (final value in raw) value.floor()];
  var remaining = total - counts.fold<int>(0, (sum, value) => sum + value);
  final remainderOrder = [0, 1, 2]
    ..sort((left, right) {
      final leftFraction = raw[left] - counts[left];
      final rightFraction = raw[right] - counts[right];
      final comparison = rightFraction.compareTo(leftFraction);
      return comparison != 0 ? comparison : left.compareTo(right);
    });
  for (var index = 0; index < remaining; index++) {
    counts[remainderOrder[index % remainderOrder.length]]++;
  }
  return {'train': counts[0], 'val': counts[1], 'test': counts[2]};
}

Map<String, Directory> _createExportSplitDirectories(
  Directory baseDir,
  _ExportSplitPlan splitPlan, {
  bool createEmptyTest = false,
}) {
  final splitDirs = <String, Directory>{};

  void makeDirs(String split) {
    splitDirs['${split}_images'] = Directory('${baseDir.path}\\$split\\images')
      ..createSync(recursive: true);
    splitDirs['${split}_labels'] = Directory('${baseDir.path}\\$split\\labels')
      ..createSync(recursive: true);
  }

  makeDirs('train');
  makeDirs('val');
  if (createEmptyTest || splitPlan.testSet.isNotEmpty) {
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
    _writeYoloLabelFile(
      path: path,
      labelFile: File('${labelDir.path}\\${entry.outputBaseName}.txt'),
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
  required Map<String, _ExportEntry> pathToEntry,
  required Map<String, Directory> splitDirs,
}) {
  final imageDir = splitDirs['${split}_images'];
  if (imageDir == null) {
    return;
  }
  for (final path in paths) {
    final outputName = pathToEntry[path]!.outputFileName;
    copyFileOverwrite(path, '${imageDir.path}\\$outputName');
  }
}

String _validatedDatasetFolderName(String value) {
  final name = value.trim().isEmpty ? 'dataset' : value.trim();
  if (name == '.' ||
      name == '..' ||
      name.contains('/') ||
      name.contains('\\') ||
      name.contains(':')) {
    throw ArgumentError.value(
      value,
      'folderName',
      'Invalid dataset folder name',
    );
  }
  return name;
}

String _exportToken() {
  final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final random = math.Random.secure().nextInt(0x7FFFFFFF).toRadixString(36);
  return '${timestamp}_$random';
}

void _commitStagedDatasetDirectory({
  required Directory stagingDir,
  required Directory targetDir,
  required String token,
}) {
  final backupDir = Directory('${targetDir.path}.rustlabel_backup_$token');
  var originalMoved = false;
  try {
    if (targetDir.existsSync()) {
      targetDir.renameSync(backupDir.path);
      originalMoved = true;
    } else if (File(targetDir.path).existsSync()) {
      throw FileSystemException(
        'Dataset output path is an existing file',
        targetDir.path,
      );
    }
    stagingDir.renameSync(targetDir.path);
  } on Object {
    if (targetDir.existsSync() && originalMoved) {
      _deleteDirectoryIfExists(targetDir);
    }
    if (originalMoved && backupDir.existsSync()) {
      backupDir.renameSync(targetDir.path);
    }
    rethrow;
  }
  _deleteDirectoryBestEffort(backupDir);
}

class _StagedDirectoryReplacement {
  _StagedDirectoryReplacement({
    required this.staged,
    required this.target,
    required String token,
  }) : backup = Directory('${target.path}.rustlabel_backup_$token');

  final Directory staged;
  final Directory target;
  final Directory backup;
  bool originalMoved = false;
  bool stagedMoved = false;
}

void _commitImportedDatasetStage({
  required ImportedDataset dataset,
  required Map<String, Directory> splitDirs,
  required File stagedYaml,
  required Directory stagingRoot,
  required String token,
}) {
  final replacements = <_StagedDirectoryReplacement>[
    for (final split in datasetSplits) ...[
      _StagedDirectoryReplacement(
        staged: splitDirs['${split}_images']!,
        target: Directory(dataset.imageDirForSplit(split)),
        token: token,
      ),
      _StagedDirectoryReplacement(
        staged: splitDirs['${split}_labels']!,
        target: Directory(dataset.labelDirForSplit(split)),
        token: token,
      ),
    ],
  ];
  final rootKey = pathKey(dataset.rootPath);
  final targetKeys = <String>{};
  for (final replacement in replacements) {
    final targetKey = pathKey(replacement.target.path);
    if (targetKey == rootKey || !targetKeys.add(targetKey)) {
      throw FileSystemException(
        'Imported dataset uses overlapping split directories',
        replacement.target.path,
      );
    }
  }

  final targetYaml = File(dataset.dataYamlPath);
  final backupYaml = File('${targetYaml.path}.rustlabel_backup_$token');
  var yamlOriginalMoved = false;
  var yamlStagedMoved = false;
  try {
    targetYaml.parent.createSync(recursive: true);
    for (final replacement in replacements) {
      replacement.target.parent.createSync(recursive: true);
      if (replacement.target.existsSync()) {
        replacement.target.renameSync(replacement.backup.path);
        replacement.originalMoved = true;
      } else if (File(replacement.target.path).existsSync()) {
        throw FileSystemException(
          'Dataset split directory is an existing file',
          replacement.target.path,
        );
      }
    }
    if (targetYaml.existsSync()) {
      targetYaml.renameSync(backupYaml.path);
      yamlOriginalMoved = true;
    }
    for (final replacement in replacements) {
      replacement.staged.renameSync(replacement.target.path);
      replacement.stagedMoved = true;
    }
    stagedYaml.renameSync(targetYaml.path);
    yamlStagedMoved = true;
  } on Object {
    if (yamlStagedMoved && targetYaml.existsSync()) {
      targetYaml.deleteSync();
    }
    for (final replacement in replacements.reversed) {
      if (replacement.stagedMoved && replacement.target.existsSync()) {
        replacement.target.deleteSync(recursive: true);
      }
    }
    if (yamlOriginalMoved && backupYaml.existsSync()) {
      backupYaml.renameSync(targetYaml.path);
    }
    for (final replacement in replacements.reversed) {
      if (replacement.originalMoved && replacement.backup.existsSync()) {
        replacement.backup.renameSync(replacement.target.path);
      }
    }
    rethrow;
  }

  _deleteFileBestEffort(backupYaml);
  for (final replacement in replacements) {
    _deleteDirectoryBestEffort(replacement.backup);
  }
  _deleteDirectoryBestEffort(stagingRoot);
}

void _deleteDirectoryIfExists(Directory directory) {
  if (directory.existsSync()) {
    directory.deleteSync(recursive: true);
  }
}

void _deleteDirectoryBestEffort(Directory directory) {
  try {
    _deleteDirectoryIfExists(directory);
  } on Object {
    // The export is already committed or another error is being propagated.
  }
}

void _deleteFileBestEffort(File file) {
  try {
    if (file.existsSync()) {
      file.deleteSync();
    }
  } on Object {
    // The new data.yaml has already been committed.
  }
}
