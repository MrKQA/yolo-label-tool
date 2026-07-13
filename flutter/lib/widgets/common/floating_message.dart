// =============================================================================
// floating_message.dart - Floating Toast Message / 浮动提示消息
// =============================================================================
// Lightweight overlay widget that fades and slides upward, used for short
// feedback like "copied", "saved", or "operation complete".
//
// 轻量覆盖层组件：渐隐并上滑消失，用于"已复制""已保存"等短反馈。
// =============================================================================

// ignore_for_file: file_names

import 'package:flutter/material.dart';

import '../../theme/theme_helpers.dart';

/// 轻量悬浮提示，用于复制成功等短反馈。
/// Lightweight floating feedback for short actions such as copy success.
class FloatingMessage extends StatefulWidget {
  const FloatingMessage({required this.message});

  final String message;

  @override
  State<FloatingMessage> createState() => _FloatingMessageState();
}

class _FloatingMessageState extends State<FloatingMessage>
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
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xCC30205A)
                    : const Color(0xDDFFFFFF),
                border: Border.all(
                  color: appBorderColor(
                    Theme.of(context).brightness == Brightness.dark,
                  ),
                ),
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
                    color: appTextColor(
                      Theme.of(context).brightness == Brightness.dark,
                    ),
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
