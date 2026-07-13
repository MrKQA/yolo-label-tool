// =============================================================================
// detect_support.dart - Detection Support Utilities / 检测辅助工具
// =============================================================================
// Constants (video extensions, device options, media type group), path helpers
// for detection output names, and utility functions shared across the detect page.
//
// 常量（视频扩展名、设备选项、媒体类型组）、检测输出路径辅助和检测页共用工具函数。
// =============================================================================

import 'dart:io';

import '../../services/path_utils.dart';

const videoExtensions = {'mp4', 'avi', 'mov', 'mkv', 'webm', 'wmv', 'flv'};

List<String> mediaFilesInDirectory(String folderPath) {
  final directory = Directory(folderPath);
  if (!directory.existsSync()) {
    return [];
  }
  final files =
      directory
          .listSync()
          .whereType<File>()
          .map((file) => file.path)
          .where((path) => isImagePath(path) || isVideoPath(path))
          .toList()
        ..sort(naturalPathCompare);
  return files;
}

String friendlyDeviceLabel(String label) {
  return label.replaceFirst(RegExp(r'^GPU\s+\d+\s+-\s+'), '').trim();
}

String detectPrimaryProcessorName() {
  final identifier = Platform.environment['PROCESSOR_IDENTIFIER']?.trim();
  if (identifier != null && identifier.isNotEmpty) {
    return identifier;
  }
  final architecture = Platform.environment['PROCESSOR_ARCHITECTURE']?.trim();
  if (architecture != null && architecture.isNotEmpty) {
    return architecture;
  }
  return 'CPU';
}

bool isVideoPath(String path) {
  final dotIndex = path.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == path.length - 1) {
    return false;
  }
  return videoExtensions.contains(path.substring(dotIndex + 1).toLowerCase());
}

bool isPredictionManifestPath(String path) {
  return path.toLowerCase().endsWith('.json') && File(path).existsSync();
}
