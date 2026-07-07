part of '../main.dart';

Future<Color?> _showWheelColorDialog({
  required BuildContext context,
  required Color initialColor,
  required String title,
  BoxConstraints constraints = const BoxConstraints(maxWidth: 420),
}) {
  return showDialog<Color>(
    context: context,
    barrierColor: Colors.black26,
    builder: (dialogContext) {
      var selectedColor = initialColor;
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final colorScheme = Theme.of(context).colorScheme;
          return AlertDialog(
            title: Text(title),
            content: ConstrainedBox(
              constraints: constraints,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 260,
                    child: ColorWheelPicker(
                      color: selectedColor,
                      onChanged: (color) {
                        setDialogState(() => selectedColor = color);
                      },
                      onWheel: (_) {},
                      wheelWidth: 18,
                      hasBorder: true,
                      borderColor: colorScheme.outlineVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: selectedColor,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: colorScheme.outline),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _colorHex(selectedColor),
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(t('label.cancelAnnotation')),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(selectedColor),
                child: Text(t('label.saveAnnotation')),
              ),
            ],
          );
        },
      );
    },
  );
}

String _colorHex(Color color) {
  final value = color.toARGB32().toRadixString(16).padLeft(8, '0');
  return '0x${value.toUpperCase()}';
}
