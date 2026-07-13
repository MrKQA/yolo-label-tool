// =============================================================================
// train_runtime_support.dart - Training Runtime Support / 训练运行时支持
// =============================================================================
// Helper functions for the training page: parameter validation ranges,
// min/max/normalize logic, resume info detection from checkpoint files,
// results.csv parsing, and epoch reading from args.yaml.
//
// 训练页辅助函数：参数验证范围、min/max/normalize 逻辑、checkpoint 续训检测、
// results.csv 解析和 args.yaml epoch 读取。
// =============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../../models/training.dart';
import '../../services/i18n.dart';
import '../../services/import_dataset.dart';
import '../../services/path_utils.dart';
import '../../services/python_environment.dart';
import '../../services/rust_backend.dart';

Future<String> readTrainingLogTail() async {
  try {
    return await RustBackend.trainingLogTail(maxChars: 30 * 1024);
  } on Object catch (error) {
    return '${t('logs.readFailed')}: $error';
  }
}

Future<TrainingResourceUsage> readTrainingResourceUsage() async {
  try {
    return await RustBackend.trainingResourceUsage();
  } on Object {
    return const TrainingResourceUsage();
  }
}

String trainingActionLabel(TrainingHistoryAction action) {
  return switch (action) {
    TrainingHistoryAction.start => t('train.historyStart'),
    TrainingHistoryAction.resume => t('train.historyResume'),
    TrainingHistoryAction.stop => t('train.historyStop'),
  };
}

String formatTrainingHistoryTime(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}:${twoDigits(value.second)}';
}

int? readTrainingEpochs(File argsYaml) {
  if (!argsYaml.existsSync()) {
    return null;
  }
  final value = importYamlScalar(argsYaml.readAsLinesSync(), 'epochs');
  return value == null ? null : int.tryParse(value);
}

String? readTrainingDataPath(File argsYaml, String runDir) {
  if (!argsYaml.existsSync()) {
    return null;
  }
  final value = importYamlScalar(argsYaml.readAsLinesSync(), 'data');
  if (value == null || value.isEmpty) {
    return null;
  }
  return resolveImportDatasetPath(runDir, value);
}

int? readLastTrainingResultEpoch(File resultsCsv) {
  if (!resultsCsv.existsSync()) {
    return null;
  }
  int? lastEpoch;
  for (final rawLine in resultsCsv.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty || line.toLowerCase().startsWith('epoch')) {
      continue;
    }
    final first = line.split(',').first.trim();
    final parsed = double.tryParse(first);
    if (parsed != null) {
      lastEpoch = parsed.round();
    }
  }
  return lastEpoch;
}

List<TrainingMetricPoint> readTrainingMetricPoints(File resultsCsv) {
  if (!resultsCsv.existsSync()) {
    return const [];
  }
  final lines = resultsCsv.readAsLinesSync();
  final headerIndex = lines.indexWhere((line) => line.trim().isNotEmpty);
  if (headerIndex < 0) {
    return const [];
  }
  final columns = _splitTrainingCsvLine(
    lines[headerIndex].trim().trimLeft().replaceFirst('\uFEFF', ''),
  );
  if (columns.isEmpty) {
    return const [];
  }

  final pointsByEpoch = <int, TrainingMetricPoint>{};
  for (final rawLine in lines.skip(headerIndex + 1)) {
    final line = rawLine.trim();
    if (line.isEmpty || line.toLowerCase().startsWith('epoch')) {
      continue;
    }
    final values = _splitTrainingCsvLine(line);
    final map = <String, double>{};
    for (
      var index = 0;
      index < math.min(columns.length, values.length);
      index += 1
    ) {
      final parsed = double.tryParse(values[index]);
      if (parsed != null) {
        map[columns[index]] = parsed;
      }
    }
    final rawEpoch = map['epoch'];
    if (rawEpoch == null) {
      continue;
    }
    final epoch = rawEpoch.round() + 1;
    if (epoch <= 0) {
      continue;
    }
    final metrics = _trainingMetricsFromResultsMap(map);
    if (!_hasAnyTrainingMetric(metrics)) {
      continue;
    }
    pointsByEpoch[epoch] = TrainingMetricPoint(
      epoch: epoch,
      timestamp: DateTime.now(),
      metrics: metrics,
    );
  }

  final points = pointsByEpoch.values.toList()
    ..sort((a, b) => a.epoch.compareTo(b.epoch));
  return trimTrainingMetricPoints(points);
}

List<String> _splitTrainingCsvLine(String line) {
  return line.split(',').map((value) => value.trim()).toList();
}

TrainingMetrics _trainingMetricsFromResultsMap(Map<String, double> map) {
  return TrainingMetrics(
    trainLoss: _trainingCsvValue(map, const ['train/box_loss', 'train/loss']),
    valLoss: _trainingCsvValue(map, const ['val/box_loss', 'val/loss']),
    map50: _trainingCsvValue(map, const [
      'metrics/mAP50(B)',
      'metrics/mAP_0.5',
    ]),
    map5095: _trainingCsvValue(map, const [
      'metrics/mAP50-95(B)',
      'metrics/mAP_0.5:0.95',
    ]),
    precision: _trainingCsvValue(map, const [
      'metrics/precision(B)',
      'metrics/precision',
    ]),
    recall: _trainingCsvValue(map, const [
      'metrics/recall(B)',
      'metrics/recall',
    ]),
    lr: _trainingCsvValue(map, const ['lr/pg0', 'lr/0']),
  );
}

double? _trainingCsvValue(Map<String, double> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value != null) {
      return value;
    }
  }
  return null;
}

bool _hasAnyTrainingMetric(TrainingMetrics metrics) {
  return metrics.trainLoss != null ||
      metrics.valLoss != null ||
      metrics.map50 != null ||
      metrics.map5095 != null ||
      metrics.precision != null ||
      metrics.recall != null ||
      metrics.lr != null;
}

List<TrainingMetricPoint> trimTrainingMetricPoints(
  List<TrainingMetricPoint> points,
) {
  if (points.length <= trainingChartPointLimit) {
    return points;
  }
  return points.sublist(points.length - trainingChartPointLimit);
}

Future<List<TrainingDeviceOption>> detectNvidiaDevices() async {
  try {
    final result =
        await Process.run('nvidia-smi', [
          '--query-gpu=index,name',
          '--format=csv,noheader',
        ]).timeout(
          const Duration(seconds: 2),
          onTimeout: () => ProcessResult(0, 124, '', 'nvidia-smi timeout'),
        );
    if (result.exitCode != 0) {
      return const [];
    }
    final output = result.stdout.toString().trim();
    if (output.isEmpty) {
      return const [];
    }
    return output
        .split(RegExp(r'\r?\n'))
        .map((line) {
          final parts = line.split(',');
          final id = parts.first.trim();
          final name = parts.length > 1
              ? parts.sublist(1).join(',').trim()
              : '';
          if (id.isEmpty) {
            return null;
          }
          return TrainingDeviceOption(
            id: id,
            label: name.isEmpty ? 'GPU $id' : 'GPU $id - $name',
          );
        })
        .whereType<TrainingDeviceOption>()
        .toList();
  } on Object {
    return const [];
  }
}

Future<OpenVinoDeviceInfo> detectOpenVinoDevices(String pythonPath) async {
  final executable = resolvePythonExecutable(pythonPath);
  if (executable == null) {
    return const OpenVinoDeviceInfo(error: 'Python path is not configured');
  }
  const script = '''
import json
try:
    from openvino import Core
    print(json.dumps({"ok": True, "devices": list(Core().available_devices)}))
except Exception as error:
    print(json.dumps({"ok": False, "error": str(error)}))
''';
  try {
    final result = await Process.run(executable, ['-c', script]).timeout(
      const Duration(seconds: 15),
      onTimeout: () => ProcessResult(0, 124, '', 'OpenVINO probe timeout'),
    );
    final stdout = result.stdout.toString().trim();
    final stderr = result.stderr.toString().trim();
    if (result.exitCode != 0) {
      return OpenVinoDeviceInfo(
        rawOutput: stdout,
        error: stderr.isEmpty ? 'exit code ${result.exitCode}' : stderr,
      );
    }
    if (stdout.isEmpty) {
      return OpenVinoDeviceInfo(
        error: stderr.isEmpty ? 'empty OpenVINO probe output' : stderr,
      );
    }
    final jsonLine = stdout
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .lastWhere(
          (line) => line.startsWith('{') && line.endsWith('}'),
          orElse: () => stdout,
        );
    final decoded = jsonDecode(jsonLine);
    if (decoded is! Map<String, dynamic>) {
      return OpenVinoDeviceInfo(
        rawOutput: stdout,
        error: 'invalid OpenVINO probe output',
      );
    }
    if (decoded['ok'] != true) {
      return OpenVinoDeviceInfo(
        rawOutput: stdout,
        error: '${decoded['error'] ?? 'OpenVINO probe failed'}',
      );
    }
    final rawDevices = decoded['devices'];
    if (rawDevices is! List) {
      return OpenVinoDeviceInfo(
        rawOutput: stdout,
        error: 'OpenVINO device list is missing',
      );
    }
    final devices = rawDevices
        .map((item) => '$item'.trim().toUpperCase())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList()
      ..sort(naturalCompare);
    return OpenVinoDeviceInfo(devices: devices, rawOutput: stdout);
  } on Object catch (error) {
    return OpenVinoDeviceInfo(error: '$error');
  }
}

double minForTrainingParameter(String name) {
  return switch (name) {
    'epochs' => 1,
    'imgsz' => 320,
    'patience' => 0,
    'momentum' => 0.5,
    'workers' => 0,
    _ => 0,
  };
}

double maxForTrainingParameter(String name) {
  return switch (name) {
    'epochs' => 500,
    'imgsz' => 1280,
    'patience' => 500,
    'lr0' => 0.1,
    'cls_pw' => 1,
    'momentum' => 0.99,
    'workers' => 16,
    'shear' => 20,
    'degrees' => 180,
    'perspective' => 0.001,
    _ => 1,
  };
}

int nearestTrainingImageSizeIndex(double value) {
  var nearestIndex = 0;
  var nearestDelta = double.infinity;
  for (var index = 0; index < trainingImageSizeOptions.length; index += 1) {
    final delta = (value - trainingImageSizeOptions[index]).abs();
    if (delta < nearestDelta) {
      nearestIndex = index;
      nearestDelta = delta;
    }
  }
  return nearestIndex;
}

double nearestTrainingImageSizeValue(double value) {
  return trainingImageSizeOptions[nearestTrainingImageSizeIndex(value)]
      .toDouble();
}

double normalizeTrainingParameterValue(String name, double value) {
  if (name == 'imgsz') {
    return nearestTrainingImageSizeValue(value);
  }
  if ({'epochs', 'workers', 'patience'}.contains(name)) {
    return value.roundToDouble();
  }
  return value;
}

String formatTrainingParameterValue(String name, double value) {
  return switch (name) {
    'epochs' || 'imgsz' || 'workers' || 'patience' => value.round().toString(),
    'lr0' => value.toStringAsFixed(4),
    'hsv_h' => value.toStringAsFixed(3),
    'perspective' => value.toStringAsFixed(6),
    'cls_pw' => value.toStringAsFixed(2),
    'momentum' => value.toStringAsFixed(3),
    _ => value.toStringAsFixed(2),
  };
}

String trainingParameterHelp(String name) {
  final key = 'train.param.$name';
  return t(key);
}
