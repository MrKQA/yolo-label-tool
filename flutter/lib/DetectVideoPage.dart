// ignore_for_file: file_names

part of 'main.dart';

const _videoExtensions = {'mp4', 'avi', 'mov', 'mkv', 'webm', 'wmv', 'flv'};
const _detectImageSizeOptions = [320, 416, 640, 800, 960, 1280];
const _detectDeviceOptions = ['auto', 'nv', 'cpu'];
const _mediaTypeGroup = XTypeGroup(
  label: 'Image or video',
  extensions: [
    'jpg',
    'jpeg',
    'png',
    'bmp',
    'gif',
    'webp',
    'mp4',
    'avi',
    'mov',
    'mkv',
    'webm',
    'wmv',
    'flv',
  ],
);

class _DetectVideoSession extends ChangeNotifier {
  bool _disposed = false;
  bool _fullscreenToggleScheduled = false;
  int _loadSerial = 0;
  Timer? _positionTimer;
  Timer? _shortcutHudTimer;
  final ValueNotifier<int> progressTick = ValueNotifier<int>(0);
  final ValueNotifier<_VideoShortcutHud?> shortcutHud =
      ValueNotifier<_VideoShortcutHud?>(null);

  bool playVideo = true;
  bool predictVideo = false;
  bool predictAll = false;
  bool saveResult = false;
  bool showPredictionResult = true;
  bool previewPanelVisible = true;
  bool videoLoading = false;
  bool scrubbing = false;
  bool predicting = false;
  bool fullscreen = false;
  double playbackSpeed = 1;
  double volume = 1;
  double detectConf = 0.25;
  int detectImageSize = 640;
  String detectDevice = 'auto';
  double? scrubSeconds;
  String? selectedInput;
  String? predictionOutputPath;
  String? detectModelPath;
  String? videoStatus;
  String? _controllerPath;
  _RustVideoInfo? videoInfo;
  video_player_win.WinVideoPlayerController? controller;
  _VideoScaleMode scaleMode = _VideoScaleMode.auto;
  List<String> folderItems = const [];
  final Map<String, String> _predictionOutputsByInput = {};
  double _positionAnchorSeconds = 0;
  DateTime? _positionAnchorTime;

  bool get selectedInputIsImage =>
      selectedInput != null && _isImagePath(selectedInput!);

  bool get selectedInputIsVideo =>
      selectedInput != null && _isVideoPath(selectedInput!);

  bool get canSaveResult => predictVideo || predictAll || selectedInputIsImage;

  String? get displayInput {
    final output = predictionOutputPath;
    if (showPredictionResult && output != null && File(output).existsSync()) {
      return output;
    }
    return selectedInput;
  }

  bool get hasInitializedVideo =>
      controller != null && controller!.value.isInitialized;

  bool get isPlaying =>
      controller != null &&
      controller!.value.isInitialized &&
      controller!.value.isPlaying;

  bool get isPaused => !isPlaying;

  double get durationSeconds {
    final value = controller?.value;
    final nativeDuration = value == null || !value.isInitialized
        ? 0.0
        : value.duration.inMilliseconds / 1000.0;
    if (nativeDuration > 0) {
      return nativeDuration;
    }
    return videoInfo?.safeDurationSeconds ?? 0;
  }

  double get positionSeconds {
    if (scrubbing && scrubSeconds != null) {
      return scrubSeconds!;
    }
    final value = controller?.value;
    if (value == null || !value.isInitialized) {
      return 0;
    }
    final nativePosition = value.position.inMilliseconds / 1000.0;
    if (nativePosition > 0) {
      return _clampPlaybackSeconds(nativePosition);
    }
    final anchorTime = _positionAnchorTime;
    if (value.isPlaying && anchorTime != null) {
      final elapsedSeconds =
          DateTime.now().difference(anchorTime).inMilliseconds / 1000.0;
      return _clampPlaybackSeconds(
        _positionAnchorSeconds + elapsedSeconds * playbackSpeed,
      );
    }
    return _clampPlaybackSeconds(_positionAnchorSeconds);
  }

  @override
  void dispose() {
    _disposed = true;
    _loadSerial++;
    _positionTimer?.cancel();
    _shortcutHudTimer?.cancel();
    final oldController = controller;
    controller = null;
    oldController?.dispose();
    progressTick.dispose();
    shortcutHud.dispose();
    super.dispose();
  }

  void _emit() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _emitProgress() {
    if (!_disposed) {
      progressTick.value = progressTick.value + 1;
    }
  }

  void _showShortcutHud(String text, {bool hold = false}) {
    if (_disposed) {
      return;
    }
    _shortcutHudTimer?.cancel();
    final current = shortcutHud.value;
    if (hold && current != null && current.text == text && current.hold) {
      return;
    }
    shortcutHud.value = _VideoShortcutHud(text: text, hold: hold);
    if (!hold) {
      _shortcutHudTimer = Timer(const Duration(milliseconds: 850), () {
        if (!_disposed) {
          shortcutHud.value = null;
        }
      });
    }
  }

  void _hideShortcutHud() {
    _shortcutHudTimer?.cancel();
    if (!_disposed) {
      shortcutHud.value = null;
    }
  }

  Future<void> chooseMediaFile() async {
    final file = await openFile(acceptedTypeGroups: const [_mediaTypeGroup]);
    if (file == null) {
      return;
    }
    _log('BROWSE', 'Media file selected: ${file.path}');
    await selectInput(file.path, newFolderItems: const []);
  }

  Future<void> chooseFolder() async {
    final folder = await getDirectoryPath();
    if (folder == null) {
      return;
    }
    final items = _mediaFilesInDirectory(folder);
    _log(
      'BROWSE',
      'Media folder selected: $folder, items=${items.length}',
      level: items.isEmpty ? _LogLevel.warning : _LogLevel.info,
    );
    await selectInput(
      items.isEmpty ? folder : items.first,
      newFolderItems: items,
      showPreviewPanel: true,
    );
  }

  Future<void> selectInput(
    String path, {
    List<String>? newFolderItems,
    bool showPreviewPanel = false,
  }) async {
    final sameInput = _pathKey(path) == _pathKey(selectedInput ?? '');
    if (newFolderItems != null) {
      folderItems = newFolderItems;
    }
    if (showPreviewPanel) {
      previewPanelVisible = true;
    }
    _log(
      'BROWSE',
      'Selected input changed: $path, folderItems=${folderItems.length}',
      level: _LogLevel.debug,
    );
    selectedInput = path;
    showPredictionResult = true;
    predictionOutputPath = _cachedPredictionOutput(path);
    saveResult = saveResult && _canSaveForInput(path);
    if (!sameInput) {
      await _resetVideoController();
    }
    _emit();
    await loadSelectedVideoIfNeeded();
  }

  bool _canSaveForInput(String? input) {
    return predictVideo || predictAll || (input != null && _isImagePath(input));
  }

  String? _cachedPredictionOutput(String input) {
    final cached = _predictionOutputsByInput[_pathKey(input)];
    if (cached == null) {
      return null;
    }
    if (File(cached).existsSync()) {
      return cached;
    }
    _predictionOutputsByInput.remove(_pathKey(input));
    return null;
  }

  Future<void> _resetVideoController() async {
    _loadSerial++;
    _positionTimer?.cancel();
    _positionTimer = null;
    final oldController = controller;
    controller = null;
    _controllerPath = null;
    videoInfo = null;
    videoLoading = false;
    videoStatus = null;
    playbackSpeed = 1;
    scrubbing = false;
    scrubSeconds = null;
    _positionAnchorSeconds = 0;
    _positionAnchorTime = null;
    await oldController?.dispose();
  }

  Future<void> loadSelectedVideoIfNeeded() async {
    final input = displayInput;
    final predictionPreview =
        predictVideo || predictAll || predictionOutputPath != null;
    if (input == null ||
        !_isVideoPath(input) ||
        (!playVideo && !predictionPreview)) {
      return;
    }
    if (controller != null &&
        _controllerPath != null &&
        _pathKey(_controllerPath!) == _pathKey(input)) {
      if (!controller!.value.isPlaying) {
        await controller!.play();
        _markPlaybackStarted();
      }
      _emit();
      return;
    }

    final requestSerial = ++_loadSerial;
    _log('BROWSE', 'Video load started: $input', level: _LogLevel.debug);
    videoLoading = true;
    videoStatus = t('detect.loadingVideo');
    playbackSpeed = 1;
    videoInfo = null;
    _positionAnchorSeconds = 0;
    _positionAnchorTime = null;
    _emit();

    final oldController = controller;
    controller = null;
    _controllerPath = null;
    _positionTimer?.cancel();
    _positionTimer = null;
    await oldController?.dispose();

    try {
      String? metadataError;
      final metadataFuture = _RustVideoBackend.loadInfo(input)
          .then<_RustVideoInfo?>((info) => info)
          .catchError((error) {
            metadataError = _shortVideoError(error);
            return null;
          });
      final nextController = video_player_win.WinVideoPlayerController.file(
        File(input),
      );
      controller = nextController;
      _controllerPath = input;
      await nextController.initialize();
      if (_disposed || requestSerial != _loadSerial) {
        await nextController.dispose();
        return;
      }
      videoInfo = await metadataFuture;
      if (_disposed || requestSerial != _loadSerial) {
        await nextController.dispose();
        return;
      }
      await nextController.setLooping(true);
      await nextController.setPlaybackSpeed(playbackSpeed);
      await nextController.setVolume(volume);
      if (playVideo || predictionPreview) {
        await nextController.play();
        _markPlaybackStarted();
      }
      videoLoading = false;
      final size = nextController.value.size;
      videoStatus = _videoStatusText(
        size: size,
        nativeDurationSeconds:
            nextController.value.duration.inMilliseconds / 1000.0,
        metadata: videoInfo,
        metadataError: metadataError,
      );
      _log(
        'BROWSE',
        'Video load completed: $input, size=${size.width.toStringAsFixed(0)}x${size.height.toStringAsFixed(0)}, duration=${durationSeconds.toStringAsFixed(2)}s',
      );
      _emit();
    } on Object catch (error) {
      if (_disposed || requestSerial != _loadSerial) {
        return;
      }
      _positionTimer?.cancel();
      _positionTimer = null;
      videoLoading = false;
      controller = null;
      _controllerPath = null;
      videoInfo = null;
      videoStatus = '${t('detect.decodeFailed')}: $error';
      _log(
        'BROWSE',
        'Video load failed: $input, error=$error',
        level: _LogLevel.error,
      );
      _emit();
    }
  }

  void _startProgressTicker() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_disposed) {
        return;
      }
      _refreshNativePositionAnchor();
      _emitProgress();
    });
  }

  void _refreshNativePositionAnchor() {
    final value = controller?.value;
    if (value == null || !value.isInitialized) {
      return;
    }
    final nativePosition = value.position.inMilliseconds / 1000.0;
    if (nativePosition > 0) {
      _positionAnchorSeconds = _clampPlaybackSeconds(nativePosition);
      if (value.isPlaying) {
        _positionAnchorTime = DateTime.now();
      }
    }
  }

  void _markPlaybackStarted() {
    _positionAnchorSeconds = positionSeconds;
    _positionAnchorTime = DateTime.now();
    _startProgressTicker();
  }

  void _markPlaybackStopped() {
    _positionAnchorSeconds = positionSeconds;
    _positionAnchorTime = null;
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  void toggleFullscreen() {
    fullscreen = !fullscreen;
    _emit();
  }

  void requestFullscreenToggle() {
    if (_disposed || _fullscreenToggleScheduled) {
      return;
    }
    _fullscreenToggleScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fullscreenToggleScheduled = false;
      if (_disposed || !hasInitializedVideo) {
        return;
      }
      toggleFullscreen();
    });
  }

  Future<void> togglePause() async {
    final currentController = controller;
    if (currentController == null || !currentController.value.isInitialized) {
      return;
    }
    if (currentController.value.isPlaying) {
      _markPlaybackStopped();
      await currentController.pause();
    } else {
      await currentController.play();
      _markPlaybackStarted();
    }
    _emit();
  }

  Future<void> seekToSeconds(double seconds) async {
    final currentController = controller;
    if (currentController == null || !currentController.value.isInitialized) {
      return;
    }
    final clamped = _clampPlaybackSeconds(seconds);
    scrubSeconds = clamped;
    _positionAnchorSeconds = clamped;
    _positionAnchorTime = currentController.value.isPlaying
        ? DateTime.now()
        : null;
    _emit();
    await currentController.seekTo(
      Duration(milliseconds: (clamped * 1000).round()),
    );
    if (!_disposed) {
      scrubbing = false;
      scrubSeconds = null;
      _emit();
    }
  }

  void beginScrub(double seconds) {
    scrubbing = true;
    scrubSeconds = _clampPlaybackSeconds(seconds);
    _emit();
  }

  void updateScrub(double seconds) {
    if (!scrubbing) {
      scrubbing = true;
    }
    scrubSeconds = _clampPlaybackSeconds(seconds);
    _emit();
  }

  Future<void> endScrub(double seconds) => seekToSeconds(seconds);

  double _clampPlaybackSeconds(double seconds) {
    final duration = durationSeconds;
    if (duration <= 0) {
      return math.max(0, seconds);
    }
    return seconds.clamp(0.0, duration).toDouble();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    final nextSpeed = speed.clamp(0.25, 3.0).toDouble();
    if ((playbackSpeed - nextSpeed).abs() < 0.001) {
      return;
    }
    _positionAnchorSeconds = positionSeconds;
    _positionAnchorTime = isPlaying ? DateTime.now() : null;
    playbackSpeed = nextSpeed;
    final currentController = controller;
    if (currentController != null && currentController.value.isInitialized) {
      await currentController.setPlaybackSpeed(nextSpeed);
    }
    _emit();
  }

  Future<void> setVolume(double value, {bool showHud = true}) async {
    final nextVolume = value.clamp(0.0, 1.0).toDouble();
    final changed = (volume - nextVolume).abs() >= 0.001;
    if (changed) {
      volume = nextVolume;
      final currentController = controller;
      if (currentController != null && currentController.value.isInitialized) {
        await currentController.setVolume(nextVolume);
      }
    }
    if (showHud) {
      _showShortcutHud(
        '${t('detect.hudVolume')} ${(nextVolume * 100).round()}%',
      );
    }
    if (changed) {
      _emit();
    }
  }

  Future<void> adjustVolume(double delta) => setVolume(volume + delta);

  void setScaleMode(_VideoScaleMode mode) {
    if (scaleMode == mode) {
      return;
    }
    scaleMode = mode;
    _showShortcutHud(t(mode.labelKey));
    _emit();
  }

  Future<void> stepSeconds(double deltaSeconds) async {
    final currentController = controller;
    if (currentController == null || !currentController.value.isInitialized) {
      return;
    }
    final current = positionSeconds;
    await seekToSeconds(current + deltaSeconds);
  }

  Future<void> setPlayMode(bool value) async {
    playVideo = value;
    if (value) {
      predictVideo = false;
      predictAll = false;
      showPredictionResult = false;
    }
    saveResult = saveResult && canSaveResult;
    if (value) {
      _emit();
      await loadSelectedVideoIfNeeded();
    } else {
      _markPlaybackStopped();
      await controller?.pause();
      _emit();
    }
  }

  Future<void> setPredictMode(bool value, _AppSettings settings) async {
    if (value && detectModelPath == null) {
      final model = await _chooseDetectModel(settings);
      if (model == null) {
        _emit();
        return;
      }
      detectModelPath = model;
    }
    predictVideo = value;
    if (value) {
      playVideo = false;
      _markPlaybackStopped();
      await controller?.pause();
    } else if (!playVideo) {
      playVideo = true;
      predictAll = false;
    }
    showPredictionResult = true;
    saveResult = saveResult && canSaveResult;
    _emit();
    if (!predictVideo && playVideo) {
      await loadSelectedVideoIfNeeded();
    }
  }

  Future<void> setPredictAllMode(bool value, _AppSettings settings) async {
    if (value && detectModelPath == null) {
      final model = await _chooseDetectModel(settings);
      if (model == null) {
        _emit();
        return;
      }
      detectModelPath = model;
    }
    predictAll = value;
    if (value) {
      predictVideo = true;
      playVideo = false;
      _markPlaybackStopped();
      await controller?.pause();
    }
    showPredictionResult = true;
    saveResult = saveResult && canSaveResult;
    _emit();
  }

  Future<void> setPredictionOutput(String? path) async {
    predictionOutputPath = path;
    final input = selectedInput;
    if (input != null) {
      cachePredictionOutputForInput(input, path);
    }
    showPredictionResult = path != null;
    if (path != null && _isImagePath(path)) {
      await FileImage(File(path)).evict();
    }
    await _resetVideoController();
    _emit();
    await loadSelectedVideoIfNeeded();
  }

  void cachePredictionOutputForInput(String input, String? path) {
    final key = _pathKey(input);
    if (path == null) {
      _predictionOutputsByInput.remove(key);
    } else {
      _predictionOutputsByInput[key] = path;
    }
  }

  void clearPredictionEffects({String? input}) {
    if (input == null) {
      _predictionOutputsByInput.clear();
    } else {
      _predictionOutputsByInput.remove(_pathKey(input));
    }
    final selectedKey = _pathKey(selectedInput ?? '');
    final clearCurrent = input == null || _pathKey(input) == selectedKey;
    if (clearCurrent) {
      predictionOutputPath = null;
    }
    showPredictionResult = true;
    predictVideo = false;
    predictAll = false;
    saveResult = saveResult && canSaveResult;
  }

  void setSaveResult(bool value) {
    if (!canSaveResult) {
      return;
    }
    saveResult = value;
    _emit();
  }

  void togglePredictionResult() {
    if (!predictVideo && !predictAll && predictionOutputPath == null) {
      return;
    }
    showPredictionResult = !showPredictionResult;
    _emit();
    _resetVideoController().then((_) {
      if (!_disposed) {
        loadSelectedVideoIfNeeded();
      }
    });
  }

  Future<bool> selectRelativeMedia(int delta) async {
    if (folderItems.isEmpty || delta == 0) {
      return false;
    }
    final currentIndex = folderItems.indexWhere(
      (path) => _pathKey(path) == _pathKey(selectedInput ?? ''),
    );
    final baseIndex = currentIndex < 0 ? 0 : currentIndex;
    final nextIndex = (baseIndex + delta).clamp(0, folderItems.length - 1);
    if (nextIndex == baseIndex) {
      return false;
    }
    await selectInput(folderItems[nextIndex]);
    return true;
  }

  void showPreviewPanel() {
    if (!previewPanelVisible) {
      previewPanelVisible = true;
      _emit();
    }
  }

  void hidePreviewPanelIfNeeded() {
    if (folderItems.isNotEmpty && previewPanelVisible) {
      previewPanelVisible = false;
      _emit();
    }
  }

  static Future<String?> _chooseDetectModel(_AppSettings settings) async {
    final initialDirectory = settings.outputPath.isNotEmpty
        ? settings.outputPath
        : _ConfigStore.defaultRunsDirectory.path;
    Directory(initialDirectory).createSync(recursive: true);
    final file = await openFile(
      initialDirectory: initialDirectory,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'YOLO model', extensions: ['pt', 'onnx']),
      ],
    );
    return file?.path;
  }

  KeyEventResult handleShortcutKey(
    KeyEvent event,
    _ShortcutConfig shortcutConfig,
  ) {
    final key = event.logicalKey;

    if (event is KeyUpEvent) {
      if (shortcutConfig.matches(_ShortcutAction.videoFastForward, key)) {
        setPlaybackSpeed(1);
        if (shortcutHud.value?.hold == true) {
          _hideShortcutHud();
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final repeated = event is KeyRepeatEvent;
    final previewStep = repeated ? 3 : 1;
    if (shortcutConfig.matches(_ShortcutAction.videoPlayPause, key)) {
      if (event is KeyDownEvent) {
        final willPause = isPlaying;
        togglePause();
        _showShortcutHud(willPause ? t('detect.paused') : t('detect.playing'));
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) {
        _showShortcutHud(
          fullscreen
              ? t('detect.hudExitFullscreen')
              : t('detect.hudFullscreen'),
        );
        requestFullscreenToggle();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyA) {
      selectRelativeMedia(-previewStep).then((changed) {
        if (!_disposed) {
          _showShortcutHud(
            changed ? t('detect.hudPrevious') : t('detect.hudNoPrevious'),
          );
        }
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyD) {
      selectRelativeMedia(previewStep).then((changed) {
        if (!_disposed) {
          _showShortcutHud(
            changed ? t('detect.hudNext') : t('detect.hudNoNext'),
          );
        }
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      adjustVolume(0.05);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      adjustVolume(-0.05);
      return KeyEventResult.handled;
    }
    if (shortcutConfig.matches(_ShortcutAction.videoRewind, key)) {
      stepSeconds(repeated ? -3 : -1);
      _showShortcutHud(repeated ? '-3s' : '-1s');
      return KeyEventResult.handled;
    }
    if (shortcutConfig.matches(_ShortcutAction.videoFastForward, key)) {
      if (repeated) {
        setPlaybackSpeed(3);
        _showShortcutHud('3x', hold: true);
      } else {
        stepSeconds(1);
        _showShortcutHud('+1s');
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

class _VideoShortcutHud {
  const _VideoShortcutHud({required this.text, required this.hold});

  final String text;
  final bool hold;
}

enum _VideoScaleMode {
  auto,
  ratio4x3,
  ratio16x9,
  fitWidth,
  fitHeight,
  original,
}

extension _VideoScaleModeLabel on _VideoScaleMode {
  String get labelKey => switch (this) {
    _VideoScaleMode.auto => 'detect.scaleAuto',
    _VideoScaleMode.ratio4x3 => 'detect.scale4x3',
    _VideoScaleMode.ratio16x9 => 'detect.scale16x9',
    _VideoScaleMode.fitWidth => 'detect.scaleFitWidth',
    _VideoScaleMode.fitHeight => 'detect.scaleFitHeight',
    _VideoScaleMode.original => 'detect.scaleOriginal',
  };
}

class _DetectVideoPage extends StatefulWidget {
  const _DetectVideoPage({
    required this.settings,
    required this.shortcutConfig,
    required this.session,
  });

  final _AppSettings settings;
  final _ShortcutConfig shortcutConfig;
  final _DetectVideoSession session;

  @override
  State<_DetectVideoPage> createState() => _DetectVideoPageState();
}

class _DetectVideoPageState extends State<_DetectVideoPage> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'detect-video');
  late final TextEditingController _confController;
  late final List<_TrainingDeviceOption> _nvidiaDeviceOptions;
  late final String _autoFallbackDeviceLabel;
  String? _activePredictionCancelPath;
  int? _pendingPredictionStartFrame;
  Timer? _previewHideTimer;
  Timer? _parameterHideTimer;
  bool _parameterPanelVisible = true;

  _DetectVideoSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _confController = TextEditingController(
      text: _session.detectConf.toStringAsFixed(2),
    );
    _nvidiaDeviceOptions = _detectNvidiaDevices();
    _autoFallbackDeviceLabel = _detectPrimaryProcessorName();
    _session.predictAll = false;
    _session.addListener(_handleSessionChanged);
    _schedulePreviewHide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus(_focusNode);
        _session.loadSelectedVideoIfNeeded();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _DetectVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_handleSessionChanged);
      widget.session.addListener(_handleSessionChanged);
      _confController.text = _session.detectConf.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _previewHideTimer?.cancel();
    _parameterHideTimer?.cancel();
    _session.removeListener(_handleSessionChanged);
    _confController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSessionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _focusPage() {
    if (mounted) {
      FocusScope.of(context).requestFocus(_focusNode);
    }
  }

  Future<void> _ensureDetectModel() async {
    if (_session.detectModelPath != null) return;
    final model = await _DetectVideoSession._chooseDetectModel(widget.settings);
    if (model != null) {
      _session.detectModelPath = model;
    }
  }

  Future<void> _chooseDetectModel() async {
    final model = await _DetectVideoSession._chooseDetectModel(widget.settings);
    if (model == null) {
      return;
    }
    _log('DETECT', 'Detect model selected: $model');
    _session.detectModelPath = model;
    _session.clearPredictionEffects();
    await _session._resetVideoController();
    _session._emit();
    await _session.loadSelectedVideoIfNeeded();
  }

  Future<void> _handlePredict() async {
    await _runDetection(save: false, currentOnly: true);
  }

  Future<void> _handlePredictButton() async {
    if (_session.detectModelPath == null) {
      await _ensureDetectModel();
      if (_session.detectModelPath == null) {
        return;
      }
      if (_session.selectedInput == null) {
        _session._emit();
        return;
      }
    }
    await _handlePredict();
  }

  Future<void> _handleSaveCurrent() async {
    await _runDetection(save: true, currentOnly: true);
  }

  Future<void> _handleSaveAll() async {
    await _runDetection(save: true, allImages: true);
  }

  Future<void> _runDetection({
    required bool save,
    int startFrame = 0,
    bool currentOnly = false,
    bool allImages = false,
  }) async {
    if (_session.predicting) {
      _log(
        'DETECT',
        'Detection request ignored: prediction is already running',
        level: _LogLevel.warning,
      );
      return;
    }
    _applyConfText();
    final input = _session.selectedInput;
    if (input == null) {
      _log(
        'DETECT',
        'Detection request blocked: no selected input',
        level: _LogLevel.warning,
      );
      return;
    }
    final pythonPath = widget.settings.pythonPath.trim();
    if (pythonPath.isEmpty) {
      _log(
        'DETECT',
        'Detection request blocked: Python path is empty',
        level: _LogLevel.warning,
      );
      _showDetectMessage(t('detect.pythonNotConfigured'));
      return;
    }
    await _ensureDetectModel();
    final modelPath = _session.detectModelPath;
    if (modelPath == null) {
      _log(
        'DETECT',
        'Detection request blocked: no model selected',
        level: _LogLevel.warning,
      );
      return;
    }
    final targets = _detectionTargets(
      input,
      currentOnly: currentOnly,
      allImages: allImages,
    );
    if (targets.isEmpty) {
      _log(
        'DETECT',
        'Detection request blocked: no image targets for input=$input',
        level: _LogLevel.warning,
      );
      _showDetectMessage(t('detect.noImageTargets'));
      return;
    }
    if (!save && targets.any(_isVideoPath)) {
      _session.playVideo = false;
      _session.predictVideo = true;
      await _session._resetVideoController();
    }
    _session.predicting = true;
    _session.showPredictionResult = true;
    _session.videoStatus = t('detect.predicting');
    _session._emit();
    try {
      var completed = 0;
      var totalLabels = 0;
      final outputDir = await _detectOutputDirectory(
        save: save,
        modelPath: modelPath,
        pythonPath: pythonPath,
      );
      _log(
        'DETECT',
        'Detection started: save=$save, currentOnly=$currentOnly, allImages=$allImages, targets=${targets.length}, model=${_fileName(modelPath)}, device=${_session.detectDevice}, imgsz=${_session.detectImageSize}, conf=${_session.detectConf.toStringAsFixed(2)}, outputDir=$outputDir, startFrame=$startFrame',
      );
      for (final target in targets) {
        if (!mounted) {
          return;
        }
        final isVideo = _isVideoPath(target);
        _session.videoStatus =
            '${t('detect.predicting')} ${completed + 1}/${targets.length}: '
            '${_fileName(target)}';
        _session._emit();
        final outputName = _detectOutputName(target, save: save);
        final previewVideo = isVideo && !save;
        final cancelPath = previewVideo ? _detectCancelPath(target) : '';
        if (previewVideo) {
          _activePredictionCancelPath = cancelPath;
          _clearCancelFile(cancelPath);
          final manifestPath = _joinPath(outputDir, outputName);
          _writeEmptyPredictionManifest(manifestPath, startFrame: startFrame);
          _session.cachePredictionOutputForInput(target, manifestPath);
          if (_pathKey(target) == _pathKey(_session.selectedInput ?? '')) {
            _session.predictVideo = true;
            _session.showPredictionResult = true;
            await _session.setPredictionOutput(manifestPath);
          }
        }
        final result = await _RustVideoBackend.detect(
          mode: isVideo ? 'video' : 'image',
          pythonPath: pythonPath,
          modelPath: modelPath,
          inputPath: target,
          outputDir: outputDir,
          outputName: outputName,
          confThreshold: _session.detectConf,
          iouThreshold: 0.45,
          imgsz: _session.detectImageSize,
          device: _session.detectDevice,
          previewFrames: previewVideo,
          cancelPath: cancelPath,
          startFrame: previewVideo ? startFrame : 0,
        );
        if (_pathKey(_activePredictionCancelPath ?? '') ==
            _pathKey(cancelPath)) {
          _activePredictionCancelPath = null;
        }
        if (!mounted) {
          return;
        }
        if (!result.ok) {
          final error = result.error ?? t('detect.detectFailed');
          _session.videoStatus = '${t('detect.detectFailed')}: $error';
          _log(
            'DETECT',
            'Detection target failed: target=$target, error=$error',
            level: _LogLevel.error,
          );
          _showDetectMessage(_session.videoStatus!);
          return;
        }
        completed += 1;
        totalLabels += result.labelCount;
        _log(
          'DETECT',
          'Detection target completed: target=$target, labels=${result.labelCount}, output=${result.outputPath}',
          level: _LogLevel.debug,
        );
        _session.cachePredictionOutputForInput(target, result.outputPath);
        if (_pathKey(target) == _pathKey(_session.selectedInput ?? '')) {
          _session.predictVideo = isVideo;
          _session.showPredictionResult = true;
          await _session.setPredictionOutput(result.outputPath);
        }
      }
      _session.videoStatus =
          '${save ? t('detect.saveDone') : t('detect.detectDone')} '
          '${targets.length}/${targets.length} '
          '(${t('detect.detectCount')}: $totalLabels)';
      _log(
        'DETECT',
        'Detection completed: save=$save, targets=${targets.length}, labels=$totalLabels',
      );
      _showDetectMessage(_session.videoStatus!);
    } on Object catch (error) {
      _log('DETECT', 'Detection failed: $error', level: _LogLevel.error);
      _session.videoStatus = '${t('detect.detectFailed')}: $error';
      _showDetectMessage(_session.videoStatus!);
    } finally {
      if (mounted) {
        _session.predicting = false;
        _session._emit();
      }
      final restartFrame = _pendingPredictionStartFrame;
      _pendingPredictionStartFrame = null;
      if (mounted && restartFrame != null) {
        await _runDetection(
          save: false,
          startFrame: restartFrame,
          currentOnly: true,
        );
      }
    }
  }

  List<String> _detectionTargets(
    String currentInput, {
    required bool currentOnly,
    required bool allImages,
  }) {
    if (currentOnly || !allImages) {
      return [currentInput];
    }
    final targets = _session.folderItems
        .where(_isImagePath)
        .toList(growable: false);
    if (targets.isNotEmpty) {
      return targets;
    }
    return _isImagePath(currentInput) ? [currentInput] : const [];
  }

  Future<String> _detectOutputDirectory({
    required bool save,
    String? modelPath,
    String? pythonPath,
  }) async {
    final root = widget.settings.outputPath.trim().isNotEmpty
        ? widget.settings.outputPath.trim()
        : _ConfigStore.defaultRunsDirectory.path;
    final directory = save
        ? _nextDetectRunDirectory(
            root,
            await _detectTaskFolderName(
              modelPath: modelPath,
              pythonPath: pythonPath,
            ),
          )
        : Directory(_joinPath(root, 'detect_preview'));
    directory.createSync(recursive: true);
    return directory.path;
  }

  Directory _nextDetectRunDirectory(String root, String taskFolder) {
    final taskRoot = Directory(_joinPath(root, taskFolder));
    taskRoot.createSync(recursive: true);
    var index = 1;
    while (true) {
      final folderName = index == 1 ? 'detect' : 'detect$index';
      final candidate = Directory(_joinPath(taskRoot.path, folderName));
      if (!candidate.existsSync()) {
        return candidate;
      }
      index += 1;
    }
  }

  Future<String> _detectTaskFolderName({
    required String? modelPath,
    required String? pythonPath,
  }) async {
    if (modelPath == null || modelPath.trim().isEmpty) {
      return 'hbb';
    }
    if (pythonPath == null || pythonPath.trim().isEmpty) {
      return 'hbb';
    }
    try {
      final result = await _RustVideoBackend.detectModelTask(
        pythonPath: pythonPath,
        modelPath: modelPath,
      );
      if (result.ok && result.folder.trim().isNotEmpty) {
        return result.folder.trim();
      }
    } on Object {
      // Fall back to HBB if model inspection fails.
    }
    return 'hbb';
  }

  String _detectOutputName(String input, {required bool save}) {
    final stem = _baseNameWithoutExtension(input);
    final extension = _isVideoPath(input) ? (save ? '.mp4' : '.json') : '.jpg';
    final suffix = save ? 'pred' : 'preview_${_pathHash(input)}';
    return '${stem}_$suffix$extension';
  }

  String _detectCancelPath(String input) {
    return _joinPath(
      _detectPreviewDirectory(),
      '${_baseNameWithoutExtension(input)}_${_pathHash(input)}.cancel',
    );
  }

  String _detectPreviewDirectory() {
    final root = widget.settings.outputPath.trim().isNotEmpty
        ? widget.settings.outputPath.trim()
        : _ConfigStore.defaultRunsDirectory.path;
    final directory = Directory(_joinPath(root, 'detect_preview'));
    directory.createSync(recursive: true);
    return directory.path;
  }

  void _clearCancelFile(String path) {
    if (path.isEmpty) {
      return;
    }
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } on Object {
      // Best effort; the Python side will still start if the path is absent.
    }
  }

  void _cancelActivePrediction() {
    final path = _activePredictionCancelPath;
    if (path == null || path.isEmpty) {
      return;
    }
    try {
      File(path).writeAsStringSync('cancel');
      _log('DETECT', 'Prediction cancellation requested: $path');
    } on Object catch (error) {
      _log(
        'DETECT',
        'Prediction cancellation failed: $path, error=$error',
        level: _LogLevel.error,
      );
      _showDetectMessage('${t('detect.detectFailed')}: $error');
    }
  }

  void _requestPredictionSeek(int frameNumber) {
    if (_session.selectedInput == null ||
        !_isVideoPath(_session.selectedInput!)) {
      return;
    }
    final targetFrame = math.max(0, frameNumber);
    _log(
      'DETECT',
      'Prediction seek requested: frame=$targetFrame, predicting=${_session.predicting}',
      level: _LogLevel.debug,
    );
    if (_session.predicting) {
      _pendingPredictionStartFrame = targetFrame;
      _cancelActivePrediction();
    } else {
      _runDetection(save: false, startFrame: targetFrame, currentOnly: true);
    }
  }

  void _writeEmptyPredictionManifest(String path, {required int startFrame}) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({
        'ok': true,
        'type': 'frames',
        'fps': 25.0,
        'totalFrames': 0,
        'startFrame': startFrame,
        'complete': false,
        'canceled': false,
        'frames': const [],
      }),
    );
  }

  String _pathHash(String input) {
    return _pathKey(input).hashCode.toUnsigned(32).toRadixString(16);
  }

  void _applyConfText() {
    final parsed = double.tryParse(_confController.text.trim());
    if (parsed == null) {
      _confController.text = _session.detectConf.toStringAsFixed(2);
      return;
    }
    final clamped = parsed.clamp(0.01, 1.0).toDouble();
    _session.detectConf = clamped;
    final normalized = clamped.toStringAsFixed(2);
    if (_confController.text != normalized) {
      _confController.text = normalized;
    }
    _session._emit();
  }

  void _showDetectMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _schedulePreviewHide() {
    _previewHideTimer?.cancel();
    _previewHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        _session.hidePreviewPanelIfNeeded();
      }
    });
  }

  void _showPreviewPanel() {
    _previewHideTimer?.cancel();
    _session.showPreviewPanel();
  }

  void _showParameterPanel() {
    _parameterHideTimer?.cancel();
    if (!_parameterPanelVisible && mounted) {
      setState(() => _parameterPanelVisible = true);
    }
  }

  void _scheduleParameterHide() {
    _parameterHideTimer?.cancel();
    _parameterHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _parameterPanelVisible = false);
      }
    });
  }

  Future<void> _resetPredictionEffect() async {
    final input = _session.selectedInput;
    _session.clearPredictionEffects(input: input);
    await _session._resetVideoController();
    _session._emit();
    await _session.loadSelectedVideoIfNeeded();
  }

  Future<void> _handleTogglePredictionResult() async {
    final selectedInput = _session.selectedInput;
    final switchingToPrediction = !_session.showPredictionResult;
    final cachedPrediction = _session.predictionOutputPath;
    final hasCachedPrediction =
        cachedPrediction != null && File(cachedPrediction).existsSync();
    _session.togglePredictionResult();
    if (!switchingToPrediction ||
        hasCachedPrediction ||
        selectedInput == null ||
        !_isVideoPath(selectedInput) ||
        _session.predicting) {
      return;
    }
    final startFrame = _currentVideoFrame();
    await _runDetection(save: false, startFrame: startFrame, currentOnly: true);
  }

  int _currentVideoFrame() {
    final fps = _session.videoInfo?.fps;
    final safeFps = fps == null || fps <= 0 ? 25.0 : fps;
    return math.max(0, (_session.positionSeconds * safeFps).round());
  }

  Future<void> _chooseMediaFile() async {
    _focusPage();
    await _session.chooseMediaFile();
  }

  Future<void> _chooseFolder() async {
    _focusPage();
    await _session.chooseFolder();
    _schedulePreviewHide();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final predictionPreviewActive =
        _session.predicting ||
        _isPredictionManifestPath(_session.predictionOutputPath ?? '');
    if (predictionPreviewActive &&
        (widget.shortcutConfig.matches(_ShortcutAction.videoFastForward, key) ||
            widget.shortcutConfig.matches(_ShortcutAction.videoRewind, key))) {
      return KeyEventResult.handled;
    }
    if (_session.predicting &&
        event is KeyDownEvent &&
        widget.shortcutConfig.matches(_ShortcutAction.videoPlayPause, key)) {
      _cancelActivePrediction();
      return KeyEventResult.handled;
    }
    return _session.handleShortcutKey(event, widget.shortcutConfig);
  }

  @override
  Widget build(BuildContext context) {
    final deviceValue = _detectDeviceOptions.contains(_session.detectDevice)
        ? _session.detectDevice
        : 'auto';
    final nvidiaDeviceLabel =
        _nvidiaDeviceOptions.firstOrNullValue?.label ??
        t('detect.deviceNvUnavailable');
    final autoDeviceLabel =
        '${t('detect.deviceAuto')} | '
        '${_friendlyDeviceLabel(_nvidiaDeviceOptions.firstOrNullValue?.label ?? _autoFallbackDeviceLabel)}';
    return Expanded(
      child: Row(
        children: [
          Expanded(
            child: Focus(
              focusNode: _focusNode,
              autofocus: true,
              descendantsAreFocusable: false,
              descendantsAreTraversable: false,
              onKeyEvent: _handleKeyEvent,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _focusPage(),
                child: Container(
                  color: _workspaceColor(context),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('detect.title'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _chooseMediaFile,
                            icon: const Icon(Icons.perm_media_outlined),
                            label: Text(t('detect.chooseFile')),
                          ),
                          OutlinedButton.icon(
                            onPressed: _chooseFolder,
                            icon: const Icon(Icons.folder_open),
                            label: Text(t('detect.chooseFolder')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_session.selectedInput != null)
                        Text(
                          '${t('detect.fileName')}: ${_fileName(_session.selectedInput!)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (widget.settings.outputPath.isNotEmpty)
                        Text(
                          '${t('path.trainingOutput')}: ${widget.settings.outputPath}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: Row(
                          children: [
                            if (_session.folderItems.isNotEmpty)
                              MouseRegion(
                                onEnter: (_) => _showPreviewPanel(),
                                onHover: (_) => _showPreviewPanel(),
                                onExit: (_) => _schedulePreviewHide(),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  width: _session.previewPanelVisible ? 220 : 8,
                                  margin: const EdgeInsets.only(right: 12),
                                  decoration: BoxDecoration(
                                    color: _panelColor(context),
                                    border: Border.all(
                                      color: _borderColor(context),
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: ClipRect(
                                    child: _session.previewPanelVisible
                                        ? _DetectPreviewList(
                                            items: _session.folderItems,
                                            selectedInput:
                                                _session.selectedInput,
                                            onSelected: (path) {
                                              _focusPage();
                                              _session.selectInput(path);
                                            },
                                          )
                                        : const SizedBox.expand(),
                                  ),
                                ),
                              ),
                            Expanded(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: _panelColor(context),
                                  border: Border.all(
                                    color: _borderColor(context),
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: _DetectPlaybackSurface(
                                  session: _session,
                                  onCancelPrediction: _cancelActivePrediction,
                                  onSeekPredictionFrame: _requestPredictionSeek,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          MouseRegion(
            onEnter: (_) => _showParameterPanel(),
            onHover: (_) => _showParameterPanel(),
            onExit: (_) => _scheduleParameterHide(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: _parameterPanelVisible ? 320 : 8,
              decoration: BoxDecoration(
                color: _panelColor(context),
                border: Border(left: BorderSide(color: _borderColor(context))),
              ),
              child: ClipRect(
                child: _parameterPanelVisible
                    ? _DetectParameterPanel(
                        session: _session,
                        confController: _confController,
                        deviceValue: deviceValue,
                        autoDeviceLabel: autoDeviceLabel,
                        nvidiaDeviceLabel: nvidiaDeviceLabel,
                        onChooseModel: () => unawaited(_chooseDetectModel()),
                        onResetEffect: () =>
                            unawaited(_resetPredictionEffect()),
                        onPredict: () => unawaited(_handlePredictButton()),
                        onSaveCurrent: () => unawaited(_handleSaveCurrent()),
                        onSaveAll: () => unawaited(_handleSaveAll()),
                        onToggleResult: () =>
                            unawaited(_handleTogglePredictionResult()),
                        onApplyConf: _applyConfText,
                        onImageSizeChanged: (value) {
                          _session.detectImageSize = value;
                          _session._emit();
                        },
                        onDeviceChanged: (value) {
                          _session.detectDevice = value;
                          _session._emit();
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

class _DetectPreviewList extends StatelessWidget {
  const _DetectPreviewList({
    required this.items,
    required this.selectedInput,
    required this.onSelected,
  });

  final List<String> items;
  final String? selectedInput;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final selected = _pathKey(item) == _pathKey(selectedInput ?? '');
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => onSelected(item),
            borderRadius: BorderRadius.circular(6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : _controlColor(context),
                border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : _borderColor(context),
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _isImagePath(item)
                          ? Image.file(File(item), fit: BoxFit.cover)
                          : const Center(
                              child: Icon(Icons.video_file_outlined, size: 32),
                            ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _fileName(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DetectParameterPanel extends StatelessWidget {
  const _DetectParameterPanel({
    required this.session,
    required this.confController,
    required this.deviceValue,
    required this.autoDeviceLabel,
    required this.nvidiaDeviceLabel,
    required this.onChooseModel,
    required this.onResetEffect,
    required this.onPredict,
    required this.onSaveCurrent,
    required this.onSaveAll,
    required this.onToggleResult,
    required this.onApplyConf,
    required this.onImageSizeChanged,
    required this.onDeviceChanged,
  });

  final _DetectVideoSession session;
  final TextEditingController confController;
  final String deviceValue;
  final String autoDeviceLabel;
  final String nvidiaDeviceLabel;
  final VoidCallback onChooseModel;
  final VoidCallback onResetEffect;
  final VoidCallback onPredict;
  final VoidCallback onSaveCurrent;
  final VoidCallback onSaveAll;
  final VoidCallback onToggleResult;
  final VoidCallback onApplyConf;
  final ValueChanged<int> onImageSizeChanged;
  final ValueChanged<String> onDeviceChanged;

  bool get _hasFolderImageTargets => session.folderItems.any(_isImagePath);

  bool get _canRunCurrent =>
      !session.predicting && session.selectedInput != null;

  @override
  Widget build(BuildContext context) {
    final selectedModel = session.detectModelPath;
    final hasPrediction = session.predictionOutputPath != null;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('detect.parameters'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              children: [
                _ParameterSectionTitle(title: t('detect.model')),
                Row(
                  children: [
                    Expanded(
                      child: Tooltip(
                        message: selectedModel ?? t('detect.chooseModel'),
                        waitDuration: const Duration(milliseconds: 500),
                        child: OutlinedButton.icon(
                          onPressed: session.predicting ? null : onChooseModel,
                          icon: const Icon(Icons.folder_open, size: 16),
                          label: Text(
                            selectedModel == null
                                ? t('detect.chooseModel')
                                : _fileName(selectedModel),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    if (selectedModel != null) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: session.predicting ? null : onResetEffect,
                        icon: const Icon(Icons.restart_alt, size: 16),
                        label: Text(t('detect.resetEffect')),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                _ParameterSectionTitle(title: t('detect.actions')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(t('detect.playVideo')),
                  value: session.playVideo,
                  onChanged: session.predicting
                      ? null
                      : (value) => unawaited(session.setPlayMode(value)),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: session.predicting ? null : onPredict,
                    icon: session.predicting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.visibility, size: 16),
                    label: Text(
                      session.predicting
                          ? t('detect.predicting')
                          : selectedModel == null
                          ? t('detect.chooseModel')
                          : t('detect.predict'),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _canRunCurrent ? onSaveCurrent : null,
                        icon: const Icon(Icons.save_alt, size: 16),
                        label: Text(t('detect.saveCurrent')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: !session.predicting && _hasFolderImageTargets
                            ? onSaveAll
                            : null,
                        icon: const Icon(Icons.library_add_check, size: 16),
                        label: Text(t('detect.saveAll')),
                      ),
                    ),
                  ],
                ),
                if (hasPrediction) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onToggleResult,
                      icon: const Icon(Icons.compare, size: 16),
                      label: Text(
                        session.showPredictionResult
                            ? t('detect.showOriginal')
                            : t('detect.showPredicted'),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                _ParameterSectionTitle(title: t('detect.inferenceParams')),
                DropdownButtonFormField<int>(
                  initialValue: session.detectImageSize,
                  items: [
                    for (final size in _detectImageSizeOptions)
                      DropdownMenuItem(value: size, child: Text('$size')),
                  ],
                  onChanged: session.predicting
                      ? null
                      : (value) {
                          if (value != null) {
                            onImageSizeChanged(value);
                          }
                        },
                  decoration: InputDecoration(
                    labelText: t('detect.imgsz'),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: confController,
                  enabled: !session.predicting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onEditingComplete: onApplyConf,
                  onSubmitted: (_) => onApplyConf(),
                  decoration: InputDecoration(
                    labelText: t('detect.conf'),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Tooltip(
                  message: t('detect.deviceHelp'),
                  waitDuration: const Duration(milliseconds: 500),
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: deviceValue,
                    items: [
                      DropdownMenuItem(
                        value: 'auto',
                        child: Text(
                          autoDeviceLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'nv',
                        child: Text(
                          nvidiaDeviceLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'cpu',
                        child: Text(t('detect.deviceCpu')),
                      ),
                    ],
                    onChanged: session.predicting
                        ? null
                        : (value) {
                            if (value != null) {
                              onDeviceChanged(value);
                            }
                          },
                    decoration: InputDecoration(
                      labelText: t('detect.device'),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetectPlaybackSurface extends StatelessWidget {
  const _DetectPlaybackSurface({
    required this.session,
    required this.onCancelPrediction,
    required this.onSeekPredictionFrame,
  });

  final _DetectVideoSession session;
  final VoidCallback onCancelPrediction;
  final ValueChanged<int> onSeekPredictionFrame;

  @override
  Widget build(BuildContext context) {
    final input = session.displayInput;
    final showPredictionStatus =
        session.predictVideo ||
        session.predictAll ||
        session.predictionOutputPath != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: null,
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: input == null
                  ? Text(t('detect.placeholder'))
                  : _isImagePath(input)
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Image.file(
                        File(input),
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    )
                  : _isPredictionManifestPath(input)
                  ? _PredictedFrameSequencePanel(
                      manifestPath: input,
                      predicting: session.predicting,
                      onCancelPrediction: onCancelPrediction,
                      onSeekFrame: onSeekPredictionFrame,
                    )
                  : _VideoPlayerPanel(session: session),
            ),
          ),
          if (input != null && showPredictionStatus)
            Positioned(
              right: 14,
              top: 14,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _controlColor(context).withAlpha(232),
                  border: Border.all(color: _borderColor(context)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Text(
                    session.showPredictionResult
                        ? t('detect.resultVisible')
                        : t('detect.resultHidden'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PredictedFrameSequencePanel extends StatefulWidget {
  const _PredictedFrameSequencePanel({
    required this.manifestPath,
    required this.predicting,
    required this.onCancelPrediction,
    required this.onSeekFrame,
  });

  final String manifestPath;
  final bool predicting;
  final VoidCallback onCancelPrediction;
  final ValueChanged<int> onSeekFrame;

  @override
  State<_PredictedFrameSequencePanel> createState() =>
      _PredictedFrameSequencePanelState();
}

class _PredictedFrameSequencePanelState
    extends State<_PredictedFrameSequencePanel> {
  Timer? _timer;
  Timer? _pollTimer;
  _PredictionFrameManifest? _manifest;
  String? _error;
  double? _scrubFrame;
  bool _paused = false;
  bool _advancingFrame = false;
  int _frameRequestSerial = 0;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _loadManifest();
  }

  @override
  void didUpdateWidget(covariant _PredictedFrameSequencePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manifestPath != widget.manifestPath) {
      _loadManifest();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _loadManifest() {
    _timer?.cancel();
    _pollTimer?.cancel();
    _timer = null;
    _pollTimer = null;
    _advancingFrame = false;
    _frameRequestSerial += 1;
    _index = 0;
    _paused = false;
    _scrubFrame = null;
    _refreshManifest(resetPlayback: true);
    _pollTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _refreshManifest(resetPlayback: false);
    });
  }

  void _refreshManifest({required bool resetPlayback}) {
    try {
      final manifest = _PredictionFrameManifest.load(widget.manifestPath);
      final previous = _manifest;
      final previousLength = previous?.frames.length ?? 0;
      final changed =
          resetPlayback ||
          previous == null ||
          previous.frames.length != manifest.frames.length ||
          previous.complete != manifest.complete ||
          previous.canceled != manifest.canceled ||
          previous.totalFrames != manifest.totalFrames ||
          previous.startFrame != manifest.startFrame;
      if (!changed) {
        return;
      }
      setState(() {
        _manifest = manifest;
        _error = null;
        if (_index >= manifest.frames.length) {
          _index = math.max(0, manifest.frames.length - 1);
        }
      });
      if (resetPlayback || previousLength <= 1 && manifest.frames.length > 1) {
        _startPlayback(manifest);
      }
    } on Object catch (error) {
      setState(() {
        _manifest = null;
        _error = '$error';
      });
    }
  }

  void _startPlayback(_PredictionFrameManifest manifest) {
    _timer?.cancel();
    if (_paused) {
      return;
    }
    if (manifest.frames.length <= 1) {
      return;
    }
    final fps = manifest.fps.clamp(1.0, 60.0).toDouble();
    final intervalMs = math.max(16, (1000 / fps).round());
    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (!mounted || manifest.frames.isEmpty) {
        return;
      }
      final current = _manifest;
      if (current == null || current.frames.isEmpty || _paused) {
        return;
      }
      if (!_advancingFrame && _index + 1 < current.frames.length) {
        unawaited(_showFrameIndex(_index + 1));
      }
    });
  }

  Future<void> _showFrameIndex(int targetIndex) async {
    final current = _manifest;
    if (!mounted || current == null || current.frames.isEmpty) {
      return;
    }
    final nextIndex = targetIndex.clamp(0, current.frames.length - 1).toInt();
    if (nextIndex == _index) {
      return;
    }

    final requestSerial = _frameRequestSerial + 1;
    _frameRequestSerial = requestSerial;
    _advancingFrame = true;
    try {
      await precacheImage(
        FileImage(File(current.frames[nextIndex].path)),
        context,
      );
    } on Object {
      // If an output frame is corrupt or still locked, keep moving so the
      // normal image error path can surface instead of freezing playback.
    } finally {
      if (requestSerial == _frameRequestSerial) {
        _advancingFrame = false;
      }
    }

    if (!mounted || requestSerial != _frameRequestSerial) {
      return;
    }
    final latest = _manifest;
    if (latest == null || latest.frames.isEmpty) {
      return;
    }
    final safeIndex = nextIndex.clamp(0, latest.frames.length - 1).toInt();
    setState(() => _index = safeIndex);
  }

  void _togglePause() {
    if (widget.predicting) {
      widget.onCancelPrediction();
      return;
    }
    setState(() => _paused = !_paused);
    if (_paused) {
      _timer?.cancel();
      _timer = null;
    } else {
      final manifest = _manifest;
      if (manifest != null) {
        _startPlayback(manifest);
      }
    }
  }

  void _seekTo(double value) {
    final target = value.round();
    final generatedIndex = _nearestGeneratedFrameIndex(target);
    final generatedFrames = _manifest?.frames ?? const <_PredictionFrameInfo>[];
    final generatedFrameValue = generatedFrames.isEmpty
        ? null
        : generatedFrames[generatedIndex].frameNumber.toDouble();
    setState(() {
      _scrubFrame = generatedFrameValue;
    });
    unawaited(
      _showFrameIndex(generatedIndex).whenComplete(() {
        if (mounted) {
          setState(() => _scrubFrame = null);
        }
      }),
    );
    widget.onSeekFrame(target);
  }

  int _nearestGeneratedFrameIndex(int frameNumber) {
    final frames = _manifest?.frames ?? const <_PredictionFrameInfo>[];
    if (frames.isEmpty) {
      return 0;
    }
    var bestIndex = 0;
    var bestDistance = (frames.first.frameNumber - frameNumber).abs();
    for (var i = 1; i < frames.length; i += 1) {
      final distance = (frames[i].frameNumber - frameNumber).abs();
      if (distance < bestDistance) {
        bestIndex = i;
        bestDistance = distance;
      }
    }
    return bestIndex;
  }

  @override
  Widget build(BuildContext context) {
    final manifest = _manifest;
    if (_error != null) {
      return Center(
        child: Text(
          '${t('detect.decodeFailed')}: $_error',
          style: const TextStyle(color: Colors.white),
        ),
      );
    }
    if (manifest == null || manifest.frames.isEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: _PredictionWaitingIndicator(
              text: t('detect.predictingFrame'),
            ),
          ),
          _PredictionFrameControls(
            frameValue: _scrubFrame ?? manifest?.startFrame.toDouble() ?? 0,
            maxFrame: math.max(1, manifest?.totalFrames ?? 1).toDouble(),
            predicting: widget.predicting,
            paused: _paused,
            onPause: _togglePause,
            onChanged: (value) => setState(() => _scrubFrame = value),
            onChangeEnd: _seekTo,
          ),
        ],
      );
    }
    final frame = manifest.frames[_index.clamp(0, manifest.frames.length - 1)];
    final waitingForNextFrame =
        widget.predicting &&
        !manifest.complete &&
        _index >= manifest.frames.length - 1;
    final maxFrame = math.max(
      frame.frameNumber + 1,
      manifest.totalFrames > 0 ? manifest.totalFrames - 1 : frame.frameNumber,
    );
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Image.file(
              File(frame.path),
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
          if (waitingForNextFrame)
            Center(
              child: _PredictionWaitingIndicator(
                text: t('detect.predictingFrame'),
              ),
            ),
          Positioned(
            left: 18,
            top: 18,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(182),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Text(
                  'pre ${frame.preprocessMs.toStringAsFixed(1)} ms  |  '
                  'infer ${frame.inferenceMs.toStringAsFixed(1)} ms  |  '
                  'post ${frame.postprocessMs.toStringAsFixed(1)} ms',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          _PredictionFrameControls(
            frameValue: _scrubFrame ?? frame.frameNumber.toDouble(),
            maxFrame: math.max(1, maxFrame).toDouble(),
            predicting: widget.predicting,
            paused: _paused,
            onPause: _togglePause,
            onChanged: (value) => setState(() => _scrubFrame = value),
            onChangeEnd: _seekTo,
          ),
        ],
      ),
    );
  }
}

class _PredictionFrameControls extends StatelessWidget {
  const _PredictionFrameControls({
    required this.frameValue,
    required this.maxFrame,
    required this.predicting,
    required this.paused,
    required this.onPause,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double frameValue;
  final double maxFrame;
  final bool predicting;
  final bool paused;
  final VoidCallback onPause;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final value = frameValue.clamp(0.0, maxFrame).toDouble();
    return Positioned(
      left: 18,
      right: 18,
      bottom: 18,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(182),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              IconButton(
                color: Colors.white,
                tooltip: predicting ? t('detect.paused') : t('detect.playing'),
                onPressed: onPause,
                icon: Icon(
                  predicting || !paused ? Icons.pause : Icons.play_arrow,
                ),
              ),
              Expanded(
                child: Slider(
                  value: value,
                  min: 0,
                  max: maxFrame,
                  onChanged: onChanged,
                  onChangeEnd: onChangeEnd,
                ),
              ),
              SizedBox(
                width: 92,
                child: Text(
                  '${value.round()} / ${maxFrame.round()}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PredictionWaitingIndicator extends StatelessWidget {
  const _PredictionWaitingIndicator({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(182),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Text(text, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _PredictionFrameManifest {
  const _PredictionFrameManifest({
    required this.fps,
    required this.totalFrames,
    required this.startFrame,
    required this.complete,
    required this.canceled,
    required this.frames,
  });

  final double fps;
  final int totalFrames;
  final int startFrame;
  final bool complete;
  final bool canceled;
  final List<_PredictionFrameInfo> frames;

  static _PredictionFrameManifest load(String path) {
    final decoded = jsonDecode(File(path).readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Invalid prediction manifest');
    }
    final rawFrames = decoded['frames'];
    if (rawFrames is! List) {
      throw StateError('Prediction manifest has no frames');
    }
    return _PredictionFrameManifest(
      fps: (decoded['fps'] as num?)?.toDouble() ?? 25.0,
      totalFrames: (decoded['totalFrames'] as num?)?.round() ?? 0,
      startFrame: (decoded['startFrame'] as num?)?.round() ?? 0,
      complete: decoded['complete'] == true,
      canceled: decoded['canceled'] == true,
      frames: [
        for (final item in rawFrames)
          if (item is Map)
            _PredictionFrameInfo(
              path: '${item['path'] ?? ''}'.replaceAll('/', '\\'),
              frameNumber: (item['frameNumber'] as num?)?.round() ?? 0,
              preprocessMs: (item['preprocessMs'] as num?)?.toDouble() ?? 0,
              inferenceMs: (item['inferenceMs'] as num?)?.toDouble() ?? 0,
              postprocessMs: (item['postprocessMs'] as num?)?.toDouble() ?? 0,
            ),
      ],
    );
  }
}

class _PredictionFrameInfo {
  const _PredictionFrameInfo({
    required this.path,
    required this.frameNumber,
    required this.preprocessMs,
    required this.inferenceMs,
    required this.postprocessMs,
  });

  final String path;
  final int frameNumber;
  final double preprocessMs;
  final double inferenceMs;
  final double postprocessMs;
}

class _VideoFullscreenOverlay extends StatefulWidget {
  const _VideoFullscreenOverlay({
    required this.session,
    required this.shortcutConfig,
  });

  final _DetectVideoSession session;
  final _ShortcutConfig shortcutConfig;

  @override
  State<_VideoFullscreenOverlay> createState() =>
      _VideoFullscreenOverlayState();
}

class _VideoFullscreenOverlayState extends State<_VideoFullscreenOverlay> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'video-fullscreen');
  Timer? _closeButtonHideTimer;
  bool _closeButtonVisible = true;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_handleSessionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus(_focusNode);
        _showCloseButton();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _VideoFullscreenOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_handleSessionChanged);
      widget.session.addListener(_handleSessionChanged);
    }
  }

  @override
  void dispose() {
    _closeButtonHideTimer?.cancel();
    widget.session.removeListener(_handleSessionChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSessionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _focusOverlay() {
    if (mounted) {
      FocusScope.of(context).requestFocus(_focusNode);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      widget.session.requestFullscreenToggle();
      return KeyEventResult.handled;
    }
    return widget.session.handleShortcutKey(event, widget.shortcutConfig);
  }

  void _showCloseButton() {
    _closeButtonHideTimer?.cancel();
    if (!_closeButtonVisible && mounted) {
      setState(() => _closeButtonVisible = true);
    }
    _closeButtonHideTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() => _closeButtonVisible = false);
      }
    });
  }

  void _hideCloseButton() {
    _closeButtonHideTimer?.cancel();
    if (_closeButtonVisible && mounted) {
      setState(() => _closeButtonVisible = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _focusOverlay(),
          child: MouseRegion(
            onEnter: (_) => _showCloseButton(),
            onHover: (_) => _showCloseButton(),
            onExit: (_) => _hideCloseButton(),
            child: Stack(
              children: [
                Positioned.fill(
                  child: _VideoPlayerPanel(
                    session: widget.session,
                    fullscreen: true,
                  ),
                ),
                Positioned(
                  right: 18,
                  top: 18,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: _closeButtonVisible ? 1 : 0,
                    child: IgnorePointer(
                      ignoring: !_closeButtonVisible,
                      child: IconButton(
                        color: Colors.white,
                        tooltip: t('action.close'),
                        onPressed: widget.session.requestFullscreenToggle,
                        icon: const Icon(Icons.fullscreen_exit),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoPlayerPanel extends StatelessWidget {
  const _VideoPlayerPanel({required this.session, this.fullscreen = false});

  final _DetectVideoSession session;
  final bool fullscreen;

  @override
  Widget build(BuildContext context) {
    if (session.fullscreen && !fullscreen) {
      return const SizedBox.expand(child: ColoredBox(color: Colors.black));
    }

    final controller = session.controller;
    if (controller == null) {
      return _VideoPlayerShell(
        session: session,
        fullscreen: fullscreen,
        child: _VideoPlaceholder(loading: session.videoLoading),
      );
    }

    return ValueListenableBuilder<video_player_win.WinVideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final initialized = value.isInitialized;
        return _VideoPlayerShell(
          session: session,
          value: value,
          fullscreen: fullscreen,
          child: initialized
              ? _ScaledVideoSurface(
                  controller: controller,
                  value: value,
                  mode: session.scaleMode,
                )
              : _VideoPlaceholder(loading: session.videoLoading),
        );
      },
    );
  }
}

class _ScaledVideoSurface extends StatelessWidget {
  const _ScaledVideoSurface({
    required this.controller,
    required this.value,
    required this.mode,
  });

  final video_player_win.WinVideoPlayerController controller;
  final video_player_win.WinVideoPlayerValue value;
  final _VideoScaleMode mode;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounds = Size(constraints.maxWidth, constraints.maxHeight);
        if (bounds.width <= 0 ||
            bounds.height <= 0 ||
            !bounds.width.isFinite ||
            !bounds.height.isFinite) {
          return const SizedBox.shrink();
        }
        final sourceSize = _videoSourceSize(value);
        final childSize = _scaledVideoSize(
          bounds: bounds,
          sourceSize: sourceSize,
          sourceAspect: _safeVideoAspect(value),
          mode: mode,
        );
        return ClipRect(
          child: Center(
            child: SizedBox(
              width: childSize.width,
              height: childSize.height,
              child: ExcludeSemantics(
                child: video_player_win.WinVideoPlayer(controller),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VideoPlayerShell extends StatefulWidget {
  const _VideoPlayerShell({
    required this.session,
    required this.child,
    required this.fullscreen,
    this.value,
  });

  final _DetectVideoSession session;
  final video_player_win.WinVideoPlayerValue? value;
  final Widget child;
  final bool fullscreen;

  @override
  State<_VideoPlayerShell> createState() => _VideoPlayerShellState();
}

class _VideoPlayerShellState extends State<_VideoPlayerShell> {
  Timer? _controlsHideTimer;
  bool _controlsVisible = true;
  bool _pointerInside = false;
  bool _shortcutHudVisible = false;
  String _shortcutHudText = '';
  Color _shortcutHudTextColor = Colors.white;
  Color _shortcutHudShadowColor = Colors.black87;
  int _shortcutHudColorSerial = 0;

  @override
  void initState() {
    super.initState();
    widget.session.shortcutHud.addListener(_handleShortcutHudChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scheduleControlsHide();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _VideoPlayerShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.shortcutHud.removeListener(_handleShortcutHudChanged);
      widget.session.shortcutHud.addListener(_handleShortcutHudChanged);
      _handleShortcutHudChanged();
    }
    if (oldWidget.fullscreen != widget.fullscreen ||
        oldWidget.session.selectedInput != widget.session.selectedInput) {
      _showControls();
    }
  }

  @override
  void dispose() {
    _controlsHideTimer?.cancel();
    widget.session.shortcutHud.removeListener(_handleShortcutHudChanged);
    super.dispose();
  }

  void _handleShortcutHudChanged() {
    final hud = widget.session.shortcutHud.value;
    if (hud == null) {
      if (_shortcutHudVisible && mounted) {
        setState(() => _shortcutHudVisible = false);
      }
      return;
    }
    setState(() {
      _shortcutHudText = hud.text;
      _shortcutHudVisible = true;
    });
    _sampleShortcutHudColor();
  }

  Future<void> _sampleShortcutHudColor() async {
    final input = widget.session.selectedInput;
    if (input == null || !_isVideoPath(input)) {
      return;
    }
    final serial = ++_shortcutHudColorSerial;
    final timestamp = widget.session.positionSeconds;
    try {
      final bytes = await _RustVideoBackend.decodeFrame(
        videoPath: input,
        timestampSeconds: timestamp,
        maxWidth: 48,
      );
      if (!mounted || serial != _shortcutHudColorSerial || bytes.isEmpty) {
        return;
      }
      final luminance = await _averageFrameLuminance(bytes);
      if (!mounted || serial != _shortcutHudColorSerial || luminance == null) {
        return;
      }
      final useDarkText = luminance > 0.58;
      setState(() {
        _shortcutHudTextColor = useDarkText ? Colors.black : Colors.white;
        _shortcutHudShadowColor = useDarkText ? Colors.white70 : Colors.black87;
      });
    } catch (_) {
      if (!mounted || serial != _shortcutHudColorSerial) {
        return;
      }
      setState(() {
        _shortcutHudTextColor = Colors.white;
        _shortcutHudShadowColor = Colors.black87;
      });
    }
  }

  void _showControls({bool scheduleHide = true}) {
    _controlsHideTimer?.cancel();
    if (!_controlsVisible && mounted) {
      setState(() => _controlsVisible = true);
    }
    if (scheduleHide) {
      _scheduleControlsHide();
    }
  }

  void _hideControls() {
    _controlsHideTimer?.cancel();
    if (widget.session.scrubbing) {
      return;
    }
    if (_controlsVisible && mounted) {
      setState(() => _controlsVisible = false);
    }
  }

  void _scheduleControlsHide() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted || widget.session.scrubbing) {
        return;
      }
      _hideControls();
    });
  }

  void _handlePointerEnter(PointerEnterEvent event) {
    _pointerInside = true;
    _showControls();
  }

  void _handlePointerHover(PointerHoverEvent event) {
    if (!_pointerInside) {
      _pointerInside = true;
    }
    _showControls();
  }

  void _handlePointerExit(PointerExitEvent event) {
    _pointerInside = false;
    _hideControls();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        !widget.session.hasInitializedVideo ||
        event.scrollDelta.dy == 0) {
      return;
    }
    _showControls();
    final delta = event.scrollDelta.dy < 0 ? 0.05 : -0.05;
    widget.session.adjustVolume(delta);
  }

  void _beginScrub(double value) {
    _showControls(scheduleHide: false);
    widget.session.beginScrub(value);
  }

  void _updateScrub(double value) {
    _showControls(scheduleHide: false);
    widget.session.updateScrub(value);
  }

  void _endScrub(double value) {
    widget.session.endScrub(value);
    _showControls();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.session.progressTick,
      builder: (context, _, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final session = widget.session;
    final fullscreen = widget.fullscreen;
    final initialized =
        widget.value?.isInitialized ?? session.hasInitializedVideo;
    final durationSeconds = session.durationSeconds;
    final canSeek = initialized && durationSeconds > 0;
    final sliderMax = canSeek ? durationSeconds : 1.0;
    final sliderValue = session.positionSeconds
        .clamp(0.0, sliderMax)
        .toDouble();
    final videoInsets = fullscreen ? EdgeInsets.zero : const EdgeInsets.all(12);
    final videoRadius = fullscreen ? 0.0 : 6.0;
    final controlColor = fullscreen
        ? Colors.black.withAlpha(218)
        : _controlColor(context).withAlpha(238);
    final controlBorder = fullscreen ? Colors.white24 : _borderColor(context);
    final controlTextStyle = TextStyle(color: fullscreen ? Colors.white : null);
    return MouseRegion(
      onEnter: _handlePointerEnter,
      onHover: _handlePointerHover,
      onExit: _handlePointerExit,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerSignal: _handlePointerSignal,
        child: ColoredBox(
          color: Colors.black,
          child: SizedBox.expand(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: videoInsets,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(videoRadius),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(videoRadius),
                        child: Center(child: widget.child),
                      ),
                    ),
                  ),
                ),
                if (session.videoLoading)
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                if (_shortcutHudText.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 180),
                          opacity: _shortcutHudVisible ? 1 : 0,
                          child: Text(
                            _shortcutHudText,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _shortcutHudTextColor,
                              fontSize: fullscreen ? 44 : 32,
                              fontWeight: FontWeight.w700,
                              shadows: [
                                Shadow(
                                  color: _shortcutHudShadowColor,
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: _controlsVisible ? 1 : 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: controlColor,
                          border: Border.all(color: controlBorder),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: IconTheme.merge(
                          data: IconThemeData(
                            color: fullscreen ? Colors.white : null,
                          ),
                          child: DefaultTextStyle.merge(
                            style: controlTextStyle,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        onPressed: session.hasInitializedVideo
                                            ? session.togglePause
                                            : null,
                                        icon: Icon(
                                          session.isPaused
                                              ? Icons.play_arrow
                                              : Icons.pause,
                                        ),
                                        tooltip: session.isPaused
                                            ? t('detect.playing')
                                            : t('detect.paused'),
                                      ),
                                      Expanded(
                                        child: Slider(
                                          value: sliderValue,
                                          min: 0,
                                          max: sliderMax,
                                          onChangeStart: canSeek
                                              ? _beginScrub
                                              : null,
                                          onChanged: canSeek
                                              ? _updateScrub
                                              : null,
                                          onChangeEnd: canSeek
                                              ? _endScrub
                                              : null,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 118,
                                        child: Text(
                                          '${_formatVideoTime(sliderValue)} / ${_formatVideoTime(durationSeconds)}',
                                          textAlign: TextAlign.right,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _SpeedSelector(
                                        currentSpeed: session.playbackSpeed,
                                        onSelected: (speed) {
                                          _showControls();
                                          session.setPlaybackSpeed(speed);
                                        },
                                      ),
                                      const SizedBox(width: 8),
                                      _VideoScaleSelector(
                                        currentMode: session.scaleMode,
                                        onSelected: (mode) {
                                          _showControls();
                                          session.setScaleMode(mode);
                                        },
                                      ),
                                      const SizedBox(width: 8),
                                      _VolumeIndicator(volume: session.volume),
                                    ],
                                  ),
                                  if (session.selectedInput != null)
                                    Text(
                                      _fileName(session.selectedInput!),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  if (session.videoStatus != null)
                                    Text(
                                      session.videoStatus!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.merge(controlTextStyle),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.video_file_outlined, size: 56, color: Colors.white70),
        const SizedBox(height: 10),
        Text(
          loading ? t('detect.loadingVideo') : t('detect.placeholder'),
          style: const TextStyle(color: Colors.white),
        ),
      ],
    );
  }
}

String _formatVideoTime(double seconds) {
  final totalSeconds = seconds.isFinite ? seconds.round().clamp(0, 999999) : 0;
  final minutes = totalSeconds ~/ 60;
  final second = totalSeconds % 60;
  return '$minutes:${second.toString().padLeft(2, '0')}';
}

Size _videoSourceSize(video_player_win.WinVideoPlayerValue value) {
  final size = value.size;
  if (size.width > 0 && size.height > 0) {
    return size;
  }
  final aspect = _safeVideoAspect(value);
  return Size(1280, 1280 / aspect);
}

double _safeVideoAspect(video_player_win.WinVideoPlayerValue value) {
  final aspect = value.aspectRatio;
  if (aspect.isFinite && aspect > 0) {
    return aspect;
  }
  final size = value.size;
  if (size.width > 0 && size.height > 0) {
    return size.width / size.height;
  }
  return 16 / 9;
}

Size _scaledVideoSize({
  required Size bounds,
  required Size sourceSize,
  required double sourceAspect,
  required _VideoScaleMode mode,
}) {
  switch (mode) {
    case _VideoScaleMode.auto:
      return _containAspect(bounds, sourceAspect);
    case _VideoScaleMode.ratio4x3:
      return _containAspect(bounds, 4 / 3);
    case _VideoScaleMode.ratio16x9:
      return _containAspect(bounds, 16 / 9);
    case _VideoScaleMode.fitWidth:
      return Size(bounds.width, bounds.width / sourceAspect);
    case _VideoScaleMode.fitHeight:
      return Size(bounds.height * sourceAspect, bounds.height);
    case _VideoScaleMode.original:
      return sourceSize;
  }
}

Size _containAspect(Size bounds, double aspect) {
  if (bounds.width / bounds.height > aspect) {
    return Size(bounds.height * aspect, bounds.height);
  }
  return Size(bounds.width, bounds.width / aspect);
}

Future<double?> _averageFrameLuminance(Uint8List pngBytes) async {
  ui.Image? image;
  try {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(pngBytes, completer.complete);
    image = await completer.future;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      return null;
    }
    final rgba = byteData.buffer.asUint8List();
    var total = 0.0;
    var count = 0;
    for (var index = 0; index + 3 < rgba.length; index += 4) {
      final alpha = rgba[index + 3];
      if (alpha < 8) {
        continue;
      }
      final red = rgba[index];
      final green = rgba[index + 1];
      final blue = rgba[index + 2];
      total += (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255.0;
      count++;
    }
    return count == 0 ? null : total / count;
  } finally {
    image?.dispose();
  }
}

String _videoStatusText({
  required Size size,
  required double nativeDurationSeconds,
  required _RustVideoInfo? metadata,
  required String? metadataError,
}) {
  final parts = <String>['${size.width.round()}x${size.height.round()}'];
  final nativeDuration = nativeDurationSeconds.isFinite
      ? nativeDurationSeconds
      : 0.0;
  final metadataDuration = metadata?.safeDurationSeconds ?? 0.0;
  if (nativeDuration > 0) {
    parts.add(_formatVideoTime(nativeDuration));
  }
  if (metadataDuration > 0 &&
      (nativeDuration <= 0 ||
          (metadataDuration - nativeDuration).abs() > 0.5)) {
    parts.add('FFmpeg ${_formatVideoTime(metadataDuration)}');
  }
  if (metadataDuration <= 0 && metadataError != null) {
    parts.add('FFmpeg metadata failed: $metadataError');
  }
  return parts.join(' | ');
}

String _shortVideoError(Object error) {
  final text = '$error'.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.length <= 120) {
    return text;
  }
  return '${text.substring(0, 120)}...';
}

class _SpeedSelector extends StatelessWidget {
  const _SpeedSelector({required this.currentSpeed, required this.onSelected});

  final double currentSpeed;
  final ValueChanged<double> onSelected;

  static const _speeds = [0.5, 0.75, 1.0, 1.5, 2.0, 3.0];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 0),
      tooltip: '${t('detect.speed')}: ${currentSpeed}x',
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final speed in _speeds)
          PopupMenuItem<double>(
            value: speed,
            height: 32,
            child: Text(
              '${speed}x',
              style: TextStyle(
                fontWeight: speed == currentSpeed ? FontWeight.bold : null,
              ),
            ),
          ),
      ],
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _borderColor(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${currentSpeed}x', style: const TextStyle(fontSize: 12)),
              const Icon(Icons.arrow_drop_down, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoScaleSelector extends StatelessWidget {
  const _VideoScaleSelector({
    required this.currentMode,
    required this.onSelected,
  });

  final _VideoScaleMode currentMode;
  final ValueChanged<_VideoScaleMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_VideoScaleMode>(
      padding: EdgeInsets.zero,
      tooltip: t('detect.scaleMode'),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final mode in _VideoScaleMode.values)
          PopupMenuItem<_VideoScaleMode>(
            value: mode,
            height: 32,
            child: Row(
              children: [
                Icon(
                  mode == currentMode ? Icons.check : Icons.aspect_ratio,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(t(mode.labelKey)),
              ],
            ),
          ),
      ],
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _borderColor(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.aspect_ratio, size: 16),
              const SizedBox(width: 4),
              Text(
                t(currentMode.labelKey),
                style: const TextStyle(fontSize: 12),
              ),
              const Icon(Icons.arrow_drop_down, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _VolumeIndicator extends StatelessWidget {
  const _VolumeIndicator({required this.volume});

  final double volume;

  @override
  Widget build(BuildContext context) {
    final percent = (volume * 100).round().clamp(0, 100);
    final icon = percent == 0
        ? Icons.volume_off
        : percent < 50
        ? Icons.volume_down
        : Icons.volume_up;
    return Tooltip(
      message: t('detect.volumeWheelHint'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _borderColor(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 4),
              Text('$percent%', style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

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
