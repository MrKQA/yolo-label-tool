// ignore_for_file: file_names

part of 'main.dart';

/// 轻量悬浮提示，用于复制成功等短反馈。
/// Lightweight floating feedback for short actions such as copy success.
class _FloatingMessage extends StatefulWidget {
  const _FloatingMessage({required this.message});

  final String message;

  @override
  State<_FloatingMessage> createState() => _FloatingMessageState();
}

class _FloatingMessageState extends State<_FloatingMessage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..forward();
    _opacity = Tween<double>(
      begin: 1,
      end: 0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _offset = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -0.35),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: SlideTransition(
          position: _offset,
          child: FadeTransition(
            opacity: _opacity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _isDarkMode(context)
                    ? const Color(0xCC30205A)
                    : const Color(0xDDFFFFFF),
                border: Border.all(color: _borderColor(context)),
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 14,
                    color: Color(0x22000000),
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                child: Text(
                  widget.message,
                  style: TextStyle(
                    color: _primaryTextColor(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
