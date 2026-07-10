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

import 'dart:convert';
import 'dart:io';

import '../models/config.dart';
import '../models/shortcut.dart';
import '../models/training.dart';
import 'rust_backend.dart';

/// 最近文件历史。
/// Recent file and folder history.
/// Last label-page image position per project.
/// Application settings for Python environment and training output path.
/// 训练参数偏好，在程序重启后恢复上次选择。
/// Training parameter preferences restored on app restart.

/// 本地配置文件读写。路径使用当前系统用户目录，不写死 Windows 用户名。
/// Local config store. The path is derived from the current user home.

class ConfigStore {
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
      const HistoryConfig(folders: [], files: []).toJson(),
    );
    _ensureDbConfig(_keybindingsKey, ShortcutConfig.defaults().toJson());
    _ensureDbConfig(
      _settingsKey,
      AppSettings(
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
      const TrainingHistoryConfig(entries: []).toJson(),
    );
    _ensureDbConfig(
      _trainingPreferencesKey,
      TrainingPreferences.fromJson(null).toJson(),
    );
    _ensureDbConfig(
      _labelResumePositionsKey,
      const LabelResumePositionsConfig(entries: {}).toJson(),
    );
  }

  static HistoryConfig loadHistory() {
    return HistoryConfig.fromJson(_readDbJson(_historyKey));
  }

  static ShortcutConfig loadKeybindings() {
    return ShortcutConfig.fromJson(_readDbJson(_keybindingsKey));
  }

  static AppSettings loadSettings() {
    return AppSettings.fromJson(
      _readDbJson(_settingsKey),
      defaultOutputPath: defaultRunsDirectory.path,
      defaultExportPath: defaultDatasetsDirectory.path,
      identity: loadStableCollaborationIdentity(),
    );
  }

  static TrainingHistoryConfig loadTrainingHistory() {
    return TrainingHistoryConfig.fromJson(_readDbJson(_trainingHistoryKey));
  }

  static LabelResumePosition? loadLabelResumePosition(String projectKey) {
    final config = LabelResumePositionsConfig.fromJson(
      _readDbJson(_labelResumePositionsKey),
    );
    return config.entries[projectKey];
  }

  static void saveHistory(HistoryConfig value) {
    _writeDbJson(_historyKey, value.toJson());
  }

  static void saveKeybindings(ShortcutConfig value) {
    _writeDbJson(_keybindingsKey, value.toJson());
  }

  static void saveSettings(AppSettings value) {
    _writeDbJson(_settingsKey, value.toJson());
  }

  static void saveLabelResumePosition(LabelResumePosition value) {
    final config = LabelResumePositionsConfig.fromJson(
      _readDbJson(_labelResumePositionsKey),
    );
    final entries = Map<String, LabelResumePosition>.of(config.entries);
    entries[value.projectKey] = value;
    _writeDbJson(
      _labelResumePositionsKey,
      LabelResumePositionsConfig(entries: entries).toJson(),
    );
  }

  static CollaborationIdentityConfig loadStableCollaborationIdentity() {
    final machineSource = _machineIdentitySource();
    if (machineSource.isNotEmpty) {
      final userName = _collaborationIdSegment(
        Platform.environment['USERNAME'] ?? Platform.environment['USER'] ?? '',
      );
      final identity = CollaborationIdentityConfig(
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
    final generated = CollaborationIdentityConfig(
      hostId: _newStableCollaborationId('host'),
      userId: _newStableCollaborationId('user'),
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

  static String _newStableCollaborationId(String prefix) {
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final userName =
        Platform.environment['USERNAME'] ?? Platform.environment['USER'] ?? '';
    final seed = '$prefix|$timestamp|${Platform.localHostname}|$userName';
    return '$prefix-$timestamp-${_stableIdentityHash(seed).toLowerCase()}';
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

  static CollaborationIdentityConfig _readCollaborationIdentityFile() {
    try {
      final file = collaborationIdentityFile;
      if (!file.existsSync()) {
        return const CollaborationIdentityConfig(hostId: '', userId: '');
      }
      return CollaborationIdentityConfig.fromJson(
        jsonDecode(file.readAsStringSync()),
      );
    } on Object {
      return const CollaborationIdentityConfig(hostId: '', userId: '');
    }
  }

  static void _writeCollaborationIdentityFile(
    CollaborationIdentityConfig value,
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

  static void saveTrainingHistory(TrainingHistoryConfig value) {
    _writeDbJson(_trainingHistoryKey, value.toJson());
  }

  static TrainingPreferences loadTrainingPreferences() {
    return TrainingPreferences.fromJson(_readDbJson(_trainingPreferencesKey));
  }

  static void saveTrainingPreferences(TrainingPreferences value) {
    _writeDbJson(_trainingPreferencesKey, value.toJson());
  }

  static int cacheSizeInBytes() {
    return _databaseSizeInBytes();
  }

  static List<String> logDates() {
    try {
      return RustBackend.logDates();
    } on Object {
      return const [];
    }
  }

  static String readLogsForDate(String date) {
    try {
      return RustBackend.readLogsForDate(date);
    } on Object {
      return '';
    }
  }

  static int deleteLogsByDateRange(String startDate, String endDate) {
    try {
      return RustBackend.deleteLogsByDateRange(
        startDate: startDate,
        endDate: endDate,
      );
    } on Object {
      return 0;
    }
  }

  static Future<Map<String, dynamic>> databaseOverview() {
    return RustBackend.databaseOverview();
  }

  static Future<Map<String, dynamic>> databaseTable({
    required String table,
    String projectId = '',
    String imageId = '',
    int limit = 50,
    int offset = 0,
  }) {
    return RustBackend.databaseTable(
      table: table,
      projectId: projectId,
      imageId: imageId,
      limit: limit,
      offset: offset,
    );
  }

  static Future<Map<String, dynamic>> databaseSqlQuery({required String sql}) {
    return RustBackend.databaseSqlQuery(sql: sql);
  }

  static Future<List<String>> trainingLogDates() {
    return RustBackend.trainingLogDates();
  }

  static Future<String> readTrainingLogForDate(String date) {
    return RustBackend.readTrainingLogForDate(date);
  }

  static Future<int> deleteTrainingLogsByDateRange(
    String startDate,
    String endDate,
  ) {
    return RustBackend.deleteTrainingLogsByDateRange(
      startDate: startDate,
      endDate: endDate,
    );
  }

  static String loadLastSam3ModelPath() {
    try {
      final value = RustBackend.loadConfigValue(
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
      RustBackend.saveConfigValue(
        key: 'ai.sam3.modelPath',
        value: normalized,
      );
    } on Object {
      // Keep the current in-memory selection if DB persistence fails.
    }
  }

  static void appendLogLines(String lines) {
    try {
      RustBackend.appendLogLines(lines: lines);
    } on Object {
      // DB-only logging: ignore write failures to avoid blocking the UI.
    }
  }

  static Object? _readDbJson(String key) {
    try {
      final value = RustBackend.loadConfigValue(key: key);
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
      RustBackend.saveConfigValue(
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
      final value = RustBackend.loadConfigValue(key: key);
      if (value.trim().isEmpty) {
        _writeDbJson(key, defaultValue);
      }
    } on Object {
      _writeDbJson(key, defaultValue);
    }
  }
}
