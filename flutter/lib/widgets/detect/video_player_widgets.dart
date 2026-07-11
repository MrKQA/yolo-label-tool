import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:video_player_win/video_player_win.dart' as video_player_win;

import '../../models/detection.dart';
import '../../models/shortcut.dart';
import '../../pages/detect_video_page.dart';
import '../../services/i18n.dart';
import '../../services/input_utils.dart';
import '../../services/path_utils.dart';
import '../../services/rust_backend.dart';
import '../../theme/theme_helpers.dart';
import 'detect_support.dart';

class VideoFullscreenOverlay extends StatefulWidget {
  const VideoFullscreenOverlay({
    required this.session,
    required this.shortcutConfig,
  });

  final DetectVideoSession session;
  final ShortcutConfig shortcutConfig;

  @override
  State<VideoFullscreenOverlay> createState() =>
      VideoFullscreenOverlayState();
}

class VideoFullscreenOverlayState extends State<VideoFullscreenOverlay> {
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
  void didUpdateWidget(covariant VideoFullscreenOverlay oldWidget) {
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
    if (isEditableTextFocused()) {
      return KeyEventResult.ignored;
    }
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
                  child: VideoPlayerPanel(
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

class VideoPlayerPanel extends StatelessWidget {
  const VideoPlayerPanel({required this.session, this.fullscreen = false});

  final DetectVideoSession session;
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
  final VideoScaleMode mode;

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

  final DetectVideoSession session;
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
    if (input == null || !isVideoPath(input)) {
      return;
    }
    final serial = ++_shortcutHudColorSerial;
    final timestamp = widget.session.positionSeconds;
    try {
      final bytes = await RustBackend.decodeFrame(
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
    final controlsBackground = fullscreen
        ? Colors.black.withAlpha(218)
        : controlColor(context).withAlpha(238);
    final controlBorder = fullscreen ? Colors.white24 : borderColor(context);
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
                          color: controlsBackground,
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
                                      fileName(session.selectedInput!),
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
  required VideoScaleMode mode,
}) {
  switch (mode) {
    case VideoScaleMode.auto:
      return _containAspect(bounds, sourceAspect);
    case VideoScaleMode.ratio4x3:
      return _containAspect(bounds, 4 / 3);
    case VideoScaleMode.ratio16x9:
      return _containAspect(bounds, 16 / 9);
    case VideoScaleMode.fitWidth:
      return Size(bounds.width, bounds.width / sourceAspect);
    case VideoScaleMode.fitHeight:
      return Size(bounds.height * sourceAspect, bounds.height);
    case VideoScaleMode.original:
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

String videoStatusText({
  required Size size,
  required double nativeDurationSeconds,
  required RustVideoInfo? metadata,
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

String shortVideoError(Object error) {
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
          border: Border.all(color: borderColor(context)),
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

  final VideoScaleMode currentMode;
  final ValueChanged<VideoScaleMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<VideoScaleMode>(
      padding: EdgeInsets.zero,
      tooltip: t('detect.scaleMode'),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final mode in VideoScaleMode.values)
          PopupMenuItem<VideoScaleMode>(
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
          border: Border.all(color: borderColor(context)),
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
          border: Border.all(color: borderColor(context)),
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
