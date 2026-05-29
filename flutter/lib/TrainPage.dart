// ignore_for_file: file_names

part of 'main.dart';

/// 训练页面，提供 models 文件夹 YOLO PT 选择、data.yaml 概览和超参数编辑。
/// Training page with YOLO PT selection from models/, data.yaml summary, and parameters.
class _TrainPage extends StatefulWidget {
  const _TrainPage({required this.settings});

  final _AppSettings settings;

  @override
  State<_TrainPage> createState() => _TrainPageState();
}

class _TrainPageState extends State<_TrainPage> {
  final Map<String, double> _parameters = {
    'epochs': 300,
    'batch': 12,
    'imgsz': 640,
    'device': 0,
    'amp': 0,
    'hsv_s': 0.25,
    'hsv_v': 0.5,
    'translate': 0.1,
    'scale': 0.25,
    'shear': 5,
    'flipud': 0,
    'fliplr': 0,
    'degrees': 0,
  };

  Timer? _hideTimer;
  bool _parameterPanelVisible = true;
  String? _modelPath;
  String? _datasetPath;
  _DatasetSummary? _datasetSummary;
  List<String> _modelOptions = const [];

  bool get _validYoloModel {
    final path = _modelPath;
    if (path == null) {
      return false;
    }
    return _modelOptions.any((item) => _pathKey(item) == _pathKey(path));
  }

  @override
  void initState() {
    super.initState();
    _loadModelOptions();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _loadModelOptions() {
    setState(() {
      _modelOptions =
          _modelsDirectoryCandidates()
              .expand((directory) {
                if (!directory.existsSync()) {
                  return const <String>[];
                }
                return directory
                    .listSync()
                    .whereType<File>()
                    .map((file) => file.path)
                    .where(_isSupportedYoloPtModel);
              })
              .toSet()
              .toList()
            ..sort(_naturalPathCompare);
      _modelPath = _modelOptions.isEmpty ? null : _modelOptions.first;
    });
  }

  List<Directory> _modelsDirectoryCandidates() {
    final current = Directory.current;
    return [
      Directory('${current.path}\\models'),
      Directory('${current.parent.path}\\models'),
    ];
  }

  bool _isSupportedYoloPtModel(String path) {
    final name = _fileName(path).toLowerCase();
    return name.startsWith('yolo') &&
        name.endsWith('.pt') &&
        !name.contains('-cls') &&
        !name.contains('-pose');
  }

  void _showPanel() {
    _hideTimer?.cancel();
    if (!_parameterPanelVisible) {
      setState(() => _parameterPanelVisible = true);
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _parameterPanelVisible = false);
      }
    });
  }

  Future<void> _chooseDataset() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Dataset yaml', extensions: ['yaml', 'yml']),
      ],
    );
    if (file == null) {
      return;
    }
    final summary = _DatasetSummary.fromYamlFile(file.path);
    setState(() {
      _datasetPath = file.path;
      _datasetSummary = summary;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Expanded(
            child: Container(
              color: _workspaceColor(context),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('train.title'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 260,
                        child: DropdownButtonFormField<String>(
                          initialValue: _modelPath,
                          items: [
                            for (final model in _modelOptions)
                              DropdownMenuItem(
                                value: model,
                                child: Text(
                                  _fileName(model),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _modelPath = value),
                          decoration: InputDecoration(
                            labelText: t('train.chooseModel'),
                            isDense: true,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _loadModelOptions,
                        icon: const Icon(Icons.refresh),
                        label: Text(t('train.refreshModels')),
                      ),
                      OutlinedButton.icon(
                        onPressed: _chooseDataset,
                        icon: const Icon(Icons.dataset_outlined),
                        label: Text(t('train.chooseDataset')),
                      ),
                      FilledButton.icon(
                        onPressed: _validYoloModel && _datasetSummary != null
                            ? () {}
                            : null,
                        icon: const Icon(Icons.play_arrow),
                        label: Text(t('train.start')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_modelOptions.isEmpty)
                    Text(
                      t('train.noModels'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (_modelPath != null)
                    Text(
                      _modelPath!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (_modelPath != null && !_validYoloModel)
                    Text(
                      t('train.invalidModel'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (_datasetPath != null)
                    Text(
                      _datasetPath!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (widget.settings.pythonPath.isNotEmpty)
                    Text(
                      widget.settings.pythonPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (widget.settings.outputPath.isNotEmpty)
                    Text(
                      widget.settings.outputPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 16),
                  _DatasetSummaryPanel(summary: _datasetSummary),
                  const SizedBox(height: 16),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _panelColor(context),
                        border: Border.all(color: _borderColor(context)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(child: Text(t('train.chartPlaceholder'))),
                    ),
                  ),
                ],
              ),
            ),
          ),
          MouseRegion(
            onEnter: (_) => _showPanel(),
            onHover: (_) => _showPanel(),
            onExit: (_) => _scheduleHide(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: _parameterPanelVisible ? 320 : 8,
              decoration: BoxDecoration(
                color: _panelColor(context),
                border: Border(left: BorderSide(color: _borderColor(context))),
              ),
              child: ClipRect(
                child: _parameterPanelVisible
                    ? _TrainingParameterPanel(
                        parameters: _parameters,
                        onChanged: (key, value) {
                          setState(() => _parameters[key] = value);
                        },
                      )
                    : const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DatasetSummaryPanel extends StatelessWidget {
  const _DatasetSummaryPanel({required this.summary});

  final _DatasetSummary? summary;

  @override
  Widget build(BuildContext context) {
    final summary = this.summary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _panelColor(context),
        border: Border.all(color: _borderColor(context)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: summary == null
              ? Text(t('train.datasetSummaryEmpty'))
              : Wrap(
                  spacing: 18,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('${t('train.classes')}: ${summary.classes.length}'),
                    Text('${t('train.trainCount')}: ${summary.trainCount}'),
                    Text('${t('train.valCount')}: ${summary.valCount}'),
                    if (summary.classes.isNotEmpty)
                      SizedBox(
                        width: 420,
                        child: Text(
                          summary.classes.join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _TrainingParameterPanel extends StatelessWidget {
  const _TrainingParameterPanel({
    required this.parameters,
    required this.onChanged,
  });

  final Map<String, double> parameters;
  final void Function(String key, double value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('train.parameters'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              children: [
                for (final entry in parameters.entries)
                  _ParameterEditor(
                    name: entry.key,
                    value: entry.value,
                    onChanged: (value) => onChanged(entry.key, value),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ParameterEditor extends StatelessWidget {
  const _ParameterEditor({
    required this.name,
    required this.value,
    required this.onChanged,
  });

  final String name;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final integerLike = {'epochs', 'batch', 'imgsz', 'device'}.contains(name);
    return Tooltip(
      waitDuration: const Duration(milliseconds: 500),
      message: _parameterHelp(name),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            SizedBox(width: 72, child: Text(name)),
            Expanded(
              child: Slider(
                value: value,
                min: 0,
                max: _maxForParameter(name),
                divisions: integerLike ? _maxForParameter(name).round() : 100,
                label: _formatParameterValue(value, integerLike),
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: 56,
              child: Text(
                _formatParameterValue(value, integerLike),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DatasetSummary {
  const _DatasetSummary({
    required this.classes,
    required this.trainCount,
    required this.valCount,
  });

  final List<String> classes;
  final int trainCount;
  final int valCount;

  static _DatasetSummary fromYamlFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      return const _DatasetSummary(classes: [], trainCount: 0, valCount: 0);
    }
    final source = file.readAsStringSync();
    final root = _datasetRoot(file.parent.path, _yamlScalar(source, 'path'));
    final trainPath = _yamlScalar(source, 'train');
    final valPath = _yamlScalar(source, 'val');
    return _DatasetSummary(
      classes: _yamlNames(source),
      trainCount: _countDatasetImages(root, trainPath),
      valCount: _countDatasetImages(root, valPath),
    );
  }
}

String _datasetRoot(String yamlRoot, String? configuredRoot) {
  if (configuredRoot == null || configuredRoot.isEmpty) {
    return yamlRoot;
  }
  final normalized = configuredRoot.replaceAll('/', Platform.pathSeparator);
  final absolute =
      RegExp(r'^[A-Za-z]:\\').hasMatch(normalized) ||
      normalized.startsWith('/') ||
      normalized.startsWith('\\');
  return absolute ? normalized : '$yamlRoot\\$normalized';
}

String? _yamlScalar(String source, String key) {
  final match = RegExp('^$key:\\s*(.+)\$', multiLine: true).firstMatch(source);
  return match?.group(1)?.trim().replaceAll('"', '').replaceAll("'", '');
}

List<String> _yamlNames(String source) {
  final inline = RegExp(
    r'^names:\s*\[(.*)\]$',
    multiLine: true,
  ).firstMatch(source);
  if (inline != null) {
    return inline
        .group(1)!
        .split(',')
        .map((item) => item.trim().replaceAll('"', '').replaceAll("'", ''))
        .where((item) => item.isNotEmpty)
        .toList();
  }

  final lines = source.split(RegExp(r'\r?\n'));
  final names = <String>[];
  var inNames = false;
  for (final rawLine in lines) {
    final line = rawLine.trimRight();
    if (line.trim() == 'names:') {
      inNames = true;
      continue;
    }
    if (!inNames) {
      continue;
    }
    if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('-')) {
      break;
    }
    final mapMatch = RegExp(r'^\s*\d+\s*:\s*(.+)$').firstMatch(line);
    final listMatch = RegExp(r'^\s*-\s*(.+)$').firstMatch(line);
    final name = mapMatch?.group(1) ?? listMatch?.group(1);
    if (name != null) {
      names.add(name.trim().replaceAll('"', '').replaceAll("'", ''));
    }
  }
  return names;
}

int _countDatasetImages(String yamlRoot, String? configuredPath) {
  if (configuredPath == null || configuredPath.isEmpty) {
    return 0;
  }
  final path = configuredPath.replaceAll('/', Platform.pathSeparator);
  final resolved = _resolveDatasetPath(yamlRoot, path);
  if (resolved is File && resolved.existsSync()) {
    return resolved
        .readAsLinesSync()
        .where((line) => _isImagePath(_resolveDatasetPath(yamlRoot, line).path))
        .length;
  }
  if (resolved is Directory && resolved.existsSync()) {
    return resolved.listSync(recursive: true).whereType<File>().where((file) {
      return _isImagePath(file.path);
    }).length;
  }
  return 0;
}

FileSystemEntity _resolveDatasetPath(String yamlRoot, String value) {
  final normalized = value.trim();
  final absolute =
      RegExp(r'^[A-Za-z]:\\').hasMatch(normalized) ||
      normalized.startsWith('/') ||
      normalized.startsWith('\\');
  final path = absolute ? normalized : '$yamlRoot\\$normalized';
  if (path.toLowerCase().endsWith('.txt')) {
    return File(path);
  }
  return Directory(path);
}

double _maxForParameter(String name) {
  return switch (name) {
    'epochs' => 500,
    'batch' => 64,
    'imgsz' => 1280,
    'device' => 8,
    'shear' => 20,
    'degrees' => 180,
    _ => 1,
  };
}

String _formatParameterValue(double value, bool integerLike) {
  return integerLike ? value.round().toString() : value.toStringAsFixed(2);
}

String _parameterHelp(String name) {
  return switch (name) {
    'epochs' => '训练轮数。值越大训练越久，可能提升收敛，也更容易过拟合。',
    'batch' => '每批图片数量。显存不足时需要降低。',
    'imgsz' => '训练输入图像尺寸，常用 640。',
    'device' => '训练设备编号，例如 0 表示第一张 GPU。',
    'amp' => '自动混合精度，开启可降低显存占用，但当前默认关闭。',
    'hsv_s' => 'HSV 饱和度增强幅度，范围 0-1。',
    'hsv_v' => 'HSV 亮度增强幅度，范围 0-1。',
    'translate' => '随机平移比例，范围 0-1。',
    'scale' => '随机缩放比例，范围 0-1。',
    'shear' => '随机错切角度。',
    'flipud' => '上下翻转概率，范围 0-1。',
    'fliplr' => '左右翻转概率，范围 0-1。',
    'degrees' => '随机旋转角度范围。',
    _ => name,
  };
}
