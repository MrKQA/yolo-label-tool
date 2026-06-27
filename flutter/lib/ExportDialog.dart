// =============================================================================
// ExportDialog.dart - YOLO Label Export / YOLO 标注导出
// =============================================================================
// Export configuration dialog with train/val/test split ratio, class-balanced
// assignment, optional image copying, and data.yaml generation.
//
// 导出配置弹窗：train/val/test 比例分配、class 平衡分配、图片复制、
// data.yaml 生成。
// =============================================================================

// ignore_for_file: file_names

part of 'main.dart';

class _ExportEntry {
  const _ExportEntry(this.path, this.annotations);
  final String path;
  final List<_AnnotationRegion> annotations;
}

class _ExportConfig {
  const _ExportConfig({
    required this.skipEmpty,
    required this.exportImages,
    required this.trainRatio,
    required this.valRatio,
    required this.testRatio,
    required this.folderName,
    required this.trainAfterExport,
  });

  final bool skipEmpty;
  final bool exportImages;
  final double trainRatio;
  final double valRatio;
  final double testRatio;
  final String folderName;
  final bool trainAfterExport;
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.exportPath});

  final String exportPath;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  bool _skipEmpty = true;
  bool _exportImages = true;
  bool _trainAfterExport = false;
  double _valPercent = 20;
  double _testPercent = 0;
  late final TextEditingController _folderNameController;

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
    Navigator.of(context).pop(
      _ExportConfig(
        skipEmpty: _skipEmpty,
        exportImages: _exportImages,
        trainRatio: (100 - _valPercent - _testPercent).clamp(0, 100) / 100,
        valRatio: _valPercent / 100,
        testRatio: _testPercent / 100,
        folderName: name.isEmpty ? 'dataset' : name,
        trainAfterExport: _trainAfterExport,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trainPercent = (100 - _valPercent - _testPercent).clamp(0, 100);
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          _confirm();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AlertDialog(
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
                decoration: InputDecoration(
                  labelText: t('export.folderName'),
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
              Text(
                t('export.splitRatio'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _RatioBadge(label: 'train', value: trainPercent.round()),
                  _RatioBadge(label: 'val', value: _valPercent.round()),
                  _RatioBadge(label: 'test', value: _testPercent.round()),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('val ', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: _valPercent,
                      min: 0,
                      max: 50,
                      divisions: 50,
                      label: '${_valPercent.round()}%',
                      onChanged: (v) => setState(() => _valPercent = v),
                    ),
                  ),
                  const Text(' test ', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: _testPercent,
                      min: 0,
                      max: 30,
                      divisions: 30,
                      label: '${_testPercent.round()}%',
                      onChanged: (v) => setState(() => _testPercent = v),
                    ),
                  ),
                ],
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
  const _RatioBadge({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
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
    );
  }
}
