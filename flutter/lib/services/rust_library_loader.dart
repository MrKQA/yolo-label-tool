import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

class RustLibraryLoadResult {
  const RustLibraryLoadResult({this.library, this.error});

  final ExternalLibrary? library;
  final String? error;
}

class RustLibraryLoader {
  const RustLibraryLoader();

  RustLibraryLoadResult openLibrary() {
    if (!Platform.isWindows) {
      return const RustLibraryLoadResult();
    }
    Object? lastError;
    for (final path in libraryCandidates()) {
      if (!File(path).existsSync()) {
        continue;
      }
      try {
        return RustLibraryLoadResult(library: ExternalLibrary.open(path));
      } on Object catch (error) {
        lastError = error;
        debugPrint('Failed to open Rust backend $path: $error');
      }
    }
    return RustLibraryLoadResult(error: lastError?.toString());
  }

  List<String> libraryCandidates() {
    final executableDirectory = File(Platform.resolvedExecutable).parent.path;
    final current = Directory.current.path;
    final currentParent = Directory.current.parent.path;
    return _dedupePaths([
      '$executableDirectory\\yolo_label_bridge.dll',
      '$current\\yolo_label_bridge.dll',
      '$current\\target\\release\\yolo_label_bridge.dll',
      '$current\\target\\debug\\yolo_label_bridge.dll',
      '$currentParent\\target\\release\\yolo_label_bridge.dll',
      '$currentParent\\target\\debug\\yolo_label_bridge.dll',
    ]);
  }

  static List<String> _dedupePaths(List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final key = value.toLowerCase();
      if (seen.add(key)) {
        result.add(value);
      }
    }
    return result;
  }
}
