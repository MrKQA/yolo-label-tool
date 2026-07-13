// =============================================================================
// training_dataset_summary.dart - Training Dataset Analysis / 训练数据集分析
// =============================================================================
// Analyzes a YOLO dataset to produce class counts, class imbalance ratio,
// recommended cls_pw weights, and train/val/test split statistics.
//
// 分析 YOLO 数据集：类别计数、类别不均衡比、推荐的 cls_pw 权重和 split 统计。
// =============================================================================

import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import '../models/imported_dataset.dart';
import '../models/training.dart';
import 'import_dataset.dart';
import 'path_utils.dart';

DatasetSummary loadDatasetSummary(String path) {
  if (!File(path).existsSync()) {
    return const DatasetSummary.empty();
  }

  final parsed = parseImportYoloDataYaml(path);
  final trainImages = _datasetImagesForSplit(parsed, 'train');
  final valImages = _datasetImagesForSplit(parsed, 'val');
  final testImages = _datasetImagesForSplit(parsed, 'test');
  final classCounts = _countYoloClassLabels(
    trainImages,
    math.max(parsed.names.length, 0),
  );
  final imbalanceRatio = _classImbalanceRatio(classCounts);
  return DatasetSummary(
    classes: parsed.names,
    trainCount: trainImages.length,
    valCount: valImages.length,
    testCount: testImages.length,
    classCounts: classCounts,
    recommendedClsPw: _recommendedClsPw(
      classCount: parsed.names.length,
      classCounts: classCounts,
    ),
    imbalanceRatio: imbalanceRatio,
  );
}

class _DatasetSummaryRequest {
  const _DatasetSummaryRequest({required this.path, required this.sendPort});

  final String path;
  final SendPort sendPort;
}

Future<DatasetSummary> loadDatasetSummaryInBackground(String path) async {
  final receivePort = ReceivePort();
  try {
    await Isolate.spawn<_DatasetSummaryRequest>(
      _datasetSummaryIsolateEntry,
      _DatasetSummaryRequest(path: path, sendPort: receivePort.sendPort),
      debugName: 'rustlabel_dataset_summary',
    );
    final message = await receivePort.first;
    if (message is DatasetSummary) {
      return message;
    }
    if (message is String) {
      throw StateError(message);
    }
    throw StateError('Unexpected dataset summary response: $message');
  } finally {
    receivePort.close();
  }
}

@pragma('vm:entry-point')
void _datasetSummaryIsolateEntry(_DatasetSummaryRequest request) {
  try {
    request.sendPort.send(loadDatasetSummary(request.path));
  } on Object catch (error, stackTrace) {
    request.sendPort.send('$error\n$stackTrace');
  }
}

List<String> _datasetImagesForSplit(ParsedYoloData parsed, String split) {
  final result = <String>[];
  for (final source in parsed.splitSources[split] ?? const <String>[]) {
    result.addAll(imagePathsFromDatasetSource(parsed.rootPath, source));
  }
  return dedupePaths(result);
}

List<int> _countYoloClassLabels(List<String> imagePaths, int classCount) {
  final counts = List<int>.filled(math.max(classCount, 0), 0, growable: true);
  for (final imagePath in imagePaths) {
    final label = File(labelPathForImagePath(imagePath));
    if (!label.existsSync()) {
      continue;
    }
    for (final rawLine in label.readAsLinesSync()) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      final classIndex = int.tryParse(line.split(RegExp(r'\s+')).first);
      if (classIndex == null || classIndex < 0) {
        continue;
      }
      while (counts.length <= classIndex) {
        counts.add(0);
      }
      counts[classIndex] += 1;
    }
  }
  return counts;
}

double _classImbalanceRatio(List<int> counts) {
  final nonZero = counts.where((count) => count > 0).toList()..sort();
  if (nonZero.length <= 1) {
    return 0;
  }
  return nonZero.last / nonZero.first;
}

double _recommendedClsPw({
  required int classCount,
  required List<int> classCounts,
}) {
  if (classCount <= 1) {
    return 0;
  }
  final nonZero = classCounts.where((count) => count > 0).toList();
  if (nonZero.isEmpty) {
    return 0.5;
  }
  if (nonZero.length < classCount) {
    return 1.0;
  }
  final ratio = _classImbalanceRatio(classCounts);
  if (ratio < 2) return 0;
  if (ratio < 5) return 0.25;
  if (ratio < 10) return 0.50;
  if (ratio < 20) return 0.75;
  return 1.0;
}
