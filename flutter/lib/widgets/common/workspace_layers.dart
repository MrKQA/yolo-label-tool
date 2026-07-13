import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/ai_assist.dart';
import '../../models/shortcut.dart';
import '../../pages/detect_video_page.dart';
import '../../services/i18n.dart';
import '../../theme/app_theme.dart';
import '../../theme/dimensions.dart';
import '../detect/video_player_widgets.dart';
import '../label/ai_assist_panel.dart';
import 'overlays.dart';

class WorkspaceMainLayout extends StatelessWidget {
  const WorkspaceMainLayout({
    super.key,
    required this.topMenu,
    required this.sidebar,
    required this.pages,
    this.bottomControls,
  });

  final Widget topMenu;
  final Widget sidebar;
  final Widget pages;
  final Widget? bottomControls;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        topMenu,
        Expanded(
          child: Row(
            children: [
              sidebar,
              Expanded(child: pages),
            ],
          ),
        ),
        AnimatedSize(
          duration: appMotionStandard,
          curve: appMotionCurve,
          alignment: Alignment.bottomCenter,
          child: bottomControls ?? const SizedBox.shrink(),
        ),
      ],
    );
  }
}

typedef AiPanelGeometryChanged = void Function(Size size, Offset offset);

class AiAssistPanelLayer extends StatefulWidget {
  const AiAssistPanelLayer({
    super.key,
    required this.requestedSize,
    required this.requestedOffset,
    required this.initialConfig,
    required this.imageCount,
    required this.pythonPath,
    required this.onClose,
    required this.onGeometryChanged,
    required this.onConfigSaved,
    required this.onSave,
    required this.onAnnotateCurrent,
    required this.onAnnotateAll,
  });

  final Size requestedSize;
  final Offset? requestedOffset;
  final AiAssistConfig? initialConfig;
  final int imageCount;
  final String pythonPath;
  final VoidCallback onClose;
  final AiPanelGeometryChanged onGeometryChanged;
  final ValueChanged<AiAssistConfig> onConfigSaved;
  final Future<void> Function(AiAssistConfig config) onSave;
  final Future<void> Function(AiAssistConfig config) onAnnotateCurrent;
  final Future<void> Function(AiAssistConfig config) onAnnotateAll;

  @override
  State<AiAssistPanelLayer> createState() => _AiAssistPanelLayerState();

  static Size clampSize(Size size, Size viewport) {
    final maxWidth = math.min(
      aiAssistPanelMaxWidth,
      math.max(aiAssistPanelMinWidth, viewport.width - aiAssistPanelMargin * 2),
    );
    final maxHeight = math.min(
      aiAssistPanelMaxHeight,
      math.max(
        aiAssistPanelMinHeight,
        viewport.height - aiAssistPanelMargin * 2,
      ),
    );
    return Size(
      size.width.clamp(aiAssistPanelMinWidth, maxWidth).toDouble(),
      size.height.clamp(aiAssistPanelMinHeight, maxHeight).toDouble(),
    );
  }

  static Offset clampOffset(Offset offset, Size viewport, Size panelSize) {
    final maxX = math.max(
      aiAssistPanelMargin,
      viewport.width - panelSize.width - aiAssistPanelMargin,
    );
    final maxY = math.max(
      aiAssistPanelMargin,
      viewport.height - panelSize.height - aiAssistPanelMargin,
    );
    return Offset(
      offset.dx.clamp(aiAssistPanelMargin, maxX).toDouble(),
      offset.dy.clamp(aiAssistPanelMargin, maxY).toDouble(),
    );
  }
}

class _AiAssistPanelLayerState extends State<AiAssistPanelLayer> {
  final ValueNotifier<Offset?> _liveOffset = ValueNotifier<Offset?>(null);
  Size? _liveSize;
  bool _dragging = false;
  bool _resizing = false;

  @override
  void didUpdateWidget(covariant AiAssistPanelLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && oldWidget.requestedOffset != widget.requestedOffset) {
      final committedOffset = widget.requestedOffset;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !_dragging &&
            widget.requestedOffset == committedOffset) {
          _liveOffset.value = null;
        }
      });
    }
    if (!_resizing && oldWidget.requestedSize != widget.requestedSize) {
      _liveSize = null;
    }
  }

  @override
  void dispose() {
    _liveOffset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final panelSize = AiAssistPanelLayer.clampSize(
          _liveSize ?? widget.requestedSize,
          viewport,
        );
        final defaultOffset = Offset(
          math.max(
            aiAssistPanelMargin,
            constraints.maxWidth -
                panelSize.width -
                toolbarWidthFor(context) -
                16,
          ),
          topMenuHeight + 18,
        );
        final panelOffset = AiAssistPanelLayer.clampOffset(
          widget.requestedOffset ?? defaultOffset,
          viewport,
          panelSize,
        );
        final panel = AiAssistFloatingPanel(
          width: panelSize.width,
          height: panelSize.height,
          initialConfig: widget.initialConfig,
          imageCount: widget.imageCount,
          pythonPath: widget.pythonPath,
          onClose: widget.onClose,
          onDragStart: () {
            _dragging = true;
            _liveOffset.value = panelOffset;
          },
          onDrag: (delta) {
            _liveOffset.value = AiAssistPanelLayer.clampOffset(
              (_liveOffset.value ?? panelOffset) + delta,
              viewport,
              panelSize,
            );
          },
          onDragEnd: () {
            if (!_dragging) return;
            _dragging = false;
            widget.onGeometryChanged(
              panelSize,
              _liveOffset.value ?? panelOffset,
            );
          },
          onResizeStart: () {
            _resizing = true;
            _liveSize = panelSize;
            _liveOffset.value ??= panelOffset;
          },
          onResize: (delta) {
            setState(() {
              final currentSize = _liveSize ?? panelSize;
              _liveSize = AiAssistPanelLayer.clampSize(
                Size(
                  currentSize.width + delta.dx,
                  currentSize.height + delta.dy,
                ),
                viewport,
              );
              _liveOffset.value = AiAssistPanelLayer.clampOffset(
                _liveOffset.value ?? panelOffset,
                viewport,
                _liveSize!,
              );
            });
          },
          onResizeEnd: () {
            if (!_resizing) return;
            _resizing = false;
            widget.onGeometryChanged(
              _liveSize ?? panelSize,
              _liveOffset.value ?? panelOffset,
            );
          },
          onConfigSaved: widget.onConfigSaved,
          onSave: widget.onSave,
          onAnnotateCurrent: widget.onAnnotateCurrent,
          onAnnotateAll: widget.onAnnotateAll,
        );
        return Stack(
          children: [
            ValueListenableBuilder<Offset?>(
              valueListenable: _liveOffset,
              child: panel,
              builder: (context, liveOffset, child) {
                final offset = AiAssistPanelLayer.clampOffset(
                  liveOffset ?? panelOffset,
                  viewport,
                  panelSize,
                );
                return Positioned(
                  left: offset.dx,
                  top: offset.dy,
                  child: child!,
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class WorkspaceStatusLayers extends StatelessWidget {
  const WorkspaceStatusLayers({
    super.key,
    required this.importingDataset,
    required this.aiAnnotating,
    required this.collaborationReconnecting,
    required this.reconnectAttempts,
    required this.onCancelReconnect,
    required this.videoFullscreenVisible,
    required this.videoSession,
    required this.shortcutConfig,
  });

  final bool importingDataset;
  final bool aiAnnotating;
  final bool collaborationReconnecting;
  final int reconnectAttempts;
  final VoidCallback onCancelReconnect;
  final bool videoFullscreenVisible;
  final DetectVideoSession videoSession;
  final ShortcutConfig shortcutConfig;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (importingDataset) const ImportBlockingOverlay(),
        if (aiAnnotating) ImportBlockingOverlay(message: t('ai.annotating')),
        if (collaborationReconnecting)
          CollaborationReconnectOverlay(
            attempts: reconnectAttempts,
            onCancel: onCancelReconnect,
          ),
        if (videoFullscreenVisible)
          VideoFullscreenOverlay(
            session: videoSession,
            shortcutConfig: shortcutConfig,
          ),
      ],
    );
  }
}
