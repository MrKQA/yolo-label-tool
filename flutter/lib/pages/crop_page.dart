// =============================================================================
// crop_page.dart - Video Frame Extraction / 视频取帧裁剪
// =============================================================================
// Batch video frame extraction via FFmpeg with hardware decoding,
// progress tracking, and configurable output format/quality.
//
// 通过 FFmpeg 批量提取视频帧：硬件解码、进度跟踪、可配置输出格式与画质。
// =============================================================================

// ignore_for_file: file_names

part of '../main.dart';

const _videoTypeGroup = XTypeGroup(
  label: 'Video',
  extensions: ['mp4', 'avi', 'mov', 'mkv', 'wmv', 'flv', 'webm'],
);

class _CropPage extends StatefulWidget {
  const _CropPage({required this.exportPath});

  final String exportPath;

  @override
  State<_CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<_CropPage> {
  final List<XFile> _videos = [];
  final _folderNameController = TextEditingController(text: 'frames');
  int _frameInterval = 0;
  int _threads = 0;
  int _imageQuality = 96;
  int _compressionRatio = 90;
  String _outputFormat = 'jpeg';
  bool _lossless = false;
  bool _processing = false;
  double _progress = 0;
  String? _statusMessage;

  @override
  void dispose() {
    _folderNameController.dispose();
    super.dispose();
  }

  Future<void> _importVideos() async {
    final files = await openFiles(acceptedTypeGroups: const [_videoTypeGroup]);
    if (files.isEmpty || !mounted) {
      return;
    }
    setState(() {
      _videos
        ..clear()
        ..addAll(files);
      _progress = 0;
      _statusMessage = '${t('crop.videoLoaded')}: ${files.length}';
    });
  }

  Future<void> _startExtraction() async {
    if (_videos.isEmpty || _processing) {
      return;
    }
    final ffmpegPath = await _findFfmpegExecutable();
    if (ffmpegPath == null) {
      setState(() => _statusMessage = t('crop.ffmpegMissing'));
      return;
    }

    final outputRoot = await getDirectoryPath(
      initialDirectory: _directoryExists(widget.exportPath)
          ? widget.exportPath
          : null,
      confirmButtonText: t('crop.chooseOutput'),
    );
    if (outputRoot == null || !mounted) {
      return;
    }

    final folderName = await _confirmOutputFolder(outputRoot);
    if (folderName == null || !mounted) {
      return;
    }

    final outputDir = Directory(
      joinPath(outputRoot, _sanitizePathPart(folderName)),
    )..createSync(recursive: true);
    final decoder = await _detectBestHardwareDecoder(ffmpegPath);
    final ffprobePath = await _findFfprobeExecutable(ffmpegPath);

    setState(() {
      _processing = true;
      _progress = 0;
      _statusMessage =
          '${t('crop.countingFrames')}\n${t('crop.hardwareDecoder')}: ${decoder.label}';
    });

    try {
      final plans = <_ExtractionPlan>[];
      var totalExpectedFrames = 0;
      for (var index = 0; index < _videos.length; index++) {
        final video = _videos[index];
        final prefix = _outputPrefix(index, video.path);
        if (mounted) {
          setState(() {
            _statusMessage =
                '${t('crop.countingFrames')} ${index + 1}/${_videos.length}: ${fileName(video.path)}';
          });
        }
        final totalFrames = ffprobePath == null
            ? null
            : await _probeVideoFrameCount(ffprobePath, video.path);
        final expectedFrames = totalFrames == null
            ? 0
            : _expectedExtractedFrameCount(totalFrames, _frameInterval);
        plans.add(
          _ExtractionPlan(
            video: video,
            outputPrefix: prefix,
            expectedFrames: expectedFrames,
          ),
        );
        totalExpectedFrames += expectedFrames;
      }

      final extension = _outputExtension;
      void refreshProgress(String message) {
        if (!mounted) {
          return;
        }
        final extractedFrames = _countExtractedPlanFrames(
          outputDir.path,
          plans,
          extension,
        );
        final progress = totalExpectedFrames <= 0
            ? 0.0
            : (extractedFrames / totalExpectedFrames).clamp(0.0, 1.0);
        setState(() {
          _progress = progress;
          _statusMessage =
              '$message\n'
              '${t('crop.hardwareDecoder')}: ${decoder.label}\n'
              '$extractedFrames / $totalExpectedFrames ${t('crop.frames')}';
        });
      }

      refreshProgress(t('crop.extracting'));
      for (var index = 0; index < plans.length; index++) {
        final plan = plans[index];
        if (mounted) {
          refreshProgress(
            '${t('crop.extracting')} ${index + 1}/${plans.length}: ${fileName(plan.video.path)}',
          );
        }
        await _extractOneVideo(
          ffmpegPath: ffmpegPath,
          videoPath: plan.video.path,
          outputDir: outputDir.path,
          outputPrefix: plan.outputPrefix,
          decoderArgs: decoder.ffmpegArgs,
          onProgress: () => refreshProgress(
            '${t('crop.extracting')} ${index + 1}/${plans.length}: ${fileName(plan.video.path)}',
          ),
        );
      }
      if (mounted) {
        final frameCount = _countExtractedPlanFrames(
          outputDir.path,
          plans,
          extension,
        );
        setState(() {
          _progress = 1;
          _statusMessage =
              '${t('crop.extractDone')}: $frameCount\n${outputDir.path}';
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _statusMessage = '${t('import.failed')}: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<String?> _confirmOutputFolder(String outputRoot) async {
    final controller = TextEditingController(text: _folderNameController.text);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('crop.outputDialogTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${t('crop.outputPath')}: $outputRoot'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: t('export.folderName'),
                isDense: true,
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('action.cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_sanitizePathPart(controller.text)),
            child: Text(t('crop.startExtract')),
          ),
        ],
      ),
    );
    controller.dispose();
    final folder = _sanitizePathPart(result ?? '');
    if (folder.isEmpty) {
      return null;
    }
    _folderNameController.text = folder;
    return folder;
  }

  Future<int> _extractOneVideo({
    required String ffmpegPath,
    required String videoPath,
    required String outputDir,
    required String outputPrefix,
    required List<String> decoderArgs,
    required VoidCallback onProgress,
  }) async {
    final extension = _outputExtension;
    final outputPattern = joinPath(outputDir, '$outputPrefix%06d.$extension');
    final args = [
      '-hide_banner',
      '-y',
      ...decoderArgs,
      '-i',
      videoPath,
      '-an',
      '-sn',
      '-dn',
      if (_frameInterval > 0) ...[
        '-vf',
        'select=not(mod(n\\,${_frameInterval.clamp(1, 10000)}))',
      ],
      '-threads',
      _threads.clamp(0, 256).toString(),
      '-fps_mode',
      'passthrough',
      ..._encoderArgs,
      outputPattern,
    ];
    final process = await Process.start(ffmpegPath, args);
    final stdoutFuture = process.stdout.drain<void>();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    final progressTimer = Timer.periodic(
      const Duration(milliseconds: 400),
      (_) => onProgress(),
    );
    final exitCode = await process.exitCode;
    progressTimer.cancel();
    onProgress();
    await stdoutFuture;
    final stderr = (await stderrFuture).trim();
    if (exitCode != 0) {
      throw stderr.isEmpty ? 'FFmpeg exited with $exitCode' : stderr;
    }
    return _countExtractedFrames(outputDir, outputPrefix, extension);
  }

  List<String> get _encoderArgs {
    if (_lossless) {
      if (_outputFormat == 'bmp') {
        return const ['-c:v', 'bmp'];
      }
      final pngLevel = (_compressionRatio.clamp(0, 100) * 9 / 100).round();
      return ['-c:v', 'png', '-compression_level', pngLevel.toString()];
    }

    if (_outputFormat == 'webp') {
      final webpLevel = (_compressionRatio.clamp(0, 100) * 6 / 100).round();
      return [
        '-c:v',
        'libwebp',
        '-lossless',
        '0',
        '-q:v',
        _imageQuality.clamp(1, 100).toString(),
        '-compression_level',
        webpLevel.clamp(0, 6).toString(),
        '-preset',
        'picture',
      ];
    }

    return ['-c:v', 'mjpeg', '-q:v', _jpegQScale, '-pix_fmt', _jpegPixFmt];
  }

  String get _jpegQScale {
    final quality = _imageQuality.clamp(1, 100);
    final qscale = 31 - ((quality - 1) * 29 ~/ 99);
    return qscale.clamp(2, 31).toString();
  }

  String get _jpegPixFmt {
    final ratio = _compressionRatio.clamp(0, 100);
    if (ratio >= 70) {
      return 'yuvj420p';
    }
    if (ratio >= 35) {
      return 'yuvj422p';
    }
    return 'yuvj444p';
  }

  List<String> get _availableOutputFormats =>
      _lossless ? const ['png', 'bmp'] : const ['jpeg', 'jpg', 'webp'];

  String get _outputExtension => _outputFormat;

  void _setLossless(bool value) {
    setState(() {
      _lossless = value;
      final formats = _availableOutputFormats;
      if (!formats.contains(_outputFormat)) {
        _outputFormat = formats.first;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasVideos = _videos.isNotEmpty;
    return SizedBox.expand(
      child: Container(
        color: _workspaceColor(context),
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('crop.title'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _processing ? null : _importVideos,
                  icon: const Icon(Icons.video_file_outlined),
                  label: Text(t('crop.importVideo')),
                ),
                if (hasVideos)
                  Text(
                    '${t('crop.selectedVideos')}: ${_videos.length}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
              ],
            ),
            if (hasVideos) ...[
              const SizedBox(height: 18),
              SizedBox(
                height: 96,
                child: ListView.separated(
                  itemCount: _videos.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Text('${index + 1}'.padLeft(2, '0')),
                    title: Text(
                      fileName(_videos[index].path),
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      _videos[index].path,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _CropSliderRow(
                label: t('crop.frameInterval'),
                value: _frameInterval.toDouble(),
                min: 0,
                max: 30,
                divisions: 30,
                valueLabel: _frameInterval == 0
                    ? t('crop.allFrames')
                    : _frameInterval == 1
                    ? t('crop.everyFrame')
                    : '${t('crop.every')} $_frameInterval ${t('crop.frames')}',
                onChanged: _processing
                    ? null
                    : (value) => setState(() => _frameInterval = value.round()),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _SmallNumberField(
                    label: t('crop.threads'),
                    value: _threads,
                    min: 0,
                    max: 256,
                    enabled: !_processing,
                    onChanged: (value) => setState(() => _threads = value),
                  ),
                  SizedBox(
                    width: 170,
                    child: DropdownButtonFormField<String>(
                      initialValue: _outputFormat,
                      decoration: InputDecoration(
                        labelText: t('crop.outputFormat'),
                        isDense: true,
                      ),
                      items: [
                        for (final format in _availableOutputFormats)
                          DropdownMenuItem(
                            value: format,
                            child: Text(format.toUpperCase()),
                          ),
                      ],
                      onChanged: _processing
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _outputFormat = value);
                              }
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _lossless,
                onChanged: _processing ? null : _setLossless,
                title: Text(t('crop.lossless')),
                subtitle: Text(_lossless ? 'PNG / BMP' : 'JPEG / JPG / WEBP'),
              ),
              if (!_lossless)
                _CropSliderRow(
                  label: t('crop.imageQuality'),
                  value: _imageQuality.toDouble(),
                  min: 1,
                  max: 100,
                  divisions: 99,
                  valueLabel: '$_imageQuality%',
                  onChanged: _processing
                      ? null
                      : (value) =>
                            setState(() => _imageQuality = value.round()),
                ),
              const SizedBox(height: 12),
              _CropSliderRow(
                label: t('crop.compressionRatio'),
                value: _compressionRatio.toDouble(),
                min: 0,
                max: 100,
                divisions: 100,
                valueLabel: '$_compressionRatio%',
                onChanged: _processing
                    ? null
                    : (value) =>
                          setState(() => _compressionRatio = value.round()),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    '${t('export.folderName')}: ',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _folderNameController,
                      enabled: !_processing,
                      decoration: const InputDecoration(isDense: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _processing ? null : _startExtraction,
                    icon: const Icon(Icons.start),
                    label: Text(t('crop.startExtract')),
                  ),
                  if (_processing) ...[
                    const SizedBox(width: 16),
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 220,
                      child: LinearProgressIndicator(value: _progress),
                    ),
                    const SizedBox(width: 10),
                    Text('${(_progress * 100).round()}%'),
                  ],
                ],
              ),
            ],
            if (_statusMessage != null) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusMessage!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
            if (!hasVideos) ...[
              const SizedBox(height: 24),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.content_cut,
                        size: 64,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        t('crop.placeholder'),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CropSliderRow extends StatelessWidget {
  const _CropSliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        SizedBox(
          width: 240,
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel,
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 180, child: Text(valueLabel)),
      ],
    );
  }
}

class _SmallNumberField extends StatelessWidget {
  const _SmallNumberField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: enabled && value > min
                ? () => onChanged((value - 1).clamp(min, max))
                : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 34,
            child: Text(value.toString(), textAlign: TextAlign.center),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: enabled && value < max
                ? () => onChanged((value + 1).clamp(min, max))
                : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

class _HardwareDecoder {
  const _HardwareDecoder({required this.label, required this.ffmpegArgs});

  final String label;
  final List<String> ffmpegArgs;
}

class _ExtractionPlan {
  const _ExtractionPlan({
    required this.video,
    required this.outputPrefix,
    required this.expectedFrames,
  });

  final XFile video;
  final String outputPrefix;
  final int expectedFrames;
}

Future<_HardwareDecoder> _detectBestHardwareDecoder(String ffmpegPath) async {
  final hwaccels = await _ffmpegHardwareAccelerators(ffmpegPath);
  final nvidiaGpu = await _detectBestNvidiaGpu();
  if (nvidiaGpu != null && hwaccels.contains('cuda')) {
    return _HardwareDecoder(
      label:
          'CUDA GPU ${nvidiaGpu.index} - ${nvidiaGpu.name} (${nvidiaGpu.freeMemoryMb} MB)',
      ffmpegArgs: [
        '-hwaccel',
        'cuda',
        '-hwaccel_device',
        nvidiaGpu.index.clamp(0, 16).toString(),
      ],
    );
  }

  final hasIntelGpu = await _hasIntelGpu();
  if (hasIntelGpu && hwaccels.contains('qsv')) {
    return const _HardwareDecoder(
      label: 'Intel Quick Sync Video (QSV)',
      ffmpegArgs: ['-hwaccel', 'qsv'],
    );
  }

  if (hasIntelGpu && hwaccels.contains('d3d11va')) {
    return const _HardwareDecoder(
      label: 'Intel D3D11VA',
      ffmpegArgs: ['-hwaccel', 'd3d11va'],
    );
  }

  if (hwaccels.contains('d3d11va')) {
    return const _HardwareDecoder(
      label: 'D3D11VA',
      ffmpegArgs: ['-hwaccel', 'd3d11va'],
    );
  }

  return _HardwareDecoder(label: t('crop.cpuDecode'), ffmpegArgs: const []);
}

Future<Set<String>> _ffmpegHardwareAccelerators(String ffmpegPath) async {
  try {
    final result = await Process.run(ffmpegPath, const [
      '-hide_banner',
      '-hwaccels',
    ]);
    if (result.exitCode != 0) {
      return const {};
    }
    return result.stdout
        .toString()
        .split(RegExp(r'\s+'))
        .map((item) => item.trim().toLowerCase())
        .where(
          (item) =>
              item.isNotEmpty && item != 'hardware' && item != 'acceleration',
        )
        .toSet();
  } on Object {
    return const {};
  }
}

Future<_NvidiaGpuInfo?> _detectBestNvidiaGpu() async {
  try {
    final result = await Process.run('nvidia-smi', const [
      '--query-gpu=index,name,memory.free',
      '--format=csv,noheader,nounits',
    ]);
    if (result.exitCode != 0) {
      return null;
    }
    final candidates = result.stdout
        .toString()
        .trim()
        .split(RegExp(r'\r?\n'))
        .map(_parseNvidiaGpu)
        .whereType<_NvidiaGpuInfo>()
        .toList();
    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort((a, b) => b.freeMemoryMb.compareTo(a.freeMemoryMb));
    return candidates.first;
  } on Object {
    return null;
  }
}

Future<bool> _hasIntelGpu() async {
  try {
    final result = await Process.run('powershell', const [
      '-NoProfile',
      '-Command',
      r'Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name }',
    ]);
    if (result.exitCode != 0) {
      return false;
    }
    return result.stdout.toString().toLowerCase().contains('intel');
  } on Object {
    return false;
  }
}

class _NvidiaGpuInfo {
  const _NvidiaGpuInfo({
    required this.index,
    required this.name,
    required this.freeMemoryMb,
  });

  final int index;
  final String name;
  final int freeMemoryMb;
}

_NvidiaGpuInfo? _parseNvidiaGpu(String line) {
  final parts = line.split(',');
  if (parts.length < 3) {
    return null;
  }
  final index = int.tryParse(parts[0].trim());
  final freeMemory = int.tryParse(parts.last.trim());
  final name = parts.sublist(1, parts.length - 1).join(',').trim();
  if (index == null || freeMemory == null) {
    return null;
  }
  return _NvidiaGpuInfo(
    index: index,
    name: name.isEmpty ? 'NVIDIA GPU' : name,
    freeMemoryMb: freeMemory,
  );
}

Future<String?> _findFfmpegExecutable() async {
  final envPath = Platform.environment['FFMPEG_PATH'];
  if (envPath != null &&
      envPath.trim().isNotEmpty &&
      File(envPath).existsSync()) {
    return envPath;
  }
  for (final candidate in _ffmpegCandidates()) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  try {
    final result = await Process.run('ffmpeg', const ['-version']);
    if (result.exitCode == 0) {
      return 'ffmpeg';
    }
  } on Object {
    return null;
  }
  return null;
}

Future<String?> _findFfprobeExecutable(String ffmpegPath) async {
  final envPath = Platform.environment['FFPROBE_PATH'];
  if (envPath != null &&
      envPath.trim().isNotEmpty &&
      File(envPath).existsSync()) {
    return envPath;
  }

  final sibling = _ffprobeSiblingOf(ffmpegPath);
  final candidates = dedupePaths([?sibling, ..._ffprobeCandidates()]);
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }

  try {
    final result = await Process.run('ffprobe', const ['-version']);
    if (result.exitCode == 0) {
      return 'ffprobe';
    }
  } on Object {
    return null;
  }
  return null;
}

String? _ffprobeSiblingOf(String ffmpegPath) {
  if (ffmpegPath.trim().isEmpty || ffmpegPath == 'ffmpeg') {
    return null;
  }
  final executable = Platform.isWindows ? 'ffprobe.exe' : 'ffprobe';
  return joinPath(File(ffmpegPath).parent.path, executable);
}

List<String> _ffmpegCandidates() {
  final current = Directory.current.path;
  final parent = Directory.current.parent.path;
  return dedupePaths([
    joinPath(current, 'ffmpeg\\bin\\ffmpeg.exe'),
    joinPath(current, 'tools\\ffmpeg\\bin\\ffmpeg.exe'),
    joinPath(parent, 'ffmpeg\\bin\\ffmpeg.exe'),
    joinPath(parent, 'tools\\ffmpeg\\bin\\ffmpeg.exe'),
  ]);
}

List<String> _ffprobeCandidates() {
  final current = Directory.current.path;
  final parent = Directory.current.parent.path;
  return dedupePaths([
    joinPath(current, 'ffmpeg\\bin\\ffprobe.exe'),
    joinPath(current, 'tools\\ffmpeg\\bin\\ffprobe.exe'),
    joinPath(parent, 'ffmpeg\\bin\\ffprobe.exe'),
    joinPath(parent, 'tools\\ffmpeg\\bin\\ffprobe.exe'),
  ]);
}

Future<int?> _probeVideoFrameCount(String ffprobePath, String videoPath) async {
  final countedFrames = await _probeIntegerStreamEntry(
    ffprobePath: ffprobePath,
    videoPath: videoPath,
    entryName: 'nb_read_frames',
    countFrames: true,
  );
  if (countedFrames != null && countedFrames > 0) {
    return countedFrames;
  }

  final declaredFrames = await _probeIntegerStreamEntry(
    ffprobePath: ffprobePath,
    videoPath: videoPath,
    entryName: 'nb_frames',
    countFrames: false,
  );
  if (declaredFrames != null && declaredFrames > 0) {
    return declaredFrames;
  }

  return _probeFrameCountFromDuration(ffprobePath, videoPath);
}

Future<int?> _probeIntegerStreamEntry({
  required String ffprobePath,
  required String videoPath,
  required String entryName,
  required bool countFrames,
}) async {
  try {
    final result = await Process.run(ffprobePath, [
      '-v',
      'error',
      '-select_streams',
      'v:0',
      if (countFrames) '-count_frames',
      '-show_entries',
      'stream=$entryName',
      '-of',
      'default=nokey=1:noprint_wrappers=1',
      videoPath,
    ]);
    if (result.exitCode != 0) {
      return null;
    }
    for (final token in result.stdout.toString().split(RegExp(r'\s+'))) {
      final value = int.tryParse(token.trim());
      if (value != null && value > 0) {
        return value;
      }
    }
  } on Object {
    return null;
  }
  return null;
}

Future<int?> _probeFrameCountFromDuration(
  String ffprobePath,
  String videoPath,
) async {
  try {
    final result = await Process.run(ffprobePath, [
      '-v',
      'error',
      '-select_streams',
      'v:0',
      '-show_entries',
      'stream=duration,avg_frame_rate,r_frame_rate:format=duration',
      '-of',
      'json',
      videoPath,
    ]);
    if (result.exitCode != 0) {
      return null;
    }
    final decoded = jsonDecode(result.stdout.toString());
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final streams = decoded['streams'];
    if (streams is! List || streams.isEmpty || streams.first is! Map) {
      return null;
    }
    final stream = Map<String, dynamic>.from(streams.first as Map);
    final format = decoded['format'] is Map
        ? Map<String, dynamic>.from(decoded['format'] as Map)
        : const <String, dynamic>{};
    final duration = double.tryParse(
      '${stream['duration'] ?? format['duration'] ?? ''}',
    );
    final fps =
        _parseFrameRate('${stream['avg_frame_rate'] ?? ''}') ??
        _parseFrameRate('${stream['r_frame_rate'] ?? ''}');
    if (duration == null || duration <= 0 || fps == null || fps <= 0) {
      return null;
    }
    return math.max(1, (duration * fps).round());
  } on Object {
    return null;
  }
}

double? _parseFrameRate(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == '0/0') {
    return null;
  }
  if (trimmed.contains('/')) {
    final parts = trimmed.split('/');
    if (parts.length != 2) {
      return null;
    }
    final numerator = double.tryParse(parts[0]);
    final denominator = double.tryParse(parts[1]);
    if (numerator == null || denominator == null || denominator == 0) {
      return null;
    }
    return numerator / denominator;
  }
  return double.tryParse(trimmed);
}

int _expectedExtractedFrameCount(int totalFrames, int frameInterval) {
  if (totalFrames <= 0) {
    return 0;
  }
  final step = frameInterval <= 1 ? 1 : frameInterval;
  return ((totalFrames - 1) ~/ step) + 1;
}

String _outputPrefix(int index, String videoPath) {
  final stem = _sanitizePathPart(baseNameWithoutExtension(videoPath));
  final serial = (index + 1).toString().padLeft(3, '0');
  return '${serial}_${stem}_';
}

String _sanitizePathPart(String value) {
  return value
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .trim()
      .replaceAll(RegExp(r'^\.+|\.+$'), '');
}

bool _directoryExists(String path) {
  return path.trim().isNotEmpty && Directory(path).existsSync();
}

int _countExtractedFrames(
  String outputDir,
  String outputPrefix,
  String extension,
) {
  final directory = Directory(outputDir);
  if (!directory.existsSync()) {
    return 0;
  }
  return directory.listSync().whereType<File>().where((file) {
    final name = fileName(file.path);
    return name.startsWith(outputPrefix) &&
        name.toLowerCase().endsWith('.${extension.toLowerCase()}');
  }).length;
}

int _countExtractedPlanFrames(
  String outputDir,
  List<_ExtractionPlan> plans,
  String extension,
) {
  final directory = Directory(outputDir);
  if (!directory.existsSync() || plans.isEmpty) {
    return 0;
  }
  final prefixes = plans.map((plan) => plan.outputPrefix).toList();
  final suffix = '.${extension.toLowerCase()}';
  return directory.listSync().whereType<File>().where((file) {
    final name = fileName(file.path);
    final lowerName = name.toLowerCase();
    return lowerName.endsWith(suffix) &&
        prefixes.any((prefix) => name.startsWith(prefix));
  }).length;
}
