// =============================================================================
// export_dialog.dart - YOLO Label Export / YOLO 标注导出
// =============================================================================
// Export configuration dialog with train/val/test split ratio, class-balanced
// assignment, optional image copying, and data.yaml generation.
//
// 导出配置弹窗：train/val/test 比例分配、class 平衡分配、图片复制、
// data.yaml 生成。
// =============================================================================

import 'package:flutter/material.dart';

import '../models/export.dart';
import '../services/i18n.dart';
import 'dialog_shortcuts.dart';

Future<bool?> showOverwriteImportedDatasetDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) => DialogPrimaryAction(
      onInvoke: () => Navigator.of(context).pop(true),
      child: AlertDialog(
        title: Text(t('export.overwriteTitle')),
        content: Text(t('export.overwriteMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(t('action.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t('export.keepNew')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t('export.overwriteOriginal')),
          ),
        ],
      ),
    ),
  );
}

class ExportDialog extends StatefulWidget {
  const ExportDialog({super.key, required this.exportPath});

  final String exportPath;

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  bool _skipEmpty = true;
  bool _exportImages = true;
  bool _trainAfterExport = false;
  bool _redistribute = true;
  RangeValues _splitBoundaries = const RangeValues(80, 100);
  late final TextEditingController _folderNameController;
  String? _folderNameError;

  double get _trainPercent => _splitBoundaries.start;
  double get _valPercent => _splitBoundaries.end - _splitBoundaries.start;
  double get _testPercent => 100 - _splitBoundaries.end;

  @override
  void initState() {
    super.initState();
    _folderNameController = TextEditingController(text: 'dataset');
  }

  @override
  void dispose() {
    _folderNameController.dispose();
    super.dispose();
  }

  void _confirm() {
    final name = _folderNameController.text.trim();
    final folderName = name.isEmpty ? 'dataset' : name;
    if (folderName == '.' ||
        folderName == '..' ||
        folderName.contains('/') ||
        folderName.contains('\\') ||
        folderName.contains(':')) {
      setState(() => _folderNameError = t('export.invalidFolderName'));
      return;
    }
    Navigator.of(context).pop(
      DatasetExportConfig(
        skipEmpty: _skipEmpty,
        exportImages: _exportImages,
        redistribute: _redistribute,
        trainRatio: _trainPercent / 100,
        valRatio: _valPercent / 100,
        testRatio: _testPercent / 100,
        folderName: folderName,
        trainAfterExport: _trainAfterExport,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DialogPrimaryAction(
      onInvoke: _confirm,
      child: AlertDialog(
        scrollable: true,
        title: Text(t('export.title')),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${t('settings.outputPath')}: ${widget.exportPath}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _folderNameController,
                onChanged: (_) {
                  if (_folderNameError != null) {
                    setState(() => _folderNameError = null);
                  }
                },
                decoration: InputDecoration(
                  labelText: t('export.folderName'),
                  errorText: _folderNameError,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: _skipEmpty,
                onChanged: (v) => setState(() => _skipEmpty = v ?? true),
                title: Text(t('export.skipEmpty')),
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                value: _exportImages,
                onChanged: (v) => setState(() => _exportImages = v ?? true),
                title: Text(t('export.copyImages')),
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                value: _trainAfterExport,
                onChanged: (v) =>
                    setState(() => _trainAfterExport = v ?? false),
                title: Text(t('export.trainAfterExport')),
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: _redistribute,
                onChanged: (value) =>
                    setState(() => _redistribute = value ?? true),
                title: Text(t('export.redistribute')),
                subtitle: Text(t('export.redistributeHint')),
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 8),
              Text(
                t('export.splitRatio'),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: _redistribute ? null : Theme.of(context).disabledColor,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _RatioBadge(
                      label: 'train',
                      value: _trainPercent.round(),
                      alignment: Alignment.centerLeft,
                    ),
                  ),
                  Expanded(
                    child: _RatioBadge(
                      label: 'val',
                      value: _valPercent.round(),
                      alignment: Alignment.center,
                    ),
                  ),
                  Expanded(
                    child: _RatioBadge(
                      label: 'test',
                      value: _testPercent.round(),
                      alignment: Alignment.centerRight,
                    ),
                  ),
                ],
              ),
              RangeSlider(
                values: _splitBoundaries,
                min: 0,
                max: 100,
                divisions: 100,
                labels: RangeLabels(
                  'train ${_trainPercent.round()}%',
                  'test ${_testPercent.round()}%',
                ),
                onChanged: _redistribute
                    ? (values) => setState(() => _splitBoundaries = values)
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('action.cancel')),
          ),
          FilledButton(onPressed: _confirm, child: Text(t('export.export'))),
        ],
      ),
    );
  }
}

class _RatioBadge extends StatelessWidget {
  const _RatioBadge({
    required this.label,
    required this.value,
    required this.alignment,
  });

  final String label;
  final int value;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$label $value%',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}
