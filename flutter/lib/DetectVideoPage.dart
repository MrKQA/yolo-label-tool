// ignore_for_file: file_names

part of 'main.dart';

const _videoExtensions = {'mp4', 'avi', 'mov', 'mkv', 'webm'};
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
  ],
);

/// 浏览/视频检测页面，提供播放/预测互斥、文件夹预览和键盘控制骨架。
/// Browse/video detection page with exclusive play/predict modes, preview pane, and keyboard controls.
class _DetectVideoPage extends StatefulWidget {
  const _DetectVideoPage({required this.settings});

  final _AppSettings settings;

  @override
  State<_DetectVideoPage> createState() => _DetectVideoPageState();
}

class _DetectVideoPageState extends State<_DetectVideoPage> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'detect-video');
  Timer? _previewHideTimer;

  bool _playVideo = true;
  bool _predictVideo = false;
  bool _predictAll = false;
  bool _saveResult = false;
  bool _paused = false;
  bool _showPredictionResult = true;
  bool _previewPanelVisible = true;
  double _playbackSeconds = 0;
  double _playbackSpeed = 1;
  String? _selectedInput;
  String? _detectModelPath;
  List<String> _folderItems = const [];

  bool get _selectedInputIsImage =>
      _selectedInput != null && _isImagePath(_selectedInput!);

  bool get _canSaveResult =>
      _predictVideo || _predictAll || _selectedInputIsImage;

  @override
  void initState() {
    super.initState();
    _schedulePreviewHide();
  }

  @override
  void dispose() {
    _previewHideTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _chooseMediaFile() async {
    final file = await openFile(acceptedTypeGroups: const [_mediaTypeGroup]);
    if (file != null) {
      setState(() {
        _selectedInput = file.path;
        _folderItems = const [];
        _showPredictionResult = true;
        _saveResult = _saveResult && _canSaveForInput(file.path);
      });
    }
  }

  Future<void> _chooseFolder() async {
    final folder = await getDirectoryPath();
    if (folder == null) {
      return;
    }
    final items = _mediaFilesInDirectory(folder);
    setState(() {
      _folderItems = items;
      _selectedInput = items.isEmpty ? folder : items.first;
      _previewPanelVisible = true;
      _showPredictionResult = true;
      _saveResult = _saveResult && _canSaveForInput(_selectedInput);
    });
    _schedulePreviewHide();
  }

  bool _canSaveForInput(String? input) {
    return _predictVideo ||
        _predictAll ||
        (input != null && _isImagePath(input));
  }

  void _setPlayMode(bool value) {
    setState(() {
      _playVideo = value;
      if (value) {
        _predictVideo = false;
        _predictAll = false;
      } else if (!_predictVideo) {
        _predictVideo = true;
      }
      _saveResult = _saveResult && _canSaveResult;
    });
  }

  Future<void> _setPredictMode(bool value) async {
    if (value && _detectModelPath == null) {
      final model = await _chooseDetectModel();
      if (model == null) {
        return;
      }
      _detectModelPath = model;
    }
    setState(() {
      _predictVideo = value;
      if (value) {
        _playVideo = false;
      } else if (!_playVideo) {
        _playVideo = true;
        _predictAll = false;
      }
      _showPredictionResult = true;
      _saveResult = _saveResult && _canSaveResult;
    });
  }

  Future<void> _setPredictAllMode(bool value) async {
    if (value && _detectModelPath == null) {
      final model = await _chooseDetectModel();
      if (model == null) {
        return;
      }
      _detectModelPath = model;
    }
    setState(() {
      _predictAll = value;
      if (value) {
        _predictVideo = true;
        _playVideo = false;
      }
      _showPredictionResult = true;
      _saveResult = _saveResult && _canSaveResult;
    });
  }

  void _setSaveResult(bool value) {
    if (!_canSaveResult) {
      return;
    }
    setState(() => _saveResult = value);
  }

  void _togglePredictionResult() {
    if (!_predictVideo && !_predictAll) {
      return;
    }
    setState(() => _showPredictionResult = !_showPredictionResult);
  }

  void _selectRelativeMedia(int delta) {
    if (_folderItems.isEmpty || delta == 0) {
      return;
    }
    final currentIndex = _folderItems.indexWhere(
      (path) => _pathKey(path) == _pathKey(_selectedInput ?? ''),
    );
    final nextIndex = ((currentIndex < 0 ? 0 : currentIndex) + delta).clamp(
      0,
      _folderItems.length - 1,
    );
    setState(() {
      _selectedInput = _folderItems[nextIndex];
      _showPredictionResult = true;
      _saveResult = _saveResult && _canSaveForInput(_selectedInput);
    });
  }

  Future<String?> _chooseDetectModel() async {
    final initialDirectory = widget.settings.outputPath.isNotEmpty
        ? widget.settings.outputPath
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

  void _showPreviewPanel() {
    _previewHideTimer?.cancel();
    if (!_previewPanelVisible) {
      setState(() => _previewPanelVisible = true);
    }
  }

  void _schedulePreviewHide() {
    _previewHideTimer?.cancel();
    _previewHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _folderItems.isNotEmpty) {
        setState(() => _previewPanelVisible = false);
      }
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowRight) {
        setState(() => _playbackSpeed = 1);
      }
      return KeyEventResult.ignored;
    }
    final repeated = event is KeyRepeatEvent;
    final previewStep = repeated ? 3 : 1;
    if (event.logicalKey == LogicalKeyboardKey.space) {
      setState(() => _paused = !_paused);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyA) {
      _selectRelativeMedia(-previewStep);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyD) {
      _selectRelativeMedia(previewStep);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      setState(() {
        _playbackSpeed = repeated ? 3 : 1;
        _playbackSeconds = math.max(0, _playbackSeconds - (repeated ? 3 : 1));
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      setState(() {
        _playbackSpeed = repeated ? 3 : 1;
        _playbackSeconds += repeated ? 3 : 1;
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
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
                    value: _playVideo,
                    label: t('detect.playVideo'),
                    onChanged: _setPlayMode,
                  ),
                  _DetectCheckbox(
                    value: _predictVideo,
                    label: t('detect.predictVideo'),
                    onChanged: (value) => _setPredictMode(value),
                  ),
                  _DetectCheckbox(
                    value: _predictAll,
                    label: t('detect.predictAll'),
                    onChanged: (value) => _setPredictAllMode(value),
                  ),
                  _DetectCheckbox(
                    value: _saveResult,
                    label: t('detect.saveResult'),
                    enabled: _canSaveResult,
                    onChanged: _setSaveResult,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_selectedInput != null)
                Text(
                  '${t('detect.fileName')}: ${_fileName(_selectedInput!)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (widget.settings.outputPath.isNotEmpty)
                Text(
                  '${t('path.trainingOutput')}: ${widget.settings.outputPath}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (_detectModelPath != null)
                Text(
                  '${t('path.model')}: ${_fileName(_detectModelPath!)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 20),
              Expanded(
                child: Row(
                  children: [
                    if (_folderItems.isNotEmpty)
                      MouseRegion(
                        onEnter: (_) => _showPreviewPanel(),
                        onHover: (_) => _showPreviewPanel(),
                        onExit: (_) => _schedulePreviewHide(),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: _previewPanelVisible ? 220 : 8,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            color: _panelColor(context),
                            border: Border.all(color: _borderColor(context)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: ClipRect(
                            child: _previewPanelVisible
                                ? _DetectPreviewList(
                                    items: _folderItems,
                                    selectedInput: _selectedInput,
                                    onSelected: (path) => setState(() {
                                      _selectedInput = path;
                                      _showPredictionResult = true;
                                      _saveResult =
                                          _saveResult && _canSaveForInput(path);
                                    }),
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
                          selectedInput: _selectedInput,
                          playVideo: _playVideo,
                          predictVideo: _predictVideo,
                          predictAll: _predictAll,
                          showPredictionResult: _showPredictionResult,
                          paused: _paused,
                          playbackSeconds: _playbackSeconds,
                          playbackSpeed: _playbackSpeed,
                          onToggleResult: _togglePredictionResult,
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

class _DetectPlaybackSurface extends StatelessWidget {
  const _DetectPlaybackSurface({
    required this.selectedInput,
    required this.playVideo,
    required this.predictVideo,
    required this.predictAll,
    required this.showPredictionResult,
    required this.paused,
    required this.playbackSeconds,
    required this.playbackSpeed,
    required this.onToggleResult,
  });

  final String? selectedInput;
  final bool playVideo;
  final bool predictVideo;
  final bool predictAll;
  final bool showPredictionResult;
  final bool paused;
  final double playbackSeconds;
  final double playbackSpeed;
  final VoidCallback onToggleResult;

  @override
  Widget build(BuildContext context) {
    final input = selectedInput;
    final isPredictionMode = predictVideo || predictAll;
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
                  : _VideoPlaceholder(
                      fileName: _fileName(input),
                      playVideo: playVideo,
                      predictVideo: predictVideo,
                      predictAll: predictAll,
                      paused: paused,
                      playbackSeconds: playbackSeconds,
                      playbackSpeed: playbackSpeed,
                    ),
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
                    showPredictionResult
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

class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder({
    required this.fileName,
    required this.playVideo,
    required this.predictVideo,
    required this.predictAll,
    required this.paused,
    required this.playbackSeconds,
    required this.playbackSpeed,
  });

  final String fileName;
  final bool playVideo;
  final bool predictVideo;
  final bool predictAll;
  final bool paused;
  final double playbackSeconds;
  final double playbackSpeed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.video_file_outlined, size: 56),
        const SizedBox(height: 10),
        Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 8),
        Text(
          predictAll
              ? t('detect.predictAll')
              : playVideo
              ? t('detect.playVideo')
              : t('detect.predictVideo'),
        ),
        Text(paused ? t('detect.paused') : t('detect.playing')),
        Text(
          '${playbackSeconds.toStringAsFixed(0)}s / ${playbackSpeed.toStringAsFixed(0)}x',
        ),
        if (predictVideo || predictAll)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(t('detect.clickToggleResult')),
          ),
      ],
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
