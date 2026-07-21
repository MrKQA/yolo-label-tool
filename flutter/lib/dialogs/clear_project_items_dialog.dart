import 'package:flutter/material.dart';

import '../models/annotation.dart';
import '../services/i18n.dart';
import '../services/path_utils.dart';
import '../widgets/label/image_filter_dropdown.dart';
import 'dialog_shortcuts.dart';

class ClearProjectItemsRequest {
  const ClearProjectItemsRequest({
    required this.clearAnnotations,
    required this.removeImages,
    required this.filterValue,
    required this.quantity,
  });

  final bool clearAnnotations;
  final bool removeImages;
  final String filterValue;
  final int quantity;
}

Future<ClearProjectItemsRequest?> showClearProjectItemsDialog({
  required BuildContext context,
  required List<ImageItem> images,
  required List<LabelClass> labelClasses,
  required Map<String, List<AnnotationRegion>> annotationsByImage,
}) {
  return showDialog<ClearProjectItemsRequest>(
    context: context,
    builder: (context) => _ClearProjectItemsDialog(
      images: images,
      labelClasses: labelClasses,
      annotationsByImage: annotationsByImage,
    ),
  );
}

Future<bool> showClearProjectItemsConfirmation({
  required BuildContext context,
  required ClearProjectItemsRequest request,
}) async {
  final target = request.removeImages
      ? t('label.clearImages')
      : t('label.clearAnnotations');
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => DialogPrimaryAction(
          onInvoke: () => Navigator.of(dialogContext).pop(true),
          child: AlertDialog(
            title: Text(t('label.clearConfirmTitle')),
            content: Text(
              '${t('label.clearConfirmMessage')} $target × ${request.quantity}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(t('action.cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(t('action.clear')),
              ),
            ],
          ),
        ),
      ) ??
      false;
}

class _ClearProjectItemsDialog extends StatefulWidget {
  const _ClearProjectItemsDialog({
    required this.images,
    required this.labelClasses,
    required this.annotationsByImage,
  });

  final List<ImageItem> images;
  final List<LabelClass> labelClasses;
  final Map<String, List<AnnotationRegion>> annotationsByImage;

  @override
  State<_ClearProjectItemsDialog> createState() =>
      _ClearProjectItemsDialogState();
}

class _ClearProjectItemsDialogState extends State<_ClearProjectItemsDialog> {
  bool _clearAnnotations = true;
  bool _removeImages = false;
  bool _annotationsBeforeImageSelection = true;
  String _filterValue = imageFilterAllValue;
  int _quantity = 0;
  bool _quantityInitialized = false;

  int get _availableCount {
    if (_removeImages) {
      return widget.images
          .where(
            (image) => imageMatchesFilter(
              image: image,
              filterValue: _filterValue,
              annotationsByImage: widget.annotationsByImage,
            ),
          )
          .length;
    }
    if (!_clearAnnotations) return 0;
    final classId = imageFilterClassId(_filterValue);
    var count = 0;
    for (final image in widget.images) {
      final annotations =
          widget.annotationsByImage[pathKey(image.path)] ??
          const <AnnotationRegion>[];
      if (_filterValue == imageFilterAllValue) {
        count += annotations.length;
      } else if (classId != null) {
        count += annotations
            .where((annotation) => annotation.classId == classId)
            .length;
      }
    }
    return count;
  }

  void _resetQuantity() {
    _quantity = _availableCount;
    _quantityInitialized = true;
  }

  void _setClearAnnotations(bool value) {
    if (_removeImages) return;
    setState(() {
      _clearAnnotations = value;
      _resetQuantity();
    });
  }

  void _setRemoveImages(bool value) {
    setState(() {
      if (value) {
        _annotationsBeforeImageSelection = _clearAnnotations;
        _removeImages = true;
        _clearAnnotations = true;
      } else {
        _removeImages = false;
        _clearAnnotations = _annotationsBeforeImageSelection;
      }
      _resetQuantity();
    });
  }

  void _setFilter(String value) {
    setState(() {
      _filterValue = value;
      _resetQuantity();
    });
  }

  void _submit() {
    final available = _availableCount;
    if (available <= 0 || _quantity <= 0) return;
    Navigator.of(context).pop(
      ClearProjectItemsRequest(
        clearAnnotations: _clearAnnotations,
        removeImages: _removeImages,
        filterValue: _filterValue,
        quantity: _quantity.clamp(1, available),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final available = _availableCount;
    if (!_quantityInitialized) {
      _quantity = available;
      _quantityInitialized = true;
    } else if (_quantity > available) {
      _quantity = available;
    }
    final enabled = available > 0 && _quantity > 0;
    return DialogPrimaryAction(
      onInvoke: _submit,
      enabled: enabled,
      child: AlertDialog(
        title: Text(t('label.clearTitle')),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _ClearTargetCheckbox(
                    label: t('label.clearAnnotations'),
                    value: _clearAnnotations,
                    enabled: !_removeImages,
                    onChanged: _setClearAnnotations,
                  ),
                  _ClearTargetCheckbox(
                    label: t('label.clearImages'),
                    value: _removeImages,
                    onChanged: _setRemoveImages,
                  ),
                  ImageFilterDropdown(
                    images: widget.images,
                    labelClasses: widget.labelClasses,
                    annotationsByImage: widget.annotationsByImage,
                    value: _filterValue,
                    width: 220,
                    onSelected: _setFilter,
                    onConfirmShortcut: _submit,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: Text(t('label.clearQuantity'))),
                  Text('$_quantity / $available'),
                ],
              ),
              Slider(
                value: available == 0
                    ? 0
                    : _quantity.clamp(1, available).toDouble(),
                min: available == 0 ? 0 : 1,
                max: available <= 1 ? 1 : available.toDouble(),
                divisions: available > 1 ? available - 1 : null,
                label: _quantity.toString(),
                onChanged: available > 1
                    ? (value) => setState(() => _quantity = value.round())
                    : null,
              ),
              if (available == 0)
                Text(
                  t('label.clearNoMatches'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('action.cancel')),
          ),
          FilledButton(
            onPressed: enabled ? _submit : null,
            child: Text(t('action.confirm')),
          ),
        ],
      ),
    );
  }
}

class _ClearTargetCheckbox extends StatelessWidget {
  const _ClearTargetCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: value,
              onChanged: enabled ? (next) => onChanged(next ?? false) : null,
            ),
            Text(label),
          ],
        ),
      ),
    );
  }
}
