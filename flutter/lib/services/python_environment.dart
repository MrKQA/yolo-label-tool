import 'dart:io';

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
