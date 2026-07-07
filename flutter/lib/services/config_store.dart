// =============================================================================
// config_store.dart - Configuration Persistence / 配置持久化
// =============================================================================
// SQLite-based local config for history, settings, keybindings,
// training preferences, training history, and application logs. The database
// file is stored in the program root as AnnotationConfig.db.
//
// 本地配置持久化：历史记录、设置、快捷键、训练偏好、训练历史和应用日志。
// 所有内容统一存入程序根目录的 AnnotationConfig.db，不再读取 JSON 或旧数据库。
// =============================================================================

// ignore_for_file: file_names

part of '../main.dart';

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

/// Last label-page image position per project.
class _LabelResumePosition {
  const _LabelResumePosition({
    required this.projectKey,
    required this.imagePath,
    required this.imageIndex,
    required this.updatedAt,
  });

  final String projectKey;
  final String imagePath;
  final int imageIndex;
  final DateTime updatedAt;

  Map<String, Object> toJson() => {
    'projectKey': projectKey,
    'imagePath': imagePath,
    'imageIndex': imageIndex,
    'updatedAt': updatedAt.toIso8601String(),
  };

  static _LabelResumePosition? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final projectKey = '${value['projectKey'] ?? ''}'.trim();
    final imagePath = '${value['imagePath'] ?? ''}'.trim();
    final imageIndex = value['imageIndex'] is num
        ? (value['imageIndex'] as num).round()
        : -1;
    final updatedAt =
        DateTime.tryParse('${value['updatedAt'] ?? ''}') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    if (projectKey.isEmpty || imagePath.isEmpty || imageIndex < 0) {
      return null;
    }
    return _LabelResumePosition(
      projectKey: projectKey,
      imagePath: imagePath,
      imageIndex: imageIndex,
      updatedAt: updatedAt,
    );
  }
}

class _LabelResumePositionsConfig {
  const _LabelResumePositionsConfig({required this.entries});

  final Map<String, _LabelResumePosition> entries;

  Map<String, Object> toJson() => {
    'entries': [for (final entry in _recentEntries()) entry.toJson()],
  };

  Iterable<_LabelResumePosition> _recentEntries() {
    final values = entries.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return values.take(80);
  }

  static _LabelResumePositionsConfig fromJson(Object? value) {
    if (value is! Map || value['entries'] is! List) {
      return const _LabelResumePositionsConfig(entries: {});
    }
    final entries = <String, _LabelResumePosition>{};
    for (final item in value['entries'] as List) {
      final position = _LabelResumePosition.fromJson(item);
      if (position != null) {
        entries[position.projectKey] = position;
      }
    }
    return _LabelResumePositionsConfig(entries: entries);
  }
}

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
    this.darkMode = false,
    this.collaborationHostId = '',
    this.collaborationUserId = '',
  });

  factory _AppSettings.empty() {
    final identity = _ConfigStore.loadStableCollaborationIdentity();
    return _AppSettings(
      pythonPath: '',
      outputPath: '',
      exportPath: '',
      logLevelIndex: 2,
      darkMode: false,
      collaborationHostId: identity.hostId,
      collaborationUserId: identity.userId,
    );
  }

  final String pythonPath;
  final String outputPath;
  final String exportPath;
  final int logLevelIndex; // 0=debug, 1=info, 2=warning, 3=error
  final bool darkMode;
  final String collaborationHostId;
  final String collaborationUserId;

  _AppSettings copyWith({
    String? pythonPath,
    String? outputPath,
    String? exportPath,
    int? logLevelIndex,
    bool? darkMode,
    String? collaborationHostId,
    String? collaborationUserId,
  }) {
    return _AppSettings(
      pythonPath: pythonPath ?? this.pythonPath,
      outputPath: outputPath ?? this.outputPath,
      exportPath: exportPath ?? this.exportPath,
      logLevelIndex: logLevelIndex ?? this.logLevelIndex,
      darkMode: darkMode ?? this.darkMode,
      collaborationHostId: collaborationHostId ?? this.collaborationHostId,
      collaborationUserId: collaborationUserId ?? this.collaborationUserId,
    );
  }

  Map<String, Object> toJson() => {
    'pythonPath': pythonPath,
    'outputPath': outputPath,
    'exportPath': exportPath,
    'logLevelIndex': logLevelIndex,
    'darkMode': darkMode,
    'collaborationHostId': collaborationHostId,
    'collaborationUserId': collaborationUserId,
  };

  static _AppSettings fromJson(Object? value) {
    if (value is! Map) {
      return _AppSettings.empty();
    }
    final identity = _ConfigStore.loadStableCollaborationIdentity();
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
      darkMode: value['darkMode'] == true,
      collaborationHostId: _collaborationIdFromJson(
        value['collaborationHostId'],
        'host',
        identity.hostId,
      ),
      collaborationUserId: _collaborationIdFromJson(
        value['collaborationUserId'],
        'user',
        identity.userId,
      ),
    );
  }
}

String _collaborationIdFromJson(
  Object? value,
  String prefix,
  String stableFallback,
) {
  if (value is String && value.trim().isNotEmpty) {
    final id = value.trim();
    if (!_looksLikeRandomCollaborationId(id, prefix) &&
        !id.toLowerCase().startsWith('$prefix-')) {
      return id;
    }
  }
  return stableFallback;
}

bool _looksLikeRandomCollaborationId(String id, String prefix) {
  return RegExp('^$prefix-[0-9a-z]+-[0-9a-z]+\$').hasMatch(id);
}

class _CollaborationIdentityConfig {
  const _CollaborationIdentityConfig({
    required this.hostId,
    required this.userId,
  });

  final String hostId;
  final String userId;

  Map<String, Object> toJson() => {'hostId': hostId, 'userId': userId};

  static _CollaborationIdentityConfig fromJson(Object? value) {
    if (value is! Map) {
      return const _CollaborationIdentityConfig(hostId: '', userId: '');
    }
    return _CollaborationIdentityConfig(
      hostId: value['hostId'] is String
          ? (value['hostId'] as String).trim()
          : '',
      userId: value['userId'] is String
          ? (value['userId'] as String).trim()
          : '',
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
class _YoloExportSettings {
  const _YoloExportSettings({
    this.format = 'openvino',
    this.autoExportAfterTraining = false,
    this.imgsz = 640,
    this.batch = 1,
    this.quantize = '',
    this.dynamic = false,
    this.nms = false,
    this.dataPath = '',
    this.fraction = 1.0,
    this.device = '',
    this.simplify = true,
    this.opset = 0,
  });

  final String format;
  final bool autoExportAfterTraining;
  final int imgsz;
  final int batch;
  final String quantize;
  final bool dynamic;
  final bool nms;
  final String dataPath;
  final double fraction;
  final String device;
  final bool simplify;
  final int opset;

  _YoloExportSettings copyWith({
    String? format,
    bool? autoExportAfterTraining,
    int? imgsz,
    int? batch,
    String? quantize,
    bool? dynamic,
    bool? nms,
    String? dataPath,
    double? fraction,
    String? device,
    bool? simplify,
    int? opset,
  }) {
    return _YoloExportSettings(
      format: format ?? this.format,
      autoExportAfterTraining:
          autoExportAfterTraining ?? this.autoExportAfterTraining,
      imgsz: imgsz ?? this.imgsz,
      batch: batch ?? this.batch,
      quantize: quantize ?? this.quantize,
      dynamic: dynamic ?? this.dynamic,
      nms: nms ?? this.nms,
      dataPath: dataPath ?? this.dataPath,
      fraction: fraction ?? this.fraction,
      device: device ?? this.device,
      simplify: simplify ?? this.simplify,
      opset: opset ?? this.opset,
    );
  }

  Map<String, Object> toJson() => {
    'format': format,
    'autoExportAfterTraining': autoExportAfterTraining,
    'imgsz': imgsz,
    'batch': batch,
    'quantize': quantize,
    'dynamic': dynamic,
    'nms': nms,
    'dataPath': dataPath,
    'fraction': fraction,
    'device': device,
    'simplify': simplify,
    'opset': opset,
  };

  static _YoloExportSettings fromJson(Object? value) {
    if (value is! Map) {
      return const _YoloExportSettings();
    }
    final format = '${value['format'] ?? 'openvino'}'.toLowerCase();
    return _YoloExportSettings(
      format: format == 'onnx' ? 'onnx' : 'openvino',
      autoExportAfterTraining: value['autoExportAfterTraining'] == true,
      imgsz: value['imgsz'] is num ? (value['imgsz'] as num).round() : 640,
      batch: value['batch'] is num ? (value['batch'] as num).round() : 1,
      quantize: value['quantize'] is String ? value['quantize'] as String : '',
      dynamic: value['dynamic'] == true,
      nms: value['nms'] == true,
      dataPath: value['dataPath'] is String ? value['dataPath'] as String : '',
      fraction: value['fraction'] is num
          ? (value['fraction'] as num).toDouble()
          : 1.0,
      device: value['device'] is String ? value['device'] as String : '',
      simplify: value['simplify'] != false,
      opset: value['opset'] is num ? (value['opset'] as num).round() : 0,
    );
  }
}

class _TrainingPreferences {
  const _TrainingPreferences({
    this.modelPath,
    this.datasetPath,
    required this.parameters,
    required this.stringParameters,
    required this.batchModeIndex,
    required this.batchSize,
    required this.batchRatio,
    this.ampEnabled = false,
    required this.selectedDeviceIds,
    this.manualDeviceSelection = false,
    required this.chartColors,
    this.exportSettings = const _YoloExportSettings(),
  });

  final String? modelPath;
  final String? datasetPath;
  final Map<String, double> parameters;
  final Map<String, String> stringParameters;
  final int batchModeIndex;
  final double batchSize;
  final double batchRatio;
  final bool ampEnabled;
  final List<String> selectedDeviceIds;
  final bool manualDeviceSelection;
  final Map<String, int> chartColors;
  final _YoloExportSettings exportSettings;

  Map<String, Object> toJson() => {
    ...modelPath == null ? const <String, Object>{} : {'modelPath': modelPath!},
    ...datasetPath == null
        ? const <String, Object>{}
        : {'datasetPath': datasetPath!},
    'parameters': parameters.map((k, v) => MapEntry(k, v)),
    'stringParameters': stringParameters.map((k, v) => MapEntry(k, v)),
    'batchModeIndex': batchModeIndex,
    'batchSize': batchSize,
    'batchRatio': batchRatio,
    'ampEnabled': ampEnabled,
    'selectedDeviceIds': selectedDeviceIds,
    'manualDeviceSelection': manualDeviceSelection,
    'chartColors': chartColors.map((k, v) => MapEntry(k, v)),
    'exportSettings': exportSettings.toJson(),
  };

  static _TrainingPreferences fromJson(Object? value) {
    if (value is! Map) {
      return const _TrainingPreferences(
        parameters: {},
        stringParameters: {},
        batchModeIndex: 0,
        batchSize: 16,
        batchRatio: 0.70,
        selectedDeviceIds: ['cpu'],
        manualDeviceSelection: false,
        chartColors: {},
        exportSettings: _YoloExportSettings(),
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
    final stringParams = <String, String>{};
    final rawStringParams = value['stringParameters'];
    if (rawStringParams is Map) {
      for (final entry in rawStringParams.entries) {
        if (entry.key is String && entry.value is String) {
          stringParams[entry.key as String] = entry.value as String;
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
      stringParameters: stringParams,
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
      exportSettings: _YoloExportSettings.fromJson(value['exportSettings']),
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
  static const collaborationIdentityFileName = 'CollaborationIdentity.json';
  static const _historyKey = 'history';
  static const _keybindingsKey = 'keybindings';
  static const _settingsKey = 'settings';
  static const _trainingHistoryKey = 'training_history';
  static const _trainingPreferencesKey = 'training_preferences';
  static const _labelResumePositionsKey = 'label_resume_positions';

  static Directory get projectDirectory {
    // Use the executable directory as the application root so packaged builds
    // read and write the same AnnotationConfig.db shown in the settings page.
    //
    // 使用 exe 所在目录作为程序根目录，避免打包后 Rust 侧回读源码目录中的旧数据库。
    return File(Platform.resolvedExecutable).parent;
  }

  static Directory get defaultRunsDirectory =>
      Directory('${projectDirectory.path}\\Runs');

  static Directory get defaultDatasetsDirectory =>
      Directory('${projectDirectory.path}\\datasets');

  static Directory get defaultModelsDirectory =>
      Directory('${projectDirectory.path}\\models');

  static File get databaseFile =>
      File('${projectDirectory.path}\\$databaseFileName');

  static File get collaborationIdentityFile =>
      File('${projectDirectory.path}\\$collaborationIdentityFileName');

  static void ensureDefaultConfig() {
    defaultModelsDirectory.createSync(recursive: true);
    final identity = loadStableCollaborationIdentity();
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
        darkMode: false,
        collaborationHostId: identity.hostId,
        collaborationUserId: identity.userId,
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
    _ensureDbConfig(
      _labelResumePositionsKey,
      const _LabelResumePositionsConfig(entries: {}).toJson(),
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

  static _LabelResumePosition? loadLabelResumePosition(String projectKey) {
    final config = _LabelResumePositionsConfig.fromJson(
      _readDbJson(_labelResumePositionsKey),
    );
    return config.entries[projectKey];
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

  static void saveLabelResumePosition(_LabelResumePosition value) {
    final config = _LabelResumePositionsConfig.fromJson(
      _readDbJson(_labelResumePositionsKey),
    );
    final entries = Map<String, _LabelResumePosition>.of(config.entries);
    entries[value.projectKey] = value;
    _writeDbJson(
      _labelResumePositionsKey,
      _LabelResumePositionsConfig(entries: entries).toJson(),
    );
  }

  static _CollaborationIdentityConfig loadStableCollaborationIdentity() {
    final machineSource = _machineIdentitySource();
    if (machineSource.isNotEmpty) {
      final userName = _collaborationIdSegment(
        Platform.environment['USERNAME'] ?? Platform.environment['USER'] ?? '',
      );
      final identity = _CollaborationIdentityConfig(
        hostId: machineSource,
        userId: userName.isEmpty ? machineSource : userName,
      );
      _writeCollaborationIdentityFile(identity);
      return identity;
    }

    final stored = _readCollaborationIdentityFile();
    if (stored.hostId.isNotEmpty && stored.userId.isNotEmpty) {
      return stored;
    }
    final generated = _CollaborationIdentityConfig(
      hostId: _newCollaborationId('host'),
      userId: _newCollaborationId('user'),
    );
    _writeCollaborationIdentityFile(generated);
    return generated;
  }

  static String _machineIdentitySource() {
    final candidates = [
      Platform.environment['COMPUTERNAME'],
      Platform.environment['HOSTNAME'],
      Platform.localHostname,
      Platform.environment['USERDOMAIN'],
    ];
    for (final candidate in candidates) {
      final normalized = _collaborationIdSegment(candidate ?? '');
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return '';
  }

  static String _collaborationIdSegment(String value) {
    final normalized = value
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (normalized.length <= 48) {
      return normalized;
    }
    return '${normalized.substring(0, 39)}-${_stableIdentityHash(normalized)}';
  }

  static String _stableIdentityHash(String value) {
    var hash = 2166136261;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0').toUpperCase();
  }

  static _CollaborationIdentityConfig _readCollaborationIdentityFile() {
    try {
      final file = collaborationIdentityFile;
      if (!file.existsSync()) {
        return const _CollaborationIdentityConfig(hostId: '', userId: '');
      }
      return _CollaborationIdentityConfig.fromJson(
        jsonDecode(file.readAsStringSync()),
      );
    } on Object {
      return const _CollaborationIdentityConfig(hostId: '', userId: '');
    }
  }

  static void _writeCollaborationIdentityFile(
    _CollaborationIdentityConfig value,
  ) {
    try {
      final file = collaborationIdentityFile;
      final parent = file.parent;
      if (!parent.existsSync()) {
        parent.createSync(recursive: true);
      }
      const encoder = JsonEncoder.withIndent('  ');
      file.writeAsStringSync(encoder.convert(value.toJson()));
    } on Object {
      // The DB settings still keep the current identity when the file is locked.
    }
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

  static Future<Map<String, dynamic>> databaseOverview() {
    return _RustVideoBackend.databaseOverview();
  }

  static Future<Map<String, dynamic>> databaseTable({
    required String table,
    String projectId = '',
    String imageId = '',
    int limit = 50,
    int offset = 0,
  }) {
    return _RustVideoBackend.databaseTable(
      table: table,
      projectId: projectId,
      imageId: imageId,
      limit: limit,
      offset: offset,
    );
  }

  static Future<Map<String, dynamic>> databaseSqlQuery({required String sql}) {
    return _RustVideoBackend.databaseSqlQuery(sql: sql);
  }

  static Future<List<String>> trainingLogDates() {
    return _RustVideoBackend.trainingLogDates();
  }

  static Future<String> readTrainingLogForDate(String date) {
    return _RustVideoBackend.readTrainingLogForDate(date);
  }

  static Future<int> deleteTrainingLogsByDateRange(
    String startDate,
    String endDate,
  ) {
    return _RustVideoBackend.deleteTrainingLogsByDateRange(
      startDate: startDate,
      endDate: endDate,
    );
  }

  static String loadLastSam3ModelPath() {
    try {
      final value = _RustVideoBackend.loadConfigValue(
        key: 'ai.sam3.modelPath',
      );
      return value.trim();
    } on Object {
      return '';
    }
  }

  static void saveLastSam3ModelPath(String path) {
    final normalized = path.trim();
    if (normalized.isEmpty) {
      return;
    }
    try {
      _RustVideoBackend.saveConfigValue(
        key: 'ai.sam3.modelPath',
        value: normalized,
      );
    } on Object {
      // Keep the current in-memory selection if DB persistence fails.
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
      _RustVideoBackend.saveConfigValue(
        key: key,
        value: encoder.convert(value),
      );
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
