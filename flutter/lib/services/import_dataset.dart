part of '../main.dart';

_ParsedYoloData _parseImportYoloDataYaml(String yamlPath) {
  final lines = File(yamlPath).readAsLinesSync();
  final yamlDir = _directoryName(yamlPath);
  final pathValue = _importYamlScalar(lines, 'path');
  final rootPath = pathValue == null || pathValue.isEmpty
      ? yamlDir
      : _resolveImportDatasetPath(yamlDir, pathValue);
  final splitSources = <String, List<String>>{};
  final splitImageDirs = <String, String>{};
  for (final split in _datasetSplits) {
    final sources = _importYamlStringValues(lines, split);
    splitSources[split] = sources;
    if (sources.isNotEmpty) {
      splitImageDirs[split] = _firstImageDirectoryForSplit(
        rootPath,
        split,
        sources,
      );
    }
  }
  return _ParsedYoloData(
    rootPath: rootPath,
    names: _importYamlNames(lines),
    splitSources: splitSources,
    splitImageDirs: splitImageDirs,
  );
}

String _datasetYamlContent(
  _ImportedDataset dataset,
  Map<String, Set<String>> grouped,
  List<_LabelClass> labelClasses,
) {
  final lines = <String>[
    'path: ${dataset.rootPath.replaceAll('\\', '/')}',
    'train: ${_pathForDataYaml(dataset.rootPath, dataset.imageDirForSplit('train'))}',
    'val: ${_pathForDataYaml(dataset.rootPath, dataset.imageDirForSplit('val'))}',
    if ((grouped['test']?.isNotEmpty ?? false) ||
        dataset.splitImageDirs.containsKey('test'))
      'test: ${_pathForDataYaml(dataset.rootPath, dataset.imageDirForSplit('test'))}',
    '',
    'nc: ${labelClasses.length}',
    'names:',
    for (var i = 0; i < labelClasses.length; i++)
      '  $i: ${labelClasses[i].name}',
  ];
  return lines.join('\n');
}

class _ImportedYoloProject {
  const _ImportedYoloProject({
    required this.images,
    required this.labelClasses,
    required this.annotationsByImage,
    required this.imageSplits,
    required this.dataset,
    required this.classSerial,
    required this.annotationSerial,
  });

  final List<_ImageItem> images;
  final List<_LabelClass> labelClasses;
  final Map<String, List<_AnnotationRegion>> annotationsByImage;
  final Map<String, String> imageSplits;
  final _ImportedDataset dataset;
  final int classSerial;
  final int annotationSerial;

  int get annotationCount {
    return annotationsByImage.values.fold<int>(
      0,
      (sum, annotations) => sum + annotations.length,
    );
  }
}

Future<_ImportedYoloProject?> _loadImportedYoloProject({
  required String yamlPath,
  required Future<Size> Function(String imagePath) ensureImageDisplaySize,
}) async {
  final parsed = _parseImportYoloDataYaml(yamlPath);
  final imageEntries = <_DatasetImageEntry>[];
  for (final split in _datasetSplits) {
    final sources = parsed.splitSources[split] ?? const [];
    for (final source in sources) {
      imageEntries.addAll(
        _imagePathsFromDatasetSource(
          parsed.rootPath,
          source,
        ).map((path) => _DatasetImageEntry(path: path, split: split)),
      );
    }
  }

  final uniqueEntries = _dedupeDatasetEntries(imageEntries);
  if (uniqueEntries.isEmpty) {
    return null;
  }

  final importedClasses = <_LabelClass>[];
  int ensureClass(int classIndex) {
    while (importedClasses.length <= classIndex) {
      final index = importedClasses.length;
      final name = index < parsed.names.length
          ? parsed.names[index]
          : 'class_$index';
      importedClasses.add(
        _LabelClass(
          id: index,
          name: name,
          colorValue:
              _labelColorPalette[index % _labelColorPalette.length].toARGB32(),
        ),
      );
    }
    return importedClasses[classIndex].id;
  }

  final importedAnnotations = <String, List<_AnnotationRegion>>{};
  final importedSplits = <String, String>{};
  var annotationSerial = 1;
  for (final entry in uniqueEntries) {
    final displaySize = await ensureImageDisplaySize(entry.path);
    importedSplits[_pathKey(entry.path)] = entry.split;
    importedAnnotations[_pathKey(entry.path)] = _readYoloAnnotations(
      imagePath: entry.path,
      imageSize: displaySize,
      ensureClass: ensureClass,
      nextId: () => 'ann_${annotationSerial++}',
    );
  }

  if (parsed.names.isNotEmpty) {
    for (var i = 0; i < parsed.names.length; i++) {
      ensureClass(i);
    }
  }

  return _ImportedYoloProject(
    images: [
      for (final entry in uniqueEntries) _ImageItem.fromPath(entry.path),
    ],
    labelClasses: importedClasses,
    annotationsByImage: importedAnnotations,
    imageSplits: importedSplits,
    dataset: _ImportedDataset(
      dataYamlPath: yamlPath,
      rootPath: parsed.rootPath,
      splitImageDirs: parsed.splitImageDirs,
    ),
    classSerial: importedClasses.length,
    annotationSerial: annotationSerial,
  );
}

List<_DatasetImageEntry> _dedupeDatasetEntries(
  List<_DatasetImageEntry> entries,
) {
  final seen = <String>{};
  final result = <_DatasetImageEntry>[];
  for (final entry in entries) {
    if (seen.add(_pathKey(entry.path))) {
      result.add(entry);
    }
  }
  return result;
}

List<String> _imagePathsFromDatasetSource(String rootPath, String source) {
  final resolved = _resolveImportDatasetSourcePath(rootPath, source);
  final directory = Directory(resolved);
  if (directory.existsSync()) {
    final paths = directory
        .listSync(recursive: true)
        .whereType<File>()
        .map<String>((file) => file.path)
        .where((path) => _isImagePath(path))
        .toList();
    paths.sort(_naturalPathCompare);
    return paths;
  }

  final file = File(resolved);
  if (!file.existsSync()) {
    return [];
  }
  if (_isImagePath(file.path)) {
    return [file.path];
  }

  final parent = _directoryName(file.path);
  final paths = file
      .readAsLinesSync()
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .map<String>((line) => _resolveImportDatasetSourcePath(parent, line))
      .where((path) => _isImagePath(path))
      .where((path) => File(path).existsSync())
      .toList();
  paths.sort(_naturalPathCompare);
  return paths;
}

List<_AnnotationRegion> _readYoloAnnotations({
  required String imagePath,
  required Size imageSize,
  required int Function(int classIndex) ensureClass,
  required String Function() nextId,
}) {
  final labelFile = File(_labelPathForImagePath(imagePath));
  if (!labelFile.existsSync()) {
    return const [];
  }
  final result = <_AnnotationRegion>[];
  for (final rawLine in labelFile.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 5) {
      continue;
    }
    final classIndex = int.tryParse(parts.first);
    if (classIndex == null || classIndex < 0) {
      continue;
    }
    final values = parts
        .skip(1)
        .map(double.tryParse)
        .whereType<double>()
        .toList(growable: false);
    if (values.length != parts.length - 1) {
      continue;
    }
    final classId = ensureClass(classIndex);
    final annotation = _annotationFromYoloValues(
      id: nextId(),
      values: values,
      classId: classId,
      imageSize: imageSize,
    );
    if (annotation != null) {
      result.add(annotation);
    }
  }
  return result;
}

_AnnotationRegion? _annotationFromYoloValues({
  required String id,
  required List<double> values,
  required int classId,
  required Size imageSize,
}) {
  final w = imageSize.width;
  final h = imageSize.height;
  if (w <= 0 || h <= 0) {
    return null;
  }
  if (values.length == 4) {
    final cx = values[0] * w;
    final cy = values[1] * h;
    final bw = values[2] * w;
    final bh = values[3] * h;
    return _AnnotationRegion.fromRect(
      id: id,
      mode: _AnnotationMode.hbb,
      rect: Rect.fromCenter(center: Offset(cx, cy), width: bw, height: bh),
      classId: classId,
    ).clampedTo(Rect.fromLTWH(0, 0, w, h));
  }
  if (values.length == 8) {
    final points = _normalizedPairsToPoints(values, imageSize);
    final width = (points[1] - points[0]).distance;
    final height = (points[2] - points[1]).distance;
    if (width <= 0 || height <= 0) {
      return null;
    }
    final center = points.reduce((a, b) => a + b) / points.length.toDouble();
    final rotation =
        math.atan2(points[1].dy - points[0].dy, points[1].dx - points[0].dx) *
        180 /
        math.pi;
    return _AnnotationRegion(
      id: id,
      mode: _AnnotationMode.obb,
      rect: Rect.fromCenter(center: center, width: width, height: height),
      classId: classId,
      rotationDegrees: rotation,
    ).clampObbToImage(imageSize);
  }
  if (values.length >= 6 && values.length.isEven) {
    final points = _normalizedPairsToPoints(values, imageSize);
    final xs = points.map((point) => point.dx);
    final ys = points.map((point) => point.dy);
    final bounds = Rect.fromLTRB(
      xs.reduce(math.min),
      ys.reduce(math.min),
      xs.reduce(math.max),
      ys.reduce(math.max),
    );
    return _AnnotationRegion(
      id: id,
      mode: _AnnotationMode.seg,
      rect: bounds,
      classId: classId,
      points: [
        for (final point in points)
          _clampOffset(point, Rect.fromLTWH(0, 0, w, h)),
      ],
    );
  }
  return null;
}

List<Offset> _normalizedPairsToPoints(List<double> values, Size imageSize) {
  return [
    for (var i = 0; i + 1 < values.length; i += 2)
      Offset(
        (values[i] * imageSize.width).clamp(0.0, imageSize.width).toDouble(),
        (values[i + 1] * imageSize.height)
            .clamp(0.0, imageSize.height)
            .toDouble(),
      ),
  ];
}

String _labelPathForImagePath(String imagePath) {
  final normalized = imagePath.replaceAll('\\', '/');
  final parts = normalized.split('/');
  for (var i = parts.length - 2; i >= 0; i--) {
    if (parts[i].toLowerCase() == 'images') {
      parts[i] = 'labels';
      return _replaceExtension(parts.join('\\'), '.txt');
    }
  }
  return _joinPath(
    _directoryName(imagePath),
    '${_baseNameWithoutExtension(imagePath)}.txt',
  );
}

String _labelDirForImageDir(String imageDir, String rootPath, String split) {
  final normalized = imageDir.replaceAll('\\', '/');
  final parts = normalized.split('/');
  for (var i = parts.length - 1; i >= 0; i--) {
    if (parts[i].toLowerCase() == 'images') {
      parts[i] = 'labels';
      return parts.join('\\');
    }
  }
  return _joinPath(rootPath, 'labels\\$split');
}

String _firstImageDirectoryForSplit(
  String rootPath,
  String split,
  List<String> sources,
) {
  for (final source in sources) {
    final resolved = _resolveImportDatasetSourcePath(rootPath, source);
    if (Directory(resolved).existsSync()) {
      return resolved;
    }
  }
  return _joinPath(rootPath, 'images\\$split');
}

String? _importYamlScalar(List<String> lines, String key) {
  for (final rawLine in lines) {
    final line = _stripImportYamlComment(rawLine).trimRight();
    if (!line.startsWith('$key:')) {
      continue;
    }
    final value = line.substring(key.length + 1).trim();
    return value.isEmpty ? null : _unquoteImportYamlValue(value);
  }
  return null;
}

List<String> _importYamlStringValues(List<String> lines, String key) {
  for (var i = 0; i < lines.length; i++) {
    final raw = _stripImportYamlComment(lines[i]);
    final line = raw.trimRight();
    final trimmed = line.trimLeft();
    if (!trimmed.startsWith('$key:')) {
      continue;
    }
    final value = trimmed.substring(key.length + 1).trim();
    if (value.isNotEmpty) {
      return _parseImportYamlValueList(value);
    }
    final result = <String>[];
    for (var j = i + 1; j < lines.length; j++) {
      final childRaw = _stripImportYamlComment(lines[j]);
      if (childRaw.trim().isEmpty) {
        continue;
      }
      if (!_hasImportYamlIndent(childRaw)) {
        break;
      }
      final child = childRaw.trim();
      if (child.startsWith('-')) {
        final item = child.substring(1).trim();
        if (item.isNotEmpty) {
          result.add(_unquoteImportYamlValue(item));
        }
      }
    }
    return result;
  }
  return const [];
}

List<String> _importYamlNames(List<String> lines) {
  for (var i = 0; i < lines.length; i++) {
    final raw = _stripImportYamlComment(lines[i]);
    final trimmed = raw.trimLeft();
    if (!trimmed.startsWith('names:')) {
      continue;
    }
    final value = trimmed.substring('names:'.length).trim();
    if (value.isNotEmpty) {
      return _parseImportYamlValueList(value);
    }
    final byIndex = <int, String>{};
    final list = <String>[];
    for (var j = i + 1; j < lines.length; j++) {
      final childRaw = _stripImportYamlComment(lines[j]);
      if (childRaw.trim().isEmpty) {
        continue;
      }
      if (!_hasImportYamlIndent(childRaw)) {
        break;
      }
      final child = childRaw.trim();
      if (child.startsWith('-')) {
        list.add(_unquoteImportYamlValue(child.substring(1).trim()));
        continue;
      }
      final colon = child.indexOf(':');
      if (colon > 0) {
        final index = int.tryParse(child.substring(0, colon).trim());
        final name = _unquoteImportYamlValue(child.substring(colon + 1).trim());
        if (index != null && name.isNotEmpty) {
          byIndex[index] = name;
        }
      }
    }
    if (byIndex.isNotEmpty) {
      final maxIndex = byIndex.keys.reduce(math.max);
      return [
        for (var index = 0; index <= maxIndex; index++)
          byIndex[index] ?? 'class_$index',
      ];
    }
    return list;
  }
  return const [];
}

List<String> _parseImportYamlValueList(String value) {
  final trimmed = value.trim();
  if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
    final content = trimmed.substring(1, trimmed.length - 1);
    return content
        .split(',')
        .map((item) => _unquoteImportYamlValue(item.trim()))
        .where((item) => item.isNotEmpty)
        .toList();
  }
  if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
    final content = trimmed.substring(1, trimmed.length - 1);
    final indexed = <int, String>{};
    for (final pair in content.split(',')) {
      final colon = pair.indexOf(':');
      if (colon < 0) {
        continue;
      }
      final index = int.tryParse(pair.substring(0, colon).trim());
      final name = _unquoteImportYamlValue(pair.substring(colon + 1).trim());
      if (index != null && name.isNotEmpty) {
        indexed[index] = name;
      }
    }
    if (indexed.isEmpty) {
      return const [];
    }
    final maxIndex = indexed.keys.reduce(math.max);
    return [
      for (var index = 0; index <= maxIndex; index++)
        indexed[index] ?? 'class_$index',
    ];
  }
  return [_unquoteImportYamlValue(trimmed)];
}

String _stripImportYamlComment(String line) {
  final index = line.indexOf('#');
  return index < 0 ? line : line.substring(0, index);
}

bool _hasImportYamlIndent(String line) {
  return line.startsWith(' ') || line.startsWith('\t');
}

String _unquoteImportYamlValue(String value) {
  final trimmed = value.trim();
  if (trimmed.length >= 2) {
    final first = trimmed[0];
    final last = trimmed[trimmed.length - 1];
    if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
      return trimmed.substring(1, trimmed.length - 1);
    }
  }
  return trimmed;
}
