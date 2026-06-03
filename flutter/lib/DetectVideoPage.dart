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
  int _loadSerial = 0;

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
  double? scrubSeconds;
  String? selectedInput;
  String? detectModelPath;
  String? videoStatus;
  String? _controllerPath;
  VideoPlayerController? controller;
  List<String> folderItems = const [];

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
    if (value == null || !value.isInitialized) {
      return 0;
    }
    return value.duration.inMilliseconds / 1000.0;
  }

  double get positionSeconds {
    if (scrubbing && scrubSeconds != null) {
      return scrubSeconds!;
    }
    final value = controller?.value;
    if (value == null || !value.isInitialized) {
      return 0;
    }
    return value.position.inMilliseconds / 1000.0;
  }

  @override
  void dispose() {
    _disposed = true;
    _loadSerial++;
    final oldController = controller;
    controller = null;
    oldController?.dispose();
    super.dispose();
  }

  void _emit() {
    if (!_disposed) {
      notifyListeners();
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
    final oldController = controller;
    controller = null;
    _controllerPath = null;
    videoLoading = false;
    videoStatus = null;
    playbackSpeed = 1;
    scrubbing = false;
    scrubSeconds = null;
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
      }
      _emit();
      return;
    }

    final requestSerial = ++_loadSerial;
    videoLoading = true;
    videoStatus = t('detect.loadingVideo');
    playbackSpeed = 1;
    _emit();

    final oldController = controller;
    controller = null;
    _controllerPath = null;
    await oldController?.dispose();

    try {
      final nextController = VideoPlayerController.file(File(input));
      controller = nextController;
      _controllerPath = input;
      await nextController.initialize();
      if (_disposed || requestSerial != _loadSerial) {
        await nextController.dispose();
        return;
      }
      await nextController.setLooping(true);
      await nextController.setPlaybackSpeed(playbackSpeed);
      if (playVideo) {
        await nextController.play();
      }
      videoLoading = false;
      final size = nextController.value.size;
      videoStatus =
          '${size.width.round()}x${size.height.round()}';
      _emit();
    } on Object catch (error) {
      if (_disposed || requestSerial != _loadSerial) {
        return;
      }
      videoLoading = false;
      controller = null;
      _controllerPath = null;
      videoStatus = '${t('detect.decodeFailed')}: $error';
      _emit();
    }
  }

  void toggleFullscreen() {
    fullscreen = !fullscreen;
    _emit();
  }

  Future<void> togglePause() async {
    final currentController = controller;
    if (currentController == null || !currentController.value.isInitialized) {
      return;
    }
    if (currentController.value.isPlaying) {
      await currentController.pause();
    } else {
      await currentController.play();
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
    playbackSpeed = nextSpeed;
    final currentController = controller;
    if (currentController != null && currentController.value.isInitialized) {
      await currentController.setPlaybackSpeed(nextSpeed);
    }
    _emit();
  }

  Future<void> stepSeconds(double deltaSeconds) async {
    final currentController = controller;
    if (currentController == null || !currentController.value.isInitialized) {
      return;
    }
    final current = currentController.value.position.inMilliseconds / 1000.0;
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

  Future<void> selectRelativeMedia(int delta) async {
    if (folderItems.isEmpty || delta == 0) {
      return;
    }
    final currentIndex = folderItems.indexWhere(
      (path) => _pathKey(path) == _pathKey(selectedInput ?? ''),
    );
    final nextIndex = ((currentIndex < 0 ? 0 : currentIndex) + delta).clamp(
      0,
      folderItems.length - 1,
    );
    await selectInput(folderItems[nextIndex]);
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
    final key = event.logicalKey;
    final shortcuts = widget.shortcutConfig;

    if (event is KeyUpEvent) {
      if (shortcuts.matches(_ShortcutAction.videoFastForward, key)) {
        _session.setPlaybackSpeed(1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final repeated = event is KeyRepeatEvent;
    final previewStep = repeated ? 3 : 1;
    if (shortcuts.matches(_ShortcutAction.videoPlayPause, key)) {
      if (event is KeyDownEvent) {
        _session.togglePause();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) {
        _session.toggleFullscreen();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyA) {
      _session.selectRelativeMedia(-previewStep);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyD) {
      _session.selectRelativeMedia(previewStep);
      return KeyEventResult.handled;
    }
    if (shortcuts.matches(_ShortcutAction.videoRewind, key)) {
      _session.stepSeconds(repeated ? -3 : -1);
      return KeyEventResult.handled;
    }
    if (shortcuts.matches(_ShortcutAction.videoFastForward, key)) {
      if (repeated) {
        _session.setPlaybackSpeed(3);
      } else {
        _session.stepSeconds(1);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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

    if (_session.fullscreen && _session.hasInitializedVideo) {
      return Stack(
        children: [
          content,
          Positioned.fill(
            child: GestureDetector(
              onTap: () => _session.toggleFullscreen(),
              child: DecoratedBox(
                decoration: const BoxDecoration(color: Colors.black),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _session.controller!.value.aspectRatio,
                    child: VideoPlayer(_session.controller!),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
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

class _VideoPlayerPanel extends StatelessWidget {
  const _VideoPlayerPanel({required this.session});

  final _DetectVideoSession session;

  @override
  Widget build(BuildContext context) {
    final controller = session.controller;
    if (controller == null) {
      return _VideoPlayerShell(
        session: session,
        child: _VideoPlaceholder(loading: session.videoLoading),
      );
    }

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final initialized = value.isInitialized;
        return _VideoPlayerShell(
          session: session,
          value: value,
          child: initialized
              ? Center(
                  child: AspectRatio(
                    aspectRatio: value.aspectRatio == 0
                        ? 16 / 9
                        : value.aspectRatio,
                    child: ExcludeSemantics(
                      child: VideoPlayer(controller),
                    ),
                  ),
                )
              : _VideoPlaceholder(loading: session.videoLoading),
        );
      },
    );
  }
}

class _VideoPlayerShell extends StatelessWidget {
  const _VideoPlayerShell({
    required this.session,
    required this.child,
    this.value,
  });

  final _DetectVideoSession session;
  final VideoPlayerValue? value;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = value?.duration.inMilliseconds ?? 0;
    final durationSeconds = duration > 0 ? duration / 1000.0 : 0.0;
    final sliderMax = durationSeconds > 0 ? durationSeconds : 1.0;
    final sliderValue = session.positionSeconds
        .clamp(0.0, sliderMax)
        .toDouble();
    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Center(child: child),
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
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _controlColor(context).withAlpha(238),
                border: Border.all(color: _borderColor(context)),
                borderRadius: BorderRadius.circular(6),
              ),
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
                            onChangeStart: session.hasInitializedVideo
                                ? (v) => session.beginScrub(v)
                                : null,
                            onChanged: session.hasInitializedVideo
                                ? (v) => session.updateScrub(v)
                                : null,
                            onChangeEnd: session.hasInitializedVideo
                                ? (v) => session.endScrub(v)
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
                          onSelected: (speed) => session.setPlaybackSpeed(speed),
                        ),
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
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (session.predictVideo || session.predictAll)
                      Text(
                        t('detect.clickToggleResult'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
