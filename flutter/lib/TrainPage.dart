// ignore_for_file: file_names

part of 'main.dart';

/// 训练页面，提供 models 文件夹 YOLO PT 选择、data.yaml 概览和超参数编辑。
/// Training page with YOLO PT selection from models/, data.yaml summary, and parameters.
class _TrainPage extends StatefulWidget {
  const _TrainPage({super.key, required this.settings});

  final _AppSettings settings;

  @override
  State<_TrainPage> createState() => _TrainPageState();
}

enum _BatchMode { fixed, autoGpu60, autoGpuRatio }

const _imageSizeOptions = [320, 416, 640, 800, 960, 1280];
const _trainingChartPointLimit = 2000;
const _parameterNameWidth = 112.0;
const Map<String, double> _defaultTrainingParameters = {
  'epochs': 300,
  'imgsz': 640,
  'cls_pw': 0,
  'workers': 4,
  'patience': 100,
  'lr0': 0.01,
  'momentum': 0.937,
  'hsv_h': 0.015,
  'hsv_s': 0.25,
  'hsv_v': 0.5,
  'translate': 0.1,
  'scale': 0.25,
  'shear': 5,
  'flipud': 0,
  'fliplr': 0,
  'degrees': 0,
  'perspective': 0,
  'bgr': 0,
  'mosaic': 1,
  'mixup': 0,
  'cutmix': 0,
  'copy_paste': 0,
  'erasing': 0.4,
};
const Map<String, String> _defaultTrainingStringParameters = {
  'copy_paste_mode': 'flip',
  'auto_augment': 'randaugment',
};
const Map<String, List<String>> _trainingStringParameterOptions = {
  'copy_paste_mode': ['flip', 'mixup'],
  'auto_augment': ['randaugment', 'autoaugment', 'augmix'],
};

class _TrainingDeviceOption {
  const _TrainingDeviceOption({required this.id, required this.label});

  final String id;
  final String label;
}

class _OpenVinoDeviceInfo {
  const _OpenVinoDeviceInfo({
    this.devices = const [],
    this.rawOutput = '',
    this.error = '',
  });

  final List<String> devices;
  final String rawOutput;
  final String error;

  bool get hasDevices => devices.isNotEmpty;
  bool get hasIntelGpu => devices.any((device) => device.startsWith('GPU'));
  bool get hasIntelNpu => devices.any((device) => device.startsWith('NPU'));
  bool get hasAccelerator => hasIntelGpu || hasIntelNpu;
  bool get hasError => error.trim().isNotEmpty;

  String get displayDevices => hasDevices ? devices.join(', ') : '-';

  String get preferredInferenceDevice {
    if (hasIntelGpu) {
      return 'intel:gpu';
    }
    if (hasIntelNpu) {
      return 'intel:npu';
    }
    return 'intel:cpu';
  }

  String get inferenceDeviceArgument => 'openvino:$preferredInferenceDevice';
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

Future<String> _readTrainingLogTail() async {
  try {
    return await _RustVideoBackend.trainingLogTail(maxChars: 30 * 1024);
  } on Object catch (error) {
    return '${t('logs.readFailed')}: $error';
  }
}

Future<_TrainingResourceUsage> _readTrainingResourceUsage() async {
  try {
    return await _RustVideoBackend.trainingResourceUsage();
  } on Object {
    return const _TrainingResourceUsage();
  }
}

class _TrainingResourceUsage {
  const _TrainingResourceUsage({
    this.cpuPercent,
    this.ramPercent,
    this.gpuPercent,
    this.vramPercent,
  });

  factory _TrainingResourceUsage.fromJson(Map<dynamic, dynamic> value) {
    return _TrainingResourceUsage(
      cpuPercent: _jsonPercent(value['cpuPercent']),
      ramPercent: _jsonPercent(value['ramPercent']),
      gpuPercent: _jsonPercent(value['gpuPercent']),
      vramPercent: _jsonPercent(value['vramPercent']),
    );
  }

  final double? cpuPercent;
  final double? ramPercent;
  final double? gpuPercent;
  final double? vramPercent;

  bool get hasAny =>
      cpuPercent != null ||
      ramPercent != null ||
      gpuPercent != null ||
      vramPercent != null;
}

double? _jsonPercent(Object? value) {
  if (value is! num) {
    return null;
  }
  final parsed = value.toDouble();
  if (!parsed.isFinite) {
    return null;
  }
  return parsed.clamp(0, 100).toDouble();
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
    required this.stringParameters,
    required this.batchMode,
    required this.batchSize,
    required this.batchRatio,
    required this.ampEnabled,
    required this.deviceOptions,
    required this.selectedDeviceIds,
    required this.batchArgument,
    required this.deviceArgument,
    required this.onChanged,
    required this.onStringChanged,
    required this.onBatchModeChanged,
    required this.onBatchSizeChanged,
    required this.onBatchRatioChanged,
    required this.onAmpChanged,
    required this.onDeviceChanged,
    required this.onReset,
  });

  final VoidCallback onReset;

  final Map<String, double> parameters;
  final Map<String, String> stringParameters;
  final _BatchMode batchMode;
  final double batchSize;
  final double batchRatio;
  final bool ampEnabled;
  final List<_TrainingDeviceOption> deviceOptions;
  final Set<String> selectedDeviceIds;
  final String batchArgument;
  final String deviceArgument;
  final void Function(String key, double value) onChanged;
  final void Function(String key, String value) onStringChanged;
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
                for (final entry in stringParameters.entries)
                  _StringParameterEditor(
                    name: entry.key,
                    value: entry.value,
                    options:
                        _trainingStringParameterOptions[entry.key] ??
                        const <String>[],
                    onChanged: (value) => onStringChanged(entry.key, value),
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onReset,
                    icon: const Icon(Icons.restart_alt, size: 16),
                    label: Text(t('action.reset')),
                  ),
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

class _YoloExportSettingsDialog extends StatefulWidget {
  const _YoloExportSettingsDialog({
    required this.initial,
    required this.onManualExport,
  });

  final _YoloExportSettings initial;
  final Future<_ModelExportResult> Function(_YoloExportSettings settings)
  onManualExport;

  @override
  State<_YoloExportSettingsDialog> createState() =>
      _YoloExportSettingsDialogState();
}

class _YoloExportSettingsDialogState
    extends State<_YoloExportSettingsDialog> {
  late String _format;
  late bool _autoExport;
  late bool _dynamic;
  late bool _nms;
  late bool _simplify;
  late String _quantize;
  late final TextEditingController _imgszController;
  late final TextEditingController _batchController;
  late final TextEditingController _dataController;
  late final TextEditingController _fractionController;
  late final TextEditingController _deviceController;
  late final TextEditingController _opsetController;
  bool _manualExporting = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load(widget.initial);
  }

  void _load(_YoloExportSettings settings) {
    _format = settings.format == 'onnx' ? 'onnx' : 'openvino';
    _autoExport = settings.autoExportAfterTraining;
    _dynamic = settings.dynamic;
    _nms = settings.nms;
    _simplify = settings.simplify;
    _quantize = _normalizeExportQuantize(settings.quantize);
    _imgszController = TextEditingController(text: settings.imgsz.toString());
    _batchController = TextEditingController(text: settings.batch.toString());
    _dataController = TextEditingController(text: settings.dataPath);
    _fractionController = TextEditingController(
      text: settings.fraction.toStringAsFixed(2),
    );
    _deviceController = TextEditingController(text: settings.device);
    _opsetController = TextEditingController(
      text: settings.opset <= 0 ? '' : settings.opset.toString(),
    );
  }

  @override
  void dispose() {
    _imgszController.dispose();
    _batchController.dispose();
    _dataController.dispose();
    _fractionController.dispose();
    _deviceController.dispose();
    _opsetController.dispose();
    super.dispose();
  }

  _YoloExportSettings _settingsFromFields() {
    return _YoloExportSettings(
      format: _format,
      autoExportAfterTraining: _autoExport,
      imgsz: _positiveInt(_imgszController.text, 640),
      batch: _positiveInt(_batchController.text, 1),
      quantize: _quantize,
      dynamic: _dynamic,
      nms: _nms,
      dataPath: _isInt8Quantize ? _dataController.text.trim() : '',
      fraction: _fraction(_fractionController.text),
      device: _format == 'onnx' ? _deviceController.text.trim() : '',
      simplify: _simplify,
      opset: _positiveInt(_opsetController.text, 0),
    );
  }

  bool get _isInt8Quantize => _isInt8QuantizeValue(_quantize);

  bool get _showDataWarning =>
      _isInt8Quantize && _dataController.text.trim().isEmpty;

  String _normalizeExportQuantize(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == '8' || normalized == 'int8' || normalized == 'w8a8') {
      return '8';
    }
    if (normalized == '16' || normalized == 'fp16' || normalized == 'w16a16') {
      return '16';
    }
    if (normalized == '32' || normalized == 'fp32' || normalized == 'w32a32') {
      return '32';
    }
    return '';
  }

  bool _isInt8QuantizeValue(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == '8' || normalized == 'int8' || normalized == 'w8a8';
  }

  int _positiveInt(String text, int fallback) {
    final parsed = int.tryParse(text.trim());
    if (parsed == null || parsed < 0) {
      return fallback;
    }
    return parsed;
  }

  double _fraction(String text) {
    final parsed = double.tryParse(text.trim());
    if (parsed == null || !parsed.isFinite) {
      return 1.0;
    }
    return parsed.clamp(0.01, 1.0).toDouble();
  }

  Future<void> _chooseDataYaml() async {
    final file = await openFile(acceptedTypeGroups: [_yamlTypeGroup]);
    if (file == null) {
      return;
    }
    setState(() => _dataController.text = file.path);
  }

  void _reset() {
    final defaults = const _YoloExportSettings();
    setState(() {
      _format = defaults.format;
      _autoExport = defaults.autoExportAfterTraining;
      _dynamic = defaults.dynamic;
      _nms = defaults.nms;
      _simplify = defaults.simplify;
      _quantize = defaults.quantize;
      _imgszController.text = defaults.imgsz.toString();
      _batchController.text = defaults.batch.toString();
      _dataController.text = defaults.dataPath;
      _fractionController.text = defaults.fraction.toStringAsFixed(2);
      _deviceController.text = defaults.device;
      _opsetController.text = '';
      _message = null;
    });
  }

  Future<void> _manualExport() async {
    setState(() {
      _manualExporting = true;
      _message = null;
    });
    try {
      final result = await widget.onManualExport(_settingsFromFields());
      if (mounted) {
        setState(() => _message = '${t('train.exportDone')}: ${result.outputPath}');
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _message = '${t('train.exportFailed')}: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _manualExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnnx = _format == 'onnx';
    return AlertDialog(
      title: Text(t('train.exportSettings')),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ExportParameterTooltip(
                name: 'format',
                child: DropdownButtonFormField<String>(
                  initialValue: _format,
                  decoration: InputDecoration(
                    labelText: t('train.exportFormat'),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'openvino',
                      child: Text('OpenVINO'),
                    ),
                    DropdownMenuItem(value: 'onnx', child: Text('ONNX')),
                  ],
                  onChanged: _manualExporting
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _format = value);
                          }
                        },
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _ExportTextField(
                    controller: _imgszController,
                    label: 'imgsz',
                    width: 120,
                    enabled: !_manualExporting,
                  ),
                  _ExportTextField(
                    controller: _batchController,
                    label: 'batch',
                    width: 120,
                    enabled: !_manualExporting,
                  ),
                  SizedBox(
                    width: 160,
                    child: _ExportParameterTooltip(
                      name: 'quantize',
                      child: DropdownButtonFormField<String>(
                        initialValue: _quantize,
                        decoration: const InputDecoration(
                          labelText: 'quantize',
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: '',
                            child: Text('FP32 / 默认'),
                          ),
                          DropdownMenuItem(value: '16', child: Text('FP16')),
                          DropdownMenuItem(value: '8', child: Text('INT8')),
                        ],
                        onChanged: _manualExporting
                            ? null
                            : (value) {
                                setState(() {
                                  _quantize = value ?? '';
                                  if (!_isInt8QuantizeValue(_quantize)) {
                                    _dataController.clear();
                                  }
                                });
                              },
                      ),
                    ),
                  ),
                  _ExportTextField(
                    controller: _fractionController,
                    label: 'fraction',
                    width: 120,
                    enabled: !_manualExporting,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _ExportParameterTooltip(
                name: 'dynamic',
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('dynamic'),
                  value: _dynamic,
                  onChanged: _manualExporting
                      ? null
                      : (value) => setState(() => _dynamic = value),
                ),
              ),
              _ExportParameterTooltip(
                name: 'nms',
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('nms'),
                  value: _nms,
                  onChanged: _manualExporting
                      ? null
                      : (value) => setState(() => _nms = value),
                ),
              ),
              if (isOnnx) ...[
                _ExportParameterTooltip(
                  name: 'simplify',
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('simplify'),
                    value: _simplify,
                    onChanged: _manualExporting
                        ? null
                        : (value) => setState(() => _simplify = value),
                  ),
                ),
                _ExportTextField(
                  controller: _opsetController,
                  label: 'opset',
                  width: 160,
                  enabled: !_manualExporting,
                  hint: 'auto',
                ),
              ],
              const SizedBox(height: 8),
              _ExportParameterTooltip(
                name: 'data',
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _dataController,
                        enabled: !_manualExporting && _isInt8Quantize,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'data',
                          hintText: _isInt8Quantize
                              ? 'data.yaml'
                              : t('train.exportDataOnlyInt8'),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _manualExporting || !_isInt8Quantize
                          ? null
                          : _chooseDataYaml,
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: Text(t('action.select')),
                    ),
                    if (_showDataWarning) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: t('train.exportDataMissing'),
                        child: Icon(
                          Icons.error,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isOnnx) ...[
                const SizedBox(height: 12),
                _ExportParameterTooltip(
                  name: 'device',
                  child: TextField(
                    controller: _deviceController,
                    enabled: !_manualExporting,
                    decoration: const InputDecoration(
                      labelText: 'device',
                      hintText: 'cpu / 0 / mps',
                      isDense: true,
                    ),
                  ),
                ),
              ],
              _ExportParameterTooltip(
                name: 'autoExport',
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('train.autoExportAfterTraining')),
                  value: _autoExport,
                  onChanged: _manualExporting
                      ? null
                      : (value) => setState(() => _autoExport = value),
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 8),
                Text(_message!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _manualExporting ? null : _reset,
          child: Text(t('action.reset')),
        ),
        OutlinedButton.icon(
          onPressed: _manualExporting ? null : _manualExport,
          icon: _manualExporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.output_outlined, size: 16),
          label: Text(t('train.exportNow')),
        ),
        TextButton(
          onPressed: _manualExporting ? null : () => Navigator.pop(context),
          child: Text(t('action.cancel')),
        ),
        FilledButton(
          onPressed: _manualExporting
              ? null
              : () => Navigator.pop(context, _settingsFromFields()),
          child: Text(t('action.save')),
        ),
      ],
    );
  }
}

class _ExportTextField extends StatelessWidget {
  const _ExportTextField({
    required this.controller,
    required this.label,
    required this.width,
    required this.enabled,
    this.hint,
    this.helpName,
  });

  final TextEditingController controller;
  final String label;
  final double width;
  final bool enabled;
  final String? hint;
  final String? helpName;

  @override
  Widget build(BuildContext context) {
    return _ExportParameterTooltip(
      name: helpName ?? label,
      child: SizedBox(
        width: width,
        child: TextField(
          controller: controller,
          enabled: enabled,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            isDense: true,
          ),
        ),
      ),
    );
  }
}

class _ExportParameterTooltip extends StatelessWidget {
  const _ExportParameterTooltip({required this.name, required this.child});

  final String name;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      waitDuration: const Duration(milliseconds: 500),
      message: _exportParameterHelp(name),
      child: child,
    );
  }
}

String _exportParameterHelp(String name) {
  return t('train.exportParam.$name');
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
                integer: true,
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
        SizedBox(width: _parameterNameWidth, child: Text(name)),
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
    this.integer = false,
    this.enabled = true,
  });

  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;
  final bool integer;
  final bool enabled;

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
            onChanged: enabled ? onChanged : null,
          ),
        ),
        _NumericParameterField(
          value: value,
          label: label,
          min: min,
          max: max,
          integer: integer,
          enabled: enabled,
          onSubmitted: onChanged,
        ),
      ],
    );
  }
}

class _NumericParameterField extends StatefulWidget {
  const _NumericParameterField({
    required this.value,
    required this.label,
    required this.min,
    required this.max,
    required this.integer,
    required this.onSubmitted,
    this.normalize,
    this.enabled = true,
  });

  final double value;
  final String label;
  final double min;
  final double max;
  final bool integer;
  final bool enabled;
  final double Function(double value)? normalize;
  final ValueChanged<double> onSubmitted;

  @override
  State<_NumericParameterField> createState() => _NumericParameterFieldState();
}

class _NumericParameterFieldState extends State<_NumericParameterField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.label);
    _focusNode = FocusNode(debugLabel: 'parameter-value');
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _NumericParameterField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus &&
        oldWidget.value != widget.value &&
        _controller.text != widget.label) {
      _controller.text = widget.label;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _commit();
    }
  }

  void _commit() {
    if (!widget.enabled) {
      return;
    }
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null) {
      _controller.text = widget.label;
      return;
    }
    var next = parsed.clamp(widget.min, widget.max).toDouble();
    if (widget.integer) {
      next = next.roundToDouble();
    }
    next = widget.normalize?.call(next) ?? next;
    widget.onSubmitted(next);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        enabled: widget.enabled,
        textAlign: TextAlign.right,
        keyboardType: TextInputType.numberWithOptions(decimal: !widget.integer),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            widget.integer ? RegExp(r'[0-9]') : RegExp(r'[0-9.]'),
          ),
        ],
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        onSubmitted: (_) => _commit(),
      ),
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
    this.enabled = true,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final bool enabled;

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
            const SizedBox(width: _parameterNameWidth, child: Text('imgsz')),
            Expanded(
              child: Slider(
                value: index.toDouble(),
                min: 0,
                max: (_imageSizeOptions.length - 1).toDouble(),
                divisions: _imageSizeOptions.length - 1,
                label: currentSize.toString(),
                onChanged: enabled
                    ? (sliderIndex) {
                        final nextIndex = sliderIndex.round().clamp(
                          0,
                          _imageSizeOptions.length - 1,
                        );
                        onChanged(_imageSizeOptions[nextIndex].toDouble());
                      }
                    : null,
              ),
            ),
            _NumericParameterField(
              value: currentSize.toDouble(),
              label: currentSize.toString(),
              min: _imageSizeOptions.first.toDouble(),
              max: _imageSizeOptions.last.toDouble(),
              integer: true,
              normalize: _nearestImageSizeValue,
              enabled: enabled,
              onSubmitted: onChanged,
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

    final integerLike = {
      'epochs',
      'imgsz',
      'workers',
      'patience',
    }.contains(name);
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
            SizedBox(width: _parameterNameWidth, child: Text(name)),
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
            _NumericParameterField(
              value: value,
              label: label,
              min: min,
              max: max,
              integer: integerLike,
              normalize: (input) => _normalizeParameterValue(name, input),
              onSubmitted: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _StringParameterEditor extends StatelessWidget {
  const _StringParameterEditor({
    required this.name,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String name;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final choices = options.contains(value) ? options : [value, ...options];
    return Tooltip(
      waitDuration: const Duration(milliseconds: 500),
      message: _parameterHelp(name),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            SizedBox(width: _parameterNameWidth, child: Text(name)),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: value,
                isDense: true,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                items: [
                  for (final choice in choices)
                    DropdownMenuItem<String>(
                      value: choice,
                      child: Text(choice, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (next) {
                  if (next != null) {
                    onChanged(next);
                  }
                },
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

List<_TrainingMetricPoint> _readTrainingMetricPoints(File resultsCsv) {
  if (!resultsCsv.existsSync()) {
    return const [];
  }
  final lines = resultsCsv.readAsLinesSync();
  final headerIndex = lines.indexWhere((line) => line.trim().isNotEmpty);
  if (headerIndex < 0) {
    return const [];
  }
  final columns = _splitTrainingCsvLine(
    lines[headerIndex].trim().trimLeft().replaceFirst('\uFEFF', ''),
  );
  if (columns.isEmpty) {
    return const [];
  }

  final pointsByEpoch = <int, _TrainingMetricPoint>{};
  for (final rawLine in lines.skip(headerIndex + 1)) {
    final line = rawLine.trim();
    if (line.isEmpty || line.toLowerCase().startsWith('epoch')) {
      continue;
    }
    final values = _splitTrainingCsvLine(line);
    final map = <String, double>{};
    for (
      var index = 0;
      index < math.min(columns.length, values.length);
      index += 1
    ) {
      final parsed = double.tryParse(values[index]);
      if (parsed != null) {
        map[columns[index]] = parsed;
      }
    }
    final rawEpoch = map['epoch'];
    if (rawEpoch == null) {
      continue;
    }
    final epoch = rawEpoch.round() + 1;
    if (epoch <= 0) {
      continue;
    }
    final metrics = _trainingMetricsFromResultsMap(map);
    if (!_hasAnyTrainingMetric(metrics)) {
      continue;
    }
    pointsByEpoch[epoch] = _TrainingMetricPoint(
      epoch: epoch,
      timestamp: DateTime.now(),
      metrics: metrics,
    );
  }

  final points = pointsByEpoch.values.toList()
    ..sort((a, b) => a.epoch.compareTo(b.epoch));
  return _trimTrainingMetricPoints(points);
}

List<String> _splitTrainingCsvLine(String line) {
  return line.split(',').map((value) => value.trim()).toList();
}

_TrainingMetrics _trainingMetricsFromResultsMap(Map<String, double> map) {
  return _TrainingMetrics(
    trainLoss: _trainingCsvValue(map, const ['train/box_loss', 'train/loss']),
    valLoss: _trainingCsvValue(map, const ['val/box_loss', 'val/loss']),
    map50: _trainingCsvValue(map, const [
      'metrics/mAP50(B)',
      'metrics/mAP_0.5',
    ]),
    map5095: _trainingCsvValue(map, const [
      'metrics/mAP50-95(B)',
      'metrics/mAP_0.5:0.95',
    ]),
    precision: _trainingCsvValue(map, const [
      'metrics/precision(B)',
      'metrics/precision',
    ]),
    recall: _trainingCsvValue(map, const [
      'metrics/recall(B)',
      'metrics/recall',
    ]),
    lr: _trainingCsvValue(map, const ['lr/pg0', 'lr/0']),
  );
}

double? _trainingCsvValue(Map<String, double> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value != null) {
      return value;
    }
  }
  return null;
}

bool _hasAnyTrainingMetric(_TrainingMetrics metrics) {
  return metrics.trainLoss != null ||
      metrics.valLoss != null ||
      metrics.map50 != null ||
      metrics.map5095 != null ||
      metrics.precision != null ||
      metrics.recall != null ||
      metrics.lr != null;
}

List<_TrainingMetricPoint> _trimTrainingMetricPoints(
  List<_TrainingMetricPoint> points,
) {
  if (points.length <= _trainingChartPointLimit) {
    return points;
  }
  return points.sublist(points.length - _trainingChartPointLimit);
}

Future<List<_TrainingDeviceOption>> _detectNvidiaDevices() async {
  try {
    final result =
        await Process.run('nvidia-smi', [
          '--query-gpu=index,name',
          '--format=csv,noheader',
        ]).timeout(
          const Duration(seconds: 2),
          onTimeout: () => ProcessResult(0, 124, '', 'nvidia-smi timeout'),
        );
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

Future<_OpenVinoDeviceInfo> _detectOpenVinoDevices(String pythonPath) async {
  final executable = _resolvePythonExecutable(pythonPath);
  if (executable == null) {
    return const _OpenVinoDeviceInfo(error: 'Python path is not configured');
  }
  const script = '''
import json
try:
    from openvino import Core
    print(json.dumps({"ok": True, "devices": list(Core().available_devices)}))
except Exception as error:
    print(json.dumps({"ok": False, "error": str(error)}))
''';
  try {
    final result = await Process.run(executable, ['-c', script]).timeout(
      const Duration(seconds: 15),
      onTimeout: () => ProcessResult(0, 124, '', 'OpenVINO probe timeout'),
    );
    final stdout = result.stdout.toString().trim();
    final stderr = result.stderr.toString().trim();
    if (result.exitCode != 0) {
      return _OpenVinoDeviceInfo(
        rawOutput: stdout,
        error: stderr.isEmpty ? 'exit code ${result.exitCode}' : stderr,
      );
    }
    if (stdout.isEmpty) {
      return _OpenVinoDeviceInfo(
        error: stderr.isEmpty ? 'empty OpenVINO probe output' : stderr,
      );
    }
    final jsonLine = stdout
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .lastWhere(
          (line) => line.startsWith('{') && line.endsWith('}'),
          orElse: () => stdout,
        );
    final decoded = jsonDecode(jsonLine);
    if (decoded is! Map<String, dynamic>) {
      return _OpenVinoDeviceInfo(
        rawOutput: stdout,
        error: 'invalid OpenVINO probe output',
      );
    }
    if (decoded['ok'] != true) {
      return _OpenVinoDeviceInfo(
        rawOutput: stdout,
        error: '${decoded['error'] ?? 'OpenVINO probe failed'}',
      );
    }
    final rawDevices = decoded['devices'];
    if (rawDevices is! List) {
      return _OpenVinoDeviceInfo(
        rawOutput: stdout,
        error: 'OpenVINO device list is missing',
      );
    }
    final devices = rawDevices
        .map((item) => '$item'.trim().toUpperCase())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList()
      ..sort(_naturalCompare);
    return _OpenVinoDeviceInfo(devices: devices, rawOutput: stdout);
  } on Object catch (error) {
    return _OpenVinoDeviceInfo(error: '$error');
  }
}

double _minForParameter(String name) {
  return switch (name) {
    'epochs' => 1,
    'imgsz' => 320,
    'patience' => 0,
    'momentum' => 0.5,
    'workers' => 0,
    _ => 0,
  };
}

double _maxForParameter(String name) {
  return switch (name) {
    'epochs' => 500,
    'imgsz' => 1280,
    'patience' => 500,
    'lr0' => 0.1,
    'cls_pw' => 1,
    'momentum' => 0.99,
    'workers' => 16,
    'shear' => 20,
    'degrees' => 180,
    'perspective' => 0.001,
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

double _nearestImageSizeValue(double value) {
  return _imageSizeOptions[_nearestImageSizeIndex(value)].toDouble();
}

double _normalizeParameterValue(String name, double value) {
  if (name == 'imgsz') {
    return _nearestImageSizeValue(value);
  }
  if ({'epochs', 'workers', 'patience'}.contains(name)) {
    return value.roundToDouble();
  }
  return value;
}

String _formatParameterValue(String name, double value) {
  return switch (name) {
    'epochs' || 'imgsz' || 'workers' || 'patience' => value.round().toString(),
    'lr0' => value.toStringAsFixed(4),
    'hsv_h' => value.toStringAsFixed(3),
    'perspective' => value.toStringAsFixed(6),
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
  const _TrainingProgressPanel({
    required this.metrics,
    required this.points,
    required this.colors,
    required this.onColorChanged,
    required this.resourceUsage,
  });

  final _TrainingMetrics metrics;
  final List<_TrainingMetricPoint> points;
  final Map<String, int> colors;
  final void Function(String key) onColorChanged;
  final _TrainingResourceUsage resourceUsage;

  @override
  Widget build(BuildContext context) {
    final seriesList = _buildTrainingSeries(points, colors);
    if (seriesList.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TrainingResourcePanel(usage: resourceUsage),
            const SizedBox(height: 12),
            Expanded(child: Center(child: Text(t('train.chartPlaceholder')))),
          ],
        ),
      );
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
      chartPanels.add(
        _metricChart(
          context,
          t('train.chartLoss'),
          lossGroup,
          minX,
          maxX,
          epochInterval,
        ),
      );
    }
    if (mapGroup.isNotEmpty) {
      chartPanels.add(
        _metricChart(
          context,
          t('train.chartMap'),
          mapGroup,
          minX,
          maxX,
          epochInterval,
        ),
      );
    }
    if (prGroup.isNotEmpty) {
      chartPanels.add(
        _metricChart(
          context,
          t('train.chartPr'),
          prGroup,
          minX,
          maxX,
          epochInterval,
        ),
      );
    }
    if (lrGroup.isNotEmpty) {
      chartPanels.add(
        _metricChart(
          context,
          t('train.chartLr'),
          lrGroup,
          minX,
          maxX,
          epochInterval,
        ),
      );
    }

    Color legendColor(String key, int fallback) {
      return Color(colors[key] ?? fallback);
    }

    final legendItems = <(String, double?, Color)>[
      if (lossGroup.any((s) => s.label == 'Train Loss'))
        (
          'Train Loss',
          metrics.trainLoss,
          legendColor('Train Loss', 0xFF2563EB),
        ),
      if (lossGroup.any((s) => s.label == 'Val Loss'))
        ('Val Loss', metrics.valLoss, legendColor('Val Loss', 0xFFDC2626)),
      if (mapGroup.any((s) => s.label == 'mAP@0.5'))
        ('mAP@0.5', metrics.map50, legendColor('mAP@0.5', 0xFF16A34A)),
      if (mapGroup.any((s) => s.label == 'mAP@0.5:0.95'))
        (
          'mAP@0.5:0.95',
          metrics.map5095,
          legendColor('mAP@0.5:0.95', 0xFF9333EA),
        ),
      if (prGroup.any((s) => s.label == 'Precision'))
        ('Precision', metrics.precision, legendColor('Precision', 0xFFEA580C)),
      if (prGroup.any((s) => s.label == 'Recall'))
        ('Recall', metrics.recall, legendColor('Recall', 0xFF0891B2)),
      if (lrGroup.isNotEmpty) ('LR', metrics.lr, legendColor('LR', 0xFF64748B)),
    ].where((e) => e.$2 != null).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TrainingResourcePanel(usage: resourceUsage),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: ListView(children: chartPanels)),
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
                                GestureDetector(
                                  onTap: () => onColorChanged(label),
                                  child: Tooltip(
                                    message: t('label.classColor'),
                                    child: Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: BorderRadius.circular(2),
                                        border: Border.all(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                          width: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                Text(
                                  value!.toStringAsFixed(4),
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
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
          ),
        ],
      ),
    );
  }
}

class _TrainingResourcePanel extends StatelessWidget {
  const _TrainingResourcePanel({required this.usage});

  final _TrainingResourceUsage usage;

  @override
  Widget build(BuildContext context) {
    final items = [
      _ResourcePercentItem(
        label: t('train.resourceCpu'),
        percent: usage.cpuPercent,
        color: const Color(0xFF2563EB),
      ),
      _ResourcePercentItem(
        label: t('train.resourceRam'),
        percent: usage.ramPercent,
        color: const Color(0xFF16A34A),
      ),
      _ResourcePercentItem(
        label: t('train.resourceGpu'),
        percent: usage.gpuPercent,
        color: const Color(0xFFEA580C),
      ),
      _ResourcePercentItem(
        label: t('train.resourceVram'),
        percent: usage.vramPercent,
        color: const Color(0xFF9333EA),
      ),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      children: [
        for (final item in items) _ResourcePercentIndicator(item: item),
      ],
    );
  }
}

class _ResourcePercentItem {
  const _ResourcePercentItem({
    required this.label,
    required this.percent,
    required this.color,
  });

  final String label;
  final double? percent;
  final Color color;
}

class _ResourcePercentIndicator extends StatelessWidget {
  const _ResourcePercentIndicator({required this.item});

  final _ResourcePercentItem item;

  @override
  Widget build(BuildContext context) {
    final percent = item.percent;
    final available = percent != null;
    final normalized = ((percent ?? 0) / 100).clamp(0.0, 1.0).toDouble();
    final color = available
        ? item.color
        : Theme.of(context).colorScheme.outline;
    final label = available ? '${percent.round()}%' : '--';
    return SizedBox(
      width: 112,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularPercentIndicator(
            radius: 30,
            lineWidth: 6,
            percent: normalized,
            animation: true,
            animateFromLastPercent: true,
            circularStrokeCap: CircularStrokeCap.round,
            progressColor: color,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
            center: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Consolas',
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
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
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
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
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: _borderColor(context), strokeWidth: 1),
                getDrawingVerticalLine: (_) =>
                    FlLine(color: _borderColor(context), strokeWidth: 1),
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
  Map<String, int> colors,
) {
  List<FlSpot> spotsFor(double? Function(_TrainingMetrics metrics) getter) {
    return [
      for (final point in points)
        if (getter(point.metrics) != null)
          FlSpot(point.epoch.toDouble(), getter(point.metrics)!),
    ];
  }

  Color seriesColor(String key, int fallback) => Color(colors[key] ?? fallback);

  return [
    _TrainingChartSeries(
      label: 'Train Loss',
      color: seriesColor('Train Loss', 0xFF2563EB),
      spots: spotsFor((metrics) => metrics.trainLoss),
    ),
    _TrainingChartSeries(
      label: 'Val Loss',
      color: seriesColor('Val Loss', 0xFFDC2626),
      spots: spotsFor((metrics) => metrics.valLoss),
    ),
    _TrainingChartSeries(
      label: 'mAP@0.5',
      color: seriesColor('mAP@0.5', 0xFF16A34A),
      spots: spotsFor((metrics) => metrics.map50),
    ),
    _TrainingChartSeries(
      label: 'mAP@0.5:0.95',
      color: seriesColor('mAP@0.5:0.95', 0xFF9333EA),
      spots: spotsFor((metrics) => metrics.map5095),
    ),
    _TrainingChartSeries(
      label: 'Precision',
      color: seriesColor('Precision', 0xFFEA580C),
      spots: spotsFor((metrics) => metrics.precision),
    ),
    _TrainingChartSeries(
      label: 'Recall',
      color: seriesColor('Recall', 0xFF0891B2),
      spots: spotsFor((metrics) => metrics.recall),
    ),
    _TrainingChartSeries(
      label: 'LR',
      color: seriesColor('LR', 0xFF64748B),
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
