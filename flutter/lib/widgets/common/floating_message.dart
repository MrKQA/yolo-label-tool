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

const appNoticeDisplayDuration = Duration(milliseconds: 2600);
const appNoticeRepeatInterval = Duration(milliseconds: 2800);

/// 轻量悬浮提示，用于复制成功等短反馈。
/// Lightweight floating feedback for short actions such as copy success.
class FloatingMessage extends StatefulWidget {
  const FloatingMessage({
    super.key,
    required this.message,
    this.duration = const Duration(milliseconds: 1800),
  });

  final String message;
  final Duration duration;

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
    _controller = AnimationController(duration: widget.duration, vsync: this)
      ..forward();
    _opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 18,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1), weight: 57),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1,
          end: 0,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 25,
      ),
    ]).animate(_controller);
    _offset = TweenSequence<Offset>([
      TweenSequenceItem(
        tween: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 18,
      ),
      TweenSequenceItem(tween: ConstantTween<Offset>(Offset.zero), weight: 57),
      TweenSequenceItem(
        tween: Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(0, -0.08),
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 25,
      ),
    ]).animate(_controller);
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
                color: panelColor(context).withValues(alpha: 0.96),
                border: Border.all(
                  color: appBorderColor(
                    Theme.of(context).brightness == Brightness.dark,
                  ),
                ),
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 14,
                    color: Colors.black.withValues(
                      alpha: isDarkMode(context) ? 0.30 : 0.13,
                    ),
                    offset: const Offset(0, 4),
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
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: bodyTextColor(context),
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
