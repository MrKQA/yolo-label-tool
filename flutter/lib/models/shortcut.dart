// =============================================================================
// ShortcutModels.dart - Keyboard Shortcuts / 快捷键模型
// =============================================================================
// Configurable keyboard shortcuts with default bindings and JSON persistence.
// 可自定义快捷键的数据模型、默认绑定与 JSON 持久化。
// =============================================================================

// ignore_for_file: file_names

import 'package:flutter/services.dart';

import '../services/input_utils.dart';

/// Configurable shortcut action / 可配置快捷键动作
/// User-configurable shortcut actions.
enum ShortcutAction {
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

enum ShortcutScope { global, label, browse, train }

extension ShortcutActionLabel on ShortcutAction {
  String get labelKey => switch (this) {
    ShortcutAction.previousImage => 'shortcut.previousImage',
    ShortcutAction.nextImage => 'shortcut.nextImage',
    ShortcutAction.zoomIn => 'shortcut.zoomIn',
    ShortcutAction.zoomOut => 'shortcut.zoomOut',
    ShortcutAction.hbbMode => 'shortcut.hbbMode',
    ShortcutAction.obbMode => 'shortcut.obbMode',
    ShortcutAction.segMode => 'shortcut.segMode',
    ShortcutAction.deleteSelected => 'shortcut.deleteSelected',
    ShortcutAction.hideClassLabels => 'shortcut.hideClassLabels',
    ShortcutAction.rotateObbLeft5 => 'shortcut.rotateObbLeft5',
    ShortcutAction.rotateObbLeft1 => 'shortcut.rotateObbLeft1',
    ShortcutAction.rotateObbRight1 => 'shortcut.rotateObbRight1',
    ShortcutAction.rotateObbRight5 => 'shortcut.rotateObbRight5',
    ShortcutAction.browsePreviousMedia => 'shortcut.browsePreviousMedia',
    ShortcutAction.browseNextMedia => 'shortcut.browseNextMedia',
    ShortcutAction.browseFullscreen => 'shortcut.browseFullscreen',
    ShortcutAction.browseVolumeUp => 'shortcut.browseVolumeUp',
    ShortcutAction.browseVolumeDown => 'shortcut.browseVolumeDown',
    ShortcutAction.videoPlayPause => 'shortcut.videoPlayPause',
    ShortcutAction.videoRewind => 'shortcut.videoRewind',
    ShortcutAction.videoFastForward => 'shortcut.videoFastForward',
    ShortcutAction.aiAnnotateCurrent => 'shortcut.aiAnnotateCurrent',
    ShortcutAction.aiAnnotateAll => 'shortcut.aiAnnotateAll',
  };

  bool get isAiAction => switch (this) {
    ShortcutAction.aiAnnotateCurrent || ShortcutAction.aiAnnotateAll => true,
    _ => false,
  };

  ShortcutScope get scope => switch (this) {
    ShortcutAction.browsePreviousMedia ||
    ShortcutAction.browseNextMedia ||
    ShortcutAction.browseFullscreen ||
    ShortcutAction.browseVolumeUp ||
    ShortcutAction.browseVolumeDown ||
    ShortcutAction.videoPlayPause ||
    ShortcutAction.videoRewind ||
    ShortcutAction.videoFastForward => ShortcutScope.browse,
    _ => ShortcutScope.label,
  };
}

extension ShortcutScopeLabel on ShortcutScope {
  String get labelKey => switch (this) {
    ShortcutScope.global => 'shortcut.scopeGlobal',
    ShortcutScope.label => 'shortcut.scopeLabel',
    ShortcutScope.browse => 'shortcut.scopeBrowse',
    ShortcutScope.train => 'shortcut.scopeTrain',
  };
}

/// 单个快捷键绑定。
/// Single shortcut key binding.
class ShortcutBinding {
  const ShortcutBinding(this.keyId, this.fallbackLabel);

  const ShortcutBinding.unassigned() : this(0, '-');

  factory ShortcutBinding.fromKey(LogicalKeyboardKey key) {
    return ShortcutBinding(key.keyId, keyboardLabel(key));
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
    return keyboardLabel(key);
  }

  bool matches(LogicalKeyboardKey key) => key.keyId == keyId;

  Map<String, Object> toJson() => {'keyId': keyId, 'label': displayLabel};

  static ShortcutBinding fromJson(Object? value, ShortcutBinding fallback) {
    if (value is! Map) {
      return fallback;
    }
    final keyId = value['keyId'];
    final label = value['label'];
    if (keyId is! int) {
      return fallback;
    }
    return ShortcutBinding(
      keyId,
      label is String ? label : fallback.fallbackLabel,
    );
  }
}

/// 快捷键配置，使用 map 便于后续继续扩展动作。
/// Shortcut configuration backed by a map so new actions can be added safely.
class ShortcutConfig {
  const ShortcutConfig(this._bindings);

  factory ShortcutConfig.defaults() {
    return ShortcutConfig({
      ShortcutAction.previousImage: ShortcutBinding.fromKey(
        LogicalKeyboardKey.keyA,
      ),
      ShortcutAction.nextImage: ShortcutBinding.fromKey(
        LogicalKeyboardKey.keyD,
      ),
      ShortcutAction.zoomIn: ShortcutBinding.fromKey(
        LogicalKeyboardKey.equal,
      ),
      ShortcutAction.zoomOut: ShortcutBinding.fromKey(
        LogicalKeyboardKey.minus,
      ),
      ShortcutAction.hbbMode: ShortcutBinding.fromKey(
        LogicalKeyboardKey.keyR,
      ),
      ShortcutAction.obbMode: ShortcutBinding.fromKey(
        LogicalKeyboardKey.keyB,
      ),
      ShortcutAction.segMode: ShortcutBinding.fromKey(
        LogicalKeyboardKey.keyS,
      ),
      ShortcutAction.deleteSelected: ShortcutBinding.fromKey(
        LogicalKeyboardKey.delete,
      ),
      ShortcutAction.hideClassLabels: ShortcutBinding.fromKey(
        LogicalKeyboardKey.keyH,
      ),
      ShortcutAction.rotateObbLeft5: ShortcutBinding.fromKey(
        LogicalKeyboardKey.keyZ,
      ),
      ShortcutAction.rotateObbLeft1: ShortcutBinding.fromKey(
        LogicalKeyboardKey.keyX,
      ),
      ShortcutAction.rotateObbRight1: ShortcutBinding.fromKey(
        LogicalKeyboardKey.keyC,
      ),
      ShortcutAction.rotateObbRight5: ShortcutBinding.fromKey(
        LogicalKeyboardKey.keyV,
      ),
      ShortcutAction.browsePreviousMedia: ShortcutBinding.fromKey(
        LogicalKeyboardKey.keyA,
      ),
      ShortcutAction.browseNextMedia: ShortcutBinding.fromKey(
        LogicalKeyboardKey.keyD,
      ),
      ShortcutAction.browseFullscreen: ShortcutBinding.fromKey(
        LogicalKeyboardKey.enter,
      ),
      ShortcutAction.browseVolumeUp: ShortcutBinding.fromKey(
        LogicalKeyboardKey.arrowUp,
      ),
      ShortcutAction.browseVolumeDown: ShortcutBinding.fromKey(
        LogicalKeyboardKey.arrowDown,
      ),
      ShortcutAction.videoPlayPause: ShortcutBinding.fromKey(
        LogicalKeyboardKey.space,
      ),
      ShortcutAction.videoRewind: ShortcutBinding.fromKey(
        LogicalKeyboardKey.arrowLeft,
      ),
      ShortcutAction.videoFastForward: ShortcutBinding.fromKey(
        LogicalKeyboardKey.arrowRight,
      ),
      ShortcutAction.aiAnnotateCurrent: const ShortcutBinding.unassigned(),
      ShortcutAction.aiAnnotateAll: const ShortcutBinding.unassigned(),
    });
  }

  final Map<ShortcutAction, ShortcutBinding> _bindings;

  ShortcutBinding binding(ShortcutAction action) {
    return _bindings[action] ?? ShortcutConfig.defaults()._bindings[action]!;
  }

  bool matches(ShortcutAction action, LogicalKeyboardKey key) {
    return binding(action).matches(key);
  }

  ShortcutConfig copyWith({
    required ShortcutAction action,
    required LogicalKeyboardKey key,
  }) {
    return ShortcutConfig({
      ..._bindings,
      action: ShortcutBinding.fromKey(key),
    });
  }

  Map<String, Object> toJson() => {
    for (final entry in _bindings.entries) entry.key.name: entry.value.toJson(),
  };

  static ShortcutConfig fromJson(Object? value) {
    final defaults = ShortcutConfig.defaults();
    if (value is! Map) {
      return defaults;
    }

    return ShortcutConfig({
      for (final action in ShortcutAction.values)
        action: ShortcutBinding.fromJson(
          value[action.name],
          defaults.binding(action),
        ),
    });
  }
}
