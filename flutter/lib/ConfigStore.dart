// =============================================================================
// ConfigStore.dart - Configuration Persistence / 配置持久化
// =============================================================================
// SQLite-based local config for history, settings, keybindings,
// training preferences, training history, and application logs. The database
// file is stored in the program root as AnnotationConfig.db.
//
// 本地配置持久化：历史记录、设置、快捷键、训练偏好、训练历史和应用日志。
// 所有内容统一存入程序根目录的 AnnotationConfig.db，不再读取 JSON 或旧数据库。
// =============================================================================

// ignore_for_file: file_names

part of 'main.dart';

/// 最近文件历史。
/// Recent file and folder history.
class _RecentEntry {
  const _RecentEntry({required this.path, required this.timestamp});

  final String path;
  final DateTime timestamp;

  Map<String, Object> toJson() => {
    'path': path,
    'timestamp': timestamp.toIso8601String(),
  };

  static _RecentEntry? fromJson(Object? value, int fallbackOrder) {
    if (value is String) {
      return _RecentEntry(
        path: value,
        timestamp: DateTime.fromMillisecondsSinceEpoch(fallbackOrder),
      );
    }
    if (value is! Map) {
      return null;
    }
    final path = value['path'];
    if (path is! String || path.trim().isEmpty) {
      return null;
    }
    return _RecentEntry(
      path: path,
      timestamp:
          DateTime.tryParse('${value['timestamp'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(fallbackOrder),
    );
  }
}

class _HistoryConfig {
  const _HistoryConfig({required this.folders, required this.files});

  final List<_RecentEntry> folders;
  final List<_RecentEntry> files;

  Map<String, Object> toJson() => {
    'folders': [for (final entry in folders) entry.toJson()],
    'files': [for (final entry in files) entry.toJson()],
  };

  static _HistoryConfig fromJson(Object? value) {
    if (value is! Map) {
      return const _HistoryConfig(folders: [], files: []);
    }
    return _HistoryConfig(
      folders: _recentEntriesFromJson(value['folders']),
      files: _recentEntriesFromJson(value['files']),
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
    this.logLevelIndex = 2, // warning by default
  });

  factory _AppSettings.empty() {
    return const _AppSettings(
      pythonPath: '',
      outputPath: '',
      exportPath: '',
      logLevelIndex: 2,
    );
  }

  final String pythonPath;
  final String outputPath;
  final String exportPath;
  final int logLevelIndex; // 0=debug, 1=info, 2=warning, 3=error

  _AppSettings copyWith({
    String? pythonPath,
    String? outputPath,
    String? exportPath,
    int? logLevelIndex,
  }) {
    return _AppSettings(
      pythonPath: pythonPath ?? this.pythonPath,
      outputPath: outputPath ?? this.outputPath,
      exportPath: exportPath ?? this.exportPath,
      logLevelIndex: logLevelIndex ?? this.logLevelIndex,
    );
  }

  Map<String, Object> toJson() => {
    'pythonPath': pythonPath,
    'outputPath': outputPath,
    'exportPath': exportPath,
    'logLevelIndex': logLevelIndex,
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
      logLevelIndex: _logLevelIndexFromJson(value['logLevelIndex']),
    );
  }
}

int _logLevelIndexFromJson(Object? value) {
  if (value is num) {
    return value.round().clamp(0, _LogLevel.values.length - 1).toInt();
  }
  return 2;
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
    this.manualDeviceSelection = false,
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
  final bool manualDeviceSelection;
  final Map<String, int> chartColors;

  Map<String, Object> toJson() => {
    ...modelPath == null
        ? const <String, Object>{}
        : {'modelPath': modelPath!},
    ...datasetPath == null
        ? const <String, Object>{}
        : {'datasetPath': datasetPath!},
    'parameters': parameters.map((k, v) => MapEntry(k, v)),
    'batchModeIndex': batchModeIndex,
    'batchSize': batchSize,
    'batchRatio': batchRatio,
    'ampEnabled': ampEnabled,
    'selectedDeviceIds': selectedDeviceIds,
    'manualDeviceSelection': manualDeviceSelection,
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
        manualDeviceSelection: false,
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
      modelPath: value['modelPath'] is String
          ? value['modelPath'] as String
          : null,
      datasetPath: value['datasetPath'] is String
          ? value['datasetPath'] as String
          : null,
      parameters: params,
      batchModeIndex: value['batchModeIndex'] is int
          ? value['batchModeIndex'] as int
          : 0,
      batchSize: value['batchSize'] is num
          ? (value['batchSize'] as num).toDouble()
          : 16,
      batchRatio: value['batchRatio'] is num
          ? (value['batchRatio'] as num).toDouble()
          : 0.70,
      ampEnabled: value['ampEnabled'] == true,
      selectedDeviceIds: _stringListFromJson(value['selectedDeviceIds']).isEmpty
          ? ['cpu']
          : _stringListFromJson(value['selectedDeviceIds']),
      manualDeviceSelection: value['manualDeviceSelection'] == true,
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
List<_RecentEntry> _recentEntriesFromJson(Object? value) {
  if (value is! List) {
    return const [];
  }
  final base = DateTime.now().millisecondsSinceEpoch;
  final entries = <_RecentEntry>[];
  final seen = <String>{};
  for (var index = 0; index < value.length; index++) {
    final entry = _RecentEntry.fromJson(value[index], base - index);
    if (entry == null) {
      continue;
    }
    if (seen.add(_pathKey(entry.path))) {
      entries.add(entry);
    }
  }
  entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return entries.take(_recentHistoryLimit).toList();
}

class _ConfigStore {
  static const databaseFileName = 'AnnotationConfig.db';
  static const _historyKey = 'history';
  static const _keybindingsKey = 'keybindings';
  static const _settingsKey = 'settings';
  static const _trainingHistoryKey = 'training_history';
  static const _trainingPreferencesKey = 'training_preferences';

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

  static File get databaseFile =>
      File('${projectDirectory.path}\\$databaseFileName');

  static void ensureDefaultConfig() {
    _ensureDbConfig(
      _historyKey,
      const _HistoryConfig(folders: [], files: []).toJson(),
    );
    _ensureDbConfig(_keybindingsKey, _ShortcutConfig.defaults().toJson());
    _ensureDbConfig(
      _settingsKey,
      _AppSettings(
        pythonPath: '',
        outputPath: defaultRunsDirectory.path,
        exportPath: defaultDatasetsDirectory.path,
        logLevelIndex: 2,
      ).toJson(),
    );
    _ensureDbConfig(
      _trainingHistoryKey,
      const _TrainingHistoryConfig(entries: []).toJson(),
    );
    _ensureDbConfig(
      _trainingPreferencesKey,
      _TrainingPreferences.fromJson(null).toJson(),
    );
  }

  static _HistoryConfig loadHistory() {
    return _HistoryConfig.fromJson(_readDbJson(_historyKey));
  }

  static _ShortcutConfig loadKeybindings() {
    return _ShortcutConfig.fromJson(_readDbJson(_keybindingsKey));
  }

  static _AppSettings loadSettings() {
    return _AppSettings.fromJson(_readDbJson(_settingsKey));
  }

  static _TrainingHistoryConfig loadTrainingHistory() {
    return _TrainingHistoryConfig.fromJson(_readDbJson(_trainingHistoryKey));
  }

  static void saveHistory(_HistoryConfig value) {
    _writeDbJson(_historyKey, value.toJson());
  }

  static void saveKeybindings(_ShortcutConfig value) {
    _writeDbJson(_keybindingsKey, value.toJson());
  }

  static void saveSettings(_AppSettings value) {
    _writeDbJson(_settingsKey, value.toJson());
  }

  static void saveTrainingHistory(_TrainingHistoryConfig value) {
    _writeDbJson(_trainingHistoryKey, value.toJson());
  }

  static _TrainingPreferences loadTrainingPreferences() {
    return _TrainingPreferences.fromJson(_readDbJson(_trainingPreferencesKey));
  }

  static void saveTrainingPreferences(_TrainingPreferences value) {
    _writeDbJson(_trainingPreferencesKey, value.toJson());
  }

  static int cacheSizeInBytes() {
    return _databaseSizeInBytes();
  }

  static List<String> logDates() {
    try {
      return _RustVideoBackend.logDates();
    } on Object {
      return const [];
    }
  }

  static String readLogsForDate(String date) {
    try {
      return _RustVideoBackend.readLogsForDate(date);
    } on Object {
      return '';
    }
  }

  static int deleteLogsByDateRange(String startDate, String endDate) {
    try {
      return _RustVideoBackend.deleteLogsByDateRange(
        startDate: startDate,
        endDate: endDate,
      );
    } on Object {
      return 0;
    }
  }

  static void appendLogLines(String lines) {
    try {
      _RustVideoBackend.appendLogLines(lines: lines);
    } on Object {
      // DB-only logging: ignore write failures to avoid blocking the UI.
    }
  }

  static Object? _readDbJson(String key) {
    try {
      final value = _RustVideoBackend.loadConfigValue(key: key);
      if (value.trim().isNotEmpty) {
        return jsonDecode(value);
      }
    } on Object {
      return null;
    }
    return null;
  }

  static void _writeDbJson(String key, Object value) {
    const encoder = JsonEncoder.withIndent('  ');
    try {
      _RustVideoBackend.saveConfigValue(key: key, value: encoder.convert(value));
    } on Object {
      // DB-only config: ignore write failures and keep current in-memory state.
    }
  }

  static int _databaseSizeInBytes() {
    try {
      return databaseFile.existsSync() ? databaseFile.lengthSync() : 0;
    } on Object {
      return 0;
    }
  }

  static void _ensureDbConfig(String key, Object defaultValue) {
    try {
      final value = _RustVideoBackend.loadConfigValue(key: key);
      if (value.trim().isEmpty) {
        _writeDbJson(key, defaultValue);
      }
    } on Object {
      _writeDbJson(key, defaultValue);
    }
  }
}
