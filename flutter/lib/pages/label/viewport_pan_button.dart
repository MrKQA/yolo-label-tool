// =============================================================================
// viewport_pan_button.dart - Viewport Pan Button / 视口平移按钮
// =============================================================================
// Directional button with long-press auto-repeat for panning the zoomed canvas.
//
// 带长按自动重复功能的方向按钮，用于平移放大后的画布视口。
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/theme_helpers.dart';

class ViewportPanButton extends StatefulWidget {
  const ViewportPanButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.onRepeat,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final VoidCallback? onRepeat;

  @override
  State<ViewportPanButton> createState() => _ViewportPanButtonState();
}

class _ViewportPanButtonState extends State<ViewportPanButton> {
  Timer? _repeatTimer;

  @override
  void didUpdateWidget(covariant ViewportPanButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onPressed == null) {
      _stopRepeating();
    }
  }

  @override
  void dispose() {
    _stopRepeating();
    super.dispose();
  }

  void _startRepeating() {
    final callback = widget.onRepeat ?? widget.onPressed;
    if (callback == null) {
      return;
    }
    callback();
    _repeatTimer?.cancel();
    _repeatTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      callback();
    });
  }

  void _stopRepeating() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: widget.tooltip,
      child: SizedBox.square(
        dimension: 36,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          onLongPressStart: enabled ? (_) => _startRepeating() : null,
          onLongPressEnd: (_) => _stopRepeating(),
          onLongPressCancel: _stopRepeating,
          child: Material(
            color: appControlColor(
              dark,
            ).withValues(alpha: enabled ? 0.92 : 0.52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: appBorderColor(dark)),
            ),
            elevation: enabled ? 3 : 0,
            child: Center(
              child: Icon(
                widget.icon,
                size: 22,
                color: enabled
                    ? appTextColor(dark)
                    : appTextColor(dark).withValues(alpha: 0.32),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
