// ignore_for_file: file_names

part of 'main.dart';

const _videoExtensions = {'mp4', 'avi', 'mov', 'mkv', 'webm'};

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
  bool _saveResult = false;
  bool _paused = false;
  bool _previewPanelVisible = true;
  double _playbackSeconds = 0;
  double _playbackSpeed = 1;
  String? _selectedInput;
  String? _detectModelPath;
  List<String> _folderItems = const [];

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

  Future<void> _chooseImage() async {
    final file = await openFile(acceptedTypeGroups: [_imageTypeGroup]);
    if (file != null) {
      setState(() {
        _selectedInput = file.path;
        _folderItems = const [];
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
    });
    _schedulePreviewHide();
  }

  Future<void> _chooseVideo() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Video',
          extensions: ['mp4', 'avi', 'mov', 'mkv', 'webm'],
        ),
      ],
    );
    if (file != null) {
      setState(() {
        _selectedInput = file.path;
        _folderItems = const [];
      });
    }
  }

  void _setPlayMode(bool value) {
    setState(() {
      _playVideo = value;
      if (value) {
        _predictVideo = false;
      } else if (!_predictVideo) {
        _predictVideo = true;
      }
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
      }
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
    if (event.logicalKey == LogicalKeyboardKey.space) {
      setState(() => _paused = !_paused);
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
                    onPressed: _chooseImage,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(t('detect.chooseImage')),
                  ),
                  OutlinedButton.icon(
                    onPressed: _chooseFolder,
                    icon: const Icon(Icons.folder_open),
                    label: Text(t('detect.chooseFolder')),
                  ),
                  OutlinedButton.icon(
                    onPressed: _chooseVideo,
                    icon: const Icon(Icons.video_file_outlined),
                    label: Text(t('detect.chooseVideo')),
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
                    value: _saveResult,
                    label: t('detect.saveResult'),
                    onChanged: (value) => setState(() => _saveResult = value),
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
                  widget.settings.outputPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (_detectModelPath != null)
                Text(
                  '${t('detect.model')}: ${_fileName(_detectModelPath!)}',
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
                                    onSelected: (path) =>
                                        setState(() => _selectedInput = path),
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
                          paused: _paused,
                          playbackSeconds: _playbackSeconds,
                          playbackSpeed: _playbackSpeed,
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
    required this.paused,
    required this.playbackSeconds,
    required this.playbackSpeed,
  });

  final String? selectedInput;
  final bool playVideo;
  final bool predictVideo;
  final bool paused;
  final double playbackSeconds;
  final double playbackSpeed;

  @override
  Widget build(BuildContext context) {
    final input = selectedInput;
    return Center(
      child: input == null
          ? Text(t('detect.placeholder'))
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isImagePath(input)
                      ? Icons.image_outlined
                      : Icons.video_file_outlined,
                  size: 56,
                ),
                const SizedBox(height: 10),
                Text(
                  _fileName(input),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  playVideo ? t('detect.playVideo') : t('detect.predictVideo'),
                ),
                Text(paused ? t('detect.paused') : t('detect.playing')),
                Text(
                  '${playbackSeconds.toStringAsFixed(0)}s / ${playbackSpeed.toStringAsFixed(0)}x',
                ),
              ],
            ),
    );
  }
}

class _DetectCheckbox extends StatelessWidget {
  const _DetectCheckbox({
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: value,
      label: Text(label),
      onSelected: onChanged,
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
