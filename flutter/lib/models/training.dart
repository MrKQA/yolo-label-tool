enum BatchMode { fixed, autoGpu60, autoGpuRatio }

const trainingImageSizeOptions = [320, 416, 640, 800, 960, 1280];
const trainingChartPointLimit = 2000;
const trainingParameterNameWidth = 112.0;
const Map<String, double> defaultTrainingParameters = {
  'epochs': 300,
  'imgsz': 640,
  'cls_pw': 0,
  'workers': 4,
  'patience': 100,
  'lr0': 0.01,
  'momentum': 0.937,
  'hsv_h': 0.015,
  'hsv_s': 0.25,
  'hsv_v': 0.5,
  'translate': 0.1,
  'scale': 0.25,
  'shear': 5,
  'flipud': 0,
  'fliplr': 0,
  'degrees': 0,
  'perspective': 0,
  'bgr': 0,
  'mosaic': 1,
  'mixup': 0,
  'cutmix': 0,
  'copy_paste': 0,
  'erasing': 0.4,
};
const Map<String, String> defaultTrainingStringParameters = {
  'copy_paste_mode': 'flip',
  'auto_augment': 'randaugment',
};
const Map<String, List<String>> trainingStringParameterOptions = {
  'copy_paste_mode': ['flip', 'mixup'],
  'auto_augment': ['randaugment', 'autoaugment', 'augmix'],
};

class TrainingDeviceOption {
  const TrainingDeviceOption({required this.id, required this.label});

  final String id;
  final String label;
}

class OpenVinoDeviceInfo {
  const OpenVinoDeviceInfo({
    this.devices = const [],
    this.rawOutput = '',
    this.error = '',
  });

  final List<String> devices;
  final String rawOutput;
  final String error;

  bool get hasDevices => devices.isNotEmpty;
  bool get hasIntelGpu => devices.any((device) => device.startsWith('GPU'));
  bool get hasIntelNpu => devices.any((device) => device.startsWith('NPU'));
  bool get hasAccelerator => hasIntelGpu || hasIntelNpu;
  bool get hasError => error.trim().isNotEmpty;

  String get displayDevices => hasDevices ? devices.join(', ') : '-';

  String get preferredInferenceDevice {
    if (hasIntelGpu) {
      return 'intel:gpu';
    }
    if (hasIntelNpu) {
      return 'intel:npu';
    }
    return 'intel:cpu';
  }

  String get inferenceDeviceArgument => 'openvino:$preferredInferenceDevice';
}

class TrainingMetrics {
  const TrainingMetrics({
    this.trainLoss,
    this.valLoss,
    this.map50,
    this.map5095,
    this.precision,
    this.recall,
    this.lr,
  });

  final double? trainLoss;
  final double? valLoss;
  final double? map50;
  final double? map5095;
  final double? precision;
  final double? recall;
  final double? lr;
}

class TrainingResourceUsage {
  const TrainingResourceUsage({
    this.cpuPercent,
    this.ramPercent,
    this.gpuPercent,
    this.vramPercent,
  });

  factory TrainingResourceUsage.fromJson(Map<dynamic, dynamic> value) {
    return TrainingResourceUsage(
      cpuPercent: _jsonPercent(value['cpuPercent']),
      ramPercent: _jsonPercent(value['ramPercent']),
      gpuPercent: _jsonPercent(value['gpuPercent']),
      vramPercent: _jsonPercent(value['vramPercent']),
    );
  }

  final double? cpuPercent;
  final double? ramPercent;
  final double? gpuPercent;
  final double? vramPercent;

  bool get hasAny =>
      cpuPercent != null ||
      ramPercent != null ||
      gpuPercent != null ||
      vramPercent != null;
}

double? _jsonPercent(Object? value) {
  if (value is! num) {
    return null;
  }
  final parsed = value.toDouble();
  if (!parsed.isFinite) {
    return null;
  }
  return parsed.clamp(0, 100).toDouble();
}

class TrainingMetricPoint {
  const TrainingMetricPoint({
    required this.epoch,
    required this.timestamp,
    required this.metrics,
  });

  final int epoch;
  final DateTime timestamp;
  final TrainingMetrics metrics;
}

class DatasetSummary {
  const DatasetSummary({
    required this.classes,
    required this.trainCount,
    required this.valCount,
    required this.testCount,
    required this.classCounts,
    required this.recommendedClsPw,
    required this.imbalanceRatio,
  });

  const DatasetSummary.empty()
      : classes = const [],
        trainCount = 0,
        valCount = 0,
        testCount = 0,
        classCounts = const [],
        recommendedClsPw = 0,
        imbalanceRatio = 0;

  final List<String> classes;
  final int trainCount;
  final int valCount;
  final int testCount;
  final List<int> classCounts;
  final double recommendedClsPw;
  final double imbalanceRatio;
}

enum TrainingHistoryAction { start, resume, stop }

class TrainingHistoryEntry {
  const TrainingHistoryEntry({
    required this.action,
    required this.timestamp,
    required this.modelPath,
    required this.datasetPath,
    required this.epoch,
    required this.targetEpochs,
    required this.resume,
  });

  final TrainingHistoryAction action;
  final DateTime timestamp;
  final String modelPath;
  final String datasetPath;
  final int epoch;
  final int targetEpochs;
  final bool resume;

  Map<String, Object> toJson() => {
    'action': action.name,
    'timestamp': timestamp.toIso8601String(),
    'modelPath': modelPath,
    'datasetPath': datasetPath,
    'epoch': epoch,
    'targetEpochs': targetEpochs,
    'resume': resume,
  };

  static TrainingHistoryEntry? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    TrainingHistoryAction? action;
    for (final candidate in TrainingHistoryAction.values) {
      if (candidate.name == value['action']) {
        action = candidate;
        break;
      }
    }
    final timestamp = DateTime.tryParse('${value['timestamp'] ?? ''}');
    if (action == null || timestamp == null) {
      return null;
    }
    return TrainingHistoryEntry(
      action: action,
      timestamp: timestamp,
      modelPath: value['modelPath'] is String
          ? value['modelPath'] as String
          : '',
      datasetPath: value['datasetPath'] is String
          ? value['datasetPath'] as String
          : '',
      epoch: value['epoch'] is num ? (value['epoch'] as num).round() : 0,
      targetEpochs: value['targetEpochs'] is num
          ? (value['targetEpochs'] as num).round()
          : 0,
      resume: value['resume'] == true,
    );
  }
}

class TrainingHistoryConfig {
  const TrainingHistoryConfig({required this.entries});

  final List<TrainingHistoryEntry> entries;

  Map<String, Object> toJson() => {
    'entries': [for (final entry in entries.take(40)) entry.toJson()],
  };

  static TrainingHistoryConfig fromJson(Object? value) {
    if (value is! Map || value['entries'] is! List) {
      return const TrainingHistoryConfig(entries: []);
    }
    final entries = (value['entries'] as List)
        .map(TrainingHistoryEntry.fromJson)
        .whereType<TrainingHistoryEntry>()
        .take(40)
        .toList();
    return TrainingHistoryConfig(entries: entries);
  }
}

class ResumeTrainingInfo {
  const ResumeTrainingInfo._({
    required this.canResume,
    required this.statusText,
    this.runDir,
    this.argsPath,
    this.resultsPath,
    this.targetEpochs,
    this.completedEpochs,
  });

  factory ResumeTrainingInfo.available({
    required String runDir,
    required String? argsPath,
    required String resultsPath,
    required int targetEpochs,
    required int completedEpochs,
    required String statusText,
  }) {
    return ResumeTrainingInfo._(
      canResume: true,
      runDir: runDir,
      argsPath: argsPath,
      resultsPath: resultsPath,
      targetEpochs: targetEpochs,
      completedEpochs: completedEpochs,
      statusText: statusText,
    );
  }

  factory ResumeTrainingInfo.unavailable(String reason) {
    return ResumeTrainingInfo._(canResume: false, statusText: reason);
  }

  final bool canResume;
  final String statusText;
  final String? runDir;
  final String? argsPath;
  final String? resultsPath;
  final int? targetEpochs;
  final int? completedEpochs;
}
