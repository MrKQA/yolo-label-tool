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
  _PythonEnvironmentCheck? _pythonCheck;
  bool _checkingPython = false;
  int _pythonCheckGeneration = 0;
  String _lastCheckedPythonPath = '';

  @override
  void initState() {
    super.initState();
    _pythonController = TextEditingController(
      text: widget.initialSettings.pythonPath,
    );
    _pythonController.addListener(_handlePythonPathChanged);
    _outputController = TextEditingController(
      text: widget.initialSettings.outputPath,
    );
    _exportController = TextEditingController(
      text: widget.initialSettings.exportPath,
    );
    _cacheSizeBytes = widget.cacheSizeBytes;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pythonPath = _pythonController.text.trim();
      if (mounted && pythonPath.isNotEmpty) {
        _validatePythonPath(pythonPath, updateController: false);
      }
    });
  }

  @override
  void dispose() {
    _pythonController.removeListener(_handlePythonPathChanged);
    _pythonController.dispose();
    _outputController.dispose();
    _exportController.dispose();
    super.dispose();
  }

  void _handlePythonPathChanged() {
    final current = _pythonController.text.trim();
    if (current == _lastCheckedPythonPath) {
      return;
    }
    _pythonCheckGeneration++;
    if (_pythonCheck != null || _checkingPython) {
      setState(() {
        _pythonCheck = null;
        _checkingPython = false;
      });
    }
  }

  Future<void> _choosePythonExecutable() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Python', extensions: ['exe']),
      ],
    );
    if (file != null) {
      await _validatePythonPath(file.path);
    }
  }

  Future<void> _choosePythonFolder() async {
    final folder = await getDirectoryPath();
    if (folder != null) {
      await _validatePythonPath(folder);
    }
  }

  Future<void> _validatePythonPath(
    String rawPath, {
    bool updateController = true,
  }) async {
    final selectedPath = rawPath.trim();
    if (selectedPath.isEmpty) {
      return;
    }
    final generation = ++_pythonCheckGeneration;
    final executable = _resolvePythonExecutable(selectedPath);
    if (executable == null) {
      setState(() {
        _lastCheckedPythonPath = selectedPath;
        _checkingPython = false;
        _pythonCheck = _PythonEnvironmentCheck.invalid(
          selectedPath,
          t('settings.pythonNotFound'),
        );
      });
      return;
    }
    if (updateController && _pythonController.text.trim() != executable) {
      _lastCheckedPythonPath = executable;
      _pythonController.text = executable;
    }
    setState(() {
      _checkingPython = true;
      _pythonCheck = null;
    });
    final check = await _probePythonEnvironment(executable);
    if (!mounted || generation != _pythonCheckGeneration) {
      return;
    }
    setState(() {
      _lastCheckedPythonPath = executable;
      _checkingPython = false;
      _pythonCheck = check;
    });
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
              onPressed: _choosePythonExecutable,
              secondaryButtonLabel: t('settings.chooseFolder'),
              onSecondaryPressed: _choosePythonFolder,
              trailing: _PythonCheckIndicator(
                checking: _checkingPython,
                check: _pythonCheck,
              ),
              statusText: _checkingPython
                  ? t('settings.pythonChecking')
                  : _pythonCheck?.message,
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
    this.secondaryButtonLabel,
    this.onSecondaryPressed,
    this.trailing,
    this.statusText,
  });

  final String label;
  final TextEditingController controller;
  final String buttonLabel;
  final VoidCallback onPressed;
  final String? secondaryButtonLabel;
  final VoidCallback? onSecondaryPressed;
  final Widget? trailing;
  final String? statusText;

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
            if (secondaryButtonLabel != null && onSecondaryPressed != null) ...[
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: onSecondaryPressed,
                child: Text(secondaryButtonLabel!),
              ),
            ],
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
        if (statusText != null && statusText!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(statusText!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}

class _PythonCheckIndicator extends StatelessWidget {
  const _PythonCheckIndicator({required this.checking, required this.check});

  final bool checking;
  final _PythonEnvironmentCheck? check;

  @override
  Widget build(BuildContext context) {
    if (checking) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final result = check;
    if (result == null) {
      return const SizedBox(width: 20, height: 20);
    }
    return Icon(
      result.valid ? Icons.check_circle : Icons.error_outline,
      color: result.valid ? Colors.green : Theme.of(context).colorScheme.error,
    );
  }
}

class _PythonEnvironmentCheck {
  const _PythonEnvironmentCheck({
    required this.valid,
    required this.executablePath,
    required this.message,
  });

  factory _PythonEnvironmentCheck.valid({
    required String executablePath,
    required String torchVersion,
    required bool cudaAvailable,
    required int cudaDeviceCount,
    required String cudaDeviceName,
    required String onnxRuntimeDevice,
  }) {
    final gpuName = cudaDeviceName.isEmpty ? 'GPU -' : cudaDeviceName;
    return _PythonEnvironmentCheck(
      valid: true,
      executablePath: executablePath,
      message:
          '${t('settings.pythonValid')}: PyTorch $torchVersion, '
          'CUDA $cudaAvailable, GPU $cudaDeviceCount $gpuName, '
          'ONNXRuntime $onnxRuntimeDevice',
    );
  }

  factory _PythonEnvironmentCheck.invalid(String executablePath, String reason) {
    return _PythonEnvironmentCheck(
      valid: false,
      executablePath: executablePath,
      message: reason,
    );
  }

  final bool valid;
  final String executablePath;
  final String message;
}

String? _resolvePythonExecutable(String selectedPath) {
  final normalized = selectedPath.trim().replaceAll('/', '\\');
  if (normalized.isEmpty) {
    return null;
  }
  final selectedFile = File(normalized);
  if (selectedFile.existsSync() &&
      _fileName(normalized).toLowerCase().endsWith('.exe')) {
    return selectedFile.path;
  }
  final directory = Directory(normalized);
  if (!directory.existsSync()) {
    return null;
  }
  final candidates = <String>[
    '${directory.path}\\python.exe',
    '${directory.path}\\Scripts\\python.exe',
    '${directory.path}\\.venv\\Scripts\\python.exe',
    '${directory.path}\\venv\\Scripts\\python.exe',
  ];
  try {
    for (final entity in directory.listSync()) {
      if (entity is! Directory) {
        continue;
      }
      candidates.add('${entity.path}\\python.exe');
      candidates.add('${entity.path}\\Scripts\\python.exe');
    }
  } on Object {
    // Some environment roots contain protected directories; direct candidates
    // above are enough for the common conda/venv layouts.
  }
  for (final candidate in _dedupePaths(candidates)) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  return null;
}

Future<_PythonEnvironmentCheck> _probePythonEnvironment(
  String executablePath,
) async {
  const script = '''
import json
import torch
import onnxruntime

cuda_available = torch.cuda.is_available()
device_count = torch.cuda.device_count()
device_name = ""
if cuda_available and device_count > 0:
    device_name = torch.cuda.get_device_name(0)

print(json.dumps({
    "torch_version": torch.__version__,
    "cuda_available": cuda_available,
    "cuda_device_count": device_count,
    "cuda_device_name": device_name,
    "onnxruntime_device": onnxruntime.get_device(),
}, ensure_ascii=False))
''';
  try {
    final result = await Process.run(
      executablePath,
      ['-c', script],
      runInShell: false,
    ).timeout(
      const Duration(seconds: 20),
      onTimeout: () => ProcessResult(0, 124, '', t('settings.pythonTimeout')),
    );
    if (result.exitCode != 0) {
      final errorText = result.stderr.toString().trim();
      return _PythonEnvironmentCheck.invalid(
        executablePath,
        errorText.isEmpty ? t('settings.pythonInvalid') : errorText,
      );
    }
    final output = result.stdout.toString().trim();
    final jsonLine = output.split(RegExp(r'\r?\n')).last;
    final decoded = jsonDecode(jsonLine);
    if (decoded is! Map) {
      return _PythonEnvironmentCheck.invalid(
        executablePath,
        t('settings.pythonInvalid'),
      );
    }
    return _PythonEnvironmentCheck.valid(
      executablePath: executablePath,
      torchVersion: '${decoded['torch_version'] ?? ''}',
      cudaAvailable: decoded['cuda_available'] == true,
      cudaDeviceCount: decoded['cuda_device_count'] is num
          ? (decoded['cuda_device_count'] as num).round()
          : 0,
      cudaDeviceName: '${decoded['cuda_device_name'] ?? ''}',
      onnxRuntimeDevice: '${decoded['onnxruntime_device'] ?? ''}',
    );
  } on Object catch (error) {
    return _PythonEnvironmentCheck.invalid(executablePath, '$error');
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
