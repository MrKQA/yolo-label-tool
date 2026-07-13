import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/config.dart';
import '../models/shortcut.dart';
import '../services/app_runtime.dart';
import '../services/config_store.dart';
import '../services/i18n.dart';
import '../services/path_utils.dart';
import 'collaboration_controller.dart';

typedef ShortcutConfigLoader = ShortcutConfig Function();
typedef ShortcutConfigSaver = void Function(ShortcutConfig config);
typedef AppSettingsLoader = AppSettings Function();
typedef AppSettingsSaver = void Function(AppSettings settings);
typedef LanguageOptionsLoader = Future<List<LanguageOption>> Function();
typedef LanguageStringsLoader =
    Future<AppLanguageStrings> Function(String code);
typedef LanguageStringsApplier = void Function(AppLanguageStrings strings);
typedef ThemeModeApplier = void Function(bool darkMode);
typedef LogLevelApplier = void Function(int levelIndex);

/// Owns persisted workspace settings, shortcuts, language, and theme state.
class WorkspaceSettingsController extends ChangeNotifier {
  WorkspaceSettingsController({
    required this.collaboration,
    ShortcutConfigLoader? shortcutLoader,
    ShortcutConfigSaver? shortcutSaver,
    AppSettingsLoader? settingsLoader,
    AppSettingsSaver? settingsSaver,
    LanguageOptionsLoader? languageOptionsLoader,
    LanguageStringsLoader? languageStringsLoader,
    LanguageStringsApplier? languageStringsApplier,
    ThemeModeApplier? themeModeApplier,
    LogLevelApplier? logLevelApplier,
  }) : _shortcutLoader = shortcutLoader ?? ConfigStore.loadKeybindings,
       _shortcutSaver = shortcutSaver ?? ConfigStore.saveKeybindings,
       _settingsLoader = settingsLoader ?? ConfigStore.loadSettings,
       _settingsSaver = settingsSaver ?? ConfigStore.saveSettings,
       _languageOptionsLoader =
           languageOptionsLoader ??
           (() => LanguageOption.loadAvailable(compare: naturalCompare)),
       _languageStringsLoader =
           languageStringsLoader ?? AppLanguageStrings.load,
       _languageStringsApplier =
           languageStringsApplier ?? setCurrentLanguageStrings,
       _themeModeApplier =
           themeModeApplier ??
           ((darkMode) {
             themeModeNotifier.value = darkMode
                 ? ThemeMode.dark
                 : ThemeMode.light;
           }),
       _logLevelApplier =
           logLevelApplier ??
           ((index) => setAppLogLevel(appLogLevelFromIndex(index)));

  final CollaborationController collaboration;
  final ShortcutConfigLoader _shortcutLoader;
  final ShortcutConfigSaver _shortcutSaver;
  final AppSettingsLoader _settingsLoader;
  final AppSettingsSaver _settingsSaver;
  final LanguageOptionsLoader _languageOptionsLoader;
  final LanguageStringsLoader _languageStringsLoader;
  final LanguageStringsApplier _languageStringsApplier;
  final ThemeModeApplier _themeModeApplier;
  final LogLevelApplier _logLevelApplier;

  ShortcutConfig shortcuts = ShortcutConfig.defaults();
  AppSettings settings = const AppSettings.empty();
  List<LanguageOption> languageOptions = const [
    LanguageOption(code: appDefaultLanguageCode, label: 'Simplified Chinese'),
  ];
  String activeLanguageCode = appDefaultLanguageCode;
  bool darkMode = false;
  bool _disposed = false;

  void loadPersisted() {
    shortcuts = _shortcutLoader();
    settings = _settingsLoader();
    darkMode = settings.darkMode;
    collaboration.restoreIdentity(
      hostId: settings.collaborationHostId,
      userId: settings.collaborationUserId,
    );
    _settingsSaver(settings);
    _themeModeApplier(darkMode);
    _logLevelApplier(settings.logLevelIndex);
    _notifyChanged();
  }

  Future<void> loadAvailableLanguages() async {
    final options = await _languageOptionsLoader();
    if (_disposed) {
      return;
    }
    languageOptions = List<LanguageOption>.unmodifiable(options);
    _notifyChanged();
  }

  Future<bool> changeLanguage(String code) async {
    if (code == activeLanguageCode) {
      return false;
    }
    final strings = await _languageStringsLoader(code);
    if (_disposed) {
      return false;
    }
    _languageStringsApplier(strings);
    activeLanguageCode = code;
    _notifyChanged();
    return true;
  }

  void saveSettings(AppSettings value) {
    settings = value.copyWith(
      collaborationHostId: collaboration.hostId,
      collaborationUserId: collaboration.userId,
    );
    darkMode = settings.darkMode;
    _themeModeApplier(darkMode);
    _settingsSaver(settings);
    _notifyChanged();
  }

  void toggleTheme() {
    saveSettings(settings.copyWith(darkMode: !darkMode));
  }

  void updateShortcut(ShortcutAction action, LogicalKeyboardKey key) {
    shortcuts = shortcuts.copyWith(action: action, key: key);
    _shortcutSaver(shortcuts);
    _notifyChanged();
  }

  void resetShortcuts() {
    shortcuts = ShortcutConfig.defaults();
    _shortcutSaver(shortcuts);
    _notifyChanged();
  }

  void _notifyChanged() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
