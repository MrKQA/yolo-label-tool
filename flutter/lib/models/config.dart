// =============================================================================
// config.dart - Configuration Data Models / 配置数据模型
// =============================================================================
// Models for persisted app settings, recent file/folder history, training
// preferences, YOLO export settings, label resume positions, collaboration
// identity, and training history records.
//
// 持久化配置模型：应用设置、最近文件/文件夹历史、训练偏好、YOLO 导出设置、
// 标注恢复位置、协作身份和训练历史记录。
// =============================================================================

import 'export.dart';

const configRecentHistoryLimit = 20;

class RecentEntry {
  const RecentEntry({required this.path, required this.timestamp});

  final String path;
  final DateTime timestamp;

  Map<String, Object> toJson() => {
    'path': path,
    'timestamp': timestamp.toIso8601String(),
  };

  static RecentEntry? fromJson(Object? value, int fallbackOrder) {
    if (value is String) {
      return RecentEntry(
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
    return RecentEntry(
      path: path,
      timestamp:
          DateTime.tryParse('${value['timestamp'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(fallbackOrder),
    );
  }
}

class HistoryConfig {
  const HistoryConfig({required this.folders, required this.files});

  final List<RecentEntry> folders;
  final List<RecentEntry> files;

  Map<String, Object> toJson() => {
    'folders': [for (final entry in folders) entry.toJson()],
    'files': [for (final entry in files) entry.toJson()],
  };

  static HistoryConfig fromJson(Object? value) {
    if (value is! Map) {
      return const HistoryConfig(folders: [], files: []);
    }
    return HistoryConfig(
      folders: _recentEntriesFromJson(value['folders']),
      files: _recentEntriesFromJson(value['files']),
    );
  }
}

class LabelResumePosition {
  const LabelResumePosition({
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

  static LabelResumePosition? fromJson(Object? value) {
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
    return LabelResumePosition(
      projectKey: projectKey,
      imagePath: imagePath,
      imageIndex: imageIndex,
      updatedAt: updatedAt,
    );
  }
}

class LabelResumePositionsConfig {
  const LabelResumePositionsConfig({required this.entries});

  final Map<String, LabelResumePosition> entries;

  Map<String, Object> toJson() => {
    'entries': [for (final entry in _recentEntries()) entry.toJson()],
  };

  Iterable<LabelResumePosition> _recentEntries() {
    final values = entries.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return values.take(80);
  }

  static LabelResumePositionsConfig fromJson(Object? value) {
    if (value is! Map || value['entries'] is! List) {
      return const LabelResumePositionsConfig(entries: {});
    }
    final entries = <String, LabelResumePosition>{};
    for (final item in value['entries'] as List) {
      final position = LabelResumePosition.fromJson(item);
      if (position != null) {
        entries[position.projectKey] = position;
      }
    }
    return LabelResumePositionsConfig(entries: entries);
  }
}

class CollaborationIdentityConfig {
  const CollaborationIdentityConfig({
    required this.hostId,
    required this.userId,
  });

  final String hostId;
  final String userId;

  Map<String, Object> toJson() => {'hostId': hostId, 'userId': userId};

  static CollaborationIdentityConfig fromJson(Object? value) {
    if (value is! Map) {
      return const CollaborationIdentityConfig(hostId: '', userId: '');
    }
    return CollaborationIdentityConfig(
      hostId: value['hostId'] is String
          ? (value['hostId'] as String).trim()
          : '',
      userId: value['userId'] is String
          ? (value['userId'] as String).trim()
          : '',
    );
  }
}

class AppSettings {
  const AppSettings({
    required this.pythonPath,
    required this.outputPath,
    required this.exportPath,
    this.logLevelIndex = 2,
    this.darkMode = false,
    this.collaborationHostId = '',
    this.collaborationUserId = '',
  });

  const AppSettings.empty()
    : pythonPath = '',
      outputPath = '',
      exportPath = '',
      logLevelIndex = 2,
      darkMode = false,
      collaborationHostId = '',
      collaborationUserId = '';

  final String pythonPath;
  final String outputPath;
  final String exportPath;
  final int logLevelIndex;
  final bool darkMode;
  final String collaborationHostId;
  final String collaborationUserId;

  AppSettings copyWith({
    String? pythonPath,
    String? outputPath,
    String? exportPath,
    int? logLevelIndex,
    bool? darkMode,
    String? collaborationHostId,
    String? collaborationUserId,
  }) {
    return AppSettings(
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

  static AppSettings fromJson(
    Object? value, {
    required String defaultOutputPath,
    required String defaultExportPath,
    required CollaborationIdentityConfig identity,
  }) {
    if (value is! Map) {
      return AppSettings(
        pythonPath: '',
        outputPath: defaultOutputPath,
        exportPath: defaultExportPath,
        collaborationHostId: identity.hostId,
        collaborationUserId: identity.userId,
      );
    }
    final outputPath = value['outputPath'];
    final exportPath = value['exportPath'];
    return AppSettings(
      pythonPath: value['pythonPath'] is String
          ? value['pythonPath'] as String
          : '',
      outputPath: outputPath is String && outputPath.isNotEmpty
          ? outputPath
          : defaultOutputPath,
      exportPath: exportPath is String && exportPath.isNotEmpty
          ? exportPath
          : defaultExportPath,
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

class TrainingPreferences {
  const TrainingPreferences({
    this.modelPath,
    this.datasetPath,
    required this.parameters,
    required this.stringParameters,
    required this.batchModeIndex,
    required this.batchSize,
    required this.batchRatio,
    this.architectureVariant = 'standard',
    this.ampEnabled = false,
    required this.selectedDeviceIds,
    this.manualDeviceSelection = false,
    required this.chartColors,
    this.exportSettings = const YoloExportSettings(),
  });

  final String? modelPath;
  final String? datasetPath;
  final Map<String, double> parameters;
  final Map<String, String> stringParameters;
  final int batchModeIndex;
  final double batchSize;
  final double batchRatio;
  final String architectureVariant;
  final bool ampEnabled;
  final List<String> selectedDeviceIds;
  final bool manualDeviceSelection;
  final Map<String, int> chartColors;
  final YoloExportSettings exportSettings;

  Map<String, Object> toJson() => {
    ...modelPath == null ? const <String, Object>{} : {'modelPath': modelPath!},
    ...datasetPath == null
        ? const <String, Object>{}
        : {'datasetPath': datasetPath!},
    'parameters': parameters,
    'stringParameters': stringParameters,
    'batchModeIndex': batchModeIndex,
    'batchSize': batchSize,
    'batchRatio': batchRatio,
    'architectureVariant': architectureVariant,
    'ampEnabled': ampEnabled,
    'selectedDeviceIds': selectedDeviceIds,
    'manualDeviceSelection': manualDeviceSelection,
    'chartColors': chartColors,
    'exportSettings': exportSettings.toJson(),
  };

  static TrainingPreferences fromJson(Object? value) {
    if (value is! Map) {
      return const TrainingPreferences(
        parameters: {},
        stringParameters: {},
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
    final stringParams = <String, String>{};
    final rawStringParams = value['stringParameters'];
    if (rawStringParams is Map) {
      for (final entry in rawStringParams.entries) {
        if (entry.key is String && entry.value is String) {
          stringParams[entry.key as String] = entry.value as String;
        }
      }
    }
    final selectedDeviceIds = _stringListFromJson(value['selectedDeviceIds']);
    return TrainingPreferences(
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
      architectureVariant: switch (value['architectureVariant']) {
        'p2' => 'p2',
        'p6' => 'p6',
        _ => 'standard',
      },
      ampEnabled: value['ampEnabled'] == true,
      selectedDeviceIds: selectedDeviceIds.isEmpty
          ? ['cpu']
          : selectedDeviceIds,
      manualDeviceSelection: value['manualDeviceSelection'] == true,
      chartColors: _intMapFromJson(value['chartColors']),
      exportSettings: YoloExportSettings.fromJson(value['exportSettings']),
    );
  }
}

List<RecentEntry> _recentEntriesFromJson(Object? value) {
  if (value is! List) {
    return const [];
  }
  final base = DateTime.now().millisecondsSinceEpoch;
  final entries = <RecentEntry>[];
  final seen = <String>{};
  for (var index = 0; index < value.length; index++) {
    final entry = RecentEntry.fromJson(value[index], base - index);
    if (entry != null && seen.add(_pathKey(entry.path))) {
      entries.add(entry);
    }
  }
  entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return entries.take(configRecentHistoryLimit).toList();
}

String _collaborationIdFromJson(
  Object? value,
  String prefix,
  String stableFallback,
) {
  if (value is String && value.trim().isNotEmpty) {
    final id = value.trim();
    if (!RegExp('^$prefix-[0-9a-z]+-[0-9a-z]+\$').hasMatch(id) &&
        !id.toLowerCase().startsWith('$prefix-')) {
      return id;
    }
  }
  return stableFallback;
}

int _logLevelIndexFromJson(Object? value) {
  return value is num ? value.round().clamp(0, 3).toInt() : 2;
}

List<String> _stringListFromJson(Object? value) {
  return value is List ? value.whereType<String>().toList() : [];
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

String _pathKey(String path) => path.replaceAll('/', '\\').toLowerCase();
