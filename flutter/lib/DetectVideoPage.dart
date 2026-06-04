// ignore_for_file: file_names

part of 'main.dart';

const _videoExtensions = {'mp4', 'avi', 'mov', 'mkv', 'webm', 'wmv', 'flv'};
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
  bool fullscreen = false;
  double playbackSpeed = 1;
  double volume = 1;
  double? scrubSeconds;
  String? selectedInput;
  String? detectModelPath;
  String? videoStatus;
  String? _controllerPath;
  _RustVideoInfo? videoInfo;
  video_player_win.WinVideoPlayerController? controller;
  _VideoScaleMode scaleMode = _VideoScaleMode.auto;
  List<String> folderItems = const [];
  double _positionAnchorSeconds = 0;
  DateTime? _positionAnchorTime;

  bool get selectedInputIsImage =>
      selectedInput != null && _isImagePath(selectedInput!);

  bool get selectedInputIsVideo =>
      selectedInput != null && _isVideoPath(selectedInput!);

  bool get canSaveResult => predictVideo || predictAll || selectedInputIsImage;

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
    await selectInput(file.path, newFolderItems: const []);
  }

  Future<void> chooseFolder() async {
    final folder = await getDirectoryPath();
    if (folder == null) {
      return;
    }
    final items = _mediaFilesInDirectory(folder);
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
    selectedInput = path;
    showPredictionResult = true;
    saveResult = saveResult && _canSaveForInput(path);
    if (!sameInput) {
      await _resetVideoController();
    }
    _emit();
    await loadSelectedVideoIfNeeded();
  }

  bool _canSaveForInput(String? input) {
    return predictVideo ||
        predictAll ||
        (input != null && _isImagePath(input));
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
    final input = selectedInput;
    if (input == null || !_isVideoPath(input) || !playVideo) {
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
      if (playVideo) {
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
      _showShortcutHud('${t('detect.hudVolume')} ${(nextVolume * 100).round()}%');
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
    } else if (!predictVideo) {
      predictVideo = true;
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

  void setSaveResult(bool value) {
    if (!canSaveResult) {
      return;
    }
    saveResult = value;
    _emit();
  }

  void togglePredictionResult() {
    if (!predictVideo && !predictAll) {
      return;
    }
    showPredictionResult = !showPredictionResult;
    _emit();
  }

  Future<bool> selectRelativeMedia(int delta) async {
    if (folderItems.isEmpty || delta == 0) {
      return false;
    }
    final currentIndex = folderItems.indexWhere(
      (path) => _pathKey(path) == _pathKey(selectedInput ?? ''),
    );
    final baseIndex = currentIndex < 0 ? 0 : currentIndex;
    final nextIndex = (baseIndex + delta).clamp(
      0,
      folderItems.length - 1,
    );
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
        XTypeGroup(label: 'PyTorch model', extensions: ['pt']),
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
          fullscreen ? t('detect.hudExitFullscreen') : t('detect.hudFullscreen'),
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
  const _VideoShortcutHud({
    required this.text,
    required this.hold,
  });

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
  Timer? _previewHideTimer;

  _DetectVideoSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
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
    }
  }

  @override
  void dispose() {
    _previewHideTimer?.cancel();
    _session.removeListener(_handleSessionChanged);
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
    return _session.handleShortcutKey(event, widget.shortcutConfig);
  }

  @override
  Widget build(BuildContext context) {
    final content = Expanded(
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
                    _DetectCheckbox(
                      value: _session.playVideo,
                      label: t('detect.playVideo'),
                      onChanged: (value) => _session.setPlayMode(value),
                    ),
                    _DetectCheckbox(
                      value: _session.predictVideo,
                      label: t('detect.predictVideo'),
                      onChanged: (value) =>
                          _session.setPredictMode(value, widget.settings),
                    ),
                    _DetectCheckbox(
                      value: _session.predictAll,
                      label: t('detect.predictAll'),
                      onChanged: (value) =>
                          _session.setPredictAllMode(value, widget.settings),
                    ),
                    _DetectCheckbox(
                      value: _session.saveResult,
                      label: t('detect.saveResult'),
                      enabled: _session.canSaveResult,
                      onChanged: _session.setSaveResult,
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
                if (_session.detectModelPath != null)
                  Text(
                    '${t('path.model')}: ${_fileName(_session.detectModelPath!)}',
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
                              border: Border.all(color: _borderColor(context)),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: ClipRect(
                              child: _session.previewPanelVisible
                                  ? _DetectPreviewList(
                                      items: _session.folderItems,
                                      selectedInput: _session.selectedInput,
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
                            border: Border.all(color: _borderColor(context)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: _DetectPlaybackSurface(
                            session: _session,
                            onToggleResult: _session.togglePredictionResult,
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
    );

    return content;
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

class _DetectPlaybackSurface extends StatelessWidget {
  const _DetectPlaybackSurface({
    required this.session,
    required this.onToggleResult,
  });

  final _DetectVideoSession session;
  final VoidCallback onToggleResult;

  @override
  Widget build(BuildContext context) {
    final input = session.selectedInput;
    final isPredictionMode = session.predictVideo || session.predictAll;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isPredictionMode ? onToggleResult : null,
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: input == null
                  ? Text(t('detect.placeholder'))
                  : _isImagePath(input)
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Image.file(File(input), fit: BoxFit.contain),
                    )
                  : _VideoPlayerPanel(session: session),
            ),
          ),
          if (input != null && isPredictionMode)
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
  const _VideoPlayerPanel({
    required this.session,
    this.fullscreen = false,
  });

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
                                        onChangeEnd: canSeek ? _endScrub : null,
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
                                if (session.predictVideo || session.predictAll)
                                  Text(
                                    t('detect.clickToggleResult'),
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
  final parts = <String>[
    '${size.width.round()}x${size.height.round()}',
  ];
  final nativeDuration = nativeDurationSeconds.isFinite
      ? nativeDurationSeconds
      : 0.0;
  final metadataDuration = metadata?.safeDurationSeconds ?? 0.0;
  if (nativeDuration > 0) {
    parts.add(_formatVideoTime(nativeDuration));
  }
  if (metadataDuration > 0 &&
      (nativeDuration <= 0 || (metadataDuration - nativeDuration).abs() > 0.5)) {
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
  const _SpeedSelector({
    required this.currentSpeed,
    required this.onSelected,
  });

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
              Text(
                '${currentSpeed}x',
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

class _DetectCheckbox extends StatelessWidget {
  const _DetectCheckbox({
    required this.value,
    required this.label,
    required this.onChanged,
    this.enabled = true,
  });

  final bool value;
  final String label;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: value,
      label: Text(label),
      onSelected: enabled ? onChanged : null,
      avatar: Icon(value ? Icons.check_box : Icons.check_box_outline_blank),
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

bool _isVideoPath(String path) {
  final dotIndex = path.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == path.length - 1) {
    return false;
  }
  return _videoExtensions.contains(path.substring(dotIndex + 1).toLowerCase());
}
