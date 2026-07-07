// ignore_for_file: file_names

part of '../main.dart';

/// 训练页面，提供 models 文件夹 YOLO PT 选择、data.yaml 概览和超参数编辑。
/// Training page with YOLO PT selection from models/, data.yaml summary, and parameters.
class _TrainPage extends StatefulWidget {
  const _TrainPage({super.key, required this.settings});

  final _AppSettings settings;

  @override
  State<_TrainPage> createState() => _TrainPageState();
}

class _TrainPageState extends State<_TrainPage> {
  final TextEditingController _datasetPathController = TextEditingController();
  final Map<String, double> _parameters = Map<String, double>.from(
    _defaultTrainingParameters,
  );
  final Map<String, String> _stringParameters = Map<String, String>.from(
    _defaultTrainingStringParameters,
  );

  Timer? _hideTimer;
  Timer? _trainingTimer;
  bool _parameterPanelVisible = true;
  bool _trainingRunning = false;
  bool _trainingStopping = false;
  bool _trainingInterrupted = false;
  int _currentEpoch = 0;
  String? _activeRunDir;
  _TrainingMetrics? _trainingMetrics;
  _TrainingResourceUsage _resourceUsage = const _TrainingResourceUsage();
  final Map<String, int> _chartColors = {
    'Train Loss': 0xFF2563EB,
    'Val Loss': 0xFFDC2626,
    'mAP@0.5': 0xFF16A34A,
    'mAP@0.5:0.95': 0xFF9333EA,
    'Precision': 0xFFEA580C,
    'Recall': 0xFF0891B2,
    'LR': 0xFF64748B,
  };
  List<_TrainingMetricPoint> _trainingMetricPoints = const [];
  bool _showTrainingTerminal = false;
  String _trainingLogText = '';
  String? _modelPath;
  String? _datasetPath;
  _DatasetSummary? _datasetSummary;
  List<String> _modelOptions = const [];
  List<_TrainingDeviceOption> _deviceOptions = const [
    _TrainingDeviceOption(id: 'cpu', label: 'CPU'),
  ];
  Set<String> _selectedDeviceIds = const {'cpu'};
  _YoloExportSettings _exportSettings = const _YoloExportSettings();
  bool _exportingModel = false;
  bool _manualDeviceSelection = false;
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
    return ids.join(',');
  }

  @override
  void initState() {
    super.initState();
    _trainingHistory = _ConfigStore.loadTrainingHistory().entries;
    unawaited(_loadDeviceOptions());
    _loadModelOptions();
    _scheduleHide();
    _restorePreferences();
  }

  @override
  void didUpdateWidget(covariant _TrainPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.pythonPath.trim() !=
        widget.settings.pythonPath.trim()) {
      unawaited(_loadDeviceOptions());
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _trainingTimer?.cancel();
    _datasetPathController.dispose();
    super.dispose();
  }

  void _loadModelOptions({bool preserveSelection = true}) {
    final previous = _modelPath;
    setState(() {
      final discovered = _modelsDirectoryCandidates().expand((directory) {
        if (!directory.existsSync()) {
          return const <String>[];
        }
        return directory
            .listSync()
            .whereType<File>()
            .map((file) => file.path)
            .where(_isSupportedYoloPtModel);
      });
      _modelOptions = _dedupeModelOptions(discovered, preferredPath: previous);
      if (preserveSelection &&
          previous != null &&
          _modelOptions.any((path) => _pathKey(path) == _pathKey(previous))) {
        _modelPath = _matchingModelOption(previous);
      } else {
        _modelPath = _modelOptions.isEmpty ? null : _modelOptions.first;
      }
    });
    _log(
      'TRAIN',
      'Model options loaded: count=${_modelOptions.length}, selected=${_modelPath == null ? '-' : _fileName(_modelPath!)}',
      level: _LogLevel.debug,
    );
    _refreshResumeInfo();
  }

  List<String> _dedupeModelOptions(
    Iterable<String> paths, {
    String? preferredPath,
  }) {
    final byKey = <String, String>{};
    for (final path in paths) {
      if (path.trim().isEmpty) {
        continue;
      }
      byKey.putIfAbsent(_pathKey(path), () => path);
    }
    if (preferredPath != null &&
        preferredPath.trim().isNotEmpty &&
        File(preferredPath).existsSync()) {
      byKey[_pathKey(preferredPath)] = preferredPath;
    }
    return byKey.values.toList()..sort(_compareModelPaths);
  }

  int _compareModelPaths(String left, String right) {
    final leftOrder = _yoloModelSortOrder(left);
    final rightOrder = _yoloModelSortOrder(right);
    final order = leftOrder.compareTo(rightOrder);
    return order == 0 ? _naturalPathCompare(left, right) : order;
  }

  String? _matchingModelOption(String path, [Iterable<String>? options]) {
    final key = _pathKey(path);
    for (final option in options ?? _modelOptions) {
      if (_pathKey(option) == key) {
        return option;
      }
    }
    return null;
  }

  String? _modelDropdownValue([Iterable<String>? options]) {
    final path = _modelPath;
    if (path == null) {
      return null;
    }
    return _matchingModelOption(path, options);
  }

  void _restorePreferences() {
    final prefs = _ConfigStore.loadTrainingPreferences();
    if (prefs.chartColors.isNotEmpty) {
      _chartColors.addAll(prefs.chartColors);
    }
    setState(() {
      if (prefs.parameters.isNotEmpty) {
        _parameters.addAll(prefs.parameters);
      }
      if (prefs.stringParameters.isNotEmpty) {
        _stringParameters.addAll(prefs.stringParameters);
      }
      _batchMode = _BatchMode
          .values[prefs.batchModeIndex.clamp(0, _BatchMode.values.length - 1)];
      _batchSize = prefs.batchSize;
      _batchRatio = prefs.batchRatio;
      _ampEnabled = prefs.ampEnabled;
      _exportSettings = prefs.exportSettings;
      _manualDeviceSelection = prefs.manualDeviceSelection;
      if (_manualDeviceSelection && prefs.selectedDeviceIds.isNotEmpty) {
        _selectedDeviceIds = prefs.selectedDeviceIds.toSet();
      }
      if (prefs.modelPath != null && File(prefs.modelPath!).existsSync()) {
        _modelOptions = _dedupeModelOptions(
          _modelOptions,
          preferredPath: prefs.modelPath,
        );
        _modelPath = _matchingModelOption(prefs.modelPath!) ?? prefs.modelPath;
      }
      if (prefs.datasetPath != null && File(prefs.datasetPath!).existsSync()) {
        _datasetPath = prefs.datasetPath;
        _datasetPathController.text = prefs.datasetPath!;
        _datasetSummary = _DatasetSummary.fromYamlFile(prefs.datasetPath!);
      }
    });
  }

  void _savePreferences() {
    final prefs = _TrainingPreferences(
      modelPath: _modelPath,
      datasetPath: _datasetPath,
      parameters: Map<String, double>.from(_parameters),
      stringParameters: Map<String, String>.from(_stringParameters),
      batchModeIndex: _batchMode.index,
      batchSize: _batchSize,
      batchRatio: _batchRatio,
      ampEnabled: _ampEnabled,
      selectedDeviceIds: _selectedDeviceIds.toList(),
      manualDeviceSelection: _manualDeviceSelection,
      chartColors: Map<String, int>.from(_chartColors),
      exportSettings: _exportSettings,
    );
    _ConfigStore.saveTrainingPreferences(prefs);
  }

  void _resetParameters() {
    setState(() {
      _parameters
        ..clear()
        ..addAll(_defaultTrainingParameters);
      _stringParameters
        ..clear()
        ..addAll(_defaultTrainingStringParameters);
      _batchMode = _BatchMode.fixed;
      _batchSize = 16;
      _batchRatio = 0.70;
      _ampEnabled = false;
      _manualDeviceSelection = false;
      _selectedDeviceIds = _autoTrainingDeviceSelection();
    });
    _savePreferences();
  }

  Future<void> _setChartColor(String key) async {
    final current = Color(_chartColors[key] ?? 0xFF2563EB);
    final selected = await _showWheelColorDialog(
      context: context,
      initialColor: current,
      title: key,
      constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
    );
    if (selected == null) {
      return;
    }
    if (mounted && selected.toARGB32() != current.toARGB32()) {
      setState(() => _chartColors[key] = selected.toARGB32());
      _savePreferences();
    }
  }

  Future<void> _loadDeviceOptions() async {
    if (_resolvePythonExecutable(widget.settings.pythonPath.trim()) == null) {
      if (mounted) {
        setState(() {
          _deviceOptions = const [
            _TrainingDeviceOption(id: 'cpu', label: 'CPU'),
          ];
          _selectedDeviceIds = const {'cpu'};
        });
      }
      return;
    }
    final devices = await _detectNvidiaDevices();
    devices.sort((a, b) => _naturalCompare(a.id, b.id));
    if (!mounted) {
      return;
    }
    setState(() {
      if (devices.isEmpty) {
        _deviceOptions = const [_TrainingDeviceOption(id: 'cpu', label: 'CPU')];
      } else {
        _deviceOptions = [
          ...devices,
          const _TrainingDeviceOption(id: 'cpu', label: 'CPU'),
        ];
      }
      _selectedDeviceIds = _manualDeviceSelection
          ? _normalizeTrainingDeviceSelection(_selectedDeviceIds)
          : _autoTrainingDeviceSelection();
    });
  }

  Set<String> _autoTrainingDeviceSelection() {
    final firstGpu = _deviceOptions
        .where((option) => option.id != 'cpu')
        .map((option) => option.id)
        .firstOrNullValue;
    return firstGpu == null ? const {'cpu'} : {firstGpu};
  }

  Set<String> _normalizeTrainingDeviceSelection(Set<String> selectedIds) {
    final availableIds = _deviceOptions.map((option) => option.id).toSet();
    final validIds = selectedIds.intersection(availableIds);
    if (validIds.isEmpty) {
      return _autoTrainingDeviceSelection();
    }
    if (validIds.contains('cpu')) {
      return const {'cpu'};
    }
    return validIds;
  }

  List<Directory> _modelsDirectoryCandidates() {
    final current = Directory.current;
    return [
      _ConfigStore.defaultModelsDirectory,
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

  int _yoloModelSortOrder(String path) {
    final name = _fileName(path).toLowerCase().replaceAll('.pt', '');
    if (name == 'last' || name == 'best') return 999999;

    // Version order: v8 < 11 < 26
    int ver;
    if (name.contains('v8')) {
      ver = 0;
    } else if (name.contains('26')) {
      ver = 2;
    } else {
      ver = 1; // yolo11 (bare number)
    }

    // Size order: n < s < m < l < x
    // Size letter follows a digit (e.g. yolo11n, yolov8x-obb)
    final sizeMatch = RegExp(r'\d([nsmlx])(?:-|$)').firstMatch(name);
    final sizes = ['n', 's', 'm', 'l', 'x'];
    int sz = 5;
    if (sizeMatch != null) {
      sz = sizes.indexOf(sizeMatch.group(1)!);
      if (sz < 0) sz = 5;
    }

    // Task type: base(0) < seg(1) < obb(2) < cls(3) < pose(4)
    int task;
    if (name.contains('-seg')) {
      task = 1;
    } else if (name.contains('-obb')) {
      task = 2;
    } else if (name.contains('-cls')) {
      task = 3;
    } else if (name.contains('-pose')) {
      task = 4;
    } else {
      task = 0;
    }

    return ver * 1000 + sz * 100 + task;
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
    _log('TRAIN', 'Model selected: ${file.path}');
    setState(() {
      _modelOptions = _dedupeModelOptions(
        _modelOptions,
        preferredPath: file.path,
      );
      _modelPath = _matchingModelOption(file.path) ?? file.path;
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
    await _loadDatasetPath(file.path);
  }

  Future<void> _loadDatasetPath(String rawPath) async {
    if (_datasetLoading) {
      return;
    }
    final path = rawPath.trim();
    if (path.isEmpty) {
      return;
    }
    if (!File(path).existsSync()) {
      _log(
        'TRAIN',
        'Dataset path does not exist: $path',
        level: _LogLevel.warning,
      );
      _showWarning('${t('train.datasetLoadFailed')}: $path');
      return;
    }
    setState(() => _datasetLoading = true);
    try {
      _log('TRAIN', 'Dataset summary loading: $path');
      final summary = await _loadDatasetSummaryInBackground(path);
      if (!mounted) {
        return;
      }
      setState(() {
        _datasetPath = path;
        _datasetPathController.text = path;
        _datasetSummary = summary;
        _parameters['cls_pw'] = summary.recommendedClsPw;
      });
      _refreshResumeInfo();
      _savePreferences();
      _log(
        'TRAIN',
        'Dataset summary loaded: path=$path, classes=${summary.classes.length}, train=${summary.trainCount}, val=${summary.valCount}, test=${summary.testCount}, cls_pw=${summary.recommendedClsPw.toStringAsFixed(2)}, imbalance=${summary.imbalanceRatio.toStringAsFixed(2)}',
      );
    } on Object catch (error) {
      _log(
        'TRAIN',
        'Dataset summary failed: $path, error=$error',
        level: _LogLevel.error,
      );
      if (mounted) {
        _showWarning('${t('train.datasetLoadFailed')}: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _datasetLoading = false);
      }
    }
  }

  Future<void> _loadExportedDatasetAndStartTraining(String dataYamlPath) async {
    if (_trainingRunning) {
      _log(
        'TRAIN',
        'Export auto training skipped: training is already running',
        level: _LogLevel.warning,
      );
      return;
    }
    await _loadDatasetPath(dataYamlPath);
    if (!mounted) {
      return;
    }
    final selectedDataset = _datasetPath;
    if (selectedDataset == null ||
        _pathKey(selectedDataset) != _pathKey(dataYamlPath)) {
      _log(
        'TRAIN',
        'Export auto training skipped: exported dataset was not loaded: $dataYamlPath',
        level: _LogLevel.warning,
      );
      return;
    }
    final modelPath = await _showExportTrainingModelDialog();
    if (!mounted || modelPath == null) {
      _log(
        'TRAIN',
        'Export auto training cancelled before model confirmation',
        level: _LogLevel.info,
      );
      return;
    }
    setState(() {
      _modelOptions = _dedupeModelOptions(
        _modelOptions,
        preferredPath: modelPath,
      );
      _modelPath = _matchingModelOption(modelPath) ?? modelPath;
    });
    _refreshResumeInfo();
    _savePreferences();
    await _startTraining();
  }

  Future<String?> _showExportTrainingModelDialog() async {
    _loadModelOptions();
    var options = _dedupeModelOptions(_modelOptions, preferredPath: _modelPath);
    var selected = _modelDropdownValue(options) ?? options.firstOrNullValue;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> chooseModelFile() async {
              final file = await openFile(
                initialDirectory: _initialModelDirectory(),
                acceptedTypeGroups: const [
                  XTypeGroup(label: 'PyTorch model', extensions: ['pt']),
                ],
              );
              if (file == null) {
                return;
              }
              final nextOptions = _dedupeModelOptions(
                options,
                preferredPath: file.path,
              );
              setDialogState(() {
                options = nextOptions;
                selected =
                    _matchingModelOption(file.path, options) ?? file.path;
              });
            }

            return AlertDialog(
              title: Text(t('train.exportModelTitle')),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('train.exportModelMessage')),
                    const SizedBox(height: 12),
                    if (options.isEmpty)
                      Text(
                        t('train.noModels'),
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    else
                      DropdownButtonFormField<String>(
                        initialValue: selected,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: t('path.model'),
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          for (final path in options)
                            DropdownMenuItem<String>(
                              value: path,
                              child: Text(_fileName(path)),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setDialogState(() => selected = value);
                        },
                      ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: chooseModelFile,
                      icon: const Icon(Icons.folder_open_outlined),
                      label: Text(t('train.chooseModel')),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(t('action.cancel')),
                ),
                FilledButton(
                  onPressed: selected == null
                      ? null
                      : () => Navigator.of(dialogContext).pop(selected),
                  child: Text(t('train.confirmStart')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _toggleTrainingDevice(String id, bool selected) {
    setState(() {
      final next = {..._selectedDeviceIds};
      _manualDeviceSelection = true;
      if (id == 'cpu') {
        _selectedDeviceIds = const {'cpu'};
        return;
      }
      if (selected) {
        next.remove('cpu');
        next.add(id);
      } else {
        next.remove(id);
      }
      _selectedDeviceIds = next.isEmpty ? const {'cpu'} : next;
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
    if (_modelPath == null || _datasetPath == null) {
      _log(
        'TRAIN',
        'Training start blocked: modelPath=${_modelPath ?? '-'}, datasetPath=${_datasetPath ?? '-'}',
        level: _LogLevel.warning,
      );
      return;
    }
    final pythonPath = widget.settings.pythonPath;
    final outputPath = widget.settings.outputPath;
    if (pythonPath.isEmpty) {
      _log(
        'TRAIN',
        'Training start blocked: Python path is empty',
        level: _LogLevel.warning,
      );
      _showWarning(t('train.pythonNotConfigured'));
      return;
    }

    final totalEpochs = _targetTrainingEpochs();
    final continuing = _showContinueTraining;
    final nextEpoch = _initialTrainingEpoch(totalEpochs);
    final initialMetricPoints = continuing
        ? _initialTrainingMetricPoints()
        : const <_TrainingMetricPoint>[];
    final initialMetrics = initialMetricPoints.isEmpty
        ? null
        : initialMetricPoints.last.metrics;
    _trainingTimer?.cancel();
    _log(
      'TRAIN',
      'Starting training: model=${_fileName(_modelPath!)}, data=$_datasetPath, epochs=$totalEpochs, imgsz=${_parameters['imgsz']?.round() ?? 640}, batch=$_batchArgument, device=$_deviceArgument, workers=${_parameters['workers']?.round() ?? 4}, resume=$_useResumeTraining, amp=$_ampEnabled',
    );

    setState(() {
      _trainingRunning = true;
      _trainingStopping = false;
      _trainingInterrupted = false;
      _currentEpoch = nextEpoch;
      _trainingMetrics = initialMetrics;
      _resourceUsage = const _TrainingResourceUsage();
      _trainingMetricPoints = initialMetricPoints;
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
        projectDir: outputPath.isNotEmpty
            ? outputPath
            : '${Directory.current.path}\\runs',
        experimentName: _trainingExperimentName(),
        epochs: totalEpochs,
        imgsz: _parameters['imgsz']?.round() ?? 640,
        batch: _batchArgument,
        device: _deviceArgument,
        lr0: _parameters['lr0'] ?? 0.01,
        momentum: _parameters['momentum'] ?? 0.937,
        patience: _parameters['patience']?.round() ?? 100,
        hsvH: _parameters['hsv_h'] ?? 0.015,
        hsvS: _parameters['hsv_s'] ?? 0.25,
        hsvV: _parameters['hsv_v'] ?? 0.5,
        translate: _parameters['translate'] ?? 0.1,
        scale: _parameters['scale'] ?? 0.25,
        shear: _parameters['shear'] ?? 5,
        flipud: _parameters['flipud'] ?? 0,
        fliplr: _parameters['fliplr'] ?? 0,
        degrees: _parameters['degrees'] ?? 0,
        perspective: _parameters['perspective'] ?? 0,
        bgr: _parameters['bgr'] ?? 0,
        mosaic: _parameters['mosaic'] ?? 1,
        mixup: _parameters['mixup'] ?? 0,
        cutmix: _parameters['cutmix'] ?? 0,
        copyPaste: _parameters['copy_paste'] ?? 0,
        copyPasteMode: _stringParameters['copy_paste_mode'] ?? 'flip',
        autoAugment: _stringParameters['auto_augment'] ?? 'randaugment',
        erasing: _parameters['erasing'] ?? 0.4,
        workers: _parameters['workers']?.round() ?? 4,
        amp: _ampEnabled,
        resume: _useResumeTraining,
        clsPw: _parameters['cls_pw'] ?? 0,
      );
      final logText = await _readTrainingLogTail();
      if (mounted) {
        setState(() {
          _activeRunDir = runDir;
          _trainingLogText = logText;
        });
      }
    } on Object catch (e) {
      _log('TRAIN', 'Training start failed: $e', level: _LogLevel.error);
      final logText = await _readTrainingLogTail();
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
    _log(
      'TRAIN',
      'Stopping training at epoch $_currentEpoch',
      level: _LogLevel.warning,
    );
    _RustVideoBackend.stopYoloTraining();
    setState(() {
      _trainingStopping = true;
      _showTrainingTerminal = true;
    });
    _appendTrainingRecord(_TrainingHistoryAction.stop);
  }

  Future<void> _showExportSettingsDialog() async {
    final result = await showDialog<_YoloExportSettings>(
      context: context,
      builder: (context) => _YoloExportSettingsDialog(
        initial: _exportSettings,
        onManualExport: (settings) async {
          setState(() => _exportSettings = settings);
          _savePreferences();
          final modelPath = _modelPath;
          if (modelPath == null || !File(modelPath).existsSync()) {
            throw StateError(t('train.exportNoModel'));
          }
          return _runModelExport(
            modelPath: modelPath,
            settings: settings,
            trigger: 'manual',
          );
        },
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() => _exportSettings = result);
    _savePreferences();
  }

  Future<_ModelExportResult> _runModelExport({
    required String modelPath,
    required _YoloExportSettings settings,
    required String trigger,
  }) async {
    final pythonPath = widget.settings.pythonPath.trim();
    if (pythonPath.isEmpty) {
      throw StateError(t('train.pythonNotConfigured'));
    }
    final exportSettings = _settingsForModelExport(
      settings: settings,
      trigger: trigger,
    );
    setState(() => _exportingModel = true);
    _log(
      'TRAIN',
      'Model export started: trigger=$trigger, model=$modelPath, format=${exportSettings.format}, imgsz=${exportSettings.imgsz}, batch=${exportSettings.batch}, quantize=${exportSettings.quantize.isEmpty ? 'fp32' : exportSettings.quantize}, data=${_exportNeedsData(exportSettings) ? exportSettings.dataPath : ''}',
    );
    try {
      final result = await _RustVideoBackend.exportYoloModel(
        pythonPath: pythonPath,
        modelPath: modelPath,
        settings: exportSettings,
      );
      _log(
        'TRAIN',
        'Model export completed: format=${result.format}, output=${result.outputPath}',
      );
      if (result.stderr.trim().isNotEmpty) {
        _log(
          'TRAIN',
          'Model export stderr: ${result.stderr.trim()}',
          level: _LogLevel.debug,
        );
      }
      return result;
    } catch (error) {
      _log('TRAIN', 'Model export failed: $error', level: _LogLevel.error);
      rethrow;
    } finally {
      if (mounted) {
        setState(() => _exportingModel = false);
      }
    }
  }

  _YoloExportSettings _settingsForModelExport({
    required _YoloExportSettings settings,
    required String trigger,
  }) {
    if (trigger != 'after-training' || !_exportNeedsData(settings)) {
      return settings;
    }
    final trainingDataYaml = _datasetPath?.trim() ?? '';
    if (trainingDataYaml.isEmpty) {
      _log(
        'TRAIN',
        'Auto export INT8 has no training data.yaml; Ultralytics may require data for calibration.',
        level: _LogLevel.warning,
      );
      return settings.copyWith(dataPath: '');
    }
    return settings.copyWith(dataPath: trainingDataYaml);
  }

  bool _exportNeedsData(_YoloExportSettings settings) {
    final quantize = settings.quantize.trim().toLowerCase();
    return quantize == '8' || quantize == 'int8' || quantize == 'w8a8';
  }

  Future<void> _exportAfterTrainingIfNeeded() async {
    if (!_exportSettings.autoExportAfterTraining) {
      return;
    }
    final modelPath = _trainedModelForExport();
    if (modelPath == null) {
      _log(
        'TRAIN',
        'Auto export skipped: no trained model was found',
        level: _LogLevel.warning,
      );
      return;
    }
    try {
      final result = await _runModelExport(
        modelPath: modelPath,
        settings: _exportSettings,
        trigger: 'after-training',
      );
      if (mounted) {
        _showWarning('${t('train.exportDone')}: ${result.outputPath}');
      }
    } on Object catch (error) {
      if (mounted) {
        _showWarning('${t('train.exportFailed')}: $error');
      }
    }
  }

  String? _trainedModelForExport() {
    final activeRunDir = _activeRunDir;
    if (activeRunDir != null && activeRunDir.trim().isNotEmpty) {
      final best = '$activeRunDir\\weights\\best.pt';
      if (File(best).existsSync()) {
        return best;
      }
      final last = '$activeRunDir\\weights\\last.pt';
      if (File(last).existsSync()) {
        return last;
      }
    }
    final modelPath = _modelPath;
    return modelPath != null && File(modelPath).existsSync() ? modelPath : null;
  }

  Future<void> _pollTrainingProgress() async {
    if (!mounted || !_trainingRunning) return;
    try {
      final progress = await _RustVideoBackend.pollYoloTrainingProgress();
      final logText = await _readTrainingLogTail();
      final resourceUsage = await _readTrainingResourceUsage();
      if (!mounted || !_trainingRunning) return;
      var shouldAutoExport = false;
      if (progress == null) {
        setState(() {
          _trainingLogText = logText;
          _resourceUsage = resourceUsage;
        });
        return;
      }
      setState(() {
        _trainingLogText = logText;
        _resourceUsage = resourceUsage;
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
          final existingIndex = nextPoints.indexWhere(
            (point) => point.epoch == progress.currentEpoch,
          );
          final nextPoint = _TrainingMetricPoint(
            epoch: progress.currentEpoch,
            timestamp: DateTime.now(),
            metrics: metrics,
          );
          if (existingIndex < 0) {
            nextPoints.add(nextPoint);
          } else {
            nextPoints[existingIndex] = nextPoint;
          }
          nextPoints.sort((a, b) => a.epoch.compareTo(b.epoch));
          _trainingMetricPoints = _trimTrainingMetricPoints(nextPoints);
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
            _log(
              'TRAIN',
              'Training failed: ${progress.status}',
              level: _LogLevel.error,
            );
          } else {
            _log(
              'TRAIN',
              'Training finished: ${progress.status} at epoch ${progress.currentEpoch}',
            );
            shouldAutoExport = progress.status == 'completed';
          }
          _trainingTimer?.cancel();
        }
      });
      if (shouldAutoExport) {
        unawaited(_exportAfterTrainingIfNeeded());
      }
    } on Object catch (error) {
      _log(
        'TRAIN',
        'Training progress poll failed: $error',
        level: _LogLevel.warning,
      );
      final logText = await _readTrainingLogTail();
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

  List<_TrainingMetricPoint> _initialTrainingMetricPoints() {
    final resultsPath = _continuationResultsPath();
    if (resultsPath == null) {
      return const [];
    }
    return _readTrainingMetricPoints(File(resultsPath));
  }

  String? _continuationResultsPath() {
    final resumeResultsPath = _resumeInfo?.resultsPath;
    if (_useResumeTraining &&
        resumeResultsPath != null &&
        File(resumeResultsPath).existsSync()) {
      return resumeResultsPath;
    }
    final activeRunDir = _activeRunDir;
    if (_trainingInterrupted && activeRunDir != null) {
      final resultsPath = '$activeRunDir\\results.csv';
      if (File(resultsPath).existsSync()) {
        return resultsPath;
      }
    }
    return null;
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
    _savePreferences();
  }

  void _setParameter(String key, double value) {
    setState(() => _parameters[key] = value);
    if (key == 'epochs') {
      _refreshResumeInfo();
    }
    _savePreferences();
  }

  void _setStringParameter(String key, String value) {
    setState(() => _stringParameters[key] = value);
    _savePreferences();
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
      _datasetPathController.text = dataYamlPath;
      _datasetSummary = summary;
      _parameters['cls_pw'] = summary.recommendedClsPw;
    });
    _savePreferences();
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
    return _readTrainingDataPath(
      File('${runDir.path}\\args.yaml'),
      runDir.path,
    );
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
    final dataMatches =
        selectedData == null ||
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
    final modelOptions = _dedupeModelOptions(
      _modelOptions,
      preferredPath: _modelPath,
    );
    final modelDropdownValue = _modelDropdownValue(modelOptions);
    return SizedBox.expand(
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
                              initialValue: modelDropdownValue,
                              onTap: () => _loadModelOptions(),
                              items: [
                                for (final model in modelOptions)
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
                          OutlinedButton.icon(
                            onPressed: _datasetLoading || _exportingModel
                                ? null
                                : _showExportSettingsDialog,
                            icon: _exportingModel
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.output_outlined),
                            label: Text(t('train.exportSettings')),
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
                      if (modelOptions.isEmpty)
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
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 860),
                        child: TextField(
                          controller: _datasetPathController,
                          enabled: !_datasetLoading,
                          minLines: 1,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: t('train.datasetPath'),
                            isDense: true,
                            suffixIcon: IconButton(
                              tooltip: t('train.chooseDataset'),
                              onPressed: _datasetLoading
                                  ? null
                                  : () => unawaited(
                                      _loadDatasetPath(
                                        _datasetPathController.text,
                                      ),
                                    ),
                              icon: const Icon(Icons.check),
                            ),
                          ),
                          onSubmitted: (value) =>
                              unawaited(_loadDatasetPath(value)),
                        ),
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
                                  ],
                                ),
                              ),
                              Expanded(
                                child: _showTrainingTerminal
                                    ? _TrainingTerminalPanel(
                                        text: _trainingLogText,
                                      )
                                    : (_trainingMetricPoints.isNotEmpty ||
                                          _trainingRunning ||
                                          _resourceUsage.hasAny)
                                    ? _TrainingProgressPanel(
                                        metrics:
                                            _trainingMetrics ??
                                            (_trainingMetricPoints.isNotEmpty
                                                ? _trainingMetricPoints
                                                      .last
                                                      .metrics
                                                : const _TrainingMetrics()),
                                        colors: _chartColors,
                                        onColorChanged: _setChartColor,
                                        points: _trainingMetricPoints,
                                        resourceUsage: _resourceUsage,
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
                            stringParameters: _stringParameters,
                            batchMode: _batchMode,
                            batchSize: _batchSize,
                            batchRatio: _batchRatio,
                            ampEnabled: _ampEnabled,
                            deviceOptions: _deviceOptions,
                            selectedDeviceIds: _selectedDeviceIds,
                            batchArgument: _batchArgument,
                            deviceArgument: _deviceArgument,
                            onChanged: _setParameter,
                            onStringChanged: _setStringParameter,
                            onBatchModeChanged: (value) {
                              setState(() => _batchMode = value);
                              _savePreferences();
                            },
                            onBatchSizeChanged: (value) {
                              setState(() => _batchSize = value);
                              _savePreferences();
                            },
                            onBatchRatioChanged: (value) {
                              setState(() => _batchRatio = value);
                              _savePreferences();
                            },
                            onAmpChanged: (value) {
                              setState(() => _ampEnabled = value);
                              _savePreferences();
                            },
                            onDeviceChanged: (id, selected) {
                              _toggleTrainingDevice(id, selected);
                              _savePreferences();
                            },
                            onReset: _resetParameters,
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

