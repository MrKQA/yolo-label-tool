part of '../../main.dart';

List<String> _mediaFilesInDirectory(String folderPath) {
  final directory = Directory(folderPath);
  if (!directory.existsSync()) {
    return [];
  }
  final files =
      directory
          .listSync()
          .whereType<File>()
          .map((file) => file.path)
          .where((path) => _isImagePath(path) || _isVideoPath(path))
          .toList()
        ..sort(_naturalPathCompare);
  return files;
}

String _friendlyDeviceLabel(String label) {
  return label.replaceFirst(RegExp(r'^GPU\s+\d+\s+-\s+'), '').trim();
}

String _detectPrimaryProcessorName() {
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

bool _isVideoPath(String path) {
  final dotIndex = path.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == path.length - 1) {
    return false;
  }
  return _videoExtensions.contains(path.substring(dotIndex + 1).toLowerCase());
}

bool _isPredictionManifestPath(String path) {
  return path.toLowerCase().endsWith('.json') && File(path).existsSync();
}
