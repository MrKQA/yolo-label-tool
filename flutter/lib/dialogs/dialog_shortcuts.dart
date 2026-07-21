import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/shortcut.dart';
import '../services/shortcut_runtime.dart';

/// Invokes a dialog's primary confirm/save action through the configurable
/// global shortcut, even when a text field inside the dialog has focus.
class DialogPrimaryAction extends StatelessWidget {
  const DialogPrimaryAction({
    super.key,
    required this.onInvoke,
    required this.child,
    this.enabled = true,
  });

  final VoidCallback onInvoke;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }
        if (ShortcutRuntime.matches(
          ShortcutAction.dialogCancel,
          event.logicalKey,
        )) {
          Navigator.of(context).maybePop();
          return KeyEventResult.handled;
        }
        if (!enabled) return KeyEventResult.ignored;
        if (!ShortcutRuntime.matches(
          ShortcutAction.dialogConfirm,
          event.logicalKey,
        )) {
          return KeyEventResult.ignored;
        }
        onInvoke();
        return KeyEventResult.handled;
      },
      child: child,
    );
  }
}

/// Applies the configurable global cancel shortcut to dialogs that do not
/// expose a primary confirm/save action.
class DialogCancelAction extends StatelessWidget {
  const DialogCancelAction({super.key, required this.child, this.onCancel});

  final Widget child;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent ||
            !ShortcutRuntime.matches(
              ShortcutAction.dialogCancel,
              event.logicalKey,
            )) {
          return KeyEventResult.ignored;
        }
        final callback = onCancel;
        if (callback != null) {
          callback();
        } else {
          Navigator.of(context).maybePop();
        }
        return KeyEventResult.handled;
      },
      child: child,
    );
  }
}
