// ignore_for_file: file_names

part of 'main.dart';

/// 标注页面入口，组合图片列表、画布和 AI 工具栏。
/// Label page entry that combines the image list, canvas, and AI toolbar.
class _LabelPage extends StatelessWidget {
  const _LabelPage({
    required this.status,
    required this.images,
    required this.selectedImage,
    required this.selectedImageIndex,
    required this.zoom,
    required this.activeTool,
    required this.onImageSelected,
    required this.onImageContextMenu,
    required this.onPointerSignal,
    required this.onToolSelected,
  });

  final _BridgeStatus status;
  final List<_ImageItem> images;
  final _ImageItem? selectedImage;
  final int selectedImageIndex;
  final double zoom;
  final String activeTool;
  final ValueChanged<int> onImageSelected;
  final Future<void> Function(TapDownDetails details, int? index)
  onImageContextMenu;
  final void Function(PointerSignalEvent event) onPointerSignal;
  final ValueChanged<String> onToolSelected;

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
              onPointerSignal: onPointerSignal,
            ),
          ),
          _AiToolbar(activeTool: activeTool, onToolSelected: onToolSelected),
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
/// Central annotation workspace stage that hosts the status header and fixed-size canvas.
class _CanvasStage extends StatelessWidget {
  const _CanvasStage({
    required this.bridgeStatus,
    required this.image,
    required this.imageIndex,
    required this.imageCount,
    required this.zoom,
    required this.onPointerSignal,
  });

  final _BridgeStatus bridgeStatus;
  final _ImageItem? image;
  final int imageIndex;
  final int imageCount;
  final double zoom;
  final void Function(PointerSignalEvent event) onPointerSignal;

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
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ClipRect(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: _annotationWorkspaceWidth,
                    height: _annotationWorkspaceHeight,
                    child: _ImageCanvas(image: image, zoom: zoom),
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

/// 标注状态栏，显示当前图片序号和可用标注模式。
/// Annotation status header showing image position and available modes.
class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({
    required this.status,
    required this.imageIndex,
    required this.imageCount,
  });

  final _BridgeStatus status;
  final int imageIndex;
  final int imageCount;

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
        for (final mode in status.modes) _StatusPill(label: mode.toUpperCase()),
      ],
    );
  }
}

/// 小型状态标签，用于展示图片数量和 HBB/OBB/SEG 模式。
/// Compact status pill for image counts and HBB/OBB/SEG modes.
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

/// 固定尺寸图片显示区，图片按比例自动缩放到完整可见。
/// Fixed-size image display area that scales the image proportionally so it is fully visible.
class _ImageCanvas extends StatelessWidget {
  const _ImageCanvas({required this.image, required this.zoom});

  final _ImageItem? image;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
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
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _CanvasGridPainter(_isDarkMode(context))),
            Center(
              child: image == null
                  ? Text(t('label.openPrompt'))
                  : Transform.scale(
                      scale: zoom / 100,
                      child: _SelectedImageView(image: image!),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 选中图片视图，使用 contain 适配固定显示区。
/// Selected-image view that uses contain fitting inside the fixed display area.
class _SelectedImageView extends StatelessWidget {
  const _SelectedImageView({required this.image});

  final _ImageItem image;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _annotationWorkspaceWidth,
      height: _annotationWorkspaceHeight,
      child: Image.file(
        File(image.path),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => SizedBox(
          width: 420,
          height: 280,
          child: ColoredBox(
            color: const Color(0xFF94A3B8),
            child: Center(
              child: Text(
                t('label.imageError'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 右侧 AI/标注工具栏，后续可接入 ONNX/SAM 辅助标注。
/// Right-side AI/annotation toolbar prepared for ONNX/SAM-assisted labeling.
class _AiToolbar extends StatelessWidget {
  const _AiToolbar({required this.activeTool, required this.onToolSelected});

  final String activeTool;
  final ValueChanged<String> onToolSelected;

  static const _tools = [
    _ToolSpec('move', Icons.pan_tool_alt_outlined, 'tool.move'),
    _ToolSpec('box', Icons.crop_square, 'tool.box'),
    _ToolSpec('crop', Icons.crop, 'tool.crop'),
    _ToolSpec('brush', Icons.brush_outlined, 'tool.brush'),
    _ToolSpec('rotate', Icons.rotate_right, 'tool.rotate'),
    _ToolSpec('effect', Icons.auto_fix_high_outlined, 'tool.effect'),
    _ToolSpec('beautify', Icons.auto_awesome, 'tool.beautify'),
    _ToolSpec('align', Icons.grid_view_outlined, 'tool.align'),
    _ToolSpec('decorate', Icons.star_outline, 'tool.decorate'),
    _ToolSpec('text', Icons.chat_bubble_outline, 'tool.text'),
    _ToolSpec('undo', Icons.undo, 'tool.undo'),
    _ToolSpec('redo', Icons.redo, 'tool.redo'),
    _ToolSpec('delete', Icons.block, 'tool.delete'),
  ];

  @override
  Widget build(BuildContext context) {
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
                Text(
                  t('label.ai'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
              itemCount: _tools.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final tool = _tools[index];
                return _ToolButton(
                  tool: tool,
                  selected: tool.id == activeTool,
                  onPressed: () => onToolSelected(tool.id),
                );
              },
            ),
          ),
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

/// 底部标注控制栏，包含缩放、主题和快捷键入口。
/// Bottom annotation controls for zoom, theme, and shortcut settings.
class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.zoom,
    required this.darkMode,
    required this.onZoomChanged,
    required this.onToggleThemeMode,
    required this.onOpenKeySettings,
  });

  final double zoom;
  final bool darkMode;
  final ValueChanged<double> onZoomChanged;
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
            onPressed: () => onZoomChanged(zoom - 10),
          ),
          _ZoomValue(value: '${zoom.round()}%'),
          _SquareIconButton(
            icon: Icons.link,
            tooltip: t('bottom.lockZoom'),
            onPressed: () {},
          ),
          _SquareIconButton(
            icon: Icons.add,
            tooltip: t('bottom.zoomIn'),
            onPressed: () => onZoomChanged(zoom + 10),
          ),
          _ControlButton(
            label: t('bottom.reset'),
            width: 96,
            onPressed: () => onZoomChanged(100),
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
  final VoidCallback onPressed;

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
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

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
