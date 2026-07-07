// Viewport pan button for the label page image canvas.

part of '../../main.dart';

class _ViewportPanButton extends StatefulWidget {
  const _ViewportPanButton({
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
  State<_ViewportPanButton> createState() => _ViewportPanButtonState();
}

class _ViewportPanButtonState extends State<_ViewportPanButton> {
  Timer? _repeatTimer;

  @override
  void didUpdateWidget(covariant _ViewportPanButton oldWidget) {
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
            color: _controlColor(
              context,
            ).withValues(alpha: enabled ? 0.92 : 0.52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: _borderColor(context)),
            ),
            elevation: enabled ? 3 : 0,
            child: Center(
              child: Icon(
                widget.icon,
                size: 22,
                color: enabled
                    ? _primaryTextColor(context)
                    : _primaryTextColor(context).withValues(alpha: 0.32),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
