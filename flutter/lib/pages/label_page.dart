// =============================================================================
// label_page.dart - Annotation Canvas & Tools / 标注画布与工具栏
// =============================================================================
// Image annotation page with drawing canvas, annotation painter,
// class management, export, and AI-assisted annotation controls.
//
// 图片标注页面：绘制画布、标注渲染器、类别管理、导出与 AI 辅助标注。
// =============================================================================

// ignore_for_file: file_names

part of '../main.dart';

/// 标注页面入口，组合图片列表、画布、工具栏和类别面板。
/// Label page entry that combines image list, canvas, toolbar, and classes.
class _LabelPage extends StatelessWidget {
  const _LabelPage({
    required this.status,
    required this.images,
    required this.selectedImage,
    required this.selectedImageIndex,
    required this.unauthorized,
    required this.zoom,
    required this.viewportOffset,
    required this.activeTool,
    required this.activeMode,
    required this.imageSplit,
    required this.activeClassId,
    required this.labelClasses,
    required this.annotationsByImage,
    required this.annotations,
    required this.sam3ClickPrompts,
    required this.sam3PreviewAnnotations,
    required this.selectedAnnotationId,
    required this.showClassLabels,
    required this.aiPanelVisible,
    required this.classesEditable,
    required this.onImageSelected,
    required this.onImageContextMenu,
    required this.onPointerSignal,
    required this.onViewportOffsetChanged,
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
    required this.onAiConfigPressed,
    this.onSam3ClickPrompt,
    this.onImageDisplaySizeChanged,
  });

  final _BridgeStatus status;
  final List<_ImageItem> images;
  final _ImageItem? selectedImage;
  final int selectedImageIndex;
  final bool unauthorized;
  final double zoom;
  final Offset viewportOffset;
  final String activeTool;
  final _AnnotationMode activeMode;
  final String imageSplit;
  final int? activeClassId;
  final List<_LabelClass> labelClasses;
  final Map<String, List<_AnnotationRegion>> annotationsByImage;
  final List<_AnnotationRegion> annotations;
  final List<_Sam3ClickPromptPoint> sam3ClickPrompts;
  final List<_AnnotationRegion> sam3PreviewAnnotations;
  final String? selectedAnnotationId;
  final bool showClassLabels;
  final bool aiPanelVisible;
  final bool classesEditable;
  final ValueChanged<int> onImageSelected;
  final Future<void> Function(TapDownDetails details, int? index)
  onImageContextMenu;
  final void Function(PointerSignalEvent event) onPointerSignal;
  final ValueChanged<Offset> onViewportOffsetChanged;
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
  final VoidCallback onAiConfigPressed;
  final Future<bool> Function(
    Offset imagePoint,
    Size imageDisplaySize,
    bool positive,
  )?
  onSam3ClickPrompt;
  final void Function(Size imageDisplaySize)? onImageDisplaySizeChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Row(
        children: [
          _ImagePreviewPane(
            images: images,
            selectedIndex: selectedImageIndex,
            labelClasses: labelClasses,
            annotationsByImage: annotationsByImage,
            onImageSelected: onImageSelected,
            onContextMenu: onImageContextMenu,
          ),
          Expanded(
            child: ClipRect(
              child: _CanvasStage(
                bridgeStatus: status,
                image: selectedImage,
                unauthorized: unauthorized,
                imageIndex: images.isEmpty ? 0 : selectedImageIndex + 1,
                imageCount: images.length,
                zoom: zoom,
                viewportOffset: viewportOffset,
                activeTool: activeTool,
                activeMode: activeMode,
                imageSplit: imageSplit,
                labelClasses: labelClasses,
                annotations: annotations,
                sam3ClickPrompts: sam3ClickPrompts,
                sam3PreviewAnnotations: sam3PreviewAnnotations,
                selectedAnnotationId: selectedAnnotationId,
                showClassLabels: showClassLabels,
                onPointerSignal: onPointerSignal,
                onViewportOffsetChanged: onViewportOffsetChanged,
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
                onSam3ClickPrompt: onSam3ClickPrompt,
                onImageDisplaySizeChanged: onImageDisplaySizeChanged,
              ),
            ),
          ),
          RepaintBoundary(
            child: _AiToolbar(
              activeTool: activeTool,
              activeClassId: activeClassId,
              labelClasses: labelClasses,
              annotations: annotations,
              selectedAnnotationId: selectedAnnotationId,
              showClassLabels: showClassLabels,
              aiPanelVisible: aiPanelVisible,
              classesEditable: classesEditable,
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
              onAiConfigPressed: onAiConfigPressed,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fixed-size image canvas with draw, select, drag, and delete support.
class _ImageCanvas extends StatefulWidget {
  const _ImageCanvas({
    required this.image,
    required this.unauthorized,
    required this.zoom,
    required this.viewportOffset,
    required this.activeTool,
    required this.activeMode,
    required this.labelClasses,
    required this.annotations,
    required this.sam3ClickPrompts,
    required this.sam3PreviewAnnotations,
    required this.selectedAnnotationId,
    required this.showClassLabels,
    required this.onViewportOffsetChanged,
    required this.onEnsureClass,
    required this.onSelectMode,
    required this.onAnnotationCreated,
    required this.onSegAnnotationCreated,
    required this.onAnnotationSelected,
    required this.onAnnotationUpdated,
    required this.onAnnotationDeleted,
    required this.onAnnotationDragStarted,
    this.onSam3ClickPrompt,
    this.onImageDisplaySizeChanged,
  });

  final void Function(Size imageDisplaySize)? onImageDisplaySizeChanged;
  final _ImageItem? image;
  final bool unauthorized;
  final double zoom;
  final Offset viewportOffset;
  final String activeTool;
  final _AnnotationMode activeMode;
  final List<_LabelClass> labelClasses;
  final List<_AnnotationRegion> annotations;
  final List<_Sam3ClickPromptPoint> sam3ClickPrompts;
  final List<_AnnotationRegion> sam3PreviewAnnotations;
  final String? selectedAnnotationId;
  final bool showClassLabels;
  final ValueChanged<Offset> onViewportOffsetChanged;
  final Future<int?> Function() onEnsureClass;
  final VoidCallback onSelectMode;
  final void Function(Rect rect, int classId) onAnnotationCreated;
  final void Function(List<Offset> points, int classId) onSegAnnotationCreated;
  final ValueChanged<String?> onAnnotationSelected;
  final ValueChanged<_AnnotationRegion> onAnnotationUpdated;
  final ValueChanged<String> onAnnotationDeleted;
  final VoidCallback onAnnotationDragStarted;
  final Future<bool> Function(
    Offset imagePoint,
    Size imageDisplaySize,
    bool positive,
  )?
  onSam3ClickPrompt;

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
  String? _draggingSegAnnotationId;
  int? _draggingSegPointIndex;
  Timer? _segAutoPointTimer;
  Offset? _segAutoPoint;
  int? _segAutoClassId;
  bool _draggingSelection = false;
  Size? _imageSize;
  Size? _sampleImageSize;
  Uint8List? _sampleRgbaBytes;
  Offset? _hoverPoint;
  Offset? _lastPointerLocalPosition;
  String? _loadedImagePath;
  List<Offset> _segDraftPoints = [];
  int? _hoveredCornerIndex;
  _SegVertexHandle? _hoveredSegVertex;
  ui.Image? _decodedImage;

  double get _scale => widget.zoom / 100;

  Offset get _scrollOffset => widget.viewportOffset;

  @override
  void initState() {
    super.initState();
    _loadImageSize();
  }

  @override
  void dispose() {
    _stopSegAutoPointTimer();
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
      _lastPointerLocalPosition = null;
      _movingAnnotationId = null;
      _resizingAnnotationId = null;
      _resizingCornerIndex = null;
      _draggingSegAnnotationId = null;
      _draggingSegPointIndex = null;
      _hoveredSegVertex = null;
      _draggingSelection = false;
      _stopSegAutoPointTimer();
      _loadedImagePath = null;
      _segDraftPoints = [];
      _loadImageSize();
    }
    if (oldWidget.zoom != widget.zoom) {
      _scheduleViewportClamp();
      _refreshPointerStateAfterViewportChange();
    }
    if (oldWidget.viewportOffset != widget.viewportOffset) {
      _refreshPointerStateAfterViewportChange();
    }
    if (oldWidget.activeTool == 'draw' && widget.activeTool != 'draw') {
      _stopSegAutoPointTimer();
      _drawStart = null;
      _draftRect = null;
      _draftClassId = null;
      _segDraftPoints = [];
      _hoverPoint = null;
    }
    if (oldWidget.activeTool != widget.activeTool) {
      _hoveredSegVertex = null;
    }
    if (oldWidget.activeMode != widget.activeMode) {
      _stopSegAutoPointTimer();
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
      _scheduleViewportClamp();
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

  Rect _placedImageRect() => _imageDisplayRect();

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
    return _localToContentPoint(localPoint);
  }

  Offset _localToContentPoint(Offset localPoint) {
    final inverse = Matrix4.inverted(_contentTransform());
    return MatrixUtils.transformPoint(inverse, localPoint);
  }

  Offset _toImagePoint(Offset contentPoint) {
    return contentPoint - _placedImageRect().topLeft;
  }

  Rect _visibleContentRect() {
    final center = const Offset(
      _annotationWorkspaceWidth / 2,
      _annotationWorkspaceHeight / 2,
    );
    return Rect.fromCenter(
      center: center,
      width: _annotationWorkspaceWidth / _scale,
      height: _annotationWorkspaceHeight / _scale,
    );
  }

  Matrix4 _contentTransform() {
    final center = const Offset(
      _annotationWorkspaceWidth / 2,
      _annotationWorkspaceHeight / 2,
    );
    return Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(_scale, _scale, 1, 1)
      ..translateByDouble(
        _scrollOffset.dx - center.dx,
        _scrollOffset.dy - center.dy,
        0,
        1,
      );
  }

  Offset _maxScrollOffset() {
    if (_scale <= 1.0) {
      return Offset.zero;
    }
    final imageRect = _imageDisplayRect();
    final visibleRect = _visibleContentRect();
    return Offset(
      math.max(0.0, (imageRect.width - visibleRect.width) / 2),
      math.max(0.0, (imageRect.height - visibleRect.height) / 2),
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
    widget.onViewportOffsetChanged(clamped);
  }

  void _panViewport(Offset direction, {double visualStep = 48.0}) {
    if (_scale <= 1.0) {
      return;
    }
    _setScrollOffset(_scrollOffset + direction * (visualStep / _scale));
  }

  void _scheduleViewportClamp() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final clamped = _clampedScrollOffset(widget.viewportOffset);
      if (clamped != widget.viewportOffset) {
        widget.onViewportOffsetChanged(clamped);
      }
    });
  }

  void _refreshPointerStateAfterViewportChange() {
    final localPosition = _lastPointerLocalPosition;
    if (localPosition == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _lastPointerLocalPosition != localPosition) {
        return;
      }
      _refreshPointerStateForLocalPosition(localPosition);
    });
  }

  void _refreshPointerStateForLocalPosition(Offset localPosition) {
    _updateHoverPoint(localPosition);
    final start = _drawStart;
    if (widget.image == null || start == null) {
      return;
    }
    final imageBounds = _imageBounds();
    final localPoint = _toContentPoint(localPosition);
    final nextDraft = Rect.fromPoints(
      start,
      _clampOffset(_toImagePoint(localPoint), imageBounds),
    ).intersect(imageBounds);
    if (_draftRect != nextDraft) {
      setState(() => _draftRect = nextDraft);
    }
  }

  void _handleCanvasPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final localPosition = event.localPosition;
    _lastPointerLocalPosition = localPosition;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _lastPointerLocalPosition != localPosition) {
        return;
      }
      _refreshPointerStateForLocalPosition(localPosition);
    });
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
    _lastPointerLocalPosition = localPosition;
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

  double get _segCloseDistance => 10 / _scale;

  void _stopSegAutoPointTimer() {
    _segAutoPointTimer?.cancel();
    _segAutoPointTimer = null;
    _segAutoPoint = null;
    _segAutoClassId = null;
  }

  void _startSegAutoPointTimer(Offset imagePoint, int classId) {
    _stopSegAutoPointTimer();
    _segAutoPoint = imagePoint;
    _segAutoClassId = classId;
    _segAutoPointTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted ||
          widget.activeTool != 'draw' ||
          widget.activeMode != _AnnotationMode.seg ||
          _segDraftPoints.isEmpty) {
        _stopSegAutoPointTimer();
        return;
      }
      final point = _segAutoPoint;
      final classId = _segAutoClassId;
      if (point == null || classId == null) {
        return;
      }
      _addSegDraftPoint(point, classId, force: false);
    });
  }

  void _updateSegAutoPoint(Offset imagePoint) {
    if (_segAutoPointTimer != null) {
      _segAutoPoint = imagePoint;
    }
  }

  bool _closeSegDraftIfNeeded(Offset imagePoint, int classId) {
    final first = _segDraftPoints.isEmpty ? null : _segDraftPoints.first;
    if (first == null || _segDraftPoints.length < 3) {
      return false;
    }
    if ((imagePoint - first).distance > _segCloseDistance) {
      return false;
    }
    _stopSegAutoPointTimer();
    widget.onSegAnnotationCreated(List<Offset>.of(_segDraftPoints), classId);
    setState(() {
      _segDraftPoints = [];
      _draftClassId = null;
    });
    return true;
  }

  void _addSegDraftPoint(
    Offset imagePoint,
    int classId, {
    required bool force,
  }) {
    final point = _clampOffset(imagePoint, _imageBounds());
    if (_closeSegDraftIfNeeded(point, classId)) {
      return;
    }
    final last = _segDraftPoints.isEmpty ? null : _segDraftPoints.last;
    if (!force &&
        last != null &&
        (point - last).distance <= _segCloseDistance) {
      return;
    }
    setState(() {
      _draftClassId = classId;
      _segDraftPoints = [..._segDraftPoints, point];
    });
  }

  void _undoSegDraftPointToStart() {
    if (_segDraftPoints.length <= 1) {
      return;
    }
    setState(() {
      _segDraftPoints = _segDraftPoints.sublist(0, _segDraftPoints.length - 1);
    });
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
      _stopSegAutoPointTimer();
      _movingAnnotationId = null;
      _resizingAnnotationId = null;
      _resizingCornerIndex = null;
      _draggingSegAnnotationId = null;
      _draggingSegPointIndex = null;
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

  _SegVertexHandle? _segVertexHandleAt(Offset point) {
    final imagePoint = _toImagePoint(point);
    final selected = _selectedAnnotation();
    final candidates = <_AnnotationRegion>[
      if (selected != null && selected.mode == _AnnotationMode.seg) selected,
      for (final annotation in widget.annotations.reversed)
        if (annotation.mode == _AnnotationMode.seg &&
            annotation.id != selected?.id)
          annotation,
    ];
    for (final annotation in candidates) {
      final points = annotation.points.length >= 3
          ? annotation.points
          : _rectToPoints(annotation.rect);
      for (var index = points.length - 1; index >= 0; index--) {
        if ((points[index] - imagePoint).distance <= 8 / _scale) {
          return _SegVertexHandle(annotation.id, index);
        }
      }
    }
    return null;
  }

  _AnnotationRegion _updatedSegVertex(
    _AnnotationRegion annotation,
    int pointIndex,
    Offset point,
  ) {
    if (annotation.mode != _AnnotationMode.seg) {
      return annotation;
    }
    final points = annotation.points.length >= 3
        ? List<Offset>.of(annotation.points)
        : _rectToPoints(annotation.rect);
    if (pointIndex < 0 || pointIndex >= points.length) {
      return annotation;
    }
    points[pointIndex] = point;
    final xs = points.map((item) => item.dx);
    final ys = points.map((item) => item.dy);
    final rect = Rect.fromLTRB(
      xs.reduce(math.min),
      ys.reduce(math.min),
      xs.reduce(math.max),
      ys.reduce(math.max),
    );
    return annotation.copyWith(points: points, rect: _normalizeRect(rect));
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
    _lastPointerLocalPosition = event.localPosition;
    _canvasFocusNode.requestFocus();
    final rawPoint = _toUnclampedContentPoint(event.localPosition);
    final insideImage = _placedImageRect().contains(rawPoint);
    final localPoint = _toContentPoint(event.localPosition);
    final hit = insideImage ? _annotationAt(rawPoint) : null;
    final sam3ClickPrompt = widget.onSam3ClickPrompt;
    if (sam3ClickPrompt != null &&
        insideImage &&
        (event.buttons == kPrimaryMouseButton ||
            event.buttons == kSecondaryMouseButton)) {
      final imageRect = _placedImageRect();
      final imagePoint = _clampOffset(
        _toImagePoint(rawPoint),
        Offset.zero & imageRect.size,
      );
      final handled = await sam3ClickPrompt(
        imagePoint,
        imageRect.size,
        event.buttons == kPrimaryMouseButton,
      );
      if (handled) {
        return;
      }
    }

    if (event.buttons == kSecondaryMouseButton) {
      if (widget.activeTool == 'draw' &&
          widget.activeMode == _AnnotationMode.seg &&
          _segDraftPoints.isNotEmpty) {
        _stopSegAutoPointTimer();
        _undoSegDraftPointToStart();
        return;
      }
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
      final segHandle = insideImage ? _segVertexHandleAt(rawPoint) : null;
      if (segHandle != null) {
        widget.onAnnotationSelected(segHandle.annotationId);
        widget.onAnnotationDragStarted();
        _draggingSegAnnotationId = segHandle.annotationId;
        _draggingSegPointIndex = segHandle.pointIndex;
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
      final imagePoint = _toImagePoint(localPoint);
      _addSegDraftPoint(imagePoint, classId, force: true);
      if (_segDraftPoints.isNotEmpty) {
        _startSegAutoPointTimer(imagePoint, classId);
      }
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
    if (_segAutoPointTimer != null && event.buttons == kPrimaryMouseButton) {
      _updateSegAutoPoint(imagePoint);
    }
    final segId = _draggingSegAnnotationId;
    final segIndex = _draggingSegPointIndex;
    if (segId != null &&
        segIndex != null &&
        event.buttons == kPrimaryMouseButton) {
      final current = widget.annotations
          .where((annotation) => annotation.id == segId)
          .firstOrNullValue;
      if (current != null) {
        final imageBounds = _imageBounds();
        widget.onAnnotationUpdated(
          _updatedSegVertex(
            current,
            segIndex,
            _clampOffset(imagePoint, imageBounds),
          ),
        );
      }
      return;
    }
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
    // ---------------------------------------------------------------------------
    // Annotation Painter / 标注渲染器
    // ---------------------------------------------------------------------------
    _updateHoverPoint(event.localPosition);

    final handle = widget.image != null
        ? _resizeHandleAt(_toUnclampedContentPoint(event.localPosition))
        : null;
    final cornerIndex = handle?.cornerIndex;
    final segHandle = widget.image != null && widget.activeTool == 'select'
        ? _segVertexHandleAt(_toUnclampedContentPoint(event.localPosition))
        : null;
    if (cornerIndex != _hoveredCornerIndex || segHandle != _hoveredSegVertex) {
      setState(() {
        _hoveredCornerIndex = cornerIndex;
        _hoveredSegVertex = segHandle;
      });
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
    _stopSegAutoPointTimer();
    if (_draggingSelection) {
      setState(() {
        _movingAnnotationId = null;
        _resizingAnnotationId = null;
        _resizingCornerIndex = null;
        _draggingSegAnnotationId = null;
        _draggingSegPointIndex = null;
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
    final MouseCursor canvasCursor;
    if (_hoveredCornerIndex != null) {
      canvasCursor = (_hoveredCornerIndex == 0 || _hoveredCornerIndex == 2)
          ? SystemMouseCursors.resizeUpLeftDownRight
          : SystemMouseCursors.resizeUpRightDownLeft;
    } else if (_hoveredSegVertex != null) {
      canvasCursor = SystemMouseCursors.move;
    } else if (widget.activeTool == 'draw') {
      canvasCursor = SystemMouseCursors.precise;
    } else {
      canvasCursor = MouseCursor.defer;
    }
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
              cursor: canvasCursor,
              onExit: (_) {
                setState(() {
                  _lastPointerLocalPosition = null;
                  _hoverPoint = null;
                  _hoveredCornerIndex = null;
                  _hoveredSegVertex = null;
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
                      onPointerSignal: _handleCanvasPointerSignal,
                      onPointerUp: _handlePointerUp,
                      onPointerCancel: (_) => _cancelDraft(),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CustomPaint(
                            painter: _CanvasGridPainter(_isDarkMode(context)),
                          ),
                          if (widget.image == null)
                            Center(
                              child: Text(
                                widget.unauthorized
                                    ? t('label.unauthorized')
                                    : t('label.openPrompt'),
                              ),
                            )
                          else
                            Center(
                              child: Transform(
                                transform: _contentTransform(),
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
                                          sam3PreviewAnnotations:
                                              widget.sam3PreviewAnnotations,
                                          sam3ClickPrompts:
                                              widget.sam3ClickPrompts,
                                          classes: widget.labelClasses,
                                          selectedAnnotation:
                                              selectedAnnotation,
                                          draftRect: _draftRect,
                                          draftSegPoints: _segDraftPoints,
                                          imageRect: imageRect,
                                          imageOffset: Offset.zero,
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
                                      if (selectedAnnotation != null)
                                        _SelectedAnnotationFilter(
                                          annotation: selectedAnnotation,
                                          imageRect: imageRect,
                                          imageOffset: Offset.zero,
                                        ),
                                      if (selectedAnnotation != null)
                                        CustomPaint(
                                          painter:
                                              _SelectedAnnotationOverlayPainter(
                                                annotation: selectedAnnotation,
                                                classes: widget.labelClasses,
                                                imageRect: imageRect,
                                                imageOffset: Offset.zero,
                                                scale: _scale,
                                                showClassLabels:
                                                    widget.showClassLabels,
                                                darkMode: _isDarkMode(context),
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
                              onRepeat: canPanHorizontally
                                  ? () => _panViewport(
                                      const Offset(1, 0),
                                      visualStep: 8,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            _ViewportPanButton(
                              icon: Icons.keyboard_arrow_right,
                              tooltip: t('viewport.panRight'),
                              onPressed: canPanHorizontally
                                  ? () => _panViewport(const Offset(-1, 0))
                                  : null,
                              onRepeat: canPanHorizontally
                                  ? () => _panViewport(
                                      const Offset(-1, 0),
                                      visualStep: 8,
                                    )
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
                              onRepeat: canPanVertically
                                  ? () => _panViewport(
                                      const Offset(0, 1),
                                      visualStep: 8,
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 8),
                            _ViewportPanButton(
                              icon: Icons.keyboard_arrow_down,
                              tooltip: t('viewport.panDown'),
                              onPressed: canPanVertically
                                  ? () => _panViewport(const Offset(0, -1))
                                  : null,
                              onRepeat: canPanVertically
                                  ? () => _panViewport(
                                      const Offset(0, -1),
                                      visualStep: 8,
                                    )
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

class _AnnotationPainter extends CustomPainter {
  const _AnnotationPainter({
    this.image,
    required this.annotations,
    required this.sam3PreviewAnnotations,
    required this.sam3ClickPrompts,
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
  final List<_AnnotationRegion> sam3PreviewAnnotations;
  final List<_Sam3ClickPromptPoint> sam3ClickPrompts;
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
      _drawOutsideOverlay(
        canvas,
        placedImageRect,
        _annotationDisplayPath(selected, imageRect, imageOffset),
      );
    }

    _drawImageBounds(canvas, placedImageRect);

    for (final annotation in sam3PreviewAnnotations) {
      _drawSam3PreviewAnnotation(canvas, annotation);
    }

    for (final annotation in annotations) {
      final labelClass = _classById(annotation.classId);
      final color = labelClass?.color ?? const Color(0xFF2563EB);
      final selected = annotation.id == selectedAnnotation?.id;
      _drawAnnotation(canvas, annotation, color, selected);
      if (showClassLabels && labelClass != null) {
        final authorColor = annotation.authorColorValue == 0
            ? color
            : Color(annotation.authorColorValue);
        final authorLabel = annotation.authorName.trim().isEmpty
            ? ''
            : ' · ${annotation.authorName}';
        _drawLabel(
          canvas,
          annotation.rect.shift(canvasOrigin),
          '${labelClass.name}$authorLabel',
          authorColor,
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
      final previewEnd = crosshairPoint;
      if (draftMode == _AnnotationMode.seg &&
          previewEnd != null &&
          placedImageRect.contains(previewEnd)) {
        _drawDraftSegPreviewLine(canvas, canvasPoints.last, previewEnd, color);
      }
    }

    final crosshair = crosshairPoint;
    final color = crosshairColor;
    if (crosshair != null &&
        color != null &&
        placedImageRect.contains(crosshair)) {
      _drawCrosshair(canvas, crosshair, color);
    }

    if (sam3ClickPrompts.isNotEmpty) {
      _drawSam3ClickPrompts(canvas, placedImageRect);
    }
  }

  _LabelClass? _classById(int? id) {
    if (id == null) {
      return null;
    }
    return classes.where((item) => item.id == id).firstOrNullValue;
  }

  void _drawOutsideOverlay(Canvas canvas, Rect bounds, Path selectedPath) {
    final selectedBounds = selectedPath.getBounds();
    if (selectedBounds.isEmpty || !selectedBounds.overlaps(bounds)) {
      return;
    }
    final paint = Paint()
      ..color = (darkMode ? Colors.black : Colors.grey).withValues(alpha: 0.42);
    final boundsPath = Path()..addRect(bounds);
    final outsidePath = Path.combine(
      ui.PathOperation.difference,
      boundsPath,
      selectedPath,
    );
    canvas.drawPath(outsidePath, paint);
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
    canvas.drawCircle(point, 2.2 / scale, Paint()..color = color);
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

  void _drawDraftSegPreviewLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color,
  ) {
    final contrast = color.computeLuminance() > 0.5
        ? const Color(0xFF111827)
        : Colors.white;
    final underlay = Paint()
      ..color = contrast.withValues(alpha: 0.50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 / scale;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 / scale;
    _drawDashedLine(canvas, start, end, underlay);
    _drawDashedLine(canvas, start, end, paint);
    canvas.drawCircle(end, 2.2 / scale, Paint()..color = color);
  }

  void _drawSam3PreviewAnnotation(Canvas canvas, _AnnotationRegion annotation) {
    final points = annotation.points.isEmpty
        ? _rectToPoints(annotation.rect)
        : annotation.points;
    if (points.length < 3) {
      return;
    }
    final canvasPoints = points
        .map((point) => point + imageRect.topLeft + imageOffset)
        .toList();
    final path = Path()..addPolygon(canvasPoints, true);
    final fill = Paint()
      ..color = const Color(0xFF06B6D4).withValues(alpha: 0.20)
      ..style = PaintingStyle.fill;
    final underlay = Paint()
      ..color = Colors.white.withValues(alpha: darkMode ? 0.45 : 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2 / scale;
    final stroke = Paint()
      ..color = const Color(0xFF0891B2).withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7 / scale;
    canvas.drawPath(path, fill);
    canvas.drawPath(path, underlay);
    canvas.drawPath(path, stroke);
  }

  void _drawSam3ClickPrompts(Canvas canvas, Rect placedImageRect) {
    for (final point in sam3ClickPrompts) {
      final canvasPoint = Offset(
        placedImageRect.left + point.x * placedImageRect.width,
        placedImageRect.top + point.y * placedImageRect.height,
      );
      if (!placedImageRect.contains(canvasPoint)) {
        continue;
      }
      _drawSam3ClickPrompt(canvas, canvasPoint, point.positive);
    }
  }

  void _drawSam3ClickPrompt(Canvas canvas, Offset center, bool positive) {
    final color = positive ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final symbol = positive ? '+' : '-';
    final haloRadius = (positive ? 9.0 : 13.0) / scale;
    final radius = 7.0 / scale;
    final halo = Paint()
      ..color = color.withValues(alpha: positive ? 0.18 : 0.24)
      ..style = PaintingStyle.fill;
    final fill = Paint()
      ..color = (darkMode ? const Color(0xFF020617) : Colors.white).withValues(
        alpha: 0.86,
      )
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color.withValues(alpha: 0.98)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 / scale;
    canvas.drawCircle(center, haloRadius, halo);
    canvas.drawCircle(center, radius, fill);
    canvas.drawCircle(center, radius, stroke);
    final textPainter = TextPainter(
      text: TextSpan(
        text: symbol,
        style: TextStyle(
          color: color,
          fontSize: 13 / scale,
          height: 1,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
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
        // ---------------------------------------------------------------------------
        // AI Toolbar & Annotation List / AI 工具栏与标注列表
        // ---------------------------------------------------------------------------
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

class _SelectedAnnotationFilter extends StatelessWidget {
  const _SelectedAnnotationFilter({
    required this.annotation,
    required this.imageRect,
    required this.imageOffset,
  });

  final _AnnotationRegion annotation;
  final Rect imageRect;
  final Offset imageOffset;

  @override
  Widget build(BuildContext context) {
    final outsidePath = _annotationOutsideDisplayPath(
      annotation,
      imageRect,
      imageOffset,
    );
    if (outsidePath.getBounds().isEmpty) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: ClipPath(
        clipper: _AnnotationPathClipper(outsidePath),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 2.2, sigmaY: 2.2),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _AnnotationPathClipper extends CustomClipper<Path> {
  const _AnnotationPathClipper(this.path);

  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(covariant _AnnotationPathClipper oldClipper) =>
      oldClipper.path != path;
}

class _SelectedAnnotationOverlayPainter extends CustomPainter {
  const _SelectedAnnotationOverlayPainter({
    required this.annotation,
    required this.classes,
    required this.imageRect,
    required this.imageOffset,
    required this.scale,
    required this.showClassLabels,
    required this.darkMode,
  });

  final _AnnotationRegion annotation;
  final List<_LabelClass> classes;
  final Rect imageRect;
  final Offset imageOffset;
  final double scale;
  final bool showClassLabels;
  final bool darkMode;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _annotationDisplayPath(annotation, imageRect, imageOffset);
    if (path.getBounds().isEmpty) {
      return;
    }
    final color = _classColorById(classes, annotation.classId);
    final outlineUnderlay = Paint()
      ..color = (darkMode ? Colors.white : const Color(0xFF0F172A)).withValues(
        alpha: 0.72,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.4 / scale
      ..strokeJoin = StrokeJoin.round;
    final outline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6 / scale
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(path, outlineUnderlay)
      ..drawPath(path, outline);

    final displayPoints = _annotationDisplayPoints(
      annotation,
      imageRect,
      imageOffset,
    );
    if (annotation.mode == _AnnotationMode.seg) {
      _drawSegOverlayNodes(canvas, displayPoints);
    } else {
      _drawBoxOverlayHandles(canvas, displayPoints);
    }

    final labelClass = classes
        .where((item) => item.id == annotation.classId)
        .firstOrNullValue;
    if (showClassLabels && labelClass != null) {
      final authorLabel = annotation.authorName.trim().isEmpty
          ? ''
          : ' · ${annotation.authorName}';
      final authorColor = annotation.authorColorValue == 0
          ? color
          : Color(annotation.authorColorValue);
      _drawSelectedLabel(
        canvas,
        path.getBounds(),
        '${labelClass.name}$authorLabel',
        authorColor,
      );
    }
  }

  void _drawBoxOverlayHandles(Canvas canvas, List<Offset> points) {
    final fill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = const Color(0xFF334155)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / scale;
    for (final point in points) {
      final handle = Rect.fromCenter(
        center: point,
        width: 8 / scale,
        height: 8 / scale,
      );
      canvas
        ..drawRect(handle, fill)
        ..drawRect(handle, border);
    }
  }

  void _drawSegOverlayNodes(Canvas canvas, List<Offset> points) {
    final fill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = const Color(0xFF334155)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / scale;
    for (final point in points) {
      canvas
        ..drawCircle(point, 4 / scale, fill)
        ..drawCircle(point, 4 / scale, border);
    }
  }

  void _drawSelectedLabel(
    Canvas canvas,
    Rect bounds,
    String label,
    Color color,
  ) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 13 / scale,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 180 / scale);
    final origin = Offset(
      bounds.left,
      (bounds.top - 20 / scale).clamp(0, bounds.top).toDouble(),
    );
    final background = Rect.fromLTWH(
      origin.dx - 4 / scale,
      origin.dy - 2 / scale,
      textPainter.width + 8 / scale,
      textPainter.height + 4 / scale,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(background, Radius.circular(3 / scale)),
      Paint()..color = color.withValues(alpha: 0.95),
    );
    textPainter.paint(canvas, origin);
  }

  @override
  bool shouldRepaint(covariant _SelectedAnnotationOverlayPainter oldDelegate) =>
      oldDelegate.annotation != annotation ||
      oldDelegate.classes != classes ||
      oldDelegate.imageRect != imageRect ||
      oldDelegate.imageOffset != imageOffset ||
      oldDelegate.scale != scale ||
      oldDelegate.showClassLabels != showClassLabels ||
      oldDelegate.darkMode != darkMode;
}

Path _annotationDisplayPath(
  _AnnotationRegion annotation,
  Rect imageRect,
  Offset imageOffset,
) {
  final points = _annotationDisplayPoints(annotation, imageRect, imageOffset);
  if (points.length >= 3) {
    return Path()..addPolygon(points, true);
  }
  return Path();
}

Path _annotationOutsideDisplayPath(
  _AnnotationRegion annotation,
  Rect imageRect,
  Offset imageOffset,
) {
  final imagePath = Path()..addRect(imageRect.shift(imageOffset));
  final selectedPath = _annotationDisplayPath(
    annotation,
    imageRect,
    imageOffset,
  );
  if (selectedPath.getBounds().isEmpty) {
    return imagePath;
  }
  return Path.combine(ui.PathOperation.difference, imagePath, selectedPath);
}

List<Offset> _annotationDisplayPoints(
  _AnnotationRegion annotation,
  Rect imageRect,
  Offset imageOffset,
) {
  final origin = imageRect.topLeft + imageOffset;
  if (annotation.mode == _AnnotationMode.seg) {
    final points = annotation.points.length >= 3
        ? annotation.points
        : _rectToPoints(annotation.rect);
    return [for (final point in points) point + origin];
  }
  if (annotation.mode == _AnnotationMode.obb) {
    return [
      for (final point in _rotatedCorners(
        annotation.rect,
        annotation.rotationDegrees,
      ))
        point + origin,
    ];
  }
  return [for (final point in _rectToPoints(annotation.rect)) point + origin];
}

Color _classColorById(List<_LabelClass> classes, int classId) {
  return classes.where((item) => item.id == classId).firstOrNullValue?.color ??
      const Color(0xFF2563EB);
}
