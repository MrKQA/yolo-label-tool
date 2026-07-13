import 'package:flutter/material.dart';

import '../models/annotation.dart';
import '../services/i18n.dart';

Future<String?> showLabelClassNameDialog({
  required BuildContext context,
  required String initialName,
  required String title,
}) async {
  final controller = TextEditingController(text: initialName);
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: t('label.className')),
        onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(t('label.cancelAnnotation')),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: Text(t('label.saveAnnotation')),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

Future<String?> showSam3SaveClassDialog({
  required BuildContext context,
  required String initialName,
  required List<LabelClass> labelClasses,
}) async {
  final controller = TextEditingController(text: initialName);
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(t('ai.sam3SaveClassTitle')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: DropdownMenu<String>(
          controller: controller,
          requestFocusOnTap: true,
          enableFilter: true,
          width: 360,
          label: Text(t('ai.sam3SaveClassName')),
          hintText: t('ai.sam3SaveClassHint'),
          dropdownMenuEntries: [
            for (final labelClass in labelClasses)
              DropdownMenuEntry<String>(
                value: labelClass.name,
                label: labelClass.name,
                leadingIcon: Icon(
                  Icons.square_rounded,
                  color: labelClass.color,
                  size: 16,
                ),
              ),
          ],
          onSelected: (value) {
            if (value != null) {
              controller.text = value;
            }
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(t('action.cancel')),
        ),
        FilledButton(
          onPressed: () {
            final value = controller.text.trim();
            if (value.isEmpty) {
              return;
            }
            Navigator.of(dialogContext).pop(value);
          },
          child: Text(t('action.save')),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
