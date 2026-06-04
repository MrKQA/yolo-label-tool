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
    'cls_pw': 0,
    'workers': 4,
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
  bool _trainingStopping = false;
  bool _trainingInterrupted = false;
  int _currentEpoch = 0;
  String? _activeRunDir;
  _TrainingMetrics? _trainingMetrics;
  List<_TrainingMetricPoint> _trainingMetricPoints = const [];
  bool _showTrainingTerminal = false;
  String _trainingLogText = '';
  String? _activeTrainingLogPath;
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
  bool _resumeEnabled = false;
  bool _datasetLoading = false;
  _ResumeTrainingInfo? _resumeInfo;
  List<_TrainingHistoryEntry> _trainingHistory = const [];

  bool get _validYoloModel {
    final path = _modelPath;
    if (path == null) {
      return false;
    }
    return File(path).existsSync() &&
        (path.toLowerCase().endsWith('.pt') || _isSupportedYoloPtModel(path));
  }

  bool get _canResumeTraining => _resumeInfo?.canResume ?? false;

  bool get _useResumeTraining => _canResumeTraining && _resumeEnabled;

  bool get _showContinueTraining => _useResumeTraining || _trainingInterrupted;

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
    _trainingHistory = _ConfigStore.loadTrainingHistory().entries;
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

  void _loadModelOptions({bool preserveSelection = true}) {
    final previous = _modelPath;
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
      if (previous != null &&
          File(previous).existsSync() &&
          !_modelOptions.any((path) => _pathKey(path) == _pathKey(previous))) {
        _modelOptions = [..._modelOptions, previous]..sort(_naturalPathCompare);
      }
      if (preserveSelection &&
          previous != null &&
          _modelOptions.any((path) => _pathKey(path) == _pathKey(previous))) {
        _modelPath = previous;
      } else {
        _modelPath = _modelOptions.isEmpty ? null : _modelOptions.first;
      }
    });
    _refreshResumeInfo();
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
    return name.endsWith('.pt') &&
        (name.startsWith('yolo') || name == 'last.pt' || name == 'best.pt') &&
        !name.contains('-cls') &&
        !name.contains('-pose');
  }

  Future<void> _chooseModel() async {
    final file = await openFile(
      initialDirectory: _initialModelDirectory(),
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PyTorch model', extensions: ['pt']),
      ],
    );
    if (file == null) {
      return;
    }
    setState(() {
      if (!_modelOptions.any((path) => _pathKey(path) == _pathKey(file.path))) {
        _modelOptions = [..._modelOptions, file.path]
          ..sort(_naturalPathCompare);
      }
      _modelPath = file.path;
    });
    _selectDatasetFromCheckpoint(file.path);
    _refreshResumeInfo();
  }

  String? _initialModelDirectory() {
    final outputPath = widget.settings.outputPath;
    if (outputPath.isNotEmpty && Directory(outputPath).existsSync()) {
      return outputPath;
    }
    for (final directory in _modelsDirectoryCandidates()) {
      if (directory.existsSync()) {
        return directory.path;
      }
    }
    return null;
  }

  void _showPanel() {
    _hideTimer?.cancel();
    if (!_parameterPanelVisible) {
      setState(() => _parameterPanelVisible = true);
    }
  }

  void _showWarning(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
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
    if (_datasetLoading) {
      return;
    }
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Dataset yaml', extensions: ['yaml', 'yml']),
      ],
    );
    if (file == null) {
      return;
    }
    setState(() => _datasetLoading = true);
    try {
      final path = file.path;
      final summary = await _loadDatasetSummaryInBackground(path);
      if (!mounted) {
        return;
      }
      setState(() {
        _datasetPath = path;
        _datasetSummary = summary;
        _parameters['cls_pw'] = summary.recommendedClsPw;
      });
      _refreshResumeInfo();
    } on Object catch (error) {
      if (mounted) {
        _showWarning('${t('train.datasetLoadFailed')}: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _datasetLoading = false);
      }
    }
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

  void _toggleTraining() {
    if (_trainingRunning) {
      _stopTraining();
      return;
    }
    _startTraining();
  }

  Future<void> _startTraining() async {
    if (_trainingRunning) return;
    if (_modelPath == null || _datasetPath == null) return;
    final pythonPath = widget.settings.pythonPath;
    final outputPath = widget.settings.outputPath;
    if (pythonPath.isEmpty) {
      _showWarning(t('train.pythonNotConfigured'));
      return;
    }

    final totalEpochs = _targetTrainingEpochs();
    final continuing = _showContinueTraining;
    final nextEpoch = _initialTrainingEpoch(totalEpochs);
    _trainingTimer?.cancel();
    final logPath = _logFileForDate(DateTime.now()).path;

    setState(() {
      _trainingRunning = true;
      _trainingStopping = false;
      _trainingInterrupted = false;
      _currentEpoch = nextEpoch;
      _trainingMetrics = null;
      _trainingMetricPoints = [];
      _activeTrainingLogPath = logPath;
      _trainingLogText = '';
    });
    _appendTrainingRecord(
      continuing ? _TrainingHistoryAction.resume : _TrainingHistoryAction.start,
    );

    try {
      final runDir = await _RustVideoBackend.startYoloTraining(
        pythonPath: pythonPath,
        modelPath: _modelPath!,
        dataYamlPath: _datasetPath!,
        projectDir: outputPath.isNotEmpty ? outputPath : '${Directory.current.path}\\runs',
        experimentName: _trainingExperimentName(),
        epochs: totalEpochs,
        imgsz: _parameters['imgsz']?.round() ?? 640,
        batch: _batchArgument,
        device: _deviceArgument,
        lr0: _parameters['lr0'] ?? 0.01,
        momentum: _parameters['momentum'] ?? 0.937,
        hsvS: _parameters['hsv_s'] ?? 0.25,
        hsvV: _parameters['hsv_v'] ?? 0.5,
        translate: _parameters['translate'] ?? 0.1,
        scale: _parameters['scale'] ?? 0.25,
        shear: _parameters['shear'] ?? 5,
        flipud: _parameters['flipud'] ?? 0,
        fliplr: _parameters['fliplr'] ?? 0,
        degrees: _parameters['degrees'] ?? 0,
        workers: _parameters['workers']?.round() ?? 4,
        amp: _ampEnabled,
        resume: _useResumeTraining,
        clsPw: _parameters['cls_pw'] ?? 0,
      );
      final logText = await _readTrainingLogTail(_activeTrainingLogPath);
      if (mounted) {
        setState(() {
          _activeRunDir = runDir;
          _trainingLogText = logText;
        });
      }
    } on Object catch (e) {
      final logText = await _readTrainingLogTail(_activeTrainingLogPath);
      _trainingTimer?.cancel();
      if (mounted) {
        setState(() {
          _trainingRunning = false;
          _trainingStopping = false;
          _trainingInterrupted = false;
          _trainingLogText = logText;
          _showTrainingTerminal = true;
        });
      }
      _showWarning('${t('train.startFailed')}: $e');
      return;
    }

    _trainingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _pollTrainingProgress();
    });
  }

  void _stopTraining() {
    if (!_trainingRunning || _trainingStopping) return;
    _RustVideoBackend.stopYoloTraining();
    setState(() {
      _trainingStopping = true;
      _showTrainingTerminal = true;
    });
    _appendTrainingRecord(_TrainingHistoryAction.stop);
  }

  Future<void> _pollTrainingProgress() async {
    if (!mounted || !_trainingRunning) return;
    try {
      final progress = await _RustVideoBackend.pollYoloTrainingProgress();
      final logText = await _readTrainingLogTail(_activeTrainingLogPath);
      if (!mounted || !_trainingRunning) return;
      if (progress == null) {
        setState(() => _trainingLogText = logText);
        return;
      }
      setState(() {
        _trainingLogText = logText;
        _currentEpoch = progress.currentEpoch;
        _trainingMetrics = _TrainingMetrics(
          trainLoss: progress.trainLoss,
          valLoss: progress.valLoss,
          map50: progress.map50,
          map5095: progress.map5095,
          precision: progress.precision,
          recall: progress.recall,
          lr: progress.lr,
        );
        final metrics = _trainingMetrics;
        if (metrics != null && progress.currentEpoch > 0) {
          final nextPoints = [..._trainingMetricPoints];
          if (nextPoints.isEmpty ||
              nextPoints.last.epoch != progress.currentEpoch) {
            nextPoints.add(
              _TrainingMetricPoint(
                epoch: progress.currentEpoch,
                timestamp: DateTime.now(),
                metrics: metrics,
              ),
            );
          } else {
            nextPoints[nextPoints.length - 1] = _TrainingMetricPoint(
              epoch: progress.currentEpoch,
              timestamp: DateTime.now(),
              metrics: metrics,
            );
          }
          _trainingMetricPoints = nextPoints.take(500).toList();
        }
        if (progress.status == 'stopping') {
          _trainingStopping = true;
          _showTrainingTerminal = true;
        }
        if (progress.status == 'completed' ||
            progress.status == 'stopped' ||
            progress.status.startsWith('error')) {
          _trainingRunning = false;
          _trainingStopping = false;
          _trainingInterrupted = progress.status == 'stopped';
          if (progress.status.startsWith('error')) {
            _showTrainingTerminal = true;
          }
          _trainingTimer?.cancel();
        }
      });
    } on Object {
      final logText = await _readTrainingLogTail(_activeTrainingLogPath);
      if (mounted && _trainingRunning) {
        setState(() => _trainingLogText = logText);
      }
    }
  }

  int _targetTrainingEpochs() {
    return _useResumeTraining
        ? _resumeInfo?.targetEpochs ?? _parameters['epochs']?.round() ?? 1
        : _parameters['epochs']?.round() ?? 1;
  }

  int _initialTrainingEpoch(int totalEpochs) {
    if (_trainingInterrupted && _currentEpoch > 0) {
      return _currentEpoch.clamp(1, totalEpochs).toInt();
    }
    if (_useResumeTraining) {
      return ((_resumeInfo?.completedEpochs ?? 0) + 1)
          .clamp(1, totalEpochs)
          .toInt();
    }
    return 1;
  }

  void _appendTrainingRecord(_TrainingHistoryAction action) {
    final entry = _TrainingHistoryEntry(
      action: action,
      timestamp: DateTime.now(),
      modelPath: _modelPath ?? '',
      datasetPath: _datasetPath ?? '',
      epoch: _currentEpoch,
      targetEpochs: _targetTrainingEpochs(),
      resume: _useResumeTraining || action == _TrainingHistoryAction.resume,
    );
    final next = [entry, ..._trainingHistory].take(40).toList();
    setState(() => _trainingHistory = next);
    _ConfigStore.saveTrainingHistory(_TrainingHistoryConfig(entries: next));
  }

  void _setModelPath(String? value) {
    setState(() => _modelPath = value);
    _selectDatasetFromCheckpoint(value);
    _refreshResumeInfo();
  }

  void _setParameter(String key, double value) {
    setState(() => _parameters[key] = value);
    if (key == 'epochs') {
      _refreshResumeInfo();
    }
  }

  void _refreshResumeInfo() {
    final modelPath = _modelPath;
    final info = modelPath == null ? null : _detectResumeInfo(modelPath);
    setState(() {
      _resumeInfo = info;
      if (info?.canResume == true) {
        _resumeEnabled = true;
      } else {
        _resumeEnabled = false;
      }
    });
  }

  void _selectDatasetFromCheckpoint(String? modelPath) {
    final dataYamlPath = _checkpointDataYamlPath(modelPath);
    if (dataYamlPath == null || !File(dataYamlPath).existsSync()) {
      return;
    }
    if (_datasetPath != null &&
        _pathKey(_datasetPath!) == _pathKey(dataYamlPath)) {
      return;
    }
    final summary = _DatasetSummary.fromYamlFile(dataYamlPath);
    setState(() {
      _datasetPath = dataYamlPath;
      _datasetSummary = summary;
      _parameters['cls_pw'] = summary.recommendedClsPw;
    });
  }

  String? _checkpointDataYamlPath(String? modelPath) {
    if (modelPath == null || _fileName(modelPath).toLowerCase() != 'last.pt') {
      return null;
    }
    final checkpoint = File(modelPath);
    if (!checkpoint.existsSync()) {
      return null;
    }
    final weightsDir = checkpoint.parent;
    final runDir = weightsDir.parent;
    if (weightsDir.path == runDir.path ||
        _fileName(weightsDir.path).toLowerCase() != 'weights') {
      return null;
    }
    return _readTrainingDataPath(File('${runDir.path}\\args.yaml'), runDir.path);
  }

  _ResumeTrainingInfo? _detectResumeInfo(String modelPath) {
    if (_fileName(modelPath).toLowerCase() != 'last.pt') {
      return null;
    }
    final checkpoint = File(modelPath);
    if (!checkpoint.existsSync()) {
      return _ResumeTrainingInfo.unavailable(t('train.resumeNoCheckpoint'));
    }
    final weightsDir = checkpoint.parent;
    final runDir = weightsDir.parent;
    if (weightsDir.path == runDir.path ||
        _fileName(weightsDir.path).toLowerCase() != 'weights') {
      return _ResumeTrainingInfo.unavailable(t('train.resumeInvalidLayout'));
    }
    final resultsCsv = File('${runDir.path}\\results.csv');
    final argsYaml = File('${runDir.path}\\args.yaml');
    if (!resultsCsv.existsSync()) {
      return _ResumeTrainingInfo.unavailable(t('train.resumeNoResults'));
    }
    final targetEpochs =
        _readTrainingEpochs(argsYaml) ?? _parameters['epochs']?.round() ?? 0;
    final lastEpoch = _readLastResultEpoch(resultsCsv);
    if (targetEpochs <= 0 || lastEpoch == null) {
      return _ResumeTrainingInfo.unavailable(t('train.resumeUnknownProgress'));
    }
    final selectedData = _datasetPath;
    final recordedData = _readTrainingDataPath(argsYaml, runDir.path);
    final dataMatches = selectedData == null ||
        recordedData == null ||
        _pathKey(selectedData) == _pathKey(recordedData);
    if (!dataMatches) {
      return _ResumeTrainingInfo.unavailable(t('train.resumeDataMismatch'));
    }
    final completedEpochs = lastEpoch + 1;
    if (completedEpochs >= targetEpochs) {
      return _ResumeTrainingInfo.unavailable(t('train.resumeAlreadyDone'));
    }
    return _ResumeTrainingInfo.available(
      runDir: runDir.path,
      argsPath: argsYaml.existsSync() ? argsYaml.path : null,
      resultsPath: resultsCsv.path,
      targetEpochs: targetEpochs,
      completedEpochs: completedEpochs,
    );
  }

  String _trainingExperimentName() {
    final datasetPath = _datasetPath;
    if (datasetPath == null || datasetPath.isEmpty) {
      return 'train_${DateTime.now().millisecondsSinceEpoch}';
    }
    final datasetName = _fileName(File(datasetPath).parent.path);
    final sanitized = datasetName
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .trim();
    return sanitized.isEmpty
        ? 'train_${DateTime.now().millisecondsSinceEpoch}'
        : sanitized;
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Row(
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
                              onTap: () => _loadModelOptions(),
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
                              onChanged: _setModelPath,
                              decoration: InputDecoration(
                                labelText: t('path.model'),
                                isDense: true,
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _datasetLoading ? null : _chooseModel,
                            icon: const Icon(Icons.folder_open),
                            label: Text(t('train.chooseModel')),
                          ),
                          OutlinedButton.icon(
                            onPressed: _datasetLoading ? null : _chooseDataset,
                            icon: const Icon(Icons.dataset_outlined),
                            label: Text(t('train.chooseDataset')),
                          ),
                          FilledButton.icon(
                            onPressed: _datasetLoading
                                ? null
                                : _trainingStopping
                                ? null
                                : _trainingRunning ||
                                      (_validYoloModel &&
                                          _datasetSummary != null)
                                ? _toggleTraining
                                : null,
                            icon: Icon(
                              _trainingStopping
                                  ? Icons.hourglass_empty
                                  : _trainingRunning
                                  ? Icons.stop
                                  : Icons.play_arrow,
                            ),
                            label: Text(
                              _trainingStopping
                                  ? t('train.stopping')
                                  : _trainingRunning
                                  ? t('train.stop')
                                  : _showContinueTraining
                                  ? t('train.continueTraining')
                                  : t('train.start'),
                            ),
                          ),
                          if (_resumeInfo != null)
                            Tooltip(
                              message: _resumeInfo!.statusText,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(t('train.resume')),
                                  Switch(
                                    value: _resumeEnabled && _canResumeTraining,
                                    onChanged: _canResumeTraining
                                        ? (value) {
                                            setState(
                                              () => _resumeEnabled = value,
                                            );
                                          }
                                        : null,
                                  ),
                                ],
                              ),
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
                      if (_activeRunDir != null)
                        Text(
                          _activeRunDir!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (_resumeInfo != null)
                        Text(
                          _resumeInfo!.statusText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      Text(
                        _trainingRunning
                            ? '${t('train.currentEpoch')}: $_currentEpoch / ${_targetTrainingEpochs()}'
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
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  10,
                                  12,
                                  4,
                                ),
                                child: Row(
                                  children: [
                                    SegmentedButton<bool>(
                                      segments: [
                                        ButtonSegment(
                                          value: false,
                                          icon: const Icon(
                                            Icons.show_chart,
                                            size: 18,
                                          ),
                                          label: Text(t('train.chart')),
                                        ),
                                        ButtonSegment(
                                          value: true,
                                          icon: const Icon(
                                            Icons.terminal,
                                            size: 18,
                                          ),
                                          label: Text(t('train.terminal')),
                                        ),
                                      ],
                                      selected: {_showTrainingTerminal},
                                      onSelectionChanged: (value) {
                                        setState(
                                          () => _showTrainingTerminal =
                                              value.first,
                                        );
                                      },
                                    ),
                                    const Spacer(),
                                    if (_activeTrainingLogPath != null)
                                      Flexible(
                                        child: Text(
                                          _activeTrainingLogPath!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: _showTrainingTerminal
                                    ? _TrainingTerminalPanel(
                                        text: _trainingLogText,
                                      )
                                    : _trainingRunning &&
                                          _trainingMetrics != null
                                    ? _TrainingProgressPanel(
                                        metrics: _trainingMetrics!,
                                        points: _trainingMetricPoints,
                                      )
                                    : Center(
                                        child: Text(
                                          t('train.chartPlaceholder'),
                                        ),
                                      ),
                              ),
                            ],
                          ),
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
                    border: Border(
                      left: BorderSide(color: _borderColor(context)),
                    ),
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
                            onChanged: _setParameter,
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
          if (_datasetLoading)
            Positioned.fill(
              child: _ImportBlockingOverlay(message: t('train.loadingDataset')),
            ),
        ],
      ),
    );
  }
}

class _TrainingMetrics {
  const _TrainingMetrics({
    this.trainLoss,
    this.valLoss,
    this.map50,
    this.map5095,
    this.precision,
    this.recall,
    this.lr,
  });

  final double? trainLoss;
  final double? valLoss;
  final double? map50;
  final double? map5095;
  final double? precision;
  final double? recall;
  final double? lr;
}

File _logFileForDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return File('${_ConfigStore.logsDirectory.path}\\$y-$m-$d.log');
}

Future<String> _readTrainingLogTail(String? activePath) async {
  final file = activePath == null ? _latestLogFile() : File(activePath);
  if (file == null || !await file.exists()) {
    return '';
  }
  try {
    final text = await file.readAsString();
    const maxChars = 30 * 1024;
    if (text.length <= maxChars) {
      return text;
    }
    return text.substring(text.length - maxChars);
  } on Object catch (error) {
    return '${t('logs.readFailed')}: $error';
  }
}

File? _latestLogFile() {
  final directory = _ConfigStore.logsDirectory;
  if (!directory.existsSync()) {
    return null;
  }
  final files = _logFilesByDate();
  if (files.isEmpty) {
    return null;
  }
  return files.first;
}

List<File> _logFilesByDate() {
  final directory = _ConfigStore.logsDirectory;
  if (!directory.existsSync()) {
    return const [];
  }
  final files = directory
      .listSync()
      .whereType<File>()
      .where((file) => file.path.toLowerCase().endsWith('.log'))
      .toList();
  files.sort((a, b) {
    final aTime = a.lastModifiedSync();
    final bTime = b.lastModifiedSync();
    return bTime.compareTo(aTime);
  });
  return files;
}

void _openLogsFolder(Directory directory) {
  directory.createSync(recursive: true);
  if (Platform.isWindows) {
    Process.start('explorer.exe', [directory.path])
        .then((_) {})
        .catchError((_) {});
  }
}

class _TrainingMetricPoint {
  const _TrainingMetricPoint({
    required this.epoch,
    required this.timestamp,
    required this.metrics,
  });

  final int epoch;
  final DateTime timestamp;
  final _TrainingMetrics metrics;
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
                    Text('${t('train.testCount')}: ${summary.testCount}'),
                    Text(
                      '${t('train.imbalanceRatio')}: ${summary.imbalanceRatio.toStringAsFixed(2)}',
                    ),
                    Text(
                      '${t('train.clsPwAuto')}: ${summary.recommendedClsPw.toStringAsFixed(2)}',
                    ),
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

    final integerLike = {'epochs', 'imgsz', 'workers'}.contains(name);
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
    required this.testCount,
    required this.classCounts,
    required this.recommendedClsPw,
    required this.imbalanceRatio,
  });

  final List<String> classes;
  final int trainCount;
  final int valCount;
  final int testCount;
  final List<int> classCounts;
  final double recommendedClsPw;
  final double imbalanceRatio;

  static _DatasetSummary fromYamlFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      return const _DatasetSummary(
        classes: [],
        trainCount: 0,
        valCount: 0,
        testCount: 0,
        classCounts: [],
        recommendedClsPw: 0,
        imbalanceRatio: 0,
      );
    }
    final parsed = _parseImportYoloDataYaml(path);
    final trainImages = _datasetImagesForSplit(parsed, 'train');
    final valImages = _datasetImagesForSplit(parsed, 'val');
    final testImages = _datasetImagesForSplit(parsed, 'test');
    final classCounts = _countYoloClassLabels(
      trainImages,
      math.max(parsed.names.length, 0),
    );
    final imbalanceRatio = _classImbalanceRatio(classCounts);
    return _DatasetSummary(
      classes: parsed.names,
      trainCount: trainImages.length,
      valCount: valImages.length,
      testCount: testImages.length,
      classCounts: classCounts,
      recommendedClsPw: _recommendedClsPw(
        classCount: parsed.names.length,
        classCounts: classCounts,
      ),
      imbalanceRatio: imbalanceRatio,
    );
  }
}

class _DatasetSummaryRequest {
  const _DatasetSummaryRequest({required this.path, required this.sendPort});

  final String path;
  final SendPort sendPort;
}

Future<_DatasetSummary> _loadDatasetSummaryInBackground(String path) async {
  final receivePort = ReceivePort();
  try {
    await Isolate.spawn<_DatasetSummaryRequest>(
      _datasetSummaryIsolateEntry,
      _DatasetSummaryRequest(path: path, sendPort: receivePort.sendPort),
      debugName: 'rustlabel_dataset_summary',
    );
    final message = await receivePort.first;
    if (message is _DatasetSummary) {
      return message;
    }
    if (message is String) {
      throw StateError(message);
    }
    throw StateError('Unexpected dataset summary response: $message');
  } finally {
    receivePort.close();
  }
}

@pragma('vm:entry-point')
void _datasetSummaryIsolateEntry(_DatasetSummaryRequest request) {
  try {
    request.sendPort.send(_DatasetSummary.fromYamlFile(request.path));
  } on Object catch (error, stackTrace) {
    request.sendPort.send('$error\n$stackTrace');
  }
}

class _ResumeTrainingInfo {
  const _ResumeTrainingInfo._({
    required this.canResume,
    required this.statusText,
    this.runDir,
    this.argsPath,
    this.resultsPath,
    this.targetEpochs,
    this.completedEpochs,
  });

  factory _ResumeTrainingInfo.available({
    required String runDir,
    required String? argsPath,
    required String resultsPath,
    required int targetEpochs,
    required int completedEpochs,
  }) {
    return _ResumeTrainingInfo._(
      canResume: true,
      runDir: runDir,
      argsPath: argsPath,
      resultsPath: resultsPath,
      targetEpochs: targetEpochs,
      completedEpochs: completedEpochs,
      statusText:
          '${t('train.resumeAvailable')}: $completedEpochs / $targetEpochs',
    );
  }

  factory _ResumeTrainingInfo.unavailable(String reason) {
    return _ResumeTrainingInfo._(canResume: false, statusText: reason);
  }

  final bool canResume;
  final String statusText;
  final String? runDir;
  final String? argsPath;
  final String? resultsPath;
  final int? targetEpochs;
  final int? completedEpochs;
}

List<String> _datasetImagesForSplit(_ParsedYoloData parsed, String split) {
  final result = <String>[];
  for (final source in parsed.splitSources[split] ?? const <String>[]) {
    result.addAll(_imagePathsFromDatasetSource(parsed.rootPath, source));
  }
  return _dedupePaths(result);
}

List<int> _countYoloClassLabels(List<String> imagePaths, int classCount) {
  final counts = List<int>.filled(math.max(classCount, 0), 0, growable: true);
  for (final imagePath in imagePaths) {
    final label = File(_labelPathForImagePath(imagePath));
    if (!label.existsSync()) {
      continue;
    }
    for (final rawLine in label.readAsLinesSync()) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      final classIndex = int.tryParse(line.split(RegExp(r'\s+')).first);
      if (classIndex == null || classIndex < 0) {
        continue;
      }
      while (counts.length <= classIndex) {
        counts.add(0);
      }
      counts[classIndex] += 1;
    }
  }
  return counts;
}

double _classImbalanceRatio(List<int> counts) {
  final nonZero = counts.where((count) => count > 0).toList();
  if (nonZero.length <= 1) {
    return 0;
  }
  nonZero.sort();
  return nonZero.last / nonZero.first;
}

double _recommendedClsPw({
  required int classCount,
  required List<int> classCounts,
}) {
  if (classCount <= 1) {
    return 0;
  }
  final nonZero = classCounts.where((count) => count > 0).toList();
  if (nonZero.isEmpty) {
    return 0.5;
  }
  if (nonZero.length < classCount) {
    return 1.0;
  }
  final ratio = _classImbalanceRatio(classCounts);
  if (ratio < 2) return 0;
  if (ratio < 5) return 0.25;
  if (ratio < 10) return 0.50;
  if (ratio < 20) return 0.75;
  return 1.0;
}

String _trainingActionLabel(_TrainingHistoryAction action) {
  return switch (action) {
    _TrainingHistoryAction.start => t('train.historyStart'),
    _TrainingHistoryAction.resume => t('train.historyResume'),
    _TrainingHistoryAction.stop => t('train.historyStop'),
  };
}

String _formatTrainingHistoryTime(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}:${twoDigits(value.second)}';
}

int? _readTrainingEpochs(File argsYaml) {
  if (!argsYaml.existsSync()) {
    return null;
  }
  final value = _importYamlScalar(argsYaml.readAsLinesSync(), 'epochs');
  return value == null ? null : int.tryParse(value);
}

String? _readTrainingDataPath(File argsYaml, String runDir) {
  if (!argsYaml.existsSync()) {
    return null;
  }
  final value = _importYamlScalar(argsYaml.readAsLinesSync(), 'data');
  if (value == null || value.isEmpty) {
    return null;
  }
  return _resolveImportDatasetPath(runDir, value);
}

int? _readLastResultEpoch(File resultsCsv) {
  if (!resultsCsv.existsSync()) {
    return null;
  }
  int? lastEpoch;
  for (final rawLine in resultsCsv.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty || line.toLowerCase().startsWith('epoch')) {
      continue;
    }
    final first = line.split(',').first.trim();
    final parsed = double.tryParse(first);
    if (parsed != null) {
      lastEpoch = parsed.round();
    }
  }
  return lastEpoch;
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
    'workers' => 0,
    _ => 0,
  };
}

double _maxForParameter(String name) {
  return switch (name) {
    'epochs' => 500,
    'imgsz' => 1280,
    'lr0' => 0.1,
    'cls_pw' => 1,
    'momentum' => 0.99,
    'workers' => 16,
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
    'epochs' || 'imgsz' || 'workers' => value.round().toString(),
    'lr0' => value.toStringAsFixed(4),
    'cls_pw' => value.toStringAsFixed(2),
    'momentum' => value.toStringAsFixed(3),
    _ => value.toStringAsFixed(2),
  };
}

String _parameterHelp(String name) {
  final key = 'train.param.$name';
  return t(key);
}

class _TrainingProgressPanel extends StatelessWidget {
  const _TrainingProgressPanel({required this.metrics, required this.points});

  final _TrainingMetrics metrics;
  final List<_TrainingMetricPoint> points;

  @override
  Widget build(BuildContext context) {
    final seriesList = _buildTrainingSeries(points);
    if (seriesList.isEmpty) {
      return Center(child: Text(t('train.chartPlaceholder')));
    }

    final minX = seriesList
        .expand((s) => s.spots)
        .map((s) => s.x)
        .fold<double>(double.infinity, math.min);
    final maxX = seriesList
        .expand((s) => s.spots)
        .map((s) => s.x)
        .fold<double>(double.negativeInfinity, math.max);
    final epochInterval = _trainingChartEpochInterval(points);

    // Group series into separate chart panels
    final lossGroup = <_TrainingChartSeries>[];
    final mapGroup = <_TrainingChartSeries>[];
    final prGroup = <_TrainingChartSeries>[];
    final lrGroup = <_TrainingChartSeries>[];

    for (final s in seriesList) {
      if (s.label == 'Train Loss' || s.label == 'Val Loss') {
        lossGroup.add(s);
      } else if (s.label.contains('mAP')) {
        mapGroup.add(s);
      } else if (s.label == 'Precision' || s.label == 'Recall') {
        prGroup.add(s);
      } else if (s.label == 'LR') {
        lrGroup.add(s);
      }
    }

    List<Widget> chartPanels = [];
    if (lossGroup.isNotEmpty) {
      chartPanels.add(_metricChart(
        context, t('train.chartLoss'), lossGroup, minX, maxX, epochInterval,
      ));
    }
    if (mapGroup.isNotEmpty) {
      chartPanels.add(_metricChart(
        context, t('train.chartMap'), mapGroup, minX, maxX, epochInterval,
      ));
    }
    if (prGroup.isNotEmpty) {
      chartPanels.add(_metricChart(
        context, t('train.chartPr'), prGroup, minX, maxX, epochInterval,
      ));
    }
    if (lrGroup.isNotEmpty) {
      chartPanels.add(_metricChart(
        context, t('train.chartLr'), lrGroup, minX, maxX, epochInterval,
      ));
    }

    final legendItems = <(String, double?, Color)>[
      if (lossGroup.any((s) => s.label == 'Train Loss'))
        ('Train Loss', metrics.trainLoss, const Color(0xFF2563EB)),
      if (lossGroup.any((s) => s.label == 'Val Loss'))
        ('Val Loss', metrics.valLoss, const Color(0xFFDC2626)),
      if (mapGroup.any((s) => s.label == 'mAP@0.5'))
        ('mAP@0.5', metrics.map50, const Color(0xFF16A34A)),
      if (mapGroup.any((s) => s.label == 'mAP@0.5:0.95'))
        ('mAP@0.5:0.95', metrics.map5095, const Color(0xFF9333EA)),
      if (prGroup.any((s) => s.label == 'Precision'))
        ('Precision', metrics.precision, const Color(0xFFEA580C)),
      if (prGroup.any((s) => s.label == 'Recall'))
        ('Recall', metrics.recall, const Color(0xFF0891B2)),
      if (lrGroup.isNotEmpty)
        ('LR', metrics.lr, const Color(0xFF64748B)),
    ].where((e) => e.$2 != null).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              children: chartPanels,
            ),
          ),
          if (legendItems.isNotEmpty) ...[
            const SizedBox(width: 12),
            SizedBox(
              width: 160,
              child: ListView(
                children: [
                  for (final (label, value, color) in legendItems)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Text(
                            value!.toStringAsFixed(4),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Widget _metricChart(
  BuildContext context,
  String title,
  List<_TrainingChartSeries> group,
  double minX,
  double maxX,
  double? epochInterval,
) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 160,
          child: LineChart(
            LineChartData(
              minX: minX,
              maxX: maxX,
              minY: 0,
              maxY: _trainingChartMaxY(group),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: _borderColor(context),
                  strokeWidth: 1,
                ),
                getDrawingVerticalLine: (_) => FlLine(
                  color: _borderColor(context),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: _borderColor(context)),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: epochInterval,
                    getTitlesWidget: (value, meta) => Text(
                      value.toInt().toString(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 38,
                    getTitlesWidget: (value, meta) => Text(
                      value.toStringAsFixed(value >= 1 ? 1 : 2),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
              lineBarsData: [
                for (final item in group)
                  LineChartBarData(
                    spots: item.spots,
                    color: item.color,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    isCurved: true,
                  ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => [
                    for (final spot in spots)
                      LineTooltipItem(
                        '${group[spot.barIndex].label}  '
                        '${spot.y.toStringAsFixed(4)}',
                        TextStyle(color: group[spot.barIndex].color),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _TrainingTerminalPanel extends StatelessWidget {
  const _TrainingTerminalPanel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final content = text.trim().isEmpty ? t('train.terminalPlaceholder') : text;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: _isDarkMode(context) ? const Color(0xFF090515) : Colors.black,
      child: Scrollbar(
        child: SingleChildScrollView(
          reverse: true,
          child: SelectableText(
            content,
            style: const TextStyle(
              color: Color(0xFFE5E7EB),
              fontFamily: 'Consolas',
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }
}

class _TrainingChartSeries {
  const _TrainingChartSeries({
    required this.label,
    required this.color,
    required this.spots,
  });

  final String label;
  final Color color;
  final List<FlSpot> spots;
}

List<_TrainingChartSeries> _buildTrainingSeries(
  List<_TrainingMetricPoint> points,
) {
  List<FlSpot> spotsFor(double? Function(_TrainingMetrics metrics) getter) {
    return [
      for (final point in points)
        if (getter(point.metrics) != null)
          FlSpot(point.epoch.toDouble(), getter(point.metrics)!),
    ];
  }

  return [
    _TrainingChartSeries(
      label: 'Train Loss',
      color: const Color(0xFF2563EB),
      spots: spotsFor((metrics) => metrics.trainLoss),
    ),
    _TrainingChartSeries(
      label: 'Val Loss',
      color: const Color(0xFFDC2626),
      spots: spotsFor((metrics) => metrics.valLoss),
    ),
    _TrainingChartSeries(
      label: 'mAP@0.5',
      color: const Color(0xFF16A34A),
      spots: spotsFor((metrics) => metrics.map50),
    ),
    _TrainingChartSeries(
      label: 'mAP@0.5:0.95',
      color: const Color(0xFF9333EA),
      spots: spotsFor((metrics) => metrics.map5095),
    ),
    _TrainingChartSeries(
      label: 'Precision',
      color: const Color(0xFFEA580C),
      spots: spotsFor((metrics) => metrics.precision),
    ),
    _TrainingChartSeries(
      label: 'Recall',
      color: const Color(0xFF0891B2),
      spots: spotsFor((metrics) => metrics.recall),
    ),
    _TrainingChartSeries(
      label: 'LR',
      color: const Color(0xFF64748B),
      spots: spotsFor((metrics) => metrics.lr),
    ),
  ].where((series) => series.spots.isNotEmpty).toList();
}

double _trainingChartMaxY(List<_TrainingChartSeries> series) {
  final maxValue = series
      .expand((item) => item.spots)
      .map((spot) => spot.y)
      .fold<double>(0, math.max);
  if (maxValue <= 0) {
    return 1;
  }
  return maxValue * 1.15;
}

double _trainingChartEpochInterval(List<_TrainingMetricPoint> points) {
  if (points.length <= 1) {
    return 1;
  }
  final minEpoch = points.map((point) => point.epoch).reduce(math.min);
  final maxEpoch = points.map((point) => point.epoch).reduce(math.max);
  return math.max(1, ((maxEpoch - minEpoch) / 6).ceil()).toDouble();
}
