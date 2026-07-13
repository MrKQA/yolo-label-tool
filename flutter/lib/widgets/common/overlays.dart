// =============================================================================
// overlays.dart - Full-Screen Overlay Widgets / 全屏覆盖组件
// =============================================================================
// ImportBlockingOverlay: semi-transparent overlay shown during dataset import
// or AI annotation, optionally with a status message.
// CollaborationReconnectOverlay: reconnection progress with cancel button.
//
// ImportBlockingOverlay：导入/AI 标注时的半透明覆盖层。
// CollaborationReconnectOverlay：重连进度覆盖层。
// =============================================================================

import 'package:flutter/material.dart';

import '../../services/i18n.dart';
import '../../theme/theme_helpers.dart';

class ImportBlockingOverlay extends StatelessWidget {
  const ImportBlockingOverlay({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: true,
      child: ColoredBox(
        color: Colors.white.withValues(alpha: 0.78),
        child: Center(
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 220),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 42,
                    height: 42,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    message ?? t('import.waiting'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                      fontFamily: appFontFamily,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CollaborationReconnectOverlay extends StatelessWidget {
  const CollaborationReconnectOverlay({
    required this.attempts,
    required this.onCancel,
  });

  final int attempts;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        AbsorbPointer(
          absorbing: true,
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.32)),
        ),
        Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: appPanelColor(dark),
              border: Border.all(color: appBorderColor(dark)),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '${t('collab.reconnecting')} ${attempts.clamp(1, 5)}/5',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: onCancel,
                    child: Text(t('action.cancel')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
