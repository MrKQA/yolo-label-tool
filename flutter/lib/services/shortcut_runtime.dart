import 'package:flutter/services.dart';

import '../models/shortcut.dart';

/// Shares the persisted shortcut configuration with modal routes, which are
/// built above the workspace provider scope by Flutter's root navigator.
class ShortcutRuntime {
  ShortcutRuntime._();

  static ShortcutConfig _config = ShortcutConfig.defaults();

  static void update(ShortcutConfig config) {
    _config = config;
  }

  static bool matches(ShortcutAction action, LogicalKeyboardKey key) {
    final binding = _config.binding(action);
    if (binding.matches(key)) {
      return true;
    }
    final configuredKey = binding.logicalKey;
    return (configuredKey == LogicalKeyboardKey.enter &&
            key == LogicalKeyboardKey.numpadEnter) ||
        (configuredKey == LogicalKeyboardKey.numpadEnter &&
            key == LogicalKeyboardKey.enter);
  }
}
