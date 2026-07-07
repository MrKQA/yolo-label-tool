part of '../main.dart';

List<String> _imageFilesInDirectory(String folderPath) {
  final directory = Directory(folderPath);
  if (!directory.existsSync()) {
    return [];
  }

  final files =
      directory
          .listSync()
          .whereType<File>()
          .map((file) => file.path)
          .where(_isImagePath)
          .toList()
        ..sort(_naturalPathCompare);

  return files;
}

// Natural-sort by filename so 2 comes before 10.
// Natural-sort by filename so 2 comes before 10, and image02 before image10.
int _naturalPathCompare(String leftPath, String rightPath) {
  final result = _naturalCompare(_fileName(leftPath), _fileName(rightPath));
  if (result != 0) {
    return result;
  }
  return _pathKey(leftPath).compareTo(_pathKey(rightPath));
}

int _naturalCompare(String left, String right) {
  final leftLower = left.toLowerCase();
  final rightLower = right.toLowerCase();
  var leftIndex = 0;
  var rightIndex = 0;

  while (leftIndex < leftLower.length && rightIndex < rightLower.length) {
    final leftCode = leftLower.codeUnitAt(leftIndex);
    final rightCode = rightLower.codeUnitAt(rightIndex);
    final leftIsDigit = _isAsciiDigit(leftCode);
    final rightIsDigit = _isAsciiDigit(rightCode);

    if (leftIsDigit && rightIsDigit) {
      final leftStart = leftIndex;
      final rightStart = rightIndex;
      while (leftIndex < leftLower.length &&
          _isAsciiDigit(leftLower.codeUnitAt(leftIndex))) {
        leftIndex++;
      }
      while (rightIndex < rightLower.length &&
          _isAsciiDigit(rightLower.codeUnitAt(rightIndex))) {
        rightIndex++;
      }

      final numberCompare = _compareNumberText(
        leftLower.substring(leftStart, leftIndex),
        rightLower.substring(rightStart, rightIndex),
      );
      if (numberCompare != 0) {
        return numberCompare;
      }
      continue;
    }

    if (leftCode != rightCode) {
      return leftCode.compareTo(rightCode);
    }
    leftIndex++;
    rightIndex++;
  }

  final lengthCompare = leftLower.length.compareTo(rightLower.length);
  if (lengthCompare != 0) {
    return lengthCompare;
  }
  return left.compareTo(right);
}

int _compareNumberText(String left, String right) {
  final normalizedLeft = _trimLeadingZeros(left);
  final normalizedRight = _trimLeadingZeros(right);
  final lengthCompare = normalizedLeft.length.compareTo(normalizedRight.length);
  if (lengthCompare != 0) {
    return lengthCompare;
  }

  final valueCompare = normalizedLeft.compareTo(normalizedRight);
  if (valueCompare != 0) {
    return valueCompare;
  }
  return left.length.compareTo(right.length);
}

String _trimLeadingZeros(String value) {
  var index = 0;
  while (index < value.length - 1 && value.codeUnitAt(index) == 48) {
    index++;
  }
  return value.substring(index);
}

bool _isAsciiDigit(int codeUnit) => codeUnit >= 48 && codeUnit <= 57;

bool _isImagePath(String path) {
  final dotIndex = path.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == path.length - 1) {
    return false;
  }
  return _imageExtensions.contains(path.substring(dotIndex + 1).toLowerCase());
}

bool _touchRecent(List<_RecentEntry> items, String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  final key = _pathKey(trimmed);
  final existingIndex = items.indexWhere((item) => _pathKey(item.path) == key);
  if (existingIndex >= 0) {
    items.removeAt(existingIndex);
  }
  items.insert(0, _RecentEntry(path: trimmed, timestamp: DateTime.now()));
  if (items.length > _recentHistoryLimit) {
    items.removeRange(_recentHistoryLimit, items.length);
  }
  return true;
}

String _fileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slashIndex = normalized.lastIndexOf('/');
  return slashIndex < 0 ? normalized : normalized.substring(slashIndex + 1);
}

String _directoryName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slashIndex = normalized.lastIndexOf('/');
  if (slashIndex < 0) {
    return '.';
  }
  return normalized.substring(0, slashIndex).replaceAll('/', '\\');
}

String _baseNameWithoutExtension(String path) {
  final name = _fileName(path);
  final dotIndex = name.lastIndexOf('.');
  return dotIndex < 0 ? name : name.substring(0, dotIndex);
}

void _copyFileOverwrite(String sourcePath, String targetPath) {
  if (_pathKey(sourcePath) == _pathKey(targetPath)) {
    return;
  }
  final target = File(targetPath);
  target.parent.createSync(recursive: true);
  if (target.existsSync()) {
    target.deleteSync();
  }
  File(sourcePath).copySync(targetPath);
}

String _replaceExtension(String path, String extension) {
  final dotIndex = path.lastIndexOf('.');
  if (dotIndex < 0) {
    return '$path$extension';
  }
  return path.substring(0, dotIndex) + extension;
}

String _resolveImportDatasetPath(String rootPath, String value) {
  final path = value.replaceAll('/', '\\');
  if (_isAbsolutePath(path)) {
    return path;
  }
  return _joinPath(rootPath, path);
}

String _resolveImportDatasetSourcePath(String rootPath, String value) {
  final direct = _resolveImportDatasetPath(rootPath, value);
  if (_fileSystemPathExists(direct)) {
    return direct;
  }

  final roboflowPath = _resolveRoboflowDatasetSourcePath(rootPath, value);
  if (roboflowPath != null && _fileSystemPathExists(roboflowPath)) {
    return roboflowPath;
  }
  return direct;
}

String? _resolveRoboflowDatasetSourcePath(String rootPath, String value) {
  if (_isAbsolutePath(value)) {
    return null;
  }
  var normalized = value.replaceAll('\\', '/').trim();
  var strippedAnyParent = false;
  while (normalized.startsWith('../')) {
    normalized = normalized.substring(3);
    strippedAnyParent = true;
  }
  if (!strippedAnyParent || normalized.isEmpty) {
    return null;
  }
  return _resolveImportDatasetPath(rootPath, normalized);
}

bool _fileSystemPathExists(String path) {
  return Directory(path).existsSync() || File(path).existsSync();
}

String _pathForDataYaml(String rootPath, String path) {
  final root = rootPath.replaceAll('/', '\\');
  final normalized = path.replaceAll('/', '\\');
  final rootWithSlash = root.endsWith('\\') ? root : '$root\\';
  if (_pathKey(normalized).startsWith(_pathKey(rootWithSlash))) {
    return normalized.substring(rootWithSlash.length).replaceAll('\\', '/');
  }
  return normalized.replaceAll('\\', '/');
}

String _joinPath(String left, String right) {
  final normalizedLeft = left.replaceAll('/', '\\');
  final normalizedRight = right.replaceAll('/', '\\');
  if (normalizedLeft.endsWith('\\')) {
    return '$normalizedLeft$normalizedRight';
  }
  return '$normalizedLeft\\$normalizedRight';
}

bool _isAbsolutePath(String path) {
  if (path.startsWith('\\\\') || path.startsWith('\\')) {
    return true;
  }
  return path.length >= 3 &&
      _isAsciiLetter(path.codeUnitAt(0)) &&
      path.codeUnitAt(1) == 58 &&
      (path.codeUnitAt(2) == 92 || path.codeUnitAt(2) == 47);
}

bool _isAsciiLetter(int codeUnit) {
  return (codeUnit >= 65 && codeUnit <= 90) ||
      (codeUnit >= 97 && codeUnit <= 122);
}

String _pathKey(String path) => path.replaceAll('/', '\\').toLowerCase();

List<String> _stringListFromJson(Object? value) {
  if (value is! List) {
    return [];
  }
  return value.whereType<String>().toList();
}

List<String> _dedupePaths(List<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in values) {
    if (seen.add(_pathKey(value))) {
      result.add(value);
    }
  }
  return result;
}
