part of '../../main.dart';

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
  PredictionFrameManifest? _manifest;
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
      final manifest = PredictionFrameManifest.load(widget.manifestPath);
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

  void _startPlayback(PredictionFrameManifest manifest) {
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
    final generatedFrames = _manifest?.frames ?? const <PredictionFrameInfo>[];
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
    final frames = _manifest?.frames ?? const <PredictionFrameInfo>[];
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
