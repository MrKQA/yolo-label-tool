part of '../../main.dart';

extension _WorkspaceShellSettingsActions on _WorkspaceShellState {
  void _toggleThemeMode() {
    final nextDarkMode = !_darkMode;
    setState(() {
      _darkMode = nextDarkMode;
      _appSettings = _appSettings.copyWith(darkMode: nextDarkMode);
    });
    _themeModeNotifier.value = nextDarkMode ? ThemeMode.dark : ThemeMode.light;
    ConfigStore.saveSettings(_appSettings);
  }

  void _updateShortcut(ShortcutAction action, LogicalKeyboardKey key) {
    setState(() {
      _shortcutConfig = _shortcutConfig.copyWith(action: action, key: key);
    });
    _saveKeybindings();
  }

  void _resetShortcuts() {
    setState(() => _shortcutConfig = ShortcutConfig.defaults());
    _saveKeybindings();
  }

  void _clearRecentItems() {
    setState(() {
      _recentFolders.clear();
      _recentFiles.clear();
    });
    _saveHistory();
  }

  void _showTopMenu() {
    _topMenuHideTimer?.cancel();
    if (!_topMenuVisible) {
      setState(() => _topMenuVisible = true);
    }
  }

  void _scheduleTopMenuHide() {
    _topMenuHideTimer?.cancel();
    _topMenuHideTimer = Timer(_topMenuAutoHideDelay, () {
      if (!mounted || !_topMenuVisible) {
        return;
      }
      setState(() => _topMenuVisible = false);
    });
  }

  Future<void> _showKeySettings() async {
    setState(() => _shortcutDialogOpen = true);
    await showDialog<void>(
      context: context,
      builder: (context) => ShortcutSettingsDialog(
        config: _shortcutConfig,
        onShortcutChanged: _updateShortcut,
        onReset: _resetShortcuts,
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() => _shortcutDialogOpen = false);
    _keyboardFocusNode.requestFocus();
  }

  Future<void> _showSettings() async {
    await showDialog<void>(
      context: context,
      builder: (context) => SettingsDialog(
        initialSettings: _appSettings,
        cacheSizeBytes: ConfigStore.cacheSizeInBytes(),
        onSave: _saveAppSettings,
        onClearCache: _clearCacheData,
        logger: _appLogger,
        onLogLevelChanged: (index) => _setLogLevel(
          _logLevelFromIndex(index),
          writeLog: true,
        ),
      ),
    );
    if (mounted) {
      _keyboardFocusNode.requestFocus();
    }
  }

  Future<void> _showAboutDialog() async {
    await showAboutDialogForContext(context);
    if (mounted) {
      _keyboardFocusNode.requestFocus();
    }
  }

  Future<void> _showLogViewerDialog() async {
    if (!mounted) return;
    await showLogViewerDialogForContext(
      context: context,
      onMessage: _showFloatingMessage,
      flushLogs: _flushLogs,
    );
    if (mounted) {
      _keyboardFocusNode.requestFocus();
    }
  }

  Future<int> _clearCacheData() async {
    setState(() {
      _recentFolders.clear();
      _recentFiles.clear();
      _labelClasses.clear();
      _annotationsByImage.clear();
      _imageSplits.clear();
      _importedDataset = null;
      _undoStack.clear();
      _redoStack.clear();
      _activeClassId = null;
      _selectedAnnotationId = null;
    });
    _saveHistory();
    unawaited(_saveAnnotationDatabaseNow());
    return ConfigStore.cacheSizeInBytes();
  }
}
