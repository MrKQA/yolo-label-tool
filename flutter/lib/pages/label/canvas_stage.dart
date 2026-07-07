// Canvas stage and header controls for the label page.

part of '../../main.dart';

class _CanvasStage extends StatelessWidget {
  const _CanvasStage({
    required this.bridgeStatus,
    required this.image,
    required this.unauthorized,
    required this.imageIndex,
    required this.imageCount,
    required this.zoom,
    required this.viewportOffset,
    required this.activeTool,
    required this.activeMode,
    required this.imageSplit,
    required this.labelClasses,
    required this.annotations,
    required this.sam3ClickPrompts,
    required this.sam3PreviewAnnotations,
    required this.selectedAnnotationId,
    required this.showClassLabels,
    required this.onPointerSignal,
    required this.onViewportOffsetChanged,
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
    this.onSam3ClickPrompt,
    this.onImageDisplaySizeChanged,
  });

  final _BridgeStatus bridgeStatus;
  final _ImageItem? image;
  final bool unauthorized;
  final int imageIndex;
  final int imageCount;
  final double zoom;
  final Offset viewportOffset;
  final String activeTool;
  final _AnnotationMode activeMode;
  final String imageSplit;
  final List<_LabelClass> labelClasses;
  final List<_AnnotationRegion> annotations;
  final List<_Sam3ClickPromptPoint> sam3ClickPrompts;
  final List<_AnnotationRegion> sam3PreviewAnnotations;
  final String? selectedAnnotationId;
  final bool showClassLabels;
  final void Function(PointerSignalEvent event) onPointerSignal;
  final ValueChanged<Offset> onViewportOffsetChanged;
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
  final Future<bool> Function(
    Offset imagePoint,
    Size imageDisplaySize,
    bool positive,
  )?
  onSam3ClickPrompt;
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final alignment = Alignment(
                      constraints.maxWidth > _annotationWorkspaceWidth
                          ? 0.0
                          : -1.0,
                      constraints.maxHeight > _annotationWorkspaceHeight
                          ? 0.0
                          : -1.0,
                    );
                    return Align(
                      alignment: alignment,
                      child: SizedBox(
                        width: _annotationWorkspaceWidth,
                        height: _annotationWorkspaceHeight,
                        child: _ImageCanvas(
                          image: image,
                          unauthorized: unauthorized,
                          zoom: zoom,
                          viewportOffset: viewportOffset,
                          activeTool: activeTool,
                          activeMode: activeMode,
                          labelClasses: labelClasses,
                          annotations: annotations,
                          sam3ClickPrompts: sam3ClickPrompts,
                          sam3PreviewAnnotations: sam3PreviewAnnotations,
                          selectedAnnotationId: selectedAnnotationId,
                          showClassLabels: showClassLabels,
                          onViewportOffsetChanged: onViewportOffsetChanged,
                          onEnsureClass: onEnsureClass,
                          onSelectMode: onSelectMode,
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
