import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../controllers/ai_annotation_controller.dart';
import '../../controllers/collaboration_controller.dart';
import '../../controllers/project_controller.dart';
import '../../controllers/workspace_navigation_controller.dart';
import '../../controllers/workspace_settings_controller.dart';
import '../../controllers/workspace_viewport_controller.dart';
import '../../models/app_status.dart';
import '../../pages/detect_video_page.dart';
import '../../pages/label/bottom_controls.dart';
import '../../pages/train_page.dart';
import '../../services/app_runtime.dart';
import '../label/label_workspace_page.dart';
import 'navigation.dart';
import 'workspace_ai_actions.dart';
import 'workspace_annotation_actions.dart';
import 'workspace_collaboration_actions.dart';
import 'workspace_composition.dart';
import 'workspace_export_actions.dart';
import 'workspace_layers.dart';
import 'workspace_project_actions.dart';
import 'workspace_settings_actions.dart';

typedef AiPanelGeometryCallback = void Function(Size size, Offset offset);

/// Renders the workspace from provider-backed state and action coordinators.
class WorkspaceShellContent extends StatelessWidget {
  const WorkspaceShellContent({
    super.key,
    required this.status,
    required this.keyboardFocusNode,
    required this.onKeyEvent,
    required this.trainPageKey,
    required this.detectVideoSession,
    required this.topMenuVisible,
    required this.aiPanelVisible,
    required this.aiAssistPanelSize,
    required this.aiAssistPanelOffset,
    required this.onLanguageSelected,
    required this.onShowTrainingHistory,
    required this.onPointerEnter,
    required this.onPointerExit,
    required this.onPointerSignal,
    required this.onAiPanelVisibilityChanged,
    required this.onAiPanelGeometryChanged,
  });

  final BridgeStatus status;
  final FocusNode keyboardFocusNode;
  final FocusOnKeyEventCallback onKeyEvent;
  final GlobalKey<TrainPageState> trainPageKey;
  final DetectVideoSession detectVideoSession;
  final bool topMenuVisible;
  final bool aiPanelVisible;
  final Size aiAssistPanelSize;
  final Offset? aiAssistPanelOffset;
  final Future<void> Function(String code) onLanguageSelected;
  final VoidCallback onShowTrainingHistory;
  final VoidCallback onPointerEnter;
  final VoidCallback onPointerExit;
  final void Function(PointerSignalEvent event) onPointerSignal;
  final ValueChanged<bool> onAiPanelVisibilityChanged;
  final AiPanelGeometryCallback onAiPanelGeometryChanged;

  @override
  Widget build(BuildContext context) {
    final project = context.watch<ProjectController>();
    final settings = context.watch<WorkspaceSettingsController>();
    final navigation = context.watch<WorkspaceNavigationController>();
    final viewport = context.watch<WorkspaceViewportController>();
    final ai = context.watch<AiAnnotationController>();
    final collaboration = context.watch<CollaborationController>();
    final projectActions = context.read<WorkspaceProjectActions>();
    final annotationActions = context.read<WorkspaceAnnotationActions>();
    final collaborationActions = context.read<WorkspaceCollaborationActions>();
    final exportActions = context.read<WorkspaceExportActions>();
    final settingsActions = context.read<WorkspaceSettingsActions>();
    final aiActions = context.read<WorkspaceAiActions>();
    final labelPage = navigation.activeSection == 'label';

    return Focus(
      focusNode: keyboardFocusNode,
      autofocus: true,
      onKeyEvent: onKeyEvent,
      child: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            WorkspaceMainLayout(
              topMenu: WorkspaceTopMenu(
                data: WorkspaceTopMenuData(
                  visible: topMenuVisible,
                  recentFolders: project.recentFolders
                      .map((entry) => entry.path)
                      .toList(),
                  recentFiles: project.recentFiles
                      .map((entry) => entry.path)
                      .toList(),
                  languageOptions: settings.languageOptions,
                  activeLanguageCode: settings.activeLanguageCode,
                  projectActionsLocked: collaboration.projectLocked,
                ),
                actions: WorkspaceTopMenuActions(
                  onOpenFile: () => projectActions.openImageFile(),
                  onOpenFolder: () => projectActions.openImageFolder(),
                  onOpenRecentFolder: (path) =>
                      unawaited(projectActions.openRecentFolder(path)),
                  onOpenRecentFile: (path) =>
                      unawaited(projectActions.openRecentFile(path)),
                  onClearRecent: settingsActions.clearRecentItems,
                  onExit: () => SystemNavigator.pop(),
                  onImportDataset: projectActions.importYoloDataset,
                  onExportDataset: exportActions.showExportDialog,
                  onShowTrainingHistory: onShowTrainingHistory,
                  onUndo: annotationActions.undo,
                  onRedo: annotationActions.redo,
                  onCopy: annotationActions.copySelected,
                  onPaste: annotationActions.paste,
                  onShowSettings: settingsActions.showSettings,
                  onShowLogs: settingsActions.showLogs,
                  onShowHelp: settingsActions.showShortcutSettings,
                  onShowAbout: settingsActions.showAbout,
                  onProjectActionBlocked:
                      projectActions.guardProjectChangeBlocked,
                  onLanguageSelected: onLanguageSelected,
                  onPointerEnter: onPointerEnter,
                  onPointerExit: onPointerExit,
                ),
              ),
              sidebar: PrimarySidebar(
                activeSection: navigation.activeSection,
                collapsed: navigation.sidebarCollapsed,
                onCollapseChanged: (value) =>
                    navigation.sidebarCollapsed = value,
                onSectionSelected: (section) {
                  logApp('NAV', 'Switched to: $section');
                  navigation.activeSection = section;
                },
              ),
              pages: WorkspacePageStack(
                labelPage: LabelWorkspacePage(
                  status: status,
                  aiPanelVisible: aiPanelVisible,
                  actions: LabelWorkspaceActions(
                    onImageSelected: projectActions.selectImage,
                    onImageContextMenu: projectActions.showImageContextMenu,
                    onPointerSignal: onPointerSignal,
                    onViewportOffsetChanged: viewport.setOffset,
                    onToolSelected: annotationActions.selectTool,
                    onSelectMode: () => annotationActions.selectTool('select'),
                    onModeSelected: annotationActions.activateMode,
                    onImageSplitChanged: projectActions.setSelectedImageSplit,
                    onEnsureClass: annotationActions.ensureActiveClass,
                    onAnnotationCreated: annotationActions.createAnnotation,
                    onSegAnnotationCreated:
                        annotationActions.createSegAnnotation,
                    onAnnotationSelected: annotationActions.selectAnnotation,
                    onAnnotationUpdated: annotationActions.updateAnnotation,
                    onAnnotationDeleted: annotationActions.deleteAnnotation,
                    onAnnotationDragStarted: annotationActions.pushSnapshot,
                    onClassSelected: annotationActions.selectLabelClass,
                    onClassAdded: () => annotationActions.addLabelClass(),
                    onClassEdited: annotationActions.editLabelClass,
                    onClassColorChanged:
                        annotationActions.chooseLabelClassColor,
                    onClassDeleted: annotationActions.deleteLabelClass,
                    onClassReordered: annotationActions.reorderLabelClass,
                    onToggleClassLabels: () => navigation.showClassLabels =
                        !navigation.showClassLabels,
                    onAnnotationClassChanged:
                        annotationActions.changeAnnotationClass,
                    onSam3ClickPrompt: aiActions.handleClickPrompt,
                    onAiConfigPressed: () =>
                        onAiPanelVisibilityChanged(!aiPanelVisible),
                    onImageDisplaySizeChanged:
                        projectActions.updateSelectedImageDisplaySize,
                  ),
                ),
                trainPageKey: trainPageKey,
                detectVideoSession: detectVideoSession,
                collaborationActions: CollaborationPageActions(
                  onUserNameChanged: collaborationActions.updateUserName,
                  onPortChanged: collaborationActions.updatePort,
                  onHostSelected: collaboration.selectHost,
                  onStartHost: collaborationActions.startHost,
                  onJoinClient: collaborationActions.joinSelectedHost,
                  onStop: collaborationActions.stop,
                  onPeerPermissionsChanged:
                      collaborationActions.updatePeerPermissions,
                ),
              ),
              bottomControls: labelPage
                  ? BottomControls(
                      zoom: viewport.zoom,
                      zoomLocked: viewport.zoomLocked,
                      darkMode: settings.darkMode,
                      onZoomChanged: viewport.setZoom,
                      onResetView: viewport.reset,
                      onToggleZoomLock: viewport.toggleZoomLock,
                      onToggleThemeMode: settingsActions.toggleTheme,
                      onOpenKeySettings: settingsActions.showShortcutSettings,
                    )
                  : null,
            ),
            if (labelPage && aiPanelVisible)
              Positioned.fill(
                child: AiAssistPanelLayer(
                  requestedSize: aiAssistPanelSize,
                  requestedOffset: aiAssistPanelOffset,
                  initialConfig: ai.config,
                  imageCount: project.images.length,
                  pythonPath: settings.settings.pythonPath,
                  onClose: () => onAiPanelVisibilityChanged(false),
                  onGeometryChanged: onAiPanelGeometryChanged,
                  onConfigSaved: aiActions.saveConfig,
                  onSave: aiActions.handleSave,
                  onAnnotateCurrent: aiActions.annotateCurrentWithConfig,
                  onAnnotateAll: aiActions.annotateAllWithConfig,
                ),
              ),
            Positioned.fill(
              child: WorkspaceStatusLayers(
                importingDataset: projectActions.importingDataset,
                aiAnnotating: ai.annotating,
                collaborationReconnecting: collaboration.reconnecting,
                reconnectAttempts: collaboration.reconnectAttempts,
                onCancelReconnect: collaborationActions.cancelReconnect,
                videoFullscreenVisible:
                    detectVideoSession.fullscreen &&
                    detectVideoSession.hasInitializedVideo,
                videoSession: detectVideoSession,
                shortcutConfig: settings.shortcuts,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
