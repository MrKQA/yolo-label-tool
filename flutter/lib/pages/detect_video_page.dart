// =============================================================================
// detect_video_page.dart - Video Playback & Detection Page / 视频播放与检测页面
// =============================================================================
// Combined media browser with video playback, YOLO detection on images/videos,
// prediction frame sequence preview, device selection (CUDA/OpenVINO/CPU), and
// result save/export.
//
// 集成视频播放、YOLO 图片/视频检测、预测帧序列预览、设备选择和结果保存/导出。
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player_win/video_player_win.dart' as video_player_win;

import '../models/config.dart';
import '../models/detection.dart';
import '../models/shortcut.dart';
import '../models/training.dart';
import '../services/app_runtime.dart';
import '../services/collection_utils.dart';
import '../services/config_store.dart';
import '../services/i18n.dart';
import '../services/input_utils.dart';
import '../services/logger.dart';
import '../services/path_utils.dart';
import '../services/python_environment.dart';
import '../services/rust_backend.dart';
import '../theme/theme_helpers.dart';
import '../widgets/common/floating_message.dart';
import '../widgets/detect/detect_panels.dart';
import '../widgets/detect/detect_playback_surface.dart';
import '../widgets/detect/detect_support.dart';
import '../widgets/detect/cam_analysis_dialog.dart';
import '../widgets/detect/video_player_widgets.dart';
import '../widgets/train/train_runtime_support.dart';

const _detectDeviceOptions = ['auto', 'nv', 'intel', 'cpu'];
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

class DetectVideoSession extends ChangeNotifier {
  bool _disposed = false;
  bool _fullscreenToggleScheduled = false;
  int _loadSerial = 0;
  Timer? _positionTimer;
  Timer? _shortcutHudTimer;
  final ValueNotifier<int> progressTick = ValueNotifier<int>(0);
  final ValueNotifier<VideoShortcutHud?> shortcutHud =
      ValueNotifier<VideoShortcutHud?>(null);

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
  RustVideoInfo? videoInfo;
  video_player_win.WinVideoPlayerController? controller;
  VideoScaleMode scaleMode = VideoScaleMode.auto;
  List<String> folderItems = const [];
  final Map<String, String> _predictionOutputsByInput = {};
  double _positionAnchorSeconds = 0;
  DateTime? _positionAnchorTime;

  bool get selectedInputIsImage =>
      selectedInput != null && isImagePath(selectedInput!);

  bool get selectedInputIsVideo =>
      selectedInput != null && isVideoPath(selectedInput!);

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
    shortcutHud.value = VideoShortcutHud(text: text, hold: hold);
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
    logApp('BROWSE', 'Media file selected: ${file.path}');
    await selectInput(file.path, newFolderItems: const []);
  }

  Future<void> chooseFolder() async {
    final folder = await getDirectoryPath();
    if (folder == null) {
      return;
    }
    final items = mediaFilesInDirectory(folder);
    logApp(
      'BROWSE',
      'Media folder selected: $folder, items=${items.length}',
      level: items.isEmpty ? AppLogLevel.warning : AppLogLevel.info,
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
    final sameInput = pathKey(path) == pathKey(selectedInput ?? '');
    if (newFolderItems != null) {
      folderItems = newFolderItems;
    }
    if (showPreviewPanel) {
      previewPanelVisible = true;
    }
    logApp(
      'BROWSE',
      'Selected input changed: $path, folderItems=${folderItems.length}',
      level: AppLogLevel.debug,
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
    return predictVideo || predictAll || (input != null && isImagePath(input));
  }

  String? _cachedPredictionOutput(String input) {
    final cached = _predictionOutputsByInput[pathKey(input)];
    if (cached == null) {
      return null;
    }
    if (File(cached).existsSync()) {
      return cached;
    }
    _predictionOutputsByInput.remove(pathKey(input));
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
        !isVideoPath(input) ||
        (!playVideo && !predictionPreview)) {
      return;
    }
    if (controller != null &&
        _controllerPath != null &&
        pathKey(_controllerPath!) == pathKey(input)) {
      if (!controller!.value.isPlaying) {
        await controller!.play();
        _markPlaybackStarted();
      }
      _emit();
      return;
    }

    final requestSerial = ++_loadSerial;
    logApp('BROWSE', 'Video load started: $input', level: AppLogLevel.debug);
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

    video_player_win.WinVideoPlayerController? loadingController;
    try {
      String? metadataError;
      final metadataFuture = RustBackend.loadInfo(input)
          .then<RustVideoInfo?>((info) => info)
          .catchError((error) {
            metadataError = shortVideoError(error);
            return null;
          });
      final nextController = video_player_win.WinVideoPlayerController.file(
        File(input),
      );
      controller = nextController;
      loadingController = nextController;
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
      videoStatus = videoStatusText(
        size: size,
        nativeDurationSeconds:
            nextController.value.duration.inMilliseconds / 1000.0,
        metadata: videoInfo,
        metadataError: metadataError,
      );
      logApp(
        'BROWSE',
        'Video load completed: $input, size=${size.width.toStringAsFixed(0)}x${size.height.toStringAsFixed(0)}, duration=${durationSeconds.toStringAsFixed(2)}s',
      );
      _emit();
    } on Object catch (error) {
      await loadingController?.dispose();
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
      logApp(
        'BROWSE',
        'Video load failed: $input, error=$error',
        level: AppLogLevel.error,
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

  void setScaleMode(VideoScaleMode mode) {
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

  Future<void> setPredictMode(bool value, AppSettings settings) async {
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

  Future<void> setPredictAllMode(bool value, AppSettings settings) async {
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
    if (path != null && isImagePath(path)) {
      await FileImage(File(path)).evict();
    }
    await _resetVideoController();
    _emit();
    await loadSelectedVideoIfNeeded();
  }

  void cachePredictionOutputForInput(String input, String? path) {
    final key = pathKey(input);
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
      _predictionOutputsByInput.remove(pathKey(input));
    }
    final selectedKey = pathKey(selectedInput ?? '');
    final clearCurrent = input == null || pathKey(input) == selectedKey;
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
      (path) => pathKey(path) == pathKey(selectedInput ?? ''),
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

  static Future<String?> _chooseDetectModel(AppSettings settings) async {
    final initialDirectory = settings.outputPath.isNotEmpty
        ? settings.outputPath
        : ConfigStore.defaultRunsDirectory.path;
    Directory(initialDirectory).createSync(recursive: true);
    final file = await openFile(
      initialDirectory: initialDirectory,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'YOLO model', extensions: ['pt', 'onnx', 'xml']),
      ],
    );
    return file?.path;
  }

  KeyEventResult handleShortcutKey(
    KeyEvent event,
    ShortcutConfig shortcutConfig,
  ) {
    final key = event.logicalKey;

    if (event is KeyUpEvent) {
      if (shortcutConfig.matches(ShortcutAction.videoFastForward, key)) {
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
    if (shortcutConfig.matches(ShortcutAction.videoPlayPause, key)) {
      if (event is KeyDownEvent) {
        final willPause = isPlaying;
        togglePause();
        _showShortcutHud(willPause ? t('detect.paused') : t('detect.playing'));
      }
      return KeyEventResult.handled;
    }
    if (shortcutConfig.matches(ShortcutAction.browseFullscreen, key)) {
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
    if (shortcutConfig.matches(ShortcutAction.browsePreviousMedia, key)) {
      selectRelativeMedia(-previewStep).then((changed) {
        if (!_disposed) {
          _showShortcutHud(
            changed ? t('detect.hudPrevious') : t('detect.hudNoPrevious'),
          );
        }
      });
      return KeyEventResult.handled;
    }
    if (shortcutConfig.matches(ShortcutAction.browseNextMedia, key)) {
      selectRelativeMedia(previewStep).then((changed) {
        if (!_disposed) {
          _showShortcutHud(
            changed ? t('detect.hudNext') : t('detect.hudNoNext'),
          );
        }
      });
      return KeyEventResult.handled;
    }
    if (shortcutConfig.matches(ShortcutAction.browseVolumeUp, key)) {
      adjustVolume(0.05);
      return KeyEventResult.handled;
    }
    if (shortcutConfig.matches(ShortcutAction.browseVolumeDown, key)) {
      adjustVolume(-0.05);
      return KeyEventResult.handled;
    }
    if (shortcutConfig.matches(ShortcutAction.videoRewind, key)) {
      stepSeconds(repeated ? -3 : -1);
      _showShortcutHud(repeated ? '-3s' : '-1s');
      return KeyEventResult.handled;
    }
    if (shortcutConfig.matches(ShortcutAction.videoFastForward, key)) {
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

class VideoShortcutHud {
  const VideoShortcutHud({required this.text, required this.hold});

  final String text;
  final bool hold;
}

enum VideoScaleMode { auto, ratio4x3, ratio16x9, fitWidth, fitHeight, original }

extension VideoScaleModeLabel on VideoScaleMode {
  String get labelKey => switch (this) {
    VideoScaleMode.auto => 'detect.scaleAuto',
    VideoScaleMode.ratio4x3 => 'detect.scale4x3',
    VideoScaleMode.ratio16x9 => 'detect.scale16x9',
    VideoScaleMode.fitWidth => 'detect.scaleFitWidth',
    VideoScaleMode.fitHeight => 'detect.scaleFitHeight',
    VideoScaleMode.original => 'detect.scaleOriginal',
  };
}

class DetectVideoPage extends StatefulWidget {
  const DetectVideoPage({
    super.key,
    required this.settings,
    required this.shortcutConfig,
    required this.session,
  });

  final AppSettings settings;
  final ShortcutConfig shortcutConfig;
  final DetectVideoSession session;

  @override
  State<DetectVideoPage> createState() => DetectVideoPageState();
}

class DetectVideoPageState extends State<DetectVideoPage> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'detect-video');
  late final TextEditingController _confController;
  List<TrainingDeviceOption> _nvidiaDeviceOptions = const [];
  OpenVinoDeviceInfo _openVinoInfo = const OpenVinoDeviceInfo();
  late final String _autoFallbackDeviceLabel;
  String? _activePredictionCancelPath;
  int? _pendingPredictionStartFrame;
  Timer? _previewHideTimer;
  Timer? _parameterHideTimer;
  bool _parameterPanelVisible = true;
  bool _analyzingCam = false;
  String? _camClassesModelPath;
  String _camModelTask = 'detect';
  List<AiModelClass> _camModelClasses = const [];
  List<CamTargetLayerOption> _camTargetLayers = const [];

  DetectVideoSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _confController = TextEditingController(
      text: _session.detectConf.toStringAsFixed(2),
    );
    _autoFallbackDeviceLabel = detectPrimaryProcessorName();
    unawaited(_loadInferenceDeviceOptions());
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
  void didUpdateWidget(covariant DetectVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.pythonPath.trim() !=
        widget.settings.pythonPath.trim()) {
      unawaited(_loadInferenceDeviceOptions());
    }
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

  Future<void> _loadInferenceDeviceOptions() async {
    if (resolvePythonExecutable(widget.settings.pythonPath.trim()) == null) {
      if (mounted &&
          (_nvidiaDeviceOptions.isNotEmpty ||
              _openVinoInfo.hasDevices ||
              _openVinoInfo.hasError)) {
        setState(() {
          _nvidiaDeviceOptions = const [];
          _openVinoInfo = const OpenVinoDeviceInfo();
        });
      }
      return;
    }
    final results = await Future.wait<Object>([
      detectNvidiaDevices(widget.settings.pythonPath.trim()),
      detectOpenVinoDevices(widget.settings.pythonPath.trim()),
    ]);
    final devices = results[0] as List<TrainingDeviceOption>;
    final openVinoInfo = results[1] as OpenVinoDeviceInfo;
    devices.sort((a, b) => naturalCompare(a.id, b.id));
    if (openVinoInfo.hasDevices) {
      logApp(
        'DETECT',
        'OpenVINO devices detected: ${openVinoInfo.displayDevices}; auto priority=NVIDIA CUDA > Intel GPU > NPU > CPU',
        level: AppLogLevel.info,
      );
    } else if (openVinoInfo.hasError) {
      logApp(
        'DETECT',
        'OpenVINO device detection failed: ${openVinoInfo.error}',
        level: AppLogLevel.warning,
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _nvidiaDeviceOptions = devices;
      _openVinoInfo = openVinoInfo;
    });
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
    final model = await DetectVideoSession._chooseDetectModel(widget.settings);
    if (model != null) {
      _session.detectModelPath = model;
    }
  }

  Future<void> _chooseDetectModel() async {
    final model = await DetectVideoSession._chooseDetectModel(widget.settings);
    if (model == null) {
      return;
    }
    logApp('DETECT', 'Detect model selected: $model');
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

  Future<void> _handlePredictAll() async {
    await _runDetection(save: false, allImages: true);
  }

  Future<void> _handleCamAnalysis() async {
    if (_session.predicting || _analyzingCam) {
      return;
    }
    final input = _session.selectedInput;
    if (input == null || (!isImagePath(input) && !isVideoPath(input))) {
      _showDetectMessage(t('detect.camNoInput'));
      return;
    }
    final pythonPath = widget.settings.pythonPath.trim();
    if (resolvePythonExecutable(pythonPath) == null) {
      _showDetectMessage(t('detect.pythonNotConfigured'));
      return;
    }
    await _ensureDetectModel();
    final modelPath = _session.detectModelPath;
    if (modelPath == null) {
      return;
    }
    if (!modelPath.toLowerCase().endsWith('.pt')) {
      _showDetectMessage(t('detect.camRequiresPt'));
      return;
    }

    final hasCachedModelInfo =
        pathKey(_camClassesModelPath ?? '') == pathKey(modelPath);
    final initialModelInfo = hasCachedModelInfo
        ? AiModelClassesResult(
            task: _camModelTask,
            classes: _camModelClasses,
            targetLayers: _camTargetLayers,
          )
        : null;
    final modelInfo = hasCachedModelInfo
        ? null
        : _loadCamModelInfo(pythonPath: pythonPath, modelPath: modelPath);
    if (!mounted) {
      return;
    }
    await showCamAnalysisDialog(
      context,
      initialModelInfo: initialModelInfo,
      modelInfo: modelInfo,
      initialThreshold: _session.detectConf,
      onAnalyze: (options) => _runCamAnalysisRequest(
        input: input,
        pythonPath: pythonPath,
        modelPath: modelPath,
        options: options,
      ),
    );
  }

  Future<CamAnalysisResult> _runCamAnalysisRequest({
    required String input,
    required String pythonPath,
    required String modelPath,
    required CamAnalysisOptions options,
  }) async {
    if (_analyzingCam) {
      throw StateError(t('detect.camRunning'));
    }
    setState(() => _analyzingCam = true);
    _session.videoStatus = t('detect.camRunning');
    _session._emit();
    String? temporaryFramePath;
    try {
      final camRoot = Directory(
        joinPath(
          joinPath(_detectPreviewDirectory(), 'cam_analysis'),
          _pathHash(input),
        ),
      );
      camRoot.createSync(recursive: true);
      final outputDir = Directory(
        joinPath(camRoot.path, 'run_${DateTime.now().microsecondsSinceEpoch}'),
      );
      outputDir.createSync(recursive: true);

      var analysisInput = input;
      if (isVideoPath(input)) {
        final frameBytes = await RustBackend.decodeFrame(
          videoPath: input,
          timestampSeconds: _session.positionSeconds,
          maxWidth: 2048,
        );
        if (frameBytes.isEmpty) {
          throw StateError(t('detect.camFrameFailed'));
        }
        temporaryFramePath = joinPath(outputDir.path, '_video_frame.png');
        await File(temporaryFramePath).writeAsBytes(frameBytes, flush: true);
        analysisInput = temporaryFramePath;
      }

      final device = _detectDeviceArgument(_selectedDetectDeviceValue);
      logApp(
        'CAM',
        'CAM analysis started: input=$input, model=$modelPath, '
            'device=$device, imgsz=${_session.detectImageSize}, '
            'mode=${options.mode}, smoothing=${options.smoothing}, '
            'targetLayers=auto+separate, '
            'classId=${options.targetClassId}, '
            'threshold=${options.threshold.toStringAsFixed(2)}',
      );
      final result = await RustBackend.analyzeCam(
        pythonPath: pythonPath,
        modelPath: modelPath,
        inputPath: analysisInput,
        outputDir: outputDir.path,
        confThreshold: options.threshold,
        iouThreshold: 0.45,
        imgsz: _session.detectImageSize,
        device: device,
        mode: options.mode,
        smoothing: options.smoothing,
        targetLayerIndex: -3,
        targetClassId: options.targetClassId,
      );
      final expectedOutputCount = result.targetLayerIndex == -3
          ? 1 + (result.availableTargetLayers.length + 1) * 5
          : 6;
      if (result.outputs.length != expectedOutputCount) {
        throw StateError(t('detect.camNoResults'));
      }
      logApp(
        'CAM',
        'CAM analysis completed: family=${result.family}, task=${result.task}, '
            'device=${result.device}, durationMs=${result.durationMs}, '
            'mode=${result.mode}, smoothing=${result.smoothing}, '
            'targetLayer=${result.targetLayerIndex}, '
            'classId=${result.targetClassId}, threshold=${result.threshold}, '
            'layers=${result.targetLayers.join(' | ')}',
      );
      _session.videoStatus = t('detect.camDone');
      _session._emit();
      _pruneCamAnalysisRuns(camRoot, keep: 3);
      return result;
    } on Object catch (error) {
      final detail = '$error';
      final gradCamMissing = _isGradCamDependencyMissing(detail);
      final noPredictions = _isCamNoPredictions(detail);
      var failure = 'runtime';
      if (gradCamMissing) {
        failure = 'grad_cam_dependency';
      } else if (noPredictions) {
        failure = 'no_predictions';
      }
      logApp(
        'CAM',
        'CAM analysis failed: failure=$failure',
        level: AppLogLevel.error,
      );
      logAppMultiline(
        'CAM',
        detail,
        level: AppLogLevel.error,
        prefix: 'detail: ',
      );
      _session.videoStatus = '${t('detect.camFailed')}: $error';
      _session._emit();
      if (gradCamMissing) {
        final message = t('detect.camGradCamMissing');
        _session.videoStatus = message;
        _session._emit();
        _showCamFloatingMessage(message);
        throw StateError(message);
      }
      if (noPredictions) {
        final message = t('detect.camNoPredictions');
        _session.videoStatus = message;
        _session._emit();
        _showCamFloatingMessage(message);
        throw StateError(message);
      }
      rethrow;
    } finally {
      if (temporaryFramePath != null) {
        try {
          final file = File(temporaryFramePath);
          if (file.existsSync()) {
            file.deleteSync();
          }
        } on Object {
          // The temporary source frame is bounded and will be replaced next run.
        }
      }
      if (mounted) {
        setState(() => _analyzingCam = false);
      }
    }
  }

  void _pruneCamAnalysisRuns(Directory root, {required int keep}) {
    try {
      final directories =
          root
              .listSync(followLinks: false)
              .whereType<Directory>()
              .toList(growable: false)
            ..sort((left, right) => right.path.compareTo(left.path));
      for (final directory in directories.skip(keep)) {
        directory.deleteSync(recursive: true);
      }
    } on Object catch (error) {
      logApp(
        'CAM',
        'CAM preview cleanup failed: $error',
        level: AppLogLevel.warning,
      );
    }
  }

  bool _isGradCamDependencyMissing(String detail) {
    final normalized = detail.toLowerCase();
    return normalized.contains("no module named 'pytorch_grad_cam'") ||
        normalized.contains('no module named "pytorch_grad_cam"') ||
        normalized.contains('pip install grad-cam') ||
        normalized.contains('grad-cam dependency import failed');
  }

  bool _isCamNoPredictions(String detail) {
    return detail.toLowerCase().contains(
      'no predictions met confidence threshold',
    );
  }

  Future<AiModelClassesResult> _loadCamModelInfo({
    required String pythonPath,
    required String modelPath,
  }) async {
    try {
      final info = await RustBackend.aiModelClasses(
        pythonPath: pythonPath,
        modelPath: modelPath,
      );
      _camClassesModelPath = modelPath;
      _camModelTask = info.task;
      _camModelClasses = info.classes;
      _camTargetLayers = info.targetLayers;
      logApp(
        'CAM',
        'CAM model info loaded: task=${info.task}, '
            'classes=${info.classes.length}, '
            'layers=${info.targetLayers.map((item) => item.name).join(' | ')}',
      );
      return info;
    } on Object catch (error) {
      logApp('CAM', 'CAM model info failed', level: AppLogLevel.error);
      logAppMultiline(
        'CAM',
        '$error',
        level: AppLogLevel.error,
        prefix: 'detail: ',
      );
      rethrow;
    }
  }

  void _showCamFloatingMessage(String message) {
    if (!mounted) {
      return;
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) =>
          FloatingMessage(message: message, duration: appNoticeDisplayDuration),
    );
    overlay.insert(entry);
    Future<void>.delayed(
      appNoticeDisplayDuration + const Duration(milliseconds: 80),
      () {
        if (entry.mounted) {
          entry.remove();
        }
      },
    );
  }

  Future<void> _runDetection({
    required bool save,
    int startFrame = 0,
    bool currentOnly = false,
    bool allImages = false,
  }) async {
    if (_session.predicting) {
      logApp(
        'DETECT',
        'Detection request ignored: prediction is already running',
        level: AppLogLevel.warning,
      );
      return;
    }
    _applyConfText();
    final input = _session.selectedInput;
    if (input == null) {
      logApp(
        'DETECT',
        'Detection request blocked: no selected input',
        level: AppLogLevel.warning,
      );
      return;
    }
    final pythonPath = widget.settings.pythonPath.trim();
    if (pythonPath.isEmpty) {
      logApp(
        'DETECT',
        'Detection request blocked: Python path is empty',
        level: AppLogLevel.warning,
      );
      _showDetectMessage(t('detect.pythonNotConfigured'));
      return;
    }
    await _ensureDetectModel();
    final modelPath = _session.detectModelPath;
    if (modelPath == null) {
      logApp(
        'DETECT',
        'Detection request blocked: no model selected',
        level: AppLogLevel.warning,
      );
      return;
    }
    final targets = _detectionTargets(
      input,
      currentOnly: currentOnly,
      allImages: allImages,
    );
    if (targets.isEmpty) {
      logApp(
        'DETECT',
        'Detection request blocked: no image targets for input=$input',
        level: AppLogLevel.warning,
      );
      _showDetectMessage(t('detect.noImageTargets'));
      return;
    }
    if (!save && targets.any(isVideoPath)) {
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
      final deviceArgument = _detectDeviceArgument(_session.detectDevice);
      final outputDir = await _detectOutputDirectory(
        save: save,
        modelPath: modelPath,
        pythonPath: pythonPath,
      );
      logApp(
        'DETECT',
        'Detection started: save=$save, currentOnly=$currentOnly, allImages=$allImages, targets=${targets.length}, model=${fileName(modelPath)}, device=$deviceArgument, deviceSelection=${_session.detectDevice}, imgsz=${_session.detectImageSize}, conf=${_session.detectConf.toStringAsFixed(2)}, outputDir=$outputDir, startFrame=$startFrame',
      );
      if (allImages && targets.every(isImagePath)) {
        final batchResult = await RustBackend.detectImages(
          pythonPath: pythonPath,
          modelPath: modelPath,
          inputPaths: targets,
          outputNames: [
            for (final target in targets) _detectOutputName(target, save: save),
          ],
          outputDir: outputDir,
          confThreshold: _session.detectConf,
          iouThreshold: 0.45,
          imgsz: _session.detectImageSize,
          device: deviceArgument,
        );
        if (batchResult.items.length != targets.length) {
          throw StateError(
            'Batch prediction returned ${batchResult.items.length} '
            'results for ${targets.length} images',
          );
        }
        for (final item in batchResult.items) {
          _session.cachePredictionOutputForInput(
            item.inputPath,
            item.outputPath,
          );
        }
        final selectedKey = pathKey(_session.selectedInput ?? '');
        BatchDetectItem? selectedResult;
        for (final item in batchResult.items) {
          if (pathKey(item.inputPath) == selectedKey) {
            selectedResult = item;
            break;
          }
        }
        if (selectedResult != null) {
          _session.predictVideo = false;
          _session.showPredictionResult = true;
          await _session.setPredictionOutput(selectedResult.outputPath);
        }
        _session.videoStatus =
            '${save ? t('detect.saveDone') : t('detect.detectDone')} '
            '${targets.length}/${targets.length} '
            '(${t('detect.detectCount')}: ${batchResult.labelCount})';
        logApp(
          'DETECT',
          'Batch detection completed: save=$save, targets=${targets.length}, '
              'labels=${batchResult.labelCount}, device=${batchResult.device}',
        );
        _showDetectMessage(_session.videoStatus!);
        return;
      }
      for (final target in targets) {
        if (!mounted) {
          return;
        }
        final isVideo = isVideoPath(target);
        _session.videoStatus =
            '${t('detect.predicting')} ${completed + 1}/${targets.length}: '
            '${fileName(target)}';
        _session._emit();
        final outputName = _detectOutputName(target, save: save);
        final previewVideo = isVideo && !save;
        final cancelPath = previewVideo ? _detectCancelPath(target) : '';
        if (previewVideo) {
          _activePredictionCancelPath = cancelPath;
          _clearCancelFile(cancelPath);
          final manifestPath = joinPath(outputDir, outputName);
          _writeEmptyPredictionManifest(manifestPath, startFrame: startFrame);
          _session.cachePredictionOutputForInput(target, manifestPath);
          if (pathKey(target) == pathKey(_session.selectedInput ?? '')) {
            _session.predictVideo = true;
            _session.showPredictionResult = true;
            await _session.setPredictionOutput(manifestPath);
          }
        }
        final result = await RustBackend.detect(
          mode: isVideo ? 'video' : 'image',
          pythonPath: pythonPath,
          modelPath: modelPath,
          inputPath: target,
          outputDir: outputDir,
          outputName: outputName,
          confThreshold: _session.detectConf,
          iouThreshold: 0.45,
          imgsz: _session.detectImageSize,
          device: deviceArgument,
          previewFrames: previewVideo,
          cancelPath: cancelPath,
          startFrame: previewVideo ? startFrame : 0,
        );
        if (pathKey(_activePredictionCancelPath ?? '') == pathKey(cancelPath)) {
          _activePredictionCancelPath = null;
        }
        if (!mounted) {
          return;
        }
        if (!result.ok) {
          final error = result.error ?? t('detect.detectFailed');
          _session.videoStatus = '${t('detect.detectFailed')}: $error';
          logApp(
            'DETECT',
            'Detection target failed: target=$target, error=$error',
            level: AppLogLevel.error,
          );
          _showDetectMessage(_session.videoStatus!);
          return;
        }
        completed += 1;
        totalLabels += result.labelCount;
        logApp(
          'DETECT',
          'Detection target completed: target=$target, labels=${result.labelCount}, output=${result.outputPath}',
          level: AppLogLevel.debug,
        );
        _session.cachePredictionOutputForInput(target, result.outputPath);
        if (pathKey(target) == pathKey(_session.selectedInput ?? '')) {
          _session.predictVideo = isVideo;
          _session.showPredictionResult = true;
          await _session.setPredictionOutput(result.outputPath);
        }
      }
      _session.videoStatus =
          '${save ? t('detect.saveDone') : t('detect.detectDone')} '
          '${targets.length}/${targets.length} '
          '(${t('detect.detectCount')}: $totalLabels)';
      logApp(
        'DETECT',
        'Detection completed: save=$save, targets=${targets.length}, labels=$totalLabels',
      );
      _showDetectMessage(_session.videoStatus!);
    } on Object catch (error) {
      logApp('DETECT', 'Detection failed: $error', level: AppLogLevel.error);
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
        .where(isImagePath)
        .toList(growable: false);
    if (targets.isNotEmpty) {
      return targets;
    }
    return isImagePath(currentInput) ? [currentInput] : const [];
  }

  Future<String> _detectOutputDirectory({
    required bool save,
    String? modelPath,
    String? pythonPath,
  }) async {
    final root = widget.settings.outputPath.trim().isNotEmpty
        ? widget.settings.outputPath.trim()
        : ConfigStore.defaultRunsDirectory.path;
    final directory = save
        ? _nextDetectRunDirectory(
            root,
            await _detectTaskFolderName(
              modelPath: modelPath,
              pythonPath: pythonPath,
            ),
          )
        : Directory(joinPath(root, 'detect_preview'));
    directory.createSync(recursive: true);
    return directory.path;
  }

  Directory _nextDetectRunDirectory(String root, String taskFolder) {
    final taskRoot = Directory(joinPath(root, taskFolder));
    taskRoot.createSync(recursive: true);
    var index = 1;
    while (true) {
      final folderName = index == 1 ? 'detect' : 'detect$index';
      final candidate = Directory(joinPath(taskRoot.path, folderName));
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
      final result = await RustBackend.detectModelTask(
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
    final stem = baseNameWithoutExtension(input);
    final extension = isVideoPath(input) ? (save ? '.mp4' : '.json') : '.jpg';
    final suffix = save ? 'pred' : 'preview_${_pathHash(input)}';
    return '${stem}_$suffix$extension';
  }

  String _detectCancelPath(String input) {
    return joinPath(
      _detectPreviewDirectory(),
      '${baseNameWithoutExtension(input)}_${_pathHash(input)}.cancel',
    );
  }

  String _detectPreviewDirectory() {
    final root = widget.settings.outputPath.trim().isNotEmpty
        ? widget.settings.outputPath.trim()
        : ConfigStore.defaultRunsDirectory.path;
    final directory = Directory(joinPath(root, 'detect_preview'));
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
      logApp('DETECT', 'Prediction cancellation requested: $path');
    } on Object catch (error) {
      logApp(
        'DETECT',
        'Prediction cancellation failed: $path, error=$error',
        level: AppLogLevel.error,
      );
      _showDetectMessage('${t('detect.detectFailed')}: $error');
    }
  }

  void _requestPredictionSeek(int frameNumber) {
    if (_session.selectedInput == null ||
        !isVideoPath(_session.selectedInput!)) {
      return;
    }
    final targetFrame = math.max(0, frameNumber);
    logApp(
      'DETECT',
      'Prediction seek requested: frame=$targetFrame, predicting=${_session.predicting}',
      level: AppLogLevel.debug,
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
    return pathKey(input).hashCode.toUnsigned(32).toRadixString(16);
  }

  void _applyConfText() {
    final parsed = double.tryParse(_confController.text.trim());
    if (parsed == null) {
      _confController.text = _session.detectConf.toStringAsFixed(2);
      return;
    }
    _setDetectConf(parsed);
  }

  void _setDetectConf(double value) {
    final clamped = value.clamp(0.01, 1.0).toDouble();
    _session.detectConf = clamped;
    final normalized = clamped.toStringAsFixed(2);
    if (_confController.text != normalized) {
      _confController.text = normalized;
    }
    _session._emit();
  }

  String get _selectedDetectDeviceValue {
    final value = _detectDeviceOptions.contains(_session.detectDevice)
        ? _session.detectDevice
        : 'auto';
    if (value == 'nv' && _nvidiaDeviceOptions.isEmpty) {
      return 'auto';
    }
    if (value == 'intel' && !_openVinoInfo.hasDevices) {
      return 'auto';
    }
    return value;
  }

  String _detectDeviceArgument(String value) {
    final normalized = _detectDeviceOptions.contains(value) ? value : 'auto';
    if (normalized == 'cpu') {
      return 'cpu';
    }
    if (normalized == 'nv') {
      return _nvidiaDeviceOptions.firstOrNullValue?.id ?? 'cpu';
    }
    if (normalized == 'intel') {
      return _openVinoInfo.hasDevices
          ? _openVinoInfo.inferenceDeviceArgument
          : 'cpu';
    }
    if (normalized == 'auto' &&
        _nvidiaDeviceOptions.isEmpty &&
        _openVinoInfo.hasDevices) {
      return _openVinoInfo.inferenceDeviceArgument;
    }
    return 'auto';
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
        !isVideoPath(selectedInput) ||
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
    if (isEditableTextFocused()) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final predictionPreviewActive =
        _session.predicting ||
        isPredictionManifestPath(_session.predictionOutputPath ?? '');
    if (predictionPreviewActive &&
        (widget.shortcutConfig.matches(ShortcutAction.videoFastForward, key) ||
            widget.shortcutConfig.matches(ShortcutAction.videoRewind, key))) {
      return KeyEventResult.handled;
    }
    if (_session.predicting &&
        event is KeyDownEvent &&
        widget.shortcutConfig.matches(ShortcutAction.videoPlayPause, key)) {
      _cancelActivePrediction();
      return KeyEventResult.handled;
    }
    return _session.handleShortcutKey(event, widget.shortcutConfig);
  }

  @override
  Widget build(BuildContext context) {
    final deviceValue = _selectedDetectDeviceValue;
    final deviceArgument = _detectDeviceArgument(deviceValue);
    final hasNvidiaDevice = _nvidiaDeviceOptions.isNotEmpty;
    final hasOpenVinoDevice = _openVinoInfo.hasDevices;
    final nvidiaDeviceLabel =
        _nvidiaDeviceOptions.firstOrNullValue?.label ??
        t('detect.deviceNvUnavailable');
    final intelDeviceLabel = hasOpenVinoDevice
        ? 'Intel OpenVINO | ${_openVinoInfo.displayDevices}'
        : t('detect.deviceIntelUnavailable');
    final autoFallbackLabel =
        _nvidiaDeviceOptions.firstOrNullValue?.label ??
        (hasOpenVinoDevice ? intelDeviceLabel : _autoFallbackDeviceLabel);
    final autoDeviceLabel =
        '${t('detect.deviceAuto')} | ${friendlyDeviceLabel(autoFallbackLabel)}';
    return SizedBox.expand(
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
                  color: workspaceColor(context),
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
                          '${t('detect.fileName')}: ${fileName(_session.selectedInput!)}',
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
                                    color: panelColor(context),
                                    border: Border.all(
                                      color: borderColor(context),
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: ClipRect(
                                    child: _session.previewPanelVisible
                                        ? DetectPreviewList(
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
                                  color: panelColor(context),
                                  border: Border.all(
                                    color: borderColor(context),
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: DetectPlaybackSurface(
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
                color: panelColor(context),
                border: Border(left: BorderSide(color: borderColor(context))),
              ),
              child: ClipRect(
                child: _parameterPanelVisible
                    ? DetectParameterPanel(
                        session: _session,
                        deviceValue: deviceValue,
                        deviceArgument: deviceArgument,
                        autoDeviceLabel: autoDeviceLabel,
                        nvidiaDeviceLabel: nvidiaDeviceLabel,
                        hasNvidiaDevice: hasNvidiaDevice,
                        intelDeviceLabel: intelDeviceLabel,
                        hasOpenVinoDevice: hasOpenVinoDevice,
                        analyzingCam: _analyzingCam,
                        onChooseModel: () => unawaited(_chooseDetectModel()),
                        onResetEffect: () =>
                            unawaited(_resetPredictionEffect()),
                        onPredict: () => unawaited(_handlePredictButton()),
                        onPredictAll: () => unawaited(_handlePredictAll()),
                        onAnalyzeCam: () => unawaited(_handleCamAnalysis()),
                        onSaveCurrent: () => unawaited(_handleSaveCurrent()),
                        onSaveAll: () => unawaited(_handleSaveAll()),
                        onToggleResult: () =>
                            unawaited(_handleTogglePredictionResult()),
                        onConfChanged: _setDetectConf,
                        onImageSizeChanged: (value) {
                          _session.detectImageSize = value;
                          _session._emit();
                        },
                        onDeviceChanged: (value) {
                          if (value == 'nv' && !hasNvidiaDevice) {
                            return;
                          }
                          if (value == 'intel' && !hasOpenVinoDevice) {
                            return;
                          }
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
