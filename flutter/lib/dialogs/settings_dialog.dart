// =============================================================================
// settings_dialog.dart - Application Settings Dialog / 应用设置对话框
// =============================================================================
// Python environment selection with validation, output/export path
// configuration, log level control, and cache size display with clear.
//
// Python 环境选择与验证、训练输出/导出路径配置、日志级别控制和缓存清理。
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../models/config.dart';
import 'dialog_shortcuts.dart';
import '../services/config_store.dart';
import '../services/i18n.dart';
import '../services/logger.dart';
import '../services/python_environment.dart';

/// 设置弹窗，保存 Python 路径、训练输出路径，并显示缓存大小。
/// Settings dialog for Python path, training output path, and cache size.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    required this.initialSettings,
    required this.cacheSizeBytes,
    required this.onSave,
    required this.onClearCache,
    required this.logger,
    required this.onLogLevelChanged,
  });

  final AppSettings initialSettings;
  final int cacheSizeBytes;
  final ValueChanged<AppSettings> onSave;
  final Future<int> Function() onClearCache;
  final AppLogger logger;
  final ValueChanged<int> onLogLevelChanged;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _iconController;
  late final TextEditingController _pythonController;
  late final TextEditingController _outputController;
  late final TextEditingController _exportController;
  late int _logLevelIndex;
  late int _cacheSizeBytes;
  _PythonEnvironmentCheck? _pythonCheck;
  bool _checkingPython = false;
  int _pythonCheckGeneration = 0;
  String _lastCheckedPythonPath = '';
  String? _brandingError;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(
      text: widget.initialSettings.applicationDisplayName,
    );
    _iconController = TextEditingController(
      text: widget.initialSettings.applicationIconPath,
    );
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
    _lastCheckedPythonPath = _pythonController.text.trim();
    _logLevelIndex = widget.initialSettings.logLevelIndex
        .clamp(0, AppLogLevel.values.length - 1)
        .toInt();
    _cacheSizeBytes = widget.cacheSizeBytes;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _iconController.dispose();
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
    final executable = resolvePythonExecutable(selectedPath);
    if (executable == null) {
      widget.logger.log(
        'SETTINGS',
        'Python environment check failed: executable not found for $selectedPath',
        level: AppLogLevel.warning,
      );
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
    widget.logger.log(
      'SETTINGS',
      'Python environment check started: $executable',
      level: AppLogLevel.debug,
    );
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
    widget.logger.log(
      'SETTINGS',
      'Python environment check ${check.valid ? 'passed' : 'failed'}: $executable, ${check.message}',
      level: check.valid ? AppLogLevel.info : AppLogLevel.warning,
    );
  }

  Future<void> _chooseOutputFolder() async {
    final folder = await getDirectoryPath();
    if (folder != null) {
      _outputController.text = folder;
    }
  }

  Future<void> _chooseApplicationIcon() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Windows icon', extensions: ['ico']),
      ],
    );
    if (file == null) {
      return;
    }
    setState(() {
      _iconController.text = file.path;
      _brandingError = null;
    });
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => DialogPrimaryAction(
        onInvoke: () => Navigator.of(context).pop(true),
        child: AlertDialog(
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
    final iconPath = _iconController.text.trim();
    if (iconPath.isNotEmpty &&
        (!iconPath.toLowerCase().endsWith('.ico') ||
            !File(iconPath).existsSync())) {
      setState(() => _brandingError = t('settings.applicationIconInvalid'));
      return;
    }
    widget.onSave(
      AppSettings(
        pythonPath: _pythonController.text.trim(),
        outputPath: _outputController.text.trim(),
        exportPath: _exportController.text.trim(),
        applicationDisplayName: _displayNameController.text.trim(),
        applicationIconPath: iconPath,
        logLevelIndex: _logLevelIndex,
        darkMode: widget.initialSettings.darkMode,
        collaborationHostId: widget.initialSettings.collaborationHostId,
        collaborationUserId: widget.initialSettings.collaborationUserId,
      ),
    );
    widget.onLogLevelChanged(_logLevelIndex);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return DialogPrimaryAction(
      onInvoke: _save,
      child: AlertDialog(
        title: Text(t('settings.title')),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SettingsReadOnlyRow(
                  label: t('settings.configPath'),
                  value: ConfigStore.databaseFile.path,
                ),
                const SizedBox(height: 16),
                Text(
                  t('settings.applicationBranding'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 10),
                Text(
                  t('settings.applicationDisplayName'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _displayNameController,
                  maxLength: 80,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: defaultApplicationDisplayName,
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                _PathSettingRow(
                  label: t('settings.applicationIcon'),
                  controller: _iconController,
                  buttonLabel: t('settings.chooseIcon'),
                  onPressed: _chooseApplicationIcon,
                  secondaryButtonLabel: t('settings.restoreDefault'),
                  onSecondaryPressed: () {
                    setState(() {
                      _iconController.clear();
                      _brandingError = null;
                    });
                  },
                  statusText:
                      _brandingError ?? t('settings.applicationIconHint'),
                  statusIsError: _brandingError != null,
                ),
                const SizedBox(height: 16),
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
                const SizedBox(height: 12),
                Text(
                  t('settings.logLevel'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var i = 0; i < 4; i++)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Radio<int>(
                            value: i,
                            groupValue: _logLevelIndex,
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => _logLevelIndex = v);
                              }
                            },
                            visualDensity: VisualDensity.compact,
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _logLevelIndex = i),
                            child: Text(
                              const ['Debug', 'Info', 'Warning', 'Error'][i],
                            ),
                          ),
                        ],
                      ),
                  ],
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
    this.statusIsError = false,
  });

  final String label;
  final TextEditingController controller;
  final String buttonLabel;
  final VoidCallback onPressed;
  final String? secondaryButtonLabel;
  final VoidCallback? onSecondaryPressed;
  final Widget? trailing;
  final String? statusText;
  final bool statusIsError;

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
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
        if (statusText != null && statusText!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            statusText!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: statusIsError ? Theme.of(context).colorScheme.error : null,
            ),
          ),
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
    final onnxText = onnxRuntimeDevice.isEmpty
        ? 'ONNXRuntime -'
        : 'ONNXRuntime $onnxRuntimeDevice';
    return _PythonEnvironmentCheck(
      valid: true,
      executablePath: executablePath,
      message:
          '${t('settings.pythonValid')}: PyTorch $torchVersion, '
          'CUDA $cudaAvailable, GPU $cudaDeviceCount $gpuName, $onnxText',
    );
  }

  factory _PythonEnvironmentCheck.invalid(
    String executablePath,
    String reason,
  ) {
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

Future<_PythonEnvironmentCheck> _probePythonEnvironment(
  String executablePath,
) async {
  const script = '''
import json
import torch
try:
    import onnxruntime
except Exception:
    onnxruntime = None

cuda_available = torch.cuda.is_available()
device_count = torch.cuda.device_count()
device_name = ""
if cuda_available and device_count > 0:
    device_name = torch.cuda.get_device_name(0)
onnxruntime_device = "" if onnxruntime is None else onnxruntime.get_device()

print(json.dumps({
    "torch_version": torch.__version__,
    "cuda_available": cuda_available,
    "cuda_device_count": device_count,
    "cuda_device_name": device_name,
    "onnxruntime_device": onnxruntime_device,
}, ensure_ascii=False))
''';
  try {
    final result =
        await Process.run(executablePath, [
          '-c',
          script,
        ], runInShell: false).timeout(
          const Duration(seconds: 20),
          onTimeout: () =>
              ProcessResult(0, 124, '', t('settings.pythonTimeout')),
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
