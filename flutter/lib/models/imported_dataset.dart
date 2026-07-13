// =============================================================================
// imported_dataset.dart - Imported Dataset Models / 导入数据集模型
// =============================================================================
// Models for parsing YOLO data.yaml files: split sources, class names, image
// directories, and the resulting imported project snapshot.
//
// 解析 YOLO data.yaml 的模型：各 split 数据源、类别名、图片目录和导入后的项目快照。
// =============================================================================

import '../services/path_utils.dart';

const datasetSplits = ['train', 'val', 'test'];

class ParsedYoloData {
  const ParsedYoloData({
    required this.rootPath,
    required this.names,
    required this.splitSources,
    required this.splitImageDirs,
  });

  final String rootPath;
  final List<String> names;
  final Map<String, List<String>> splitSources;
  final Map<String, String> splitImageDirs;
}

class ImportedDataset {
  const ImportedDataset({
    required this.dataYamlPath,
    required this.rootPath,
    required this.splitImageDirs,
  });

  final String dataYamlPath;
  final String rootPath;
  final Map<String, String> splitImageDirs;

  String imageDirForSplit(String split) {
    return splitImageDirs[split] ?? joinPath(rootPath, 'images\\$split');
  }

  String labelDirForSplit(String split) {
    return _labelDirForImageDir(imageDirForSplit(split), rootPath, split);
  }
}

class DatasetImageEntry {
  const DatasetImageEntry({required this.path, required this.split});

  final String path;
  final String split;
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
  return joinPath(rootPath, 'labels\\$split');
}
