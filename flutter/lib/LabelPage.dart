// ignore_for_file: file_names

part of 'main.dart';

/// 标注页面入口，组合图片列表、画布、工具栏和类别面板。
/// Label page entry that combines image list, canvas, toolbar, and classes.
class _LabelPage extends StatelessWidget {
  const _LabelPage({
    required this.status,
    required this.images,
    required this.selectedImage,
    required this.selectedImageIndex,
    required this.zoom,
    required this.activeTool,
    required this.activeMode,
    required this.imageSplit,
    required this.activeClassId,
    required this.labelClasses,
    required this.annotations,
    required this.selectedAnnotationId,
    required this.showClassLabels,
    required this.onImageSelected,
    required this.onImageContextMenu,
    required this.onPointerSignal,
    required this.onToolSelected,
    required this.onSelectMode,
    required this.onModeSelected,
    required this.onImageSplitChanged,
    required this.onEnsureClass,
    required this.onAnnotationCreated,
    required this.onSegAnnotationCreated,
    required this.onAnnotationSelected,
    required this.onAnnotationUpdated,
    required this.onAnnotationDeleted,
    required this.onAnnotationDragStarted,
    required this.onClassSelected,
    required this.onClassAdded,
    required this.onClassEdited,
    required this.onClassColorChanged,
    required this.onClassDeleted,
    required this.onClassReordered,
    required this.onToggleClassLabels,
    required this.onAnnotationClassChanged,
    this.onImageDisplaySizeChanged,
  });

  final _BridgeStatus status;
  final List<_ImageItem> images;
  final _ImageItem? selectedImage;
  final int selectedImageIndex;
  final double zoom;
  final String activeTool;
  final _AnnotationMode activeMode;
  final String imageSplit;
  final int? activeClassId;
  final List<_LabelClass> labelClasses;
  final List<_AnnotationRegion> annotations;
  final String? selectedAnnotationId;
  final bool showClassLabels;
  final ValueChanged<int> onImageSelected;
  final Future<void> Function(TapDownDetails details, int? index)
  onImageContextMenu;
  final void Function(PointerSignalEvent event) onPointerSignal;
  final ValueChanged<String> onToolSelected;
  final VoidCallback onSelectMode;
  final ValueChanged<_AnnotationMode> onModeSelected;
  final ValueChanged<String> onImageSplitChanged;
  final Future<int?> Function() onEnsureClass;
  final void Function(Rect rect, int classId) onAnnotationCreated;
  final void Function(List<Offset> points, int classId) onSegAnnotationCreated;
  final ValueChanged<String?> onAnnotationSelected;
  final ValueChanged<_AnnotationRegion> onAnnotationUpdated;
  final ValueChanged<String> onAnnotationDeleted;
  final VoidCallback onAnnotationDragStarted;
  final ValueChanged<int> onClassSelected;
  final VoidCallback onClassAdded;
  final ValueChanged<_LabelClass> onClassEdited;
  final ValueChanged<_LabelClass> onClassColorChanged;
  final ValueChanged<_LabelClass> onClassDeleted;
  final void Function(int oldIndex, int newIndex) onClassReordered;
  final VoidCallback onToggleClassLabels;
  final void Function(String annotationId, int classId)
  onAnnotationClassChanged;
  final void Function(Size imageDisplaySize)? onImageDisplaySizeChanged;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          _ImagePreviewPane(
            images: images,
            selectedIndex: selectedImageIndex,
            onImageSelected: onImageSelected,
            onContextMenu: onImageContextMenu,
          ),
          Expanded(
            child: _CanvasStage(
              bridgeStatus: status,
              image: selectedImage,
              imageIndex: images.isEmpty ? 0 : selectedImageIndex + 1,
              imageCount: images.length,
              zoom: zoom,
              activeTool: activeTool,
              activeMode: activeMode,
              imageSplit: imageSplit,
              labelClasses: labelClasses,
              annotations: annotations,
              selectedAnnotationId: selectedAnnotationId,
              showClassLabels: showClassLabels,
              onPointerSignal: onPointerSignal,
              onModeSelected: onModeSelected,
              onImageSplitChanged: onImageSplitChanged,
              onSelectMode: onSelectMode,
              onEnsureClass: onEnsureClass,
              onAnnotationCreated: onAnnotationCreated,
              onSegAnnotationCreated: onSegAnnotationCreated,
              onAnnotationSelected: onAnnotationSelected,
              onAnnotationUpdated: onAnnotationUpdated,
              onAnnotationDeleted: onAnnotationDeleted,
              onAnnotationDragStarted: onAnnotationDragStarted,
              onImageDisplaySizeChanged: onImageDisplaySizeChanged,
            ),
          ),
          _AiToolbar(
            activeTool: activeTool,
            activeClassId: activeClassId,
            labelClasses: labelClasses,
            annotations: annotations,
            selectedAnnotationId: selectedAnnotationId,
            showClassLabels: showClassLabels,
            onToolSelected: onToolSelected,
            onClassSelected: onClassSelected,
            onClassAdded: onClassAdded,
            onClassEdited: onClassEdited,
            onClassColorChanged: onClassColorChanged,
            onClassDeleted: onClassDeleted,
            onClassReordered: onClassReordered,
            onToggleClassLabels: onToggleClassLabels,
            onAnnotationSelected: onAnnotationSelected,
            onAnnotationClassChanged: onAnnotationClassChanged,
          ),
        ],
      ),
    );
  }
}

/// 左侧图片预览区，负责显示当前索引和缩略图列表。
/// Left preview pane showing the current index and thumbnail list.
class _ImagePreviewPane extends StatelessWidget {
  const _ImagePreviewPane({
    required this.images,
    required this.selectedIndex,
    required this.onImageSelected,
    required this.onContextMenu,
  });

  final List<_ImageItem> images;
  final int selectedIndex;
  final ValueChanged<int> onImageSelected;
  final Future<void> Function(TapDownDetails details, int? index) onContextMenu;

  @override
  Widget build(BuildContext context) {
    final current = images.isEmpty ? 0 : selectedIndex + 1;
    final total = images.length;
    final previewWidth = (MediaQuery.sizeOf(context).width * 0.22)
        .clamp(_previewPaneMinWidth, _previewPaneWidth)
        .toDouble();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => onContextMenu(details, null),
      child: Container(
        width: previewWidth,
        decoration: BoxDecoration(
          color: _panelColor(context),
          border: Border(right: BorderSide(color: _borderColor(context))),
        ),
        child: Column(
          children: [
            SizedBox(
              height: _paneHeaderHeight,
              child: Center(
                child: Text(
                  '$current / $total',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: images.isEmpty
                  ? Center(child: Text(t('label.previewEmpty')))
                  : Scrollbar(
                      thumbVisibility: true,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(10),
                        itemCount: images.length,
                        itemBuilder: (context, index) {
                          return _PreviewTile(
                            image: images[index],
                            selected: index == selectedIndex,
                            onTap: () => onImageSelected(index),
                            onContextMenu: (details) =>
                                onContextMenu(details, index),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单张图片缩略图条目，支持选中和右键菜单。
/// Thumbnail item for one image with selection and context-menu support.
class _PreviewTile extends StatelessWidget {
  const _PreviewTile({
    required this.image,
    required this.selected,
    required this.onTap,
    required this.onContextMenu,
  });

  final _ImageItem image;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<TapDownDetails> onContextMenu;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        onSecondaryTapDown: onContextMenu,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? (_isDarkMode(context)
                      ? _darkControlBackground
                      : const Color(0xFFEFF6FF))
                : _panelColor(context),
            border: Border.all(
              color: selected ? colorScheme.primary : _borderColor(context),
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ImagePreview(image: image),
                const SizedBox(height: 6),
                Text(
                  image.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 缩略图图片渲染组件，图片损坏时显示占位图标。
/// Thumbnail renderer that shows a placeholder icon when loading fails.
class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.image});

  final _ImageItem image;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.file(
          File(image.path),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const ColoredBox(
            color: Color(0xFF94A3B8),
            child: Center(
              child: Icon(Icons.broken_image_outlined, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

/// 中间标注工作区舞台，承载状态栏和固定尺寸画布。
/// Central annotation workspace stage with status header and fixed-size canvas.
class _CanvasStage extends StatelessWidget {
  const _CanvasStage({
    required this.bridgeStatus,
    required this.image,
    required this.imageIndex,
    required this.imageCount,
    required this.zoom,
    required this.activeTool,
    required this.activeMode,
    required this.imageSplit,
    required this.labelClasses,
    required this.annotations,
    required this.selectedAnnotationId,
    required this.showClassLabels,
    required this.onPointerSignal,
    required this.onModeSelected,
    required this.onImageSplitChanged,
    required this.onSelectMode,
    required this.onEnsureClass,
    required this.onAnnotationCreated,
    required this.onSegAnnotationCreated,
    required this.onAnnotationSelected,
    required this.onAnnotationUpdated,
    required this.onAnnotationDeleted,
    required this.onAnnotationDragStarted,
    this.onImageDisplaySizeChanged,
  });

  final _BridgeStatus bridgeStatus;
  final _ImageItem? image;
  final int imageIndex;
  final int imageCount;
  final double zoom;
  final String activeTool;
  final _AnnotationMode activeMode;
  final String imageSplit;
  final List<_LabelClass> labelClasses;
  final List<_AnnotationRegion> annotations;
  final String? selectedAnnotationId;
  final bool showClassLabels;
  final void Function(PointerSignalEvent event) onPointerSignal;
  final ValueChanged<_AnnotationMode> onModeSelected;
  final ValueChanged<String> onImageSplitChanged;
  final VoidCallback onSelectMode;
  final Future<int?> Function() onEnsureClass;
  final void Function(Rect rect, int classId) onAnnotationCreated;
  final void Function(List<Offset> points, int classId) onSegAnnotationCreated;
  final ValueChanged<String?> onAnnotationSelected;
  final ValueChanged<_AnnotationRegion> onAnnotationUpdated;
  final ValueChanged<String> onAnnotationDeleted;
  final VoidCallback onAnnotationDragStarted;
  final void Function(Size imageDisplaySize)? onImageDisplaySizeChanged;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: onPointerSignal,
      child: Container(
        color: _workspaceColor(context),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WorkspaceHeader(
              status: bridgeStatus,
              imageIndex: imageIndex,
              imageCount: imageCount,
              activeMode: activeMode,
              activeTool: activeTool,
              imageSplit: imageSplit,
              onModeSelected: onModeSelected,
              onImageSplitChanged: onImageSplitChanged,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ClipRect(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: _annotationWorkspaceWidth,
                    height: _annotationWorkspaceHeight,
                    child: _ImageCanvas(
                      image: image,
                      zoom: zoom,
                      activeTool: activeTool,
                      activeMode: activeMode,
                      labelClasses: labelClasses,
                      annotations: annotations,
                      selectedAnnotationId: selectedAnnotationId,
                      showClassLabels: showClassLabels,
                      onEnsureClass: onEnsureClass,
                      onSelectMode: onSelectMode,
                      onAnnotationCreated: onAnnotationCreated,
                      onSegAnnotationCreated: onSegAnnotationCreated,
                      onAnnotationSelected: onAnnotationSelected,
                      onAnnotationUpdated: onAnnotationUpdated,
                      onAnnotationDeleted: onAnnotationDeleted,
                      onAnnotationDragStarted: onAnnotationDragStarted,
                      onImageDisplaySizeChanged: onImageDisplaySizeChanged,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 标注状态栏，显示当前图片序号、模式和绘制/选择状态。
/// Annotation status header with image count, modes, and drawing/selection state.
class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({
    required this.status,
    required this.imageIndex,
    required this.imageCount,
    required this.activeMode,
    required this.activeTool,
    required this.imageSplit,
    required this.onModeSelected,
    required this.onImageSplitChanged,
  });

  final _BridgeStatus status;
  final int imageIndex;
  final int imageCount;
  final _AnnotationMode activeMode;
  final String activeTool;
  final String imageSplit;
  final ValueChanged<_AnnotationMode> onModeSelected;
  final ValueChanged<String> onImageSplitChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          t('label.workspace'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        _StatusPill(label: '$imageIndex / $imageCount'),
        for (final mode in _AnnotationMode.values)
          _ModeButton(
            mode: mode,
            enabled: status.modes
                .map((item) => item.toUpperCase())
                .contains(mode.label),
            selected: activeMode == mode && activeTool == 'draw',
            onPressed: () => onModeSelected(mode),
          ),
        _SplitSelector(
          value: imageSplit,
          enabled: imageCount > 0,
          onChanged: onImageSplitChanged,
        ),
        _StatusPill(
          label: activeTool == 'draw'
              ? t('label.drawMode')
              : t('label.selectMode'),
        ),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.mode,
    required this.enabled,
    required this.selected,
    required this.onPressed,
  });

  final _AnnotationMode mode;
  final bool enabled;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: enabled ? onPressed : null,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected
            ? colorScheme.primaryContainer
            : _controlColor(context),
        foregroundColor: selected
            ? colorScheme.onPrimaryContainer
            : _primaryTextColor(context),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: Text(mode.label),
    );
  }
}

/// 小型状态标签，用于展示图片数量和当前状态。
/// Compact status pill for image counts and current state.
class _SplitSelector extends StatelessWidget {
  const _SplitSelector({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = _datasetSplits.contains(value) ? value : 'train';
    return SizedBox(
      height: 36,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: _borderColor(context)),
          borderRadius: BorderRadius.circular(6),
          color: _controlColor(context),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selected,
              isDense: true,
              onChanged: enabled
                  ? (value) {
                      if (value != null) {
                        onChanged(value);
                      }
                    }
                  : null,
              items: [
                for (final split in _datasetSplits)
                  DropdownMenuItem(value: split, child: Text(split)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: _borderColor(context)),
        borderRadius: BorderRadius.circular(6),
        color: _panelColor(context),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(label, style: Theme.of(context).textTheme.labelMedium),
      ),
    );
  }
}

/// 固定尺寸图片显示区，支持绘制、选择、拖动和删除基础标注。
/// Fixed-size image canvas with basic draw, select, drag, and delete support.
class _ImageCanvas extends StatefulWidget {
  const _ImageCanvas({
    required this.image,
    required this.zoom,
    required this.activeTool,
    required this.activeMode,
    required this.labelClasses,
    required this.annotations,
    required this.selectedAnnotationId,
    required this.showClassLabels,
    required this.onEnsureClass,
    required this.onSelectMode,
    required this.onAnnotationCreated,
    required this.onSegAnnotationCreated,
    required this.onAnnotationSelected,
    required this.onAnnotationUpdated,
    required this.onAnnotationDeleted,
    required this.onAnnotationDragStarted,
    this.onImageDisplaySizeChanged,
  });

  final void Function(Size imageDisplaySize)? onImageDisplaySizeChanged;
  final _ImageItem? image;
  final double zoom;
  final String activeTool;
  final _AnnotationMode activeMode;
  final List<_LabelClass> labelClasses;
  final List<_AnnotationRegion> annotations;
  final String? selectedAnnotationId;
  final bool showClassLabels;
  final Future<int?> Function() onEnsureClass;
  final VoidCallback onSelectMode;
  final void Function(Rect rect, int classId) onAnnotationCreated;
  final void Function(List<Offset> points, int classId) onSegAnnotationCreated;
  final ValueChanged<String?> onAnnotationSelected;
  final ValueChanged<_AnnotationRegion> onAnnotationUpdated;
  final ValueChanged<String> onAnnotationDeleted;
  final VoidCallback onAnnotationDragStarted;

  @override
  State<_ImageCanvas> createState() => _ImageCanvasState();
}

class _ImageCanvasState extends State<_ImageCanvas> {
  final FocusNode _canvasFocusNode = FocusNode(debugLabel: 'image-canvas');
  Offset? _drawStart;
  Offset? _lastMovePoint;
  Rect? _draftRect;
  int? _draftClassId;
  String? _movingAnnotationId;
  String? _resizingAnnotationId;
  int? _resizingCornerIndex;
  bool _draggingSelection = false;
  Size? _imageSize;
  Size? _sampleImageSize;
  Uint8List? _sampleRgbaBytes;
  Offset? _hoverPoint;
  String? _loadedImagePath;
  List<Offset> _segDraftPoints = [];
  int? _hoveredCornerIndex;
  ui.Image? _decodedImage;
  Offset _scrollOffset = Offset.zero;

  double get _scale => widget.zoom / 100;

  @override
  void initState() {
    super.initState();
    _loadImageSize();
  }

  @override
  void dispose() {
    _canvasFocusNode.dispose();
    _decodedImage?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ImageCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image?.path != widget.image?.path) {
      _imageSize = null;
      _sampleImageSize = null;
      _sampleRgbaBytes = null;
      _decodedImage?.dispose();
      _decodedImage = null;
      _hoverPoint = null;
      _loadedImagePath = null;
      _segDraftPoints = [];
      _scrollOffset = Offset.zero;
      _loadImageSize();
    }
    if (oldWidget.zoom != widget.zoom) {
      _scrollOffset = _clampedScrollOffset(_scrollOffset);
    }
    if (oldWidget.activeTool == 'draw' && widget.activeTool != 'draw') {
      _drawStart = null;
      _draftRect = null;
      _draftClassId = null;
      _segDraftPoints = [];
      _hoverPoint = null;
    }
  }

  Future<void> _loadImageSize() async {
    final path = widget.image?.path;
    if (path == null || path == _loadedImagePath) {
      return;
    }
    _loadedImagePath = path;
    try {
      final bytes = await File(path).readAsBytes();
      final completer = Completer<ui.Image>();
      ui.decodeImageFromList(bytes, completer.complete);
      final decoded = await completer.future;
      final sample = await _decodeSampleImage(bytes);
      if (!mounted || widget.image?.path != path) {
        decoded.dispose();
        sample?.image.dispose();
        return;
      }
      setState(() {
        _imageSize = Size(decoded.width.toDouble(), decoded.height.toDouble());
        _sampleImageSize = sample?.size;
        _sampleRgbaBytes = sample?.bytes;
        _decodedImage?.dispose();
        _decodedImage = decoded;
      });
      sample?.image.dispose();
      final displayRect = _imageDisplayRect();
      widget.onImageDisplaySizeChanged?.call(
        Size(displayRect.width, displayRect.height),
      );
    } on Object {
      if (mounted && widget.image?.path == path) {
        setState(() {
          _imageSize = null;
          _sampleImageSize = null;
          _sampleRgbaBytes = null;
        });
        widget.onImageDisplaySizeChanged?.call(Size.zero);
      }
    }
  }

  Future<_SampledImage?> _decodeSampleImage(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 64);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) {
        image.dispose();
        return null;
      }
      return _SampledImage(
        image: image,
        size: Size(image.width.toDouble(), image.height.toDouble()),
        bytes: byteData.buffer.asUint8List(),
      );
    } on Object {
      return null;
    }
  }

  Rect _imageDisplayRect() {
    final imageSize = _imageSize;
    if (imageSize == null || imageSize.width <= 0 || imageSize.height <= 0) {
      return const Rect.fromLTWH(
        0,
        0,
        _annotationWorkspaceWidth,
        _annotationWorkspaceHeight,
      );
    }
    final scale = math.min(
      _annotationWorkspaceWidth / imageSize.width,
      _annotationWorkspaceHeight / imageSize.height,
    );
    final width = imageSize.width * scale;
    final height = imageSize.height * scale;
    return Rect.fromLTWH(
      (_annotationWorkspaceWidth - width) / 2,
      (_annotationWorkspaceHeight - height) / 2,
      width,
      height,
    );
  }

  Rect _placedImageRect() => _imageDisplayRect().shift(_scrollOffset);

  Rect _imageBounds() {
    final imageRect = _imageDisplayRect();
    return Rect.fromLTWH(0, 0, imageRect.width, imageRect.height);
  }

  Offset _toContentPoint(Offset localPoint) {
    return _clampOffset(
      _toUnclampedContentPoint(localPoint),
      _placedImageRect(),
    );
  }

  Offset _toUnclampedContentPoint(Offset localPoint) {
    final center = const Offset(
      _annotationWorkspaceWidth / 2,
      _annotationWorkspaceHeight / 2,
    );
    return (localPoint - center) / _scale + center;
  }

  Offset _toImagePoint(Offset contentPoint) {
    return contentPoint - _placedImageRect().topLeft;
  }

  Offset _maxScrollOffset() {
    if (_scale <= 1.0) {
      return Offset.zero;
    }
    final factor = 1 - 1 / _scale;
    return Offset(
      _annotationWorkspaceWidth * factor / 2,
      _annotationWorkspaceHeight * factor / 2,
    );
  }

  Offset _clampedScrollOffset(Offset offset) {
    final maxOffset = _maxScrollOffset();
    return Offset(
      offset.dx.clamp(-maxOffset.dx, maxOffset.dx).toDouble(),
      offset.dy.clamp(-maxOffset.dy, maxOffset.dy).toDouble(),
    );
  }

  void _setScrollOffset(Offset offset) {
    final clamped = _clampedScrollOffset(offset);
    if (clamped == _scrollOffset) {
      return;
    }
    setState(() => _scrollOffset = clamped);
  }

  void _panViewport(Offset direction) {
    if (_scale <= 1.0) {
      return;
    }
    const visualStep = 48.0;
    _setScrollOffset(_scrollOffset + direction * (visualStep / _scale));
  }

  KeyEventResult _handleCanvasKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _panViewport(const Offset(1, 0));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _panViewport(const Offset(-1, 0));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _panViewport(const Offset(0, 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _panViewport(const Offset(0, -1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _setScrollOffset(Offset.zero);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _updateHoverPoint(Offset localPosition) {
    if (widget.image == null || widget.activeTool != 'draw') {
      if (_hoverPoint != null) {
        setState(() => _hoverPoint = null);
      }
      return;
    }
    final placedRect = _placedImageRect();
    final point = _toUnclampedContentPoint(localPosition);
    final nextPoint = placedRect.contains(point) ? point : null;
    if (_hoverPoint == nextPoint) {
      return;
    }
    setState(() => _hoverPoint = nextPoint);
  }

  Color _crosshairColorFor(Offset point) {
    final bytes = _sampleRgbaBytes;
    final sampleSize = _sampleImageSize;
    final placedRect = _placedImageRect();
    if (bytes == null || sampleSize == null || !placedRect.contains(point)) {
      return _isDarkMode(context) ? Colors.white : const Color(0xFF111827);
    }
    final nx = ((point.dx - placedRect.left) / placedRect.width).clamp(
      0.0,
      1.0,
    );
    final ny = ((point.dy - placedRect.top) / placedRect.height).clamp(
      0.0,
      1.0,
    );
    final sx = (nx * (sampleSize.width - 1)).round();
    final sy = (ny * (sampleSize.height - 1)).round();
    final index = ((sy * sampleSize.width.toInt()) + sx) * 4;
    if (index + 3 >= bytes.length) {
      return _isDarkMode(context) ? Colors.white : const Color(0xFF111827);
    }
    final r = bytes[index];
    final g = bytes[index + 1];
    final b = bytes[index + 2];
    final a = bytes[index + 3];
    if (a < 96) {
      return _isDarkMode(context) ? Colors.white : const Color(0xFF111827);
    }
    final luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
    return luminance > 0.52 ? const Color(0xFF111827) : Colors.white;
  }

  _AnnotationRegion? _annotationAt(Offset point) {
    final imagePoint = _toImagePoint(point);
    final hits = widget.annotations
        .where((annotation) => annotation.hitTest(imagePoint))
        .toList();
    if (hits.isEmpty) {
      return null;
    }
    final selectedId = widget.selectedAnnotationId;
    final selectedIndex = hits.indexWhere(
      (annotation) => annotation.id == selectedId,
    );
    if (selectedIndex < 0) {
      return hits.last;
    }
    if (selectedIndex + 1 < hits.length) {
      return hits[selectedIndex + 1];
    }
    return null;
  }

  _AnnotationRegion? _selectedAnnotation() {
    final selectedId = widget.selectedAnnotationId;
    if (selectedId == null) {
      return null;
    }
    return widget.annotations
        .where((annotation) => annotation.id == selectedId)
        .firstOrNullValue;
  }

  void _cancelDraft({bool selectModeWhenEmpty = false}) {
    final hadDraft =
        _drawStart != null || _draftRect != null || _segDraftPoints.isNotEmpty;
    setState(() {
      _drawStart = null;
      _draftRect = null;
      _draftClassId = null;
      _segDraftPoints = [];
      _movingAnnotationId = null;
      _resizingAnnotationId = null;
      _resizingCornerIndex = null;
      _lastMovePoint = null;
      _draggingSelection = false;
      if (!hadDraft && selectModeWhenEmpty) {
        widget.onAnnotationSelected(null);
      }
    });
  }

  bool _handleEscape() {
    if (_drawStart != null ||
        _draftRect != null ||
        _segDraftPoints.isNotEmpty) {
      _cancelDraft();
      return true;
    }
    return false;
  }

  _ResizeHandle? _resizeHandleAt(Offset point) {
    final selected = _selectedAnnotation();
    if (selected == null || selected.mode == _AnnotationMode.seg) {
      return null;
    }
    final canvasRect = selected.rect.shift(_placedImageRect().topLeft);
    final corners = selected.mode == _AnnotationMode.obb
        ? _rotatedCorners(canvasRect, selected.rotationDegrees)
        : _rectToPoints(canvasRect);
    for (var index = 0; index < corners.length; index++) {
      if ((corners[index] - point).distance <= 8 / _scale) {
        return _ResizeHandle(selected.id, index);
      }
    }
    return null;
  }

  _AnnotationRegion _resizedAnnotation(
    _AnnotationRegion annotation,
    int cornerIndex,
    Offset point,
  ) {
    final imageSize = _imageDisplayRect();
    final imageBounds = Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);

    if (annotation.mode == _AnnotationMode.obb) {
      final rotatedCorners = _rotatedCorners(
        annotation.rect,
        annotation.rotationDegrees,
      );
      final opposite = rotatedCorners[(cornerIndex + 2) % 4];
      final newCenter = Offset(
        (point.dx + opposite.dx) / 2,
        (point.dy + opposite.dy) / 2,
      );
      final halfDiagonal = point - newCenter;
      final radians = -annotation.rotationDegrees * math.pi / 180;
      final unrotated = _rotatePoint(
        newCenter + halfDiagonal,
        newCenter,
        radians,
      );
      final halfSize = unrotated - newCenter;
      final width = ((halfSize.dx.abs()) * 2).clamp(4.0, double.infinity);
      final height = ((halfSize.dy.abs()) * 2).clamp(4.0, double.infinity);
      final newRect = Rect.fromCenter(
        center: newCenter,
        width: width,
        height: height,
      );
      return annotation.copyWith(rect: _normalizeRect(newRect));
    }

    final corners = _rectToPoints(annotation.rect);
    final opposite = corners[(cornerIndex + 2) % 4];
    final rect = Rect.fromPoints(opposite, point).intersect(imageBounds);
    if (rect.width < 4 || rect.height < 4) {
      return annotation;
    }
    return annotation.copyWith(rect: _normalizeRect(rect));
  }

  Future<void> _handlePointerDown(PointerDownEvent event) async {
    if (widget.image == null) {
      return;
    }
    _canvasFocusNode.requestFocus();
    final rawPoint = _toUnclampedContentPoint(event.localPosition);
    final insideImage = _placedImageRect().contains(rawPoint);
    final localPoint = _toContentPoint(event.localPosition);
    final hit = insideImage ? _annotationAt(rawPoint) : null;

    if (event.buttons == kSecondaryMouseButton) {
      if (!insideImage) {
        return;
      }
      final imagePoint = _toImagePoint(rawPoint);
      final rightHit = widget.annotations
          .where((annotation) => annotation.hitTest(imagePoint))
          .toList()
          .lastOrNull;
      if (rightHit != null) {
        widget.onAnnotationSelected(rightHit.id);
        await _showAnnotationContextMenu(event.position, rightHit);
      }
      return;
    }

    if (event.buttons != kPrimaryMouseButton) {
      return;
    }

    if (widget.activeTool == 'delete') {
      if (hit != null) {
        widget.onAnnotationDeleted(hit.id);
      }
      return;
    }

    if (widget.activeTool == 'select') {
      final handle = insideImage ? _resizeHandleAt(rawPoint) : null;
      if (handle != null) {
        widget.onAnnotationDragStarted();
        _resizingAnnotationId = handle.annotationId;
        _resizingCornerIndex = handle.cornerIndex;
        _draggingSelection = true;
        return;
      }
      widget.onAnnotationSelected(hit?.id);
      if (hit != null) {
        widget.onAnnotationDragStarted();
        _movingAnnotationId = hit.id;
        _lastMovePoint = _toImagePoint(localPoint);
        _draggingSelection = true;
        return;
      }
      return;
    }

    if (widget.activeTool == 'draw' &&
        widget.activeMode == _AnnotationMode.seg) {
      final classId = await widget.onEnsureClass();
      if (!mounted || classId == null) {
        return;
      }
      final first = _segDraftPoints.isEmpty ? null : _segDraftPoints.first;
      final canClose =
          first != null &&
          _segDraftPoints.length >= 3 &&
          (_toImagePoint(localPoint) - first).distance <= 10 / _scale;
      if (canClose) {
        widget.onSegAnnotationCreated(_segDraftPoints, classId);
        setState(() {
          _segDraftPoints = [];
          _draftClassId = null;
        });
        return;
      }
      setState(() {
        _draftClassId = classId;
        _segDraftPoints = [..._segDraftPoints, _toImagePoint(localPoint)];
      });
      return;
    }

    if (widget.activeTool == 'draw') {
      final classId = await widget.onEnsureClass();
      if (!mounted || classId == null) {
        return;
      }
      final start = _drawStart;
      if (start != null) {
        final imageBounds = _imageBounds();
        final completedRect = Rect.fromPoints(
          start,
          _toImagePoint(localPoint),
        ).intersect(imageBounds);
        widget.onAnnotationCreated(completedRect, classId);
        setState(() {
          _drawStart = null;
          _draftRect = null;
          _draftClassId = null;
        });
        return;
      }
      final imagePoint = _toImagePoint(localPoint);
      setState(() {
        _draftClassId = classId;
        _drawStart = imagePoint;
        _draftRect = Rect.fromPoints(imagePoint, imagePoint);
      });
    }
  }

  Future<void> _showAnnotationContextMenu(
    Offset globalPosition,
    _AnnotationRegion annotation,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(value: 'delete', child: Text(t('tool.delete'))),
        if (annotation.mode == _AnnotationMode.obb) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'rotateLeft',
            child: Text(t('context.rotateLeft')),
          ),
          PopupMenuItem(
            value: 'rotateRight',
            child: Text(t('context.rotateRight')),
          ),
        ],
        if (widget.labelClasses.isNotEmpty) ...[
          const PopupMenuDivider(),
          for (final labelClass in widget.labelClasses)
            PopupMenuItem(
              value: 'class:${labelClass.id}',
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: labelClass.color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const SizedBox.square(dimension: 14),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(labelClass.name)),
                ],
              ),
            ),
        ],
      ],
    );
    if (action == null) {
      return;
    }
    if (action == 'delete') {
      widget.onAnnotationDeleted(annotation.id);
      return;
    }
    if (action == 'rotateLeft') {
      widget.onAnnotationDragStarted();
      final imageRect = _imageDisplayRect();
      widget.onAnnotationUpdated(
        annotation
            .rotated(-5)
            .clampObbToImage(Size(imageRect.width, imageRect.height)),
      );
      return;
    }
    if (action == 'rotateRight') {
      widget.onAnnotationDragStarted();
      final imageRect = _imageDisplayRect();
      widget.onAnnotationUpdated(
        annotation
            .rotated(5)
            .clampObbToImage(Size(imageRect.width, imageRect.height)),
      );
      return;
    }
    if (action.startsWith('class:')) {
      final classId = int.tryParse(action.substring('class:'.length));
      if (classId != null) {
        widget.onAnnotationDragStarted();
        widget.onAnnotationUpdated(annotation.copyWith(classId: classId));
      }
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (widget.image == null) {
      return;
    }
    _updateHoverPoint(event.localPosition);
    final localPoint = _toContentPoint(event.localPosition);
    final imagePoint = _toImagePoint(localPoint);
    final resizingId = _resizingAnnotationId;
    final resizingCorner = _resizingCornerIndex;
    if (resizingId != null &&
        resizingCorner != null &&
        event.buttons == kPrimaryMouseButton) {
      final current = widget.annotations
          .where((annotation) => annotation.id == resizingId)
          .firstOrNullValue;
      if (current != null) {
        widget.onAnnotationUpdated(
          _resizedAnnotation(current, resizingCorner, imagePoint),
        );
      }
      return;
    }
    final movingId = _movingAnnotationId;
    if (movingId != null && event.buttons == kPrimaryMouseButton) {
      final current = widget.annotations
          .where((annotation) => annotation.id == movingId)
          .firstOrNullValue;
      final last = _lastMovePoint;
      if (current != null && last != null) {
        final imageBounds = _imageBounds();
        widget.onAnnotationUpdated(
          current.translated(imagePoint - last).clampedTo(imageBounds),
        );
        _lastMovePoint = imagePoint;
      }
      return;
    }

    final start = _drawStart;
    if (start != null) {
      final imageBounds = _imageBounds();
      setState(() {
        _draftRect = Rect.fromPoints(
          start,
          _clampOffset(_toImagePoint(localPoint), imageBounds),
        ).intersect(imageBounds);
      });
    }
  }

  void _handlePointerHover(PointerHoverEvent event) {
    _updateHoverPoint(event.localPosition);

    final handle = widget.image != null
        ? _resizeHandleAt(_toUnclampedContentPoint(event.localPosition))
        : null;
    final cornerIndex = handle?.cornerIndex;
    if (cornerIndex != _hoveredCornerIndex) {
      setState(() => _hoveredCornerIndex = cornerIndex);
    }

    final start = _drawStart;
    if (widget.image == null || start == null) return;

    final imageBounds = _imageBounds();
    final localPoint = _toContentPoint(event.localPosition);
    setState(() {
      _draftRect = Rect.fromPoints(
        start,
        _clampOffset(_toImagePoint(localPoint), imageBounds),
      ).intersect(imageBounds);
    });
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_draggingSelection) {
      setState(() {
        _movingAnnotationId = null;
        _resizingAnnotationId = null;
        _resizingCornerIndex = null;
        _lastMovePoint = null;
        _draggingSelection = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedAnnotation = _selectedAnnotation();
    final imageRect = _imageDisplayRect();
    final crosshairPoint = widget.activeTool == 'draw' ? _hoverPoint : null;
    final crosshairColor = crosshairPoint == null
        ? null
        : _crosshairColorFor(crosshairPoint);
    final maxScrollOffset = _maxScrollOffset();
    final showPanButtons = widget.image != null && widget.zoom > 70;
    final canPanHorizontally = maxScrollOffset.dx > 0;
    final canPanVertically = maxScrollOffset.dy > 0;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): _CancelDraftIntent(),
      },
      child: Actions(
        actions: {
          _CancelDraftIntent: CallbackAction<_CancelDraftIntent>(
            onInvoke: (_) {
              if (!_handleEscape()) {
                widget.onAnnotationSelected(null);
                widget.onSelectMode();
              }
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: _canvasFocusNode,
          autofocus: true,
          onKeyEvent: _handleCanvasKeyEvent,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _canvasColor(context),
              border: Border.all(color: _borderColor(context), width: 1.5),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 16,
                  color: Color(0x140F172A),
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: MouseRegion(
              cursor: _hoveredCornerIndex == null
                  ? widget.activeTool == 'draw'
                        ? SystemMouseCursors.precise
                        : MouseCursor.defer
                  : (_hoveredCornerIndex == 0 || _hoveredCornerIndex == 2)
                  ? SystemMouseCursors.resizeUpLeftDownRight
                  : SystemMouseCursors.resizeUpRightDownLeft,
              onExit: (_) {
                setState(() {
                  _hoverPoint = null;
                  _hoveredCornerIndex = null;
                });
              },
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _handlePointerDown,
                      onPointerMove: _handlePointerMove,
                      onPointerHover: _handlePointerHover,
                      onPointerUp: _handlePointerUp,
                      onPointerCancel: (_) => _cancelDraft(),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CustomPaint(
                            painter: _CanvasGridPainter(_isDarkMode(context)),
                          ),
                          if (widget.image == null)
                            Center(child: Text(t('label.openPrompt')))
                          else
                            Center(
                              child: Transform.scale(
                                scale: _scale,
                                child: SizedBox(
                                  width: _annotationWorkspaceWidth,
                                  height: _annotationWorkspaceHeight,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      CustomPaint(
                                        painter: _AnnotationPainter(
                                          image: _decodedImage,
                                          annotations: widget.annotations,
                                          classes: widget.labelClasses,
                                          selectedAnnotation:
                                              selectedAnnotation,
                                          draftRect: _draftRect,
                                          draftSegPoints: _segDraftPoints,
                                          imageRect: imageRect,
                                          imageOffset: _scrollOffset,
                                          draftMode: widget.activeMode,
                                          draftClassId: _draftClassId,
                                          showClassLabels:
                                              widget.showClassLabels,
                                          scale: _scale,
                                          darkMode: _isDarkMode(context),
                                          crosshairPoint: crosshairPoint,
                                          crosshairColor: crosshairColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (showPanButtons)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 12,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _ViewportPanButton(
                              icon: Icons.keyboard_arrow_left,
                              tooltip: t('viewport.panLeft'),
                              onPressed: canPanHorizontally
                                  ? () => _panViewport(const Offset(1, 0))
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            _ViewportPanButton(
                              icon: Icons.keyboard_arrow_right,
                              tooltip: t('viewport.panRight'),
                              onPressed: canPanHorizontally
                                  ? () => _panViewport(const Offset(-1, 0))
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    if (showPanButtons)
                      Positioned(
                        top: 0,
                        right: 12,
                        bottom: 0,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _ViewportPanButton(
                              icon: Icons.keyboard_arrow_up,
                              tooltip: t('viewport.panUp'),
                              onPressed: canPanVertically
                                  ? () => _panViewport(const Offset(0, 1))
                                  : null,
                            ),
                            const SizedBox(height: 8),
                            _ViewportPanButton(
                              icon: Icons.keyboard_arrow_down,
                              tooltip: t('viewport.panDown'),
                              onPressed: canPanVertically
                                  ? () => _panViewport(const Offset(0, -1))
                                  : null,
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
      ),
    );
  }
}

class _SampledImage {
  const _SampledImage({
    required this.image,
    required this.size,
    required this.bytes,
  });

  final ui.Image image;
  final Size size;
  final Uint8List bytes;
}

class _CancelDraftIntent extends Intent {
  const _CancelDraftIntent();
}

class _ResizeHandle {
  const _ResizeHandle(this.annotationId, this.cornerIndex);

  final String annotationId;
  final int cornerIndex;
}

class _ViewportPanButton extends StatelessWidget {
  const _ViewportPanButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 36,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _controlColor(
              context,
            ).withValues(alpha: enabled ? 0.92 : 0.52),
            border: Border.all(color: _borderColor(context)),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                blurRadius: 10,
                color: Color(0x22000000),
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: IconButton(
            onPressed: onPressed,
            padding: EdgeInsets.zero,
            iconSize: 22,
            color: _primaryTextColor(context),
            disabledColor: _primaryTextColor(context).withValues(alpha: 0.32),
            icon: Icon(icon),
          ),
        ),
      ),
    );
  }
}

class _AnnotationPainter extends CustomPainter {
  const _AnnotationPainter({
    this.image,
    required this.annotations,
    required this.classes,
    required this.selectedAnnotation,
    required this.draftRect,
    required this.draftSegPoints,
    required this.imageRect,
    required this.imageOffset,
    required this.draftMode,
    required this.draftClassId,
    required this.showClassLabels,
    required this.scale,
    required this.darkMode,
    required this.crosshairPoint,
    required this.crosshairColor,
  });

  final ui.Image? image;
  final List<_AnnotationRegion> annotations;
  final List<_LabelClass> classes;
  final _AnnotationRegion? selectedAnnotation;
  final Rect? draftRect;
  final List<Offset> draftSegPoints;
  final Rect imageRect;
  final Offset imageOffset;
  final _AnnotationMode draftMode;
  final int? draftClassId;
  final bool showClassLabels;
  final double scale;
  final bool darkMode;
  final Offset? crosshairPoint;
  final Color? crosshairColor;

  @override
  void paint(Canvas canvas, Size size) {
    final canvasOrigin = imageRect.topLeft + imageOffset;
    final placedImageRect = imageRect.shift(imageOffset);

    // Draw the image at the computed position
    final img = image;
    if (img != null) {
      final srcRect = Rect.fromLTWH(
        0,
        0,
        img.width.toDouble(),
        img.height.toDouble(),
      );
      canvas.drawImageRect(img, srcRect, placedImageRect, Paint());
    }

    final selected = selectedAnnotation;
    if (selected != null) {
      final overlayRect = selected.mode == _AnnotationMode.obb
          ? _rotatedBoundingRect(
              selected.rect,
              selected.rotationDegrees,
            ).shift(canvasOrigin)
          : selected.rect.shift(canvasOrigin);
      _drawOutsideOverlay(canvas, placedImageRect, overlayRect);
    }

    _drawImageBounds(canvas, placedImageRect);

    for (final annotation in annotations) {
      final labelClass = _classById(annotation.classId);
      final color = labelClass?.color ?? const Color(0xFF2563EB);
      final selected = annotation.id == selectedAnnotation?.id;
      _drawAnnotation(canvas, annotation, color, selected);
      if (showClassLabels && labelClass != null) {
        _drawLabel(
          canvas,
          annotation.rect.shift(canvasOrigin),
          labelClass.name,
          color,
          selected,
        );
      }
    }

    final draft = draftRect;
    if (draft != null) {
      final labelClass = _classById(draftClassId);
      _drawAnnotation(
        canvas,
        _AnnotationRegion.fromRect(
          id: 'draft',
          mode: draftMode,
          rect: draft,
          classId: draftClassId ?? -1,
        ),
        labelClass?.color ?? const Color(0xFF2563EB),
        false,
      );
    }

    if (draftSegPoints.isNotEmpty) {
      final color = _classById(draftClassId)?.color ?? const Color(0xFF2563EB);
      final canvasPoints = draftSegPoints.map((p) => p + canvasOrigin).toList();
      _drawDraftSegPolygon(canvas, canvasPoints, color);
    }

    final crosshair = crosshairPoint;
    final color = crosshairColor;
    if (crosshair != null &&
        color != null &&
        placedImageRect.contains(crosshair)) {
      _drawCrosshair(canvas, crosshair, color);
    }
  }

  _LabelClass? _classById(int? id) {
    if (id == null) {
      return null;
    }
    return classes.where((item) => item.id == id).firstOrNullValue;
  }

  Rect _rotatedBoundingRect(Rect rect, double degrees) {
    final corners = _rotatedCorners(rect, degrees);
    final xs = corners.map((p) => p.dx);
    final ys = corners.map((p) => p.dy);
    return Rect.fromLTRB(
      xs.reduce(math.min),
      ys.reduce(math.min),
      xs.reduce(math.max),
      ys.reduce(math.max),
    );
  }

  void _drawOutsideOverlay(Canvas canvas, Rect bounds, Rect rect) {
    final target = rect.intersect(bounds);
    if (target.isEmpty) {
      return;
    }
    final paint = Paint()
      ..color = (darkMode ? Colors.black : Colors.grey).withValues(alpha: 0.42);
    canvas
      ..drawRect(
        Rect.fromLTRB(bounds.left, bounds.top, bounds.right, target.top),
        paint,
      )
      ..drawRect(
        Rect.fromLTRB(bounds.left, target.bottom, bounds.right, bounds.bottom),
        paint,
      )
      ..drawRect(
        Rect.fromLTRB(bounds.left, target.top, target.left, target.bottom),
        paint,
      )
      ..drawRect(
        Rect.fromLTRB(target.right, target.top, bounds.right, target.bottom),
        paint,
      );
  }

  void _drawImageBounds(Canvas canvas, Rect placedRect) {
    final paint = Paint()
      ..color = darkMode ? const Color(0xFF6D5BD0) : const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / scale;
    canvas.drawRect(placedRect, paint);
  }

  void _drawCrosshair(Canvas canvas, Offset point, Color color) {
    final contrast = color.computeLuminance() > 0.5
        ? const Color(0xFF111827)
        : Colors.white;
    final underlay = Paint()
      ..color = contrast.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2 / scale;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 / scale;
    final placedRect = imageRect.shift(imageOffset);
    final horizontal = [
      Offset(placedRect.left, point.dy),
      Offset(placedRect.right, point.dy),
    ];
    final vertical = [
      Offset(point.dx, placedRect.top),
      Offset(point.dx, placedRect.bottom),
    ];
    _drawDashedLine(canvas, horizontal.first, horizontal.last, underlay);
    _drawDashedLine(canvas, vertical.first, vertical.last, underlay);
    _drawDashedLine(canvas, horizontal.first, horizontal.last, paint);
    _drawDashedLine(canvas, vertical.first, vertical.last, paint);
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    final dash = 8 / scale;
    final gap = 6 / scale;
    final delta = end - start;
    final distance = delta.distance;
    if (distance <= 0) {
      return;
    }
    final direction = delta / distance;
    var current = 0.0;
    while (current < distance) {
      final next = math.min(current + dash, distance);
      canvas.drawLine(
        start + direction * current,
        start + direction * next,
        paint,
      );
      current += dash + gap;
    }
  }

  void _drawDraftSegPolygon(Canvas canvas, List<Offset> points, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 / scale;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
    _drawSegNodes(canvas, points, closeHint: points.length >= 3);
  }

  void _drawAnnotation(
    Canvas canvas,
    _AnnotationRegion annotation,
    Color color,
    bool selected,
  ) {
    final strokeWidth = (selected ? 2.6 : 2.0) / scale;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    if (annotation.mode == _AnnotationMode.seg) {
      final points = annotation.points.isEmpty
          ? _rectToPoints(annotation.rect)
          : annotation.points;
      final canvasPoints = points
          .map((p) => p + imageRect.topLeft + imageOffset)
          .toList();
      final path = Path()..addPolygon(canvasPoints, true);
      canvas.drawPath(path, paint);
      if (selected) {
        _drawSegNodes(canvas, canvasPoints);
      }
      return;
    }

    if (annotation.mode == _AnnotationMode.obb) {
      final center = annotation.rect.center + imageRect.topLeft + imageOffset;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(annotation.rotationDegrees * 3.1415926535 / 180);
      final centered = Rect.fromCenter(
        center: Offset.zero,
        width: annotation.rect.width,
        height: annotation.rect.height,
      );
      canvas.drawRect(centered, paint);
      if (selected) {
        _drawCornerHandles(canvas, centered);
      }
      canvas.restore();
      return;
    }

    canvas.drawRect(
      annotation.rect.shift(imageRect.topLeft + imageOffset),
      paint,
    );
    if (selected) {
      _drawCornerHandles(
        canvas,
        annotation.rect.shift(imageRect.topLeft + imageOffset),
      );
    }
  }

  void _drawCornerHandles(Canvas canvas, Rect rect) {
    final handlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = const Color(0xFF334155)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / scale;
    for (final point in [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ]) {
      final handle = Rect.fromCenter(
        center: point,
        width: 8 / scale,
        height: 8 / scale,
      );
      canvas.drawRect(handle, handlePaint);
      canvas.drawRect(handle, borderPaint);
    }
  }

  void _drawSegNodes(
    Canvas canvas,
    List<Offset> points, {
    bool closeHint = false,
  }) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = const Color(0xFF334155)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / scale;
    for (final point in points) {
      if (closeHint && point == points.first) {
        canvas.drawRect(
          Rect.fromCenter(center: point, width: 10 / scale, height: 10 / scale),
          paint,
        );
        canvas.drawRect(
          Rect.fromCenter(center: point, width: 10 / scale, height: 10 / scale),
          border,
        );
      } else {
        canvas.drawCircle(point, 4 / scale, paint);
        canvas.drawCircle(point, 4 / scale, border);
      }
    }
  }

  void _drawLabel(
    Canvas canvas,
    Rect rect,
    String label,
    Color color,
    bool selected,
  ) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: selected ? Colors.white : color,
          fontSize: 13 / scale,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 180 / scale);
    final origin = Offset(
      rect.left,
      (rect.top - 20 / scale).clamp(0, rect.top),
    );
    if (selected) {
      final background = Rect.fromLTWH(
        origin.dx - 4 / scale,
        origin.dy - 2 / scale,
        textPainter.width + 8 / scale,
        textPainter.height + 4 / scale,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(background, Radius.circular(3 / scale)),
        Paint()..color = const Color(0xFF64748B),
      );
    }
    textPainter.paint(canvas, origin);
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) => true;
}

/// 右侧 AI/标注工具栏，包含工具按钮和类别管理。
/// Right-side AI/annotation toolbar with tools and class management.
class _AiToolbar extends StatelessWidget {
  const _AiToolbar({
    required this.activeTool,
    required this.activeClassId,
    required this.labelClasses,
    required this.annotations,
    required this.selectedAnnotationId,
    required this.showClassLabels,
    required this.onToolSelected,
    required this.onClassSelected,
    required this.onClassAdded,
    required this.onClassEdited,
    required this.onClassColorChanged,
    required this.onClassDeleted,
    required this.onClassReordered,
    required this.onToggleClassLabels,
    required this.onAnnotationSelected,
    required this.onAnnotationClassChanged,
  });

  final String activeTool;
  final int? activeClassId;
  final List<_LabelClass> labelClasses;
  final List<_AnnotationRegion> annotations;
  final String? selectedAnnotationId;
  final bool showClassLabels;
  final ValueChanged<String> onToolSelected;
  final ValueChanged<int> onClassSelected;
  final VoidCallback onClassAdded;
  final ValueChanged<_LabelClass> onClassEdited;
  final ValueChanged<_LabelClass> onClassColorChanged;
  final ValueChanged<_LabelClass> onClassDeleted;
  final void Function(int oldIndex, int newIndex) onClassReordered;
  final VoidCallback onToggleClassLabels;
  final ValueChanged<String?> onAnnotationSelected;
  final void Function(String annotationId, int classId)
  onAnnotationClassChanged;

  static const _tools = [
    _ToolSpec('select', Icons.near_me_outlined, 'tool.select'),
    _ToolSpec('copy', Icons.copy_outlined, 'tool.copy'),
    _ToolSpec('paste', Icons.content_paste_outlined, 'tool.paste'),
    _ToolSpec('undo', Icons.undo, 'tool.undo'),
    _ToolSpec('redo', Icons.redo, 'tool.redo'),
    _ToolSpec('delete', Icons.delete_outline, 'tool.delete'),
    _ToolSpec('export', Icons.file_download_outlined, 'tool.export'),
  ];

  @override
  Widget build(BuildContext context) {
    final showAnnotations =
        selectedAnnotationId != null || activeTool == 'annotations';
    return Container(
      width: _toolbarWidth,
      decoration: BoxDecoration(
        color: _panelColor(context),
        border: Border(left: BorderSide(color: _borderColor(context))),
      ),
      child: Column(
        children: [
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    showAnnotations ? t('label.annotations') : t('label.ai'),
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Tooltip(
                  message: showAnnotations
                      ? t('label.showTools')
                      : t('label.showAnnotations'),
                  child: IconButton(
                    onPressed: () => onToolSelected(
                      showAnnotations ? 'select' : 'annotations',
                    ),
                    icon: Icon(
                      showAnnotations
                          ? Icons.construction_outlined
                          : Icons.format_list_bulleted,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (showAnnotations)
            Expanded(
              child: _AnnotationListPanel(
                annotations: annotations,
                labelClasses: labelClasses,
                selectedAnnotationId: selectedAnnotationId,
                onAnnotationSelected: onAnnotationSelected,
                onAnnotationClassChanged: onAnnotationClassChanged,
              ),
            )
          else ...[
            for (final tool in _tools)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                child: _ToolButton(
                  tool: tool,
                  selected: tool.id == activeTool,
                  onPressed: () => onToolSelected(tool.id),
                ),
              ),
            const Divider(height: 16),
            Expanded(
              child: _ClassManager(
                activeClassId: activeClassId,
                labelClasses: labelClasses,
                showClassLabels: showClassLabels,
                onClassSelected: onClassSelected,
                onClassAdded: onClassAdded,
                onClassEdited: onClassEdited,
                onClassColorChanged: onClassColorChanged,
                onClassDeleted: onClassDeleted,
                onClassReordered: onClassReordered,
                onToggleClassLabels: onToggleClassLabels,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 工具栏按钮，负责图标、文字和选中态显示。
/// Toolbar button that renders icon, text, and selected state.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.tool,
    required this.selected,
    required this.onPressed,
  });

  final _ToolSpec tool;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = selected
        ? colorScheme.primaryContainer
        : _controlColor(context);
    final foreground = selected
        ? colorScheme.onPrimaryContainer
        : _primaryTextColor(context);

    return Tooltip(
      message: t(tool.label),
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: selected ? colorScheme.primary : _borderColor(context),
          ),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 42,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(tool.icon, size: 19, color: foreground),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t(tool.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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

class _AnnotationListPanel extends StatelessWidget {
  const _AnnotationListPanel({
    required this.annotations,
    required this.labelClasses,
    required this.selectedAnnotationId,
    required this.onAnnotationSelected,
    required this.onAnnotationClassChanged,
  });

  final List<_AnnotationRegion> annotations;
  final List<_LabelClass> labelClasses;
  final String? selectedAnnotationId;
  final ValueChanged<String?> onAnnotationSelected;
  final void Function(String annotationId, int classId)
  onAnnotationClassChanged;

  @override
  Widget build(BuildContext context) {
    if (annotations.isEmpty) {
      return Center(child: Text(t('label.noAnnotations')));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
      itemCount: annotations.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final annotation = annotations[index];
        final selected = annotation.id == selectedAnnotationId;
        final labelClass = labelClasses
            .where((item) => item.id == annotation.classId)
            .firstOrNullValue;
        return Tooltip(
          waitDuration: const Duration(milliseconds: 350),
          message: _annotationCoordinateTooltip(annotation),
          child: Material(
            color: selected
                ? Theme.of(context).colorScheme.primaryContainer
                : _controlColor(context),
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: () => onAnnotationSelected(annotation.id),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : _borderColor(context),
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${index + 1}. ${annotation.mode.label}',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const Spacer(),
                        if (labelClass != null)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: labelClass.color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const SizedBox.square(dimension: 14),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      initialValue: annotation.classId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                      items: [
                        for (final labelClass in labelClasses)
                          DropdownMenuItem(
                            value: labelClass.id,
                            child: Text(
                              labelClass.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (classId) {
                        if (classId != null) {
                          onAnnotationClassChanged(annotation.id, classId);
                        }
                      },
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

String _annotationCoordinateTooltip(_AnnotationRegion annotation) {
  final rect = annotation.rect;
  final lines = [
    '${annotation.mode.label} 图片坐标',
    'left=${_coord(rect.left)}, top=${_coord(rect.top)}',
    'right=${_coord(rect.right)}, bottom=${_coord(rect.bottom)}',
    'center=(${_coord(rect.center.dx)}, ${_coord(rect.center.dy)})',
    'size=${_coord(rect.width)} x ${_coord(rect.height)}',
  ];
  if (annotation.mode == _AnnotationMode.obb) {
    lines.add('rotation=${annotation.rotationDegrees.toStringAsFixed(1)}°');
  }
  if (annotation.mode == _AnnotationMode.seg && annotation.points.isNotEmpty) {
    lines.add('points=${annotation.points.length}');
    final previewPoints = annotation.points
        .take(6)
        .map((point) {
          return '(${_coord(point.dx)}, ${_coord(point.dy)})';
        })
        .join(' ');
    lines.add(previewPoints);
    if (annotation.points.length > 6) {
      lines.add('...');
    }
  }
  return lines.join('\n');
}

String _coord(double value) => value.toStringAsFixed(1);

class _ClassManager extends StatelessWidget {
  const _ClassManager({
    required this.activeClassId,
    required this.labelClasses,
    required this.showClassLabels,
    required this.onClassSelected,
    required this.onClassAdded,
    required this.onClassEdited,
    required this.onClassColorChanged,
    required this.onClassDeleted,
    required this.onClassReordered,
    required this.onToggleClassLabels,
  });

  final int? activeClassId;
  final List<_LabelClass> labelClasses;
  final bool showClassLabels;
  final ValueChanged<int> onClassSelected;
  final VoidCallback onClassAdded;
  final ValueChanged<_LabelClass> onClassEdited;
  final ValueChanged<_LabelClass> onClassColorChanged;
  final ValueChanged<_LabelClass> onClassDeleted;
  final void Function(int oldIndex, int newIndex) onClassReordered;
  final VoidCallback onToggleClassLabels;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t('label.classes'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Tooltip(
                message: t('label.addClass'),
                child: IconButton(
                  onPressed: onClassAdded,
                  icon: const Icon(Icons.add),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onToggleClassLabels,
              icon: Icon(
                showClassLabels
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 17,
              ),
              label: Text(
                showClassLabels ? t('label.hideNames') : t('label.showNames'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: labelClasses.isEmpty
              ? Center(child: Text(t('label.noClasses')))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                  itemCount: labelClasses.length,
                  onReorderItem: onClassReordered,
                  buildDefaultDragHandles: false,
                  itemBuilder: (context, index) {
                    final labelClass = labelClasses[index];
                    return _ClassTile(
                      key: ValueKey(labelClass.id),
                      index: index,
                      labelClass: labelClass,
                      selected: labelClass.id == activeClassId,
                      onSelected: () => onClassSelected(labelClass.id),
                      onEdit: () => onClassEdited(labelClass),
                      onColor: () => onClassColorChanged(labelClass),
                      onDelete: () => onClassDeleted(labelClass),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ClassTile extends StatelessWidget {
  const _ClassTile({
    super.key,
    required this.index,
    required this.labelClass,
    required this.selected,
    required this.onSelected,
    required this.onEdit,
    required this.onColor,
    required this.onDelete,
  });

  final int index;
  final _LabelClass labelClass;
  final bool selected;
  final VoidCallback onSelected;
  final VoidCallback onEdit;
  final VoidCallback onColor;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? colorScheme.primaryContainer : _controlColor(context),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onSelected,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? colorScheme.primary : _borderColor(context),
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onColor,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: labelClass.color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const SizedBox.square(dimension: 18),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    labelClass.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: t('label.editClass'),
                  visualDensity: VisualDensity.compact,
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
                IconButton(
                  tooltip: t('label.deleteClass'),
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                  icon: const Icon(Icons.close, size: 18),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.drag_indicator, size: 18),
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

/// 底部标注控制栏，包含缩放、主题和快捷键入口。
/// Bottom annotation controls for zoom, theme, and shortcut settings.
class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.zoom,
    required this.zoomLocked,
    required this.darkMode,
    required this.onZoomChanged,
    required this.onToggleZoomLock,
    required this.onToggleThemeMode,
    required this.onOpenKeySettings,
  });

  final double zoom;
  final bool zoomLocked;
  final bool darkMode;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onToggleZoomLock;
  final VoidCallback onToggleThemeMode;
  final VoidCallback onOpenKeySettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _bottomBarHeight,
      decoration: BoxDecoration(
        color: _panelColor(context),
        border: Border(top: BorderSide(color: _borderColor(context))),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        children: [
          _SquareIconButton(
            icon: Icons.remove,
            tooltip: t('bottom.zoomOut'),
            onPressed: zoomLocked ? null : () => onZoomChanged(zoom - 10),
          ),
          _ZoomValue(value: '${zoom.round()}%'),
          _SquareIconButton(
            icon: zoomLocked ? Icons.link_off : Icons.link,
            tooltip: t('bottom.lockZoom'),
            selected: zoomLocked,
            onPressed: onToggleZoomLock,
          ),
          _SquareIconButton(
            icon: Icons.add,
            tooltip: t('bottom.zoomIn'),
            onPressed: zoomLocked ? null : () => onZoomChanged(zoom + 10),
          ),
          _ControlButton(
            label: t('bottom.reset'),
            width: 96,
            onPressed: zoomLocked ? null : () => onZoomChanged(100),
          ),
          _ControlButton(
            icon: darkMode
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
            label: darkMode ? t('bottom.dayMode') : t('bottom.nightMode'),
            width: 126,
            onPressed: onToggleThemeMode,
          ),
          _ControlButton(
            icon: Icons.keyboard_outlined,
            label: t('bottom.shortcuts'),
            width: 154,
            onPressed: onOpenKeySettings,
          ),
        ],
      ),
    );
  }
}

/// 带文字的底部控制按钮，固定宽度避免文字挤压。
/// Text control button with fixed width to avoid label clipping.
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.label,
    required this.width,
    required this.onPressed,
    this.icon,
  });

  final IconData? icon;
  final String label;
  final double width;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final labelWidget = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: SizedBox(
        height: 42,
        width: width,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          child: icon == null
              ? labelWidget
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 18),
                    const SizedBox(width: 6),
                    Flexible(child: labelWidget),
                  ],
                ),
        ),
      ),
    );
  }
}

/// 当前缩放比例显示，只显示状态不触发操作。
/// Current zoom display; it shows state without triggering actions.
class _ZoomValue extends StatelessWidget {
  const _ZoomValue({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: SizedBox(
        width: 72,
        height: 42,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _controlColor(context),
            border: Border.all(color: _borderColor(context)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ),
      ),
    );
  }
}

/// 仅图标方形按钮，用于缩放等高频操作。
/// Square icon-only button for frequent actions such as zooming.
class _SquareIconButton extends StatelessWidget {
  const _SquareIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Tooltip(
        message: tooltip,
        child: SizedBox.square(
          dimension: 42,
          child: OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              backgroundColor: selected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              foregroundColor: selected
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: Icon(icon, size: 18),
          ),
        ),
      ),
    );
  }
}
