// ignore_for_file: file_names

part of 'main.dart';

/// 设置弹窗，保存 Python 路径、训练输出路径，并显示缓存大小。
/// Settings dialog for Python path, training output path, and cache size.
class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({
    required this.initialSettings,
    required this.cacheSizeBytes,
    required this.onSave,
    required this.onClearCache,
  });

  final _AppSettings initialSettings;
  final int cacheSizeBytes;
  final ValueChanged<_AppSettings> onSave;
  final Future<int> Function() onClearCache;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final TextEditingController _pythonController;
  late final TextEditingController _outputController;
  late final TextEditingController _exportController;
  late int _cacheSizeBytes;

  @override
  void initState() {
    super.initState();
    _pythonController = TextEditingController(
      text: widget.initialSettings.pythonPath,
    );
    _outputController = TextEditingController(
      text: widget.initialSettings.outputPath,
    );
    _exportController = TextEditingController(
      text: widget.initialSettings.exportPath,
    );
    _cacheSizeBytes = widget.cacheSizeBytes;
  }

  @override
  void dispose() {
    _pythonController.dispose();
    _outputController.dispose();
    _exportController.dispose();
    super.dispose();
  }

  Future<void> _choosePython() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Python', extensions: ['exe']),
      ],
    );
    if (file != null) {
      _pythonController.text = file.path;
    }
  }

  Future<void> _chooseOutputFolder() async {
    final folder = await getDirectoryPath();
    if (folder != null) {
      _outputController.text = folder;
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('settings.clearCache')),
        content: Text(t('settings.clearCacheConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t('action.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t('action.clear')),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    final newSize = await widget.onClearCache();
    if (mounted) {
      setState(() => _cacheSizeBytes = newSize);
    }
  }

  void _save() {
    widget.onSave(
      _AppSettings(
        pythonPath: _pythonController.text.trim(),
        outputPath: _outputController.text.trim(),
        exportPath: _exportController.text.trim(),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          _save();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AlertDialog(
        title: Text(t('settings.title')),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SettingsReadOnlyRow(
              label: t('settings.configPath'),
              value: _ConfigStore.configDirectory.path,
            ),
            const SizedBox(height: 12),
            _PathSettingRow(
              label: t('settings.pythonPath'),
              controller: _pythonController,
              buttonLabel: t('settings.choosePython'),
              onPressed: _choosePython,
            ),
            const SizedBox(height: 12),
            _PathSettingRow(
              label: t('settings.outputPath'),
              controller: _outputController,
              buttonLabel: t('settings.chooseFolder'),
              onPressed: _chooseOutputFolder,
            ),
            const SizedBox(height: 12),
            _PathSettingRow(
              label: t('settings.exportPath'),
              controller: _exportController,
              buttonLabel: t('settings.chooseFolder'),
              onPressed: () async {
                final folder = await getDirectoryPath();
                if (folder != null) {
                  _exportController.text = folder;
                }
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${t('settings.cacheSize')}: ${_formatBytes(_cacheSizeBytes)}',
                  ),
                ),
                OutlinedButton(
                  onPressed: _clearCache,
                  child: Text(t('settings.clearCache')),
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
        TextButton(onPressed: _save, child: Text(t('action.save'))),
      ],
      ),
    );
  }
}

class _SettingsReadOnlyRow extends StatelessWidget {
  const _SettingsReadOnlyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        SelectableText(value),
      ],
    );
  }
}

class _PathSettingRow extends StatelessWidget {
  const _PathSettingRow({
    required this.label,
    required this.controller,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String label;
  final TextEditingController controller;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: onPressed, child: Text(buttonLabel)),
          ],
        ),
      ],
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(1)} KB';
  }
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(1)} MB';
}
