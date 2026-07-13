import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/annotation_database_controller.dart';
import '../../controllers/project_controller.dart';
import '../../controllers/workspace_settings_controller.dart';
import '../../dialogs/about_dialog.dart';
import '../../dialogs/log_viewer_dialog.dart';
import '../../dialogs/settings_dialog.dart';
import '../../dialogs/shortcut_dialog.dart';
import '../../models/shortcut.dart';
import '../../services/app_runtime.dart';
import '../../services/config_store.dart';

/// Owns settings-related dialogs while the shell retains application lifecycle.
class WorkspaceSettingsActions {
  WorkspaceSettingsActions({
    required this.settings,
    required this.project,
    required this.annotationDatabase,
    required this.context,
    required this.mounted,
    required this.keyboardFocusNode,
    required this.showMessage,
  });

  final WorkspaceSettingsController settings;
  final ProjectController project;
  final AnnotationDatabaseController annotationDatabase;
  final BuildContext Function() context;
  final bool Function() mounted;
  final FocusNode keyboardFocusNode;
  final ValueChanged<String> showMessage;

  bool shortcutDialogOpen = false;

  void toggleTheme() => settings.toggleTheme();

  void clearRecentItems() => project.clearRecentHistory();

  Future<void> showShortcutSettings() async {
    shortcutDialogOpen = true;
    try {
      await showDialog<void>(
        context: context(),
        builder: (context) => ShortcutSettingsDialog(
          config: settings.shortcuts,
          onShortcutChanged: _updateShortcut,
          onReset: settings.resetShortcuts,
        ),
      );
    } finally {
      shortcutDialogOpen = false;
      _restoreKeyboardFocus();
    }
  }

  Future<void> showSettings() async {
    await showDialog<void>(
      context: context(),
      builder: (context) => SettingsDialog(
        initialSettings: settings.settings,
        cacheSizeBytes: ConfigStore.cacheSizeInBytes(),
        onSave: settings.saveSettings,
        onClearCache: clearCacheData,
        logger: appLogger,
        onLogLevelChanged: (index) =>
            setAppLogLevel(appLogLevelFromIndex(index), writeLog: true),
      ),
    );
    _restoreKeyboardFocus();
  }

  Future<void> showAbout() async {
    await showAboutDialogForContext(context());
    _restoreKeyboardFocus();
  }

  Future<void> showLogs() async {
    if (!mounted()) return;
    await showLogViewerDialogForContext(
      context: context(),
      onMessage: showMessage,
      flushLogs: flushAppLogs,
    );
    _restoreKeyboardFocus();
  }

  Future<int> clearCacheData() async {
    project.clearAnnotationData();
    project.clearRecentHistory();
    unawaited(annotationDatabase.saveNow());
    return ConfigStore.cacheSizeInBytes();
  }

  void _updateShortcut(ShortcutAction action, LogicalKeyboardKey key) {
    settings.updateShortcut(action, key);
  }

  void _restoreKeyboardFocus() {
    if (mounted()) keyboardFocusNode.requestFocus();
  }
}
