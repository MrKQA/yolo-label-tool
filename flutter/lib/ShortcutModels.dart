// =============================================================================
// ShortcutModels.dart - Keyboard Shortcuts / 快捷键模型
// =============================================================================
// Configurable keyboard shortcuts with default bindings and JSON persistence.
// 可自定义快捷键的数据模型、默认绑定与 JSON 持久化。
// =============================================================================

// ignore_for_file: file_names

part of 'main.dart';

/// Configurable shortcut action / 可配置快捷键动作
/// User-configurable shortcut actions.
enum _ShortcutAction {
  previousImage,
  nextImage,
  zoomIn,
  zoomOut,
  hbbMode,
  obbMode,
  segMode,
  deleteSelected,
  hideClassLabels,
  rotateObbLeft5,
  rotateObbLeft1,
  rotateObbRight1,
  rotateObbRight5,
  browsePreviousMedia,
  browseNextMedia,
  browseFullscreen,
  browseVolumeUp,
  browseVolumeDown,
  videoPlayPause,
  videoRewind,
  videoFastForward,
  aiAnnotateCurrent,
  aiAnnotateAll,
}

enum _ShortcutScope { global, label, browse, train }

extension _ShortcutActionLabel on _ShortcutAction {
  String get labelKey => switch (this) {
    _ShortcutAction.previousImage => 'shortcut.previousImage',
    _ShortcutAction.nextImage => 'shortcut.nextImage',
    _ShortcutAction.zoomIn => 'shortcut.zoomIn',
    _ShortcutAction.zoomOut => 'shortcut.zoomOut',
    _ShortcutAction.hbbMode => 'shortcut.hbbMode',
    _ShortcutAction.obbMode => 'shortcut.obbMode',
    _ShortcutAction.segMode => 'shortcut.segMode',
    _ShortcutAction.deleteSelected => 'shortcut.deleteSelected',
    _ShortcutAction.hideClassLabels => 'shortcut.hideClassLabels',
    _ShortcutAction.rotateObbLeft5 => 'shortcut.rotateObbLeft5',
    _ShortcutAction.rotateObbLeft1 => 'shortcut.rotateObbLeft1',
    _ShortcutAction.rotateObbRight1 => 'shortcut.rotateObbRight1',
    _ShortcutAction.rotateObbRight5 => 'shortcut.rotateObbRight5',
    _ShortcutAction.browsePreviousMedia => 'shortcut.browsePreviousMedia',
    _ShortcutAction.browseNextMedia => 'shortcut.browseNextMedia',
    _ShortcutAction.browseFullscreen => 'shortcut.browseFullscreen',
    _ShortcutAction.browseVolumeUp => 'shortcut.browseVolumeUp',
    _ShortcutAction.browseVolumeDown => 'shortcut.browseVolumeDown',
    _ShortcutAction.videoPlayPause => 'shortcut.videoPlayPause',
    _ShortcutAction.videoRewind => 'shortcut.videoRewind',
    _ShortcutAction.videoFastForward => 'shortcut.videoFastForward',
    _ShortcutAction.aiAnnotateCurrent => 'shortcut.aiAnnotateCurrent',
    _ShortcutAction.aiAnnotateAll => 'shortcut.aiAnnotateAll',
  };

  bool get isAiAction => switch (this) {
    _ShortcutAction.aiAnnotateCurrent || _ShortcutAction.aiAnnotateAll => true,
    _ => false,
  };

  _ShortcutScope get scope => switch (this) {
    _ShortcutAction.browsePreviousMedia ||
    _ShortcutAction.browseNextMedia ||
    _ShortcutAction.browseFullscreen ||
    _ShortcutAction.browseVolumeUp ||
    _ShortcutAction.browseVolumeDown ||
    _ShortcutAction.videoPlayPause ||
    _ShortcutAction.videoRewind ||
    _ShortcutAction.videoFastForward => _ShortcutScope.browse,
    _ => _ShortcutScope.label,
  };
}

extension _ShortcutScopeLabel on _ShortcutScope {
  String get labelKey => switch (this) {
    _ShortcutScope.global => 'shortcut.scopeGlobal',
    _ShortcutScope.label => 'shortcut.scopeLabel',
    _ShortcutScope.browse => 'shortcut.scopeBrowse',
    _ShortcutScope.train => 'shortcut.scopeTrain',
  };
}

/// 单个快捷键绑定。
/// Single shortcut key binding.
class _ShortcutBinding {
  const _ShortcutBinding(this.keyId, this.fallbackLabel);

  const _ShortcutBinding.unassigned() : this(0, '-');

  factory _ShortcutBinding.fromKey(LogicalKeyboardKey key) {
    return _ShortcutBinding(key.keyId, _keyboardLabel(key));
  }

  final int keyId;
  final String fallbackLabel;

  LogicalKeyboardKey? get logicalKey =>
      LogicalKeyboardKey.findKeyByKeyId(keyId);

  String get displayLabel {
    final key = logicalKey;
    if (key == null) {
      return fallbackLabel;
    }
    return _keyboardLabel(key);
  }

  bool matches(LogicalKeyboardKey key) => key.keyId == keyId;

  Map<String, Object> toJson() => {'keyId': keyId, 'label': displayLabel};

  static _ShortcutBinding fromJson(Object? value, _ShortcutBinding fallback) {
    if (value is! Map) {
      return fallback;
    }
    final keyId = value['keyId'];
    final label = value['label'];
    if (keyId is! int) {
      return fallback;
    }
    return _ShortcutBinding(
      keyId,
      label is String ? label : fallback.fallbackLabel,
    );
  }
}

/// 快捷键配置，使用 map 便于后续继续扩展动作。
/// Shortcut configuration backed by a map so new actions can be added safely.
class _ShortcutConfig {
  const _ShortcutConfig(this._bindings);

  factory _ShortcutConfig.defaults() {
    return _ShortcutConfig({
      _ShortcutAction.previousImage: _ShortcutBinding.fromKey(
        LogicalKeyboardKey.keyA,
      ),
      _ShortcutAction.nextImage: _ShortcutBinding.fromKey(
        LogicalKeyboardKey.keyD,
      ),
      _ShortcutAction.zoomIn: _ShortcutBinding.fromKey(
        LogicalKeyboardKey.equal,
      ),
      _ShortcutAction.zoomOut: _ShortcutBinding.fromKey(
        LogicalKeyboardKey.minus,
      ),
      _ShortcutAction.hbbMode: _ShortcutBinding.fromKey(
        LogicalKeyboardKey.keyR,
      ),
      _ShortcutAction.obbMode: _ShortcutBinding.fromKey(
        LogicalKeyboardKey.keyB,
      ),
      _ShortcutAction.segMode: _ShortcutBinding.fromKey(
        LogicalKeyboardKey.keyS,
      ),
      _ShortcutAction.deleteSelected: _ShortcutBinding.fromKey(
        LogicalKeyboardKey.delete,
      ),
      _ShortcutAction.hideClassLabels: _ShortcutBinding.fromKey(
        LogicalKeyboardKey.keyH,
      ),
      _ShortcutAction.rotateObbLeft5: _ShortcutBinding.fromKey(
        LogicalKeyboardKey.keyZ,
      ),
      _ShortcutAction.rotateObbLeft1: _ShortcutBinding.fromKey(
        LogicalKeyboardKey.keyX,
      ),
      _ShortcutAction.rotateObbRight1: _ShortcutBinding.fromKey(
        LogicalKeyboardKey.keyC,
      ),
      _ShortcutAction.rotateObbRight5: _ShortcutBinding.fromKey(
        LogicalKeyboardKey.keyV,
      ),
      _ShortcutAction.browsePreviousMedia: _ShortcutBinding.fromKey(
        LogicalKeyboardKey.keyA,
      ),
      _ShortcutAction.browseNextMedia: _ShortcutBinding.fromKey(
        LogicalKeyboardKey.keyD,
      ),
      _ShortcutAction.browseFullscreen: _ShortcutBinding.fromKey(
        LogicalKeyboardKey.enter,
      ),
      _ShortcutAction.browseVolumeUp: _ShortcutBinding.fromKey(
        LogicalKeyboardKey.arrowUp,
      ),
      _ShortcutAction.browseVolumeDown: _ShortcutBinding.fromKey(
        LogicalKeyboardKey.arrowDown,
      ),
      _ShortcutAction.videoPlayPause: _ShortcutBinding.fromKey(
        LogicalKeyboardKey.space,
      ),
      _ShortcutAction.videoRewind: _ShortcutBinding.fromKey(
        LogicalKeyboardKey.arrowLeft,
      ),
      _ShortcutAction.videoFastForward: _ShortcutBinding.fromKey(
        LogicalKeyboardKey.arrowRight,
      ),
      _ShortcutAction.aiAnnotateCurrent: const _ShortcutBinding.unassigned(),
      _ShortcutAction.aiAnnotateAll: const _ShortcutBinding.unassigned(),
    });
  }

  final Map<_ShortcutAction, _ShortcutBinding> _bindings;

  _ShortcutBinding binding(_ShortcutAction action) {
    return _bindings[action] ?? _ShortcutConfig.defaults()._bindings[action]!;
  }

  bool matches(_ShortcutAction action, LogicalKeyboardKey key) {
    return binding(action).matches(key);
  }

  _ShortcutConfig copyWith({
    required _ShortcutAction action,
    required LogicalKeyboardKey key,
  }) {
    return _ShortcutConfig({
      ..._bindings,
      action: _ShortcutBinding.fromKey(key),
    });
  }

  Map<String, Object> toJson() => {
    for (final entry in _bindings.entries) entry.key.name: entry.value.toJson(),
  };

  static _ShortcutConfig fromJson(Object? value) {
    final defaults = _ShortcutConfig.defaults();
    if (value is! Map) {
      return defaults;
    }

    return _ShortcutConfig({
      for (final action in _ShortcutAction.values)
        action: _ShortcutBinding.fromJson(
          value[action.name],
          defaults.binding(action),
        ),
    });
  }
}
