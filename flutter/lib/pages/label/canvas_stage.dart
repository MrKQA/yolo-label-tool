// =============================================================================
// canvas_stage.dart - Annotation Canvas Stage / 标注画布舞台
// =============================================================================
// Central workspace: mode buttons, split selector header, and fixed-size canvas
// container that hosts the image canvas with zoom/pan support.
//
// 工作区核心：模式按钮、split 选择器标题栏和承载画布的固定尺寸容器。
// =============================================================================

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/annotation.dart';
import '../../models/app_status.dart';
import '../../models/imported_dataset.dart';
import '../../services/i18n.dart';
import '../../theme/app_theme.dart';
import '../../theme/dimensions.dart';
import '../../theme/theme_helpers.dart';

class CanvasStage extends StatelessWidget {
  const CanvasStage({
    super.key,
    required this.bridgeStatus,
    required this.imageIndex,
    required this.imageCount,
    required this.activeTool,
    required this.activeMode,
    required this.imageSplit,
    required this.canvas,
    required this.onPointerSignal,
    required this.onModeSelected,
    required this.onImageSplitChanged,
  });

  final BridgeStatus bridgeStatus;
  final int imageIndex;
  final int imageCount;
  final String activeTool;
  final AnnotationMode activeMode;
  final String imageSplit;
  final Widget canvas;
  final void Function(PointerSignalEvent event) onPointerSignal;
  final ValueChanged<AnnotationMode> onModeSelected;
  final ValueChanged<String> onImageSplitChanged;

  @override
  Widget build(BuildContext context) {
    final compact = useCompactWorkspaceLayout(context);
    return Listener(
      onPointerSignal: onPointerSignal,
      child: AnimatedContainer(
        duration: appMotionStandard,
        curve: appMotionCurve,
        color: workspaceColor(context),
        padding: EdgeInsets.all(compact ? 12 : 20),
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
            SizedBox(height: compact ? 10 : 14),
            Expanded(
              child: ClipRect(child: SizedBox.expand(child: canvas)),
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

  final BridgeStatus status;
  final int imageIndex;
  final int imageCount;
  final AnnotationMode activeMode;
  final String activeTool;
  final String imageSplit;
  final ValueChanged<AnnotationMode> onModeSelected;
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
        for (final mode in AnnotationMode.values)
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

  final AnnotationMode mode;
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
            : controlColor(context),
        foregroundColor: selected
            ? colorScheme.onPrimaryContainer
            : primaryTextColor(context),
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

  static const _unselectedColor = Color(0xFFFFFFFF);
  static const _trainColor = Color(0xFF2563EB);
  static const _valColor = Color(0xFF16803A);
  static const _testColor = Color(0xFFE85D04);
  static const _unselectedForeground = Color(0xFF15141A);

  Color _splitColor(String? split) => switch (split) {
    'train' => _trainColor,
    'val' => _valColor,
    'test' => _testColor,
    _ => _unselectedColor,
  };

  @override
  Widget build(BuildContext context) {
    final selected = datasetSplits.contains(value) ? value : null;
    final backgroundColor = _splitColor(selected);
    final foregroundColor = selected == null
        ? _unselectedForeground
        : Colors.white;
    final unselectedLabel = t('label.splitUnselected');
    final unselectedText = Text(
      unselectedLabel,
      style: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(color: _unselectedForeground),
    );
    return SizedBox(
      height: 36,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: borderColor(context)),
          borderRadius: BorderRadius.circular(6),
          color: backgroundColor,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selected,
              hint: unselectedText,
              disabledHint: unselectedText,
              isDense: true,
              dropdownColor: panelColor(context),
              iconEnabledColor: foregroundColor,
              iconDisabledColor: foregroundColor,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: foregroundColor),
              onChanged: enabled
                  ? (value) {
                      if (value != null) {
                        onChanged(value);
                      }
                    }
                  : null,
              items: [
                for (final split in datasetSplits)
                  DropdownMenuItem(
                    value: split,
                    child: Text(
                      split,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: _splitColor(split),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
              selectedItemBuilder: (context) => [
                for (final split in datasetSplits)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      split,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor(context)),
        borderRadius: BorderRadius.circular(6),
        color: panelColor(context),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(label, style: Theme.of(context).textTheme.labelMedium),
      ),
    );
  }
}
