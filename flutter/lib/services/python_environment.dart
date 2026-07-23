// =============================================================================
// python_environment.dart - Python Environment Detection / Python 环境探测
// =============================================================================
// Resolves Python executable paths from user input (direct .exe or conda/venv
// directory), probes PyTorch/CUDA/ONNXRuntime availability, and detects
// NVIDIA GPU and OpenVINO device capabilities for training and inference.
//
// 解析 Python 可执行文件路径、探测 PyTorch/CUDA/ONNXRuntime 可用性、
// 检测 NVIDIA GPU 和 OpenVINO 设备能力。
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/training.dart';
import 'app_runtime.dart';
import 'logger.dart';
import 'path_utils.dart';

String? resolvePythonExecutable(String selectedPath) {
  final normalized = selectedPath.trim().replaceAll('/', '\\');
  if (normalized.isEmpty) {
    return null;
  }
  final selectedFile = File(normalized);
  if (selectedFile.existsSync() &&
      fileName(normalized).toLowerCase().endsWith('.exe')) {
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
    // Protected directories can be skipped; direct candidates cover common layouts.
  }
  for (final candidate in dedupePaths(candidates)) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  return null;
}

Future<List<TrainingDeviceOption>> detectNvidiaDevices(
  String pythonPath,
) async {
  final smiProbe = await _probeNvidiaSmiDevices();
  if (smiProbe.devices.isNotEmpty) {
    logApp(
      'GPU',
      'NVIDIA devices detected through nvidia-smi: '
          '${_deviceSummary(smiProbe.devices)}',
      level: AppLogLevel.debug,
    );
    return smiProbe.devices;
  }

  final executable = resolvePythonExecutable(pythonPath);
  if (executable == null) {
    logApp(
      'GPU',
      'NVIDIA detection failed: nvidia-smi=${smiProbe.error}; '
          'Python executable is unavailable',
      level: AppLogLevel.warning,
    );
    return const [];
  }

  final torchProbe = await _probeTorchCudaDevices(executable);
  if (torchProbe.devices.isNotEmpty) {
    logApp(
      'GPU',
      'NVIDIA devices detected through PyTorch CUDA: '
          '${_deviceSummary(torchProbe.devices)}',
    );
    return torchProbe.devices;
  }

  final level = torchProbe.completed ? AppLogLevel.warning : AppLogLevel.error;
  logApp(
    'GPU',
    'NVIDIA detection failed: nvidia-smi=${smiProbe.error}; '
        'torch.cuda=${torchProbe.error}',
    level: level,
  );
  return const [];
}

Future<_NvidiaDeviceProbe> _probeNvidiaSmiDevices() async {
  final windowsDirectory = Platform.environment['WINDIR']?.trim();
  final programW6432 = Platform.environment['ProgramW6432']?.trim();
  final candidates = <String>[
    'nvidia-smi',
    if (windowsDirectory != null && windowsDirectory.isNotEmpty)
      '$windowsDirectory\\System32\\nvidia-smi.exe',
    if (programW6432 != null && programW6432.isNotEmpty)
      '$programW6432\\NVIDIA Corporation\\NVSMI\\nvidia-smi.exe',
  ];
  final attempted = <String>{};
  final errors = <String>[];
  for (final candidate in candidates) {
    final key = candidate.toLowerCase();
    if (!attempted.add(key)) {
      continue;
    }
    if (candidate.contains('\\') && !File(candidate).existsSync()) {
      continue;
    }
    try {
      final result =
          await Process.run(candidate, const [
            '--query-gpu=index,name',
            '--format=csv,noheader,nounits',
          ], runInShell: false).timeout(
            const Duration(seconds: 8),
            onTimeout: () => ProcessResult(
              0,
              124,
              '',
              '$candidate timed out after 8 seconds',
            ),
          );
      if (result.exitCode != 0) {
        final stderr = result.stderr.toString().trim();
        errors.add(
          '$candidate exit=${result.exitCode}'
          '${stderr.isEmpty ? '' : ': $stderr'}',
        );
        continue;
      }
      final devices = _parseNvidiaSmiDevices(result.stdout.toString());
      if (devices.isNotEmpty) {
        return _NvidiaDeviceProbe(completed: true, devices: devices, error: '');
      }
      errors.add('$candidate returned no devices');
    } on Object catch (error) {
      errors.add('$candidate: $error');
    }
  }
  return _NvidiaDeviceProbe(
    completed: false,
    devices: const [],
    error: errors.isEmpty ? 'nvidia-smi unavailable' : errors.join(' | '),
  );
}

List<TrainingDeviceOption> _parseNvidiaSmiDevices(String output) {
  return output
      .trim()
      .split(RegExp(r'\r?\n'))
      .map((line) {
        final parts = line.split(',');
        final id = parts.first.trim().replaceFirst('\ufeff', '');
        final name = parts.length > 1 ? parts.sublist(1).join(',').trim() : '';
        if (id.isEmpty || int.tryParse(id) == null) {
          return null;
        }
        return TrainingDeviceOption(
          id: id,
          label: name.isEmpty ? 'GPU $id' : 'GPU $id - $name',
        );
      })
      .whereType<TrainingDeviceOption>()
      .toList();
}

Future<_NvidiaDeviceProbe> _probeTorchCudaDevices(String executable) async {
  const marker = '__RUSTLABEL_CUDA__';
  const script = '''
import json
try:
    import torch
    available = bool(torch.cuda.is_available())
    count = int(torch.cuda.device_count()) if available else 0
    devices = []
    for index in range(count):
        properties = torch.cuda.get_device_properties(index)
        devices.append({
            "id": index,
            "name": torch.cuda.get_device_name(index),
            "memory_mb": int(properties.total_memory // (1024 * 1024)),
        })
    payload = {
        "ok": True,
        "available": available,
        "count": count,
        "devices": devices,
        "torch_version": str(torch.__version__),
        "cuda_version": str(torch.version.cuda or ""),
    }
except Exception as error:
    payload = {
        "ok": False,
        "error": f"{type(error).__name__}: {error}",
    }
print("__RUSTLABEL_CUDA__" + json.dumps(payload, ensure_ascii=False))
''';
  try {
    final result =
        await Process.run(executable, const [
          '-c',
          script,
        ], runInShell: false).timeout(
          const Duration(seconds: 25),
          onTimeout: () => ProcessResult(
            0,
            124,
            '',
            'PyTorch CUDA probe timed out after 25 seconds',
          ),
        );
    final stdout = result.stdout.toString();
    final payloadLine = stdout
        .split(RegExp(r'\r?\n'))
        .reversed
        .where((line) => line.startsWith(marker))
        .firstOrNull;
    if (result.exitCode != 0 || payloadLine == null) {
      final stderr = result.stderr.toString().trim();
      return _NvidiaDeviceProbe(
        completed: false,
        devices: const [],
        error: stderr.isNotEmpty
            ? stderr
            : 'exit=${result.exitCode}, CUDA probe output marker missing',
      );
    }
    final decoded = jsonDecode(payloadLine.substring(marker.length));
    if (decoded is! Map || decoded['ok'] != true) {
      return _NvidiaDeviceProbe(
        completed: false,
        devices: const [],
        error: decoded is Map
            ? '${decoded['error'] ?? 'unknown PyTorch CUDA error'}'
            : 'invalid PyTorch CUDA response',
      );
    }
    final rawDevices = decoded['devices'];
    final devices = <TrainingDeviceOption>[];
    if (rawDevices is List) {
      for (final item in rawDevices.whereType<Map>()) {
        final id = item['id'];
        if (id is! num) {
          continue;
        }
        final name = '${item['name'] ?? ''}'.trim();
        final memoryMb = item['memory_mb'] is num
            ? (item['memory_mb'] as num).round()
            : 0;
        final memoryLabel = memoryMb > 0 ? ' ($memoryMb MB)' : '';
        devices.add(
          TrainingDeviceOption(
            id: id.round().toString(),
            label:
                'GPU ${id.round()}'
                '${name.isEmpty ? '' : ' - $name'}$memoryLabel',
          ),
        );
      }
    }
    final available = decoded['available'] == true;
    final torchVersion = '${decoded['torch_version'] ?? 'unknown'}';
    final cudaVersion = '${decoded['cuda_version'] ?? ''}';
    return _NvidiaDeviceProbe(
      completed: true,
      devices: devices,
      error: available
          ? 'CUDA reported available but returned no devices'
          : 'PyTorch $torchVersion does not expose CUDA'
                '${cudaVersion.isEmpty ? '' : ' $cudaVersion'}',
    );
  } on Object catch (error) {
    return _NvidiaDeviceProbe(
      completed: false,
      devices: const [],
      error: '$error',
    );
  }
}

String _deviceSummary(List<TrainingDeviceOption> devices) {
  return devices.map((device) => '${device.id}:${device.label}').join(', ');
}

class _NvidiaDeviceProbe {
  const _NvidiaDeviceProbe({
    required this.completed,
    required this.devices,
    required this.error,
  });

  final bool completed;
  final List<TrainingDeviceOption> devices;
  final String error;
}
