// =============================================================================
// bottom_controls.dart - Label Page Bottom Bar / 标注页底部控制栏
// =============================================================================
// Zoom slider, zoom lock, reset viewport, dark/light mode toggle, and
// keyboard shortcut settings button.
//
// 缩放滑块、缩放锁定、重置视图、暗色/亮色模式和快捷键设置按钮。
// =============================================================================

import 'package:flutter/material.dart';

import '../../services/i18n.dart';
import '../../theme/dimensions.dart';
import '../../theme/theme_helpers.dart';

/// Bottom annotation controls for zoom, theme, and shortcut settings.
class BottomControls extends StatelessWidget {
  const BottomControls({
    required this.zoom,
    required this.zoomLocked,
    required this.darkMode,
    required this.onZoomChanged,
    required this.onResetView,
    required this.onToggleZoomLock,
    required this.onToggleThemeMode,
    required this.onOpenKeySettings,
  });

  final double zoom;
  final bool zoomLocked;
  final bool darkMode;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onResetView;
  final VoidCallback onToggleZoomLock;
  final VoidCallback onToggleThemeMode;
  final VoidCallback onOpenKeySettings;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final compact = useCompactWorkspaceLayout(context);
    return Container(
      height: bottomBarHeightFor(context),
      decoration: BoxDecoration(
        color: appPanelColor(dark),
        border: Border(top: BorderSide(color: appBorderColor(dark))),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 24,
          vertical: compact ? 10 : 14,
        ),
        children: [
          _SquareIconButton(
            icon: Icons.remove,
            tooltip: t('bottom.zoomOut'),
            onPressed: zoomLocked ? null : () => onZoomChanged(zoom - 10),
          ),
          _ZoomValue(value: '${zoom.round()}%'),
          _SquareIconButton(
            icon: Icons.add,
            tooltip: t('bottom.zoomIn'),
            onPressed: zoomLocked ? null : () => onZoomChanged(zoom + 10),
          ),
          _SquareIconButton(
            icon: zoomLocked ? Icons.link_off : Icons.link,
            tooltip: t('bottom.lockZoom'),
            selected: zoomLocked,
            onPressed: onToggleZoomLock,
          ),
          _ControlButton(
            label: t('bottom.reset'),
            width: 96,
            onPressed: zoomLocked ? null : onResetView,
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
        height: workspaceControlHeightFor(context),
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: SizedBox(
        width: 72,
        height: workspaceControlHeightFor(context),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: appControlColor(dark),
            border: Border.all(color: appBorderColor(dark)),
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
          dimension: workspaceControlHeightFor(context),
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
