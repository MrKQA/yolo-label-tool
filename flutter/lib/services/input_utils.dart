// =============================================================================
// input_utils.dart - Input Utilities / 输入工具
// =============================================================================
// Checks whether the current keyboard focus is on an editable text field
// and provides human-readable keyboard key labels for shortcut display.
//
// 检测当前键盘焦点是否在可编辑文本字段上，并提供快捷键显示用的按键标签。
// =============================================================================

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

final Set<FocusNode> _registeredEditableFocusNodes = <FocusNode>{};

void registerEditableFocusNode(FocusNode node) {
  _registeredEditableFocusNodes.add(node);
}

void unregisterEditableFocusNode(FocusNode node) {
  _registeredEditableFocusNodes.remove(node);
}

bool isEditableTextFocused() {
  if (_registeredEditableFocusNodes.any((node) => node.hasFocus)) {
    return true;
  }
  final primaryFocus = FocusManager.instance.primaryFocus;
  if (primaryFocus == null) return false;
  for (final node in <FocusNode>[primaryFocus, ...primaryFocus.ancestors]) {
    final context = node.context;
    if (context == null) continue;
    if (context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null ||
        context.findAncestorStateOfType<EditableTextState>() != null) {
      return true;
    }
  }
  return false;
}

String keyboardLabel(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.space) return 'Space';
  if (key == LogicalKeyboardKey.arrowLeft) return 'Left';
  if (key == LogicalKeyboardKey.arrowRight) return 'Right';
  if (key == LogicalKeyboardKey.arrowUp) return 'Up';
  if (key == LogicalKeyboardKey.arrowDown) return 'Down';
  if (key.keyLabel.isNotEmpty) {
    return key.keyLabel.toUpperCase();
  }
  return key.debugName ?? key.keyId.toString();
}
