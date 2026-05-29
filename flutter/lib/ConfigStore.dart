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
class _AppSettings {
  const _AppSettings({required this.pythonPath, required this.outputPath});

  factory _AppSettings.empty() {
    return _AppSettings(
      pythonPath: '',
      outputPath: _ConfigStore.defaultRunsDirectory.path,
    );
  }

  final String pythonPath;
  final String outputPath;

  _AppSettings copyWith({String? pythonPath, String? outputPath}) {
    return _AppSettings(
      pythonPath: pythonPath ?? this.pythonPath,
      outputPath: outputPath ?? this.outputPath,
    );
  }

  Map<String, Object> toJson() => {
    'pythonPath': pythonPath,
    'outputPath': outputPath,
  };

  static _AppSettings fromJson(Object? value) {
    if (value is! Map) {
      return _AppSettings.empty();
    }
    final outputPath = value['outputPath'];
    return _AppSettings(
      pythonPath: value['pythonPath'] is String
          ? value['pythonPath'] as String
          : '',
      outputPath: outputPath is String && outputPath.isNotEmpty
          ? outputPath
          : _ConfigStore.defaultRunsDirectory.path,
    );
  }
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

  static _HistoryConfig loadHistory() {
    return _HistoryConfig.fromJson(_readJson(_historyFile));
  }

  static _ShortcutConfig loadKeybindings() {
    return _ShortcutConfig.fromJson(_readJson(_keybindingsFile));
  }

  static _AppSettings loadSettings() {
    return _AppSettings.fromJson(_readJson(_settingsFile));
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
