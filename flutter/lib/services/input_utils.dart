part of '../main.dart';

bool _isEditableTextFocused() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) {
    return false;
  }
  if (context.widget is EditableText) {
    return true;
  }
  return context.findAncestorWidgetOfExactType<EditableText>() != null;
}

String _keyboardLabel(LogicalKeyboardKey key) {
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
