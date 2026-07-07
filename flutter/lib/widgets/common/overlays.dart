part of '../../main.dart';

class _ImportBlockingOverlay extends StatelessWidget {
  const _ImportBlockingOverlay({this.message});

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
                      fontFamily: _fontFamily,
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

class _CollaborationReconnectOverlay extends StatelessWidget {
  const _CollaborationReconnectOverlay({
    required this.attempts,
    required this.onCancel,
  });

  final int attempts;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
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
              color: _panelColor(context),
              border: Border.all(color: _borderColor(context)),
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
