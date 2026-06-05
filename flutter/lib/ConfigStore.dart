// ignore_for_file: file_names

part of 'main.dart';

/// 最近文件历史。
/// Recent file and folder history.
class _HistoryConfig {
  const _HistoryConfig({required this.folders, required this.files});

  final List<String> folders;
  final List<String> files;

  Map<String, Object> toJson() => {'folders': folders, 'files': files};

  static _HistoryConfig fromJson(Object? value) {
    if (value is! Map) {
      return const _HistoryConfig(folders: [], files: []);
    }
    return _HistoryConfig(
      folders: _stringListFromJson(value['folders']),
      files: _stringListFromJson(value['files']),
    );
  }
}

/// 软件设置，先保存 Python 环境和训练结果路径。
/// Application settings for Python environment and training output path.
enum _TrainingHistoryAction { start, resume, stop }

class _TrainingHistoryEntry {
  const _TrainingHistoryEntry({
    required this.action,
    required this.timestamp,
    required this.modelPath,
    required this.datasetPath,
    required this.epoch,
    required this.targetEpochs,
    required this.resume,
  });

  final _TrainingHistoryAction action;
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

  static _TrainingHistoryEntry? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final action = _TrainingHistoryAction.values
        .where((item) => item.name == value['action'])
        .firstOrNullValue;
    final timestamp = DateTime.tryParse('${value['timestamp'] ?? ''}');
    if (action == null || timestamp == null) {
      return null;
    }
    return _TrainingHistoryEntry(
      action: action,
      timestamp: timestamp,
      modelPath: value['modelPath'] is String ? value['modelPath'] as String : '',
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

class _TrainingHistoryConfig {
  const _TrainingHistoryConfig({required this.entries});

  final List<_TrainingHistoryEntry> entries;

  Map<String, Object> toJson() => {
    'entries': [for (final entry in entries.take(40)) entry.toJson()],
  };

  static _TrainingHistoryConfig fromJson(Object? value) {
    if (value is! Map || value['entries'] is! List) {
      return const _TrainingHistoryConfig(entries: []);
    }
    final entries = (value['entries'] as List)
        .map(_TrainingHistoryEntry.fromJson)
        .whereType<_TrainingHistoryEntry>()
        .take(40)
        .toList();
    return _TrainingHistoryConfig(entries: entries);
  }
}

class _AppSettings {
  const _AppSettings({
    required this.pythonPath,
    required this.outputPath,
    required this.exportPath,
  });

  factory _AppSettings.empty() {
    return _AppSettings(
      pythonPath: '',
      outputPath: _ConfigStore.defaultRunsDirectory.path,
      exportPath: _ConfigStore.defaultDatasetsDirectory.path,
    );
  }

  final String pythonPath;
  final String outputPath;
  final String exportPath;

  _AppSettings copyWith({
    String? pythonPath,
    String? outputPath,
    String? exportPath,
  }) {
    return _AppSettings(
      pythonPath: pythonPath ?? this.pythonPath,
      outputPath: outputPath ?? this.outputPath,
      exportPath: exportPath ?? this.exportPath,
    );
  }

  Map<String, Object> toJson() => {
    'pythonPath': pythonPath,
    'outputPath': outputPath,
    'exportPath': exportPath,
  };

  static _AppSettings fromJson(Object? value) {
    if (value is! Map) {
      return _AppSettings.empty();
    }
    final outputPath = value['outputPath'];
    final exportPath = value['exportPath'];
    return _AppSettings(
      pythonPath: value['pythonPath'] is String
          ? value['pythonPath'] as String
          : '',
      outputPath: outputPath is String && outputPath.isNotEmpty
          ? outputPath
          : _ConfigStore.defaultRunsDirectory.path,
      exportPath: exportPath is String && exportPath.isNotEmpty
          ? exportPath
          : _ConfigStore.defaultDatasetsDirectory.path,
    );
  }
}

/// 训练参数偏好，在程序重启后恢复上次选择。
/// Training parameter preferences restored on app restart.
class _TrainingPreferences {
  const _TrainingPreferences({
    this.modelPath,
    this.datasetPath,
    required this.parameters,
    required this.batchModeIndex,
    required this.batchSize,
    required this.batchRatio,
    this.ampEnabled = false,
    required this.selectedDeviceIds,
    required this.chartColors,
  });

  final String? modelPath;
  final String? datasetPath;
  final Map<String, double> parameters;
  final int batchModeIndex;
  final double batchSize;
  final double batchRatio;
  final bool ampEnabled;
  final List<String> selectedDeviceIds;
  final Map<String, int> chartColors;

  Map<String, Object> toJson() => {
    if (modelPath case final p?) 'modelPath': p,
    if (datasetPath case final p?) 'datasetPath': p,
    'parameters': parameters.map((k, v) => MapEntry(k, v)),
    'batchModeIndex': batchModeIndex,
    'batchSize': batchSize,
    'batchRatio': batchRatio,
    'ampEnabled': ampEnabled,
    'selectedDeviceIds': selectedDeviceIds,
    'chartColors': chartColors.map((k, v) => MapEntry(k, v)),
  };

  static _TrainingPreferences fromJson(Object? value) {
    if (value is! Map) {
      return const _TrainingPreferences(
        parameters: {},
        batchModeIndex: 0,
        batchSize: 16,
        batchRatio: 0.70,
        selectedDeviceIds: ['cpu'],
        chartColors: {},
      );
    }
    final params = <String, double>{};
    final rawParams = value['parameters'];
    if (rawParams is Map) {
      for (final entry in rawParams.entries) {
        if (entry.key is String && entry.value is num) {
          params[entry.key as String] = (entry.value as num).toDouble();
        }
      }
    }
    return _TrainingPreferences(
      modelPath: value['modelPath'] is String ? value['modelPath'] as String : null,
      datasetPath: value['datasetPath'] is String ? value['datasetPath'] as String : null,
      parameters: params,
      batchModeIndex: value['batchModeIndex'] is int ? value['batchModeIndex'] as int : 0,
      batchSize: value['batchSize'] is num ? (value['batchSize'] as num).toDouble() : 16,
      batchRatio: value['batchRatio'] is num ? (value['batchRatio'] as num).toDouble() : 0.70,
      ampEnabled: value['ampEnabled'] == true,
      selectedDeviceIds: _stringListFromJson(value['selectedDeviceIds']).isEmpty
          ? ['cpu']
          : _stringListFromJson(value['selectedDeviceIds']),
      chartColors: _intMapFromJson(value['chartColors']),
    );
  }
}

Map<String, int> _intMapFromJson(Object? value) {
  if (value is! Map) return {};
  final result = <String, int>{};
  for (final entry in value.entries) {
    if (entry.key is String && entry.value is num) {
      result[entry.key as String] = (entry.value as num).toInt();
    }
  }
  return result;
}

/// 本地配置文件读写。路径使用当前系统用户目录，不写死 Windows 用户名。
/// Local config store. The path is derived from the current user home.
class _ConfigStore {
  static Directory get projectDirectory {
    final current = Directory.current;
    if (_fileName(current.path).toLowerCase() == 'flutter') {
      return current.parent;
    }
    return current;
  }

  static Directory get defaultRunsDirectory =>
      Directory('${projectDirectory.path}\\Runs');

  static Directory get defaultDatasetsDirectory =>
      Directory('${projectDirectory.path}\\datasets');

  static Directory get logsDirectory => Directory('${projectDirectory.path}\\logs');

  static Directory get configDirectory {
    final homeDirectory =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    final root = homeDirectory == null || homeDirectory.isEmpty
        ? Directory.current.path
        : homeDirectory;
    return Directory('$root\\.rustlabel');
  }

  static File get _historyFile =>
      File('${configDirectory.path}\\$_historyFileName');

  static File get _keybindingsFile =>
      File('${configDirectory.path}\\$_keybindingsFileName');

  static File get _settingsFile =>
      File('${configDirectory.path}\\$_settingsFileName');

  static File get _trainingHistoryFile =>
      File('${configDirectory.path}\\$_trainingHistoryFileName');

  static File get _trainingPreferencesFile =>
      File('${configDirectory.path}\\$_trainingPreferencesFileName');

  static _HistoryConfig loadHistory() {
    return _HistoryConfig.fromJson(_readJson(_historyFile));
  }

  static _ShortcutConfig loadKeybindings() {
    return _ShortcutConfig.fromJson(_readJson(_keybindingsFile));
  }

  static _AppSettings loadSettings() {
    return _AppSettings.fromJson(_readJson(_settingsFile));
  }

  static _TrainingHistoryConfig loadTrainingHistory() {
    return _TrainingHistoryConfig.fromJson(_readJson(_trainingHistoryFile));
  }

  static void saveHistory(_HistoryConfig value) {
    _writeJson(_historyFile, value.toJson());
  }

  static void saveKeybindings(_ShortcutConfig value) {
    _writeJson(_keybindingsFile, value.toJson());
  }

  static void saveSettings(_AppSettings value) {
    _writeJson(_settingsFile, value.toJson());
  }

  static void saveTrainingHistory(_TrainingHistoryConfig value) {
    _writeJson(_trainingHistoryFile, value.toJson());
  }

  static _TrainingPreferences loadTrainingPreferences() {
    return _TrainingPreferences.fromJson(_readJson(_trainingPreferencesFile));
  }

  static void saveTrainingPreferences(_TrainingPreferences value) {
    _writeJson(_trainingPreferencesFile, value.toJson());
  }

  static int cacheSizeInBytes() {
    try {
      if (!configDirectory.existsSync()) {
        return 0;
      }
      var total = 0;
      for (final entity in configDirectory.listSync(recursive: true)) {
        if (entity is File) {
          total += entity.lengthSync();
        }
      }
      return total;
    } on Object {
      return 0;
    }
  }

  static Object? _readJson(File file) {
    try {
      if (!file.existsSync()) {
        return null;
      }
      return jsonDecode(file.readAsStringSync());
    } on Object {
      return null;
    }
  }

  static void _writeJson(File file, Object value) {
    configDirectory.createSync(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    file.writeAsStringSync(encoder.convert(value));
  }
}
