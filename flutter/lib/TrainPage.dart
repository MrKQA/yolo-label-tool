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

enum _BatchMode { fixed, autoGpu60, autoGpuRatio }

const _imageSizeOptions = [320, 416, 640, 800, 960, 1280];

class _TrainingDeviceOption {
  const _TrainingDeviceOption({required this.id, required this.label});

  final String id;
  final String label;
}

class _TrainPageState extends State<_TrainPage> {
  final Map<String, double> _parameters = {
    'epochs': 300,
    'imgsz': 640,
    'lr0': 0.01,
    'momentum': 0.937,
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
  Timer? _trainingTimer;
  bool _parameterPanelVisible = true;
  bool _trainingRunning = false;
  int _currentEpoch = 0;
  String? _modelPath;
  String? _datasetPath;
  _DatasetSummary? _datasetSummary;
  List<String> _modelOptions = const [];
  List<_TrainingDeviceOption> _deviceOptions = const [
    _TrainingDeviceOption(id: 'cpu', label: 'CPU'),
  ];
  Set<String> _selectedDeviceIds = const {'cpu'};
  _BatchMode _batchMode = _BatchMode.fixed;
  double _batchSize = 16;
  double _batchRatio = 0.70;
  bool _ampEnabled = false;

  bool get _validYoloModel {
    final path = _modelPath;
    if (path == null) {
      return false;
    }
    return _modelOptions.any((item) => _pathKey(item) == _pathKey(path));
  }

  bool get _usingCpuDevice => _selectedDeviceIds.contains('cpu');

  String get _batchArgument {
    return switch (_batchMode) {
      _BatchMode.fixed => _batchSize.round().toString(),
      _BatchMode.autoGpu60 => '-1',
      _BatchMode.autoGpuRatio => _batchRatio.toStringAsFixed(2),
    };
  }

  String get _deviceArgument {
    if (_usingCpuDevice || _selectedDeviceIds.isEmpty) {
      return 'cpu';
    }
    final ids = _selectedDeviceIds.toList()..sort(_naturalCompare);
    return ids.length == 1 ? ids.first : '[${ids.join(', ')}]';
  }

  @override
  void initState() {
    super.initState();
    _loadDeviceOptions();
    _loadModelOptions();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _trainingTimer?.cancel();
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

  void _loadDeviceOptions() {
    final devices = _detectNvidiaDevices();
    if (devices.isEmpty) {
      _deviceOptions = const [_TrainingDeviceOption(id: 'cpu', label: 'CPU')];
      _selectedDeviceIds = const {'cpu'};
      return;
    }
    _deviceOptions = devices;
    _selectedDeviceIds = {devices.first.id};
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

  void _toggleTrainingDevice(String id, bool selected) {
    setState(() {
      final next = {..._selectedDeviceIds};
      if (selected) {
        next.add(id);
      } else if (next.length > 1) {
        next.remove(id);
      }
      _selectedDeviceIds = next.isEmpty ? {id} : next;
    });
  }

  void _startTrainingPreview() {
    if (_trainingRunning) {
      return;
    }
    final totalEpochs = _parameters['epochs']?.round() ?? 1;
    _trainingTimer?.cancel();
    setState(() {
      _trainingRunning = true;
      _currentEpoch = 1;
    });
    _trainingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_currentEpoch >= totalEpochs) {
        timer.cancel();
        setState(() => _trainingRunning = false);
        return;
      }
      setState(() => _currentEpoch += 1);
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
                        onPressed:
                            _validYoloModel &&
                                _datasetSummary != null &&
                                !_trainingRunning
                            ? _startTrainingPreview
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
                      '${t('path.model')}: $_modelPath',
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
                      '${t('train.datasetPath')}: $_datasetPath',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (widget.settings.pythonPath.isNotEmpty)
                    Text(
                      '${t('settings.pythonPath')}: ${widget.settings.pythonPath}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (widget.settings.outputPath.isNotEmpty)
                    Text(
                      '${t('path.trainingOutput')}: ${widget.settings.outputPath}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(
                    _trainingRunning
                        ? '${t('train.currentEpoch')}: $_currentEpoch / ${_parameters['epochs']?.round() ?? 1}'
                        : '${t('train.currentEpoch')}: ${t('train.notStarted')}',
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
                        batchMode: _batchMode,
                        batchSize: _batchSize,
                        batchRatio: _batchRatio,
                        ampEnabled: _ampEnabled,
                        deviceOptions: _deviceOptions,
                        selectedDeviceIds: _selectedDeviceIds,
                        batchArgument: _batchArgument,
                        deviceArgument: _deviceArgument,
                        onChanged: (key, value) {
                          setState(() => _parameters[key] = value);
                        },
                        onBatchModeChanged: (value) {
                          setState(() => _batchMode = value);
                        },
                        onBatchSizeChanged: (value) {
                          setState(() => _batchSize = value);
                        },
                        onBatchRatioChanged: (value) {
                          setState(() => _batchRatio = value);
                        },
                        onAmpChanged: (value) {
                          setState(() => _ampEnabled = value);
                        },
                        onDeviceChanged: _toggleTrainingDevice,
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
    required this.batchMode,
    required this.batchSize,
    required this.batchRatio,
    required this.ampEnabled,
    required this.deviceOptions,
    required this.selectedDeviceIds,
    required this.batchArgument,
    required this.deviceArgument,
    required this.onChanged,
    required this.onBatchModeChanged,
    required this.onBatchSizeChanged,
    required this.onBatchRatioChanged,
    required this.onAmpChanged,
    required this.onDeviceChanged,
  });

  final Map<String, double> parameters;
  final _BatchMode batchMode;
  final double batchSize;
  final double batchRatio;
  final bool ampEnabled;
  final List<_TrainingDeviceOption> deviceOptions;
  final Set<String> selectedDeviceIds;
  final String batchArgument;
  final String deviceArgument;
  final void Function(String key, double value) onChanged;
  final ValueChanged<_BatchMode> onBatchModeChanged;
  final ValueChanged<double> onBatchSizeChanged;
  final ValueChanged<double> onBatchRatioChanged;
  final ValueChanged<bool> onAmpChanged;
  final void Function(String id, bool selected) onDeviceChanged;

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
                _ParameterSectionTitle(title: t('train.coreParameters')),
                _BatchParameterEditor(
                  mode: batchMode,
                  batchSize: batchSize,
                  batchRatio: batchRatio,
                  argumentValue: batchArgument,
                  onModeChanged: onBatchModeChanged,
                  onBatchSizeChanged: onBatchSizeChanged,
                  onBatchRatioChanged: onBatchRatioChanged,
                ),
                _AmpParameterEditor(value: ampEnabled, onChanged: onAmpChanged),
                _DeviceParameterEditor(
                  options: deviceOptions,
                  selectedIds: selectedDeviceIds,
                  argumentValue: deviceArgument,
                  onChanged: onDeviceChanged,
                ),
                for (final entry in parameters.entries)
                  _ParameterEditor(
                    name: entry.key,
                    value: entry.value,
                    onChanged: (value) => onChanged(entry.key, value),
                  ),
                _ParameterSectionTitle(title: t('train.tuningTitle')),
                _TrainingTuningTips(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ParameterSectionTitle extends StatelessWidget {
  const _ParameterSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _BatchParameterEditor extends StatelessWidget {
  const _BatchParameterEditor({
    required this.mode,
    required this.batchSize,
    required this.batchRatio,
    required this.argumentValue,
    required this.onModeChanged,
    required this.onBatchSizeChanged,
    required this.onBatchRatioChanged,
  });

  final _BatchMode mode;
  final double batchSize;
  final double batchRatio;
  final String argumentValue;
  final ValueChanged<_BatchMode> onModeChanged;
  final ValueChanged<double> onBatchSizeChanged;
  final ValueChanged<double> onBatchRatioChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      waitDuration: const Duration(milliseconds: 500),
      message: _parameterHelp('batch'),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ParameterHeader(name: 'batch', value: 'batch=$argumentValue'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  selected: mode == _BatchMode.fixed,
                  label: Text(t('train.batchFixed')),
                  onSelected: (_) => onModeChanged(_BatchMode.fixed),
                ),
                ChoiceChip(
                  selected: mode == _BatchMode.autoGpu60,
                  label: Text(t('train.batchAuto60')),
                  onSelected: (_) => onModeChanged(_BatchMode.autoGpu60),
                ),
                ChoiceChip(
                  selected: mode == _BatchMode.autoGpuRatio,
                  label: Text(t('train.batchRatio')),
                  onSelected: (_) => onModeChanged(_BatchMode.autoGpuRatio),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (mode == _BatchMode.fixed)
              _CompactSlider(
                value: batchSize,
                min: 1,
                max: 128,
                divisions: 127,
                label: batchSize.round().toString(),
                onChanged: onBatchSizeChanged,
              )
            else if (mode == _BatchMode.autoGpuRatio)
              _CompactSlider(
                value: batchRatio,
                min: 0.10,
                max: 0.95,
                divisions: 85,
                label: batchRatio.toStringAsFixed(2),
                onChanged: onBatchRatioChanged,
              )
            else
              Text(t('train.batchAuto60Help')),
          ],
        ),
      ),
    );
  }
}

class _AmpParameterEditor extends StatelessWidget {
  const _AmpParameterEditor({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      waitDuration: const Duration(milliseconds: 500),
      message: _parameterHelp('amp'),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('amp'),
        subtitle: Text('amp=${value ? 1 : 0}'),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

class _DeviceParameterEditor extends StatelessWidget {
  const _DeviceParameterEditor({
    required this.options,
    required this.selectedIds,
    required this.argumentValue,
    required this.onChanged,
  });

  final List<_TrainingDeviceOption> options;
  final Set<String> selectedIds;
  final String argumentValue;
  final void Function(String id, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      waitDuration: const Duration(milliseconds: 500),
      message: _parameterHelp('device'),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ParameterHeader(name: 'device', value: 'device=$argumentValue'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in options)
                  FilterChip(
                    selected: selectedIds.contains(option.id),
                    label: Text(option.label),
                    onSelected: (selected) => onChanged(option.id, selected),
                    avatar: Icon(
                      selectedIds.contains(option.id)
                          ? Icons.check_circle
                          : Icons.memory_outlined,
                      size: 18,
                    ),
                  ),
              ],
            ),
            if (options.length == 1 && options.first.id == 'cpu')
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  t('train.noGpuDetected'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ParameterHeader extends StatelessWidget {
  const _ParameterHeader({required this.name, required this.value});

  final String name;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 72, child: Text(name)),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _CompactSlider extends StatelessWidget {
  const _CompactSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: label,
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 56, child: Text(label, textAlign: TextAlign.right)),
      ],
    );
  }
}

class _TrainingTuningTips extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _controlColor(context),
        border: Border.all(color: _borderColor(context)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          t('train.tuningTips'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _ImageSizeParameterEditor extends StatelessWidget {
  const _ImageSizeParameterEditor({
    required this.value,
    required this.onChanged,
  });

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final index = _nearestImageSizeIndex(value);
    final currentSize = _imageSizeOptions[index];
    return Tooltip(
      waitDuration: const Duration(milliseconds: 500),
      message: _parameterHelp('imgsz'),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            const SizedBox(width: 72, child: Text('imgsz')),
            Expanded(
              child: Slider(
                value: index.toDouble(),
                min: 0,
                max: (_imageSizeOptions.length - 1).toDouble(),
                divisions: _imageSizeOptions.length - 1,
                label: currentSize.toString(),
                onChanged: (sliderIndex) {
                  final nextIndex = sliderIndex.round().clamp(
                    0,
                    _imageSizeOptions.length - 1,
                  );
                  onChanged(_imageSizeOptions[nextIndex].toDouble());
                },
              ),
            ),
            SizedBox(
              width: 56,
              child: Text(currentSize.toString(), textAlign: TextAlign.right),
            ),
          ],
        ),
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
    if (name == 'imgsz') {
      return _ImageSizeParameterEditor(value: value, onChanged: onChanged);
    }

    final integerLike = {'epochs', 'imgsz'}.contains(name);
    final min = _minForParameter(name);
    final max = _maxForParameter(name);
    final divisions = integerLike ? (max - min).round() : 100;
    final label = _formatParameterValue(name, value);
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
                min: min,
                max: max,
                divisions: divisions,
                label: label,
                onChanged: onChanged,
              ),
            ),
            SizedBox(width: 56, child: Text(label, textAlign: TextAlign.right)),
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
    final trainPaths = _yamlPathValues(source, 'train');
    final valPaths = _yamlPathValues(source, 'val');
    return _DatasetSummary(
      classes: _yamlNames(source),
      trainCount: _countDatasetImagePaths(root, trainPaths),
      valCount: _countDatasetImagePaths(root, valPaths),
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

List<String> _yamlPathValues(String source, String key) {
  final scalar = _yamlScalar(source, key);
  if (scalar != null && scalar.isNotEmpty) {
    final trimmed = scalar.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      return trimmed
          .substring(1, trimmed.length - 1)
          .split(',')
          .map(_cleanYamlValue)
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return [_cleanYamlValue(trimmed)];
  }

  final lines = source.split(RegExp(r'\r?\n'));
  final values = <String>[];
  var inBlock = false;
  for (final rawLine in lines) {
    final line = rawLine.trimRight();
    if (line.trim() == '$key:') {
      inBlock = true;
      continue;
    }
    if (!inBlock) {
      continue;
    }
    if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('-')) {
      break;
    }
    final listMatch = RegExp(r'^\s*-\s*(.+)$').firstMatch(line);
    if (listMatch != null) {
      final value = _cleanYamlValue(listMatch.group(1)!);
      if (value.isNotEmpty) {
        values.add(value);
      }
    }
  }
  return values;
}

String _cleanYamlValue(String value) {
  return value.split('#').first.trim().replaceAll('"', '').replaceAll("'", '');
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

int _countDatasetImagePaths(String yamlRoot, List<String> configuredPaths) {
  return configuredPaths.fold<int>(
    0,
    (count, path) => count + _countDatasetImages(yamlRoot, path),
  );
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

List<_TrainingDeviceOption> _detectNvidiaDevices() {
  try {
    final result = Process.runSync('nvidia-smi', [
      '--query-gpu=index,name',
      '--format=csv,noheader',
    ]);
    if (result.exitCode != 0) {
      return const [];
    }
    final output = result.stdout.toString().trim();
    if (output.isEmpty) {
      return const [];
    }
    return output
        .split(RegExp(r'\r?\n'))
        .map((line) {
          final parts = line.split(',');
          final id = parts.first.trim();
          final name = parts.length > 1
              ? parts.sublist(1).join(',').trim()
              : '';
          if (id.isEmpty) {
            return null;
          }
          return _TrainingDeviceOption(
            id: id,
            label: name.isEmpty ? 'GPU $id' : 'GPU $id - $name',
          );
        })
        .whereType<_TrainingDeviceOption>()
        .toList();
  } on Object {
    return const [];
  }
}

double _minForParameter(String name) {
  return switch (name) {
    'epochs' => 1,
    'imgsz' => 320,
    'momentum' => 0.5,
    _ => 0,
  };
}

double _maxForParameter(String name) {
  return switch (name) {
    'epochs' => 500,
    'imgsz' => 1280,
    'lr0' => 0.1,
    'momentum' => 0.99,
    'shear' => 20,
    'degrees' => 180,
    _ => 1,
  };
}

int _nearestImageSizeIndex(double value) {
  var nearestIndex = 0;
  var nearestDelta = double.infinity;
  for (var index = 0; index < _imageSizeOptions.length; index += 1) {
    final delta = (value - _imageSizeOptions[index]).abs();
    if (delta < nearestDelta) {
      nearestIndex = index;
      nearestDelta = delta;
    }
  }
  return nearestIndex;
}

String _formatParameterValue(String name, double value) {
  return switch (name) {
    'epochs' || 'imgsz' => value.round().toString(),
    'lr0' => value.toStringAsFixed(4),
    'momentum' => value.toStringAsFixed(3),
    _ => value.toStringAsFixed(2),
  };
}

String _parameterHelp(String name) {
  return switch (name) {
    'epochs' => '训练轮数。值越大训练越久，可能提升收敛，也更容易过拟合。',
    'batch' => '批大小支持固定整数、batch=-1 自动使用约 60% 显存、或 batch=0.70 按显存比例自动调整。',
    'imgsz' => '训练输入图像尺寸，只能选择 320、416、640、800、960、1280，且必须能被 32 整除。',
    'device' => '训练设备编号。多选 GPU 时按 device=[0, 1] 形式传递。',
    'amp' => '自动混合精度。关闭传 0，开启传 1；开启通常可以降低显存占用。',
    'lr0' => '初始学习率。过大容易震荡，过小会导致训练收敛慢。',
    'momentum' => '动量参数，影响梯度更新的平滑程度。',
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
