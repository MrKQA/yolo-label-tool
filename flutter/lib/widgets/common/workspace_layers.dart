import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/ai_assist.dart';
import '../../models/shortcut.dart';
import '../../pages/detect_video_page.dart';
import '../../services/i18n.dart';
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
        if (bottomControls != null) bottomControls!,
      ],
    );
  }
}

typedef AiPanelGeometryChanged = void Function(Size size, Offset offset);

class AiAssistPanelLayer extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final panelSize = clampSize(requestedSize, viewport);
        final defaultOffset = Offset(
          math.max(
            aiAssistPanelMargin,
            constraints.maxWidth - panelSize.width - toolbarWidth - 16,
          ),
          topMenuHeight + 18,
        );
        final panelOffset = clampOffset(
          requestedOffset ?? defaultOffset,
          viewport,
          panelSize,
        );
        return Stack(
          children: [
            Positioned(
              left: panelOffset.dx,
              top: panelOffset.dy,
              child: AiAssistFloatingPanel(
                width: panelSize.width,
                height: panelSize.height,
                initialConfig: initialConfig,
                imageCount: imageCount,
                pythonPath: pythonPath,
                onClose: onClose,
                onDrag: (delta) => onGeometryChanged(
                  panelSize,
                  clampOffset(panelOffset + delta, viewport, panelSize),
                ),
                onResize: (delta) {
                  final nextSize = clampSize(
                    Size(
                      panelSize.width + delta.dx,
                      panelSize.height + delta.dy,
                    ),
                    viewport,
                  );
                  onGeometryChanged(
                    nextSize,
                    clampOffset(panelOffset, viewport, nextSize),
                  );
                },
                onConfigSaved: onConfigSaved,
                onSave: onSave,
                onAnnotateCurrent: onAnnotateCurrent,
                onAnnotateAll: onAnnotateAll,
              ),
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
