import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/ai_annotation_controller.dart';
import '../../controllers/collaboration_controller.dart';
import '../../controllers/project_controller.dart';
import '../../controllers/workspace_navigation_controller.dart';
import '../../controllers/workspace_viewport_controller.dart';
import '../../models/ai_assist.dart';
import '../../models/annotation.dart';
import '../../models/app_status.dart';
import '../../pages/label_page.dart';

/// Commands emitted by the annotation page.
class LabelWorkspaceActions {
  const LabelWorkspaceActions({
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

  final ValueChanged<int> onImageSelected;
  final Future<void> Function(TapDownDetails details, int? index)
  onImageContextMenu;
  final void Function(PointerSignalEvent event) onPointerSignal;
  final ValueChanged<Offset> onViewportOffsetChanged;
  final ValueChanged<String> onToolSelected;
  final VoidCallback onSelectMode;
  final ValueChanged<AnnotationMode> onModeSelected;
  final ValueChanged<String> onImageSplitChanged;
  final Future<int?> Function() onEnsureClass;
  final void Function(Rect rect, int classId) onAnnotationCreated;
  final void Function(List<Offset> points, int classId) onSegAnnotationCreated;
  final ValueChanged<String?> onAnnotationSelected;
  final ValueChanged<AnnotationRegion> onAnnotationUpdated;
  final ValueChanged<String> onAnnotationDeleted;
  final VoidCallback onAnnotationDragStarted;
  final ValueChanged<int> onClassSelected;
  final VoidCallback onClassAdded;
  final ValueChanged<LabelClass> onClassEdited;
  final ValueChanged<LabelClass> onClassColorChanged;
  final ValueChanged<LabelClass> onClassDeleted;
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
}

/// Adapts workspace state and commands to the annotation page contract.
class LabelWorkspacePage extends StatelessWidget {
  const LabelWorkspacePage({
    super.key,
    required this.status,
    required this.aiPanelVisible,
    required this.actions,
  });

  final BridgeStatus status;
  final bool aiPanelVisible;
  final LabelWorkspaceActions actions;

  @override
  Widget build(BuildContext context) {
    final project = context.watch<ProjectController>();
    final collaboration = context.watch<CollaborationController>();
    final navigation = context.watch<WorkspaceNavigationController>();
    final viewport = context.watch<WorkspaceViewportController>();
    final ai = context.watch<AiAnnotationController>();
    final authorized = collaboration.isImageIndexAuthorized(
      project.selectedImageIndex,
      project.images.length,
    );
    final selectedImage = authorized ? project.selectedImage : null;
    final config = ai.config;
    final sam3ClickMode =
        aiPanelVisible &&
        config != null &&
        config.backend == AiAssistBackend.sam3 &&
        config.sam3PromptMode == AiSam3PromptMode.click;
    final imagePath = selectedImage?.path;
    final prompts = sam3ClickMode && imagePath != null
        ? ai.promptsFor(imagePath)
        : const <Sam3ClickPromptPoint>[];
    final preview = sam3ClickMode && imagePath != null
        ? ai.previewFor(imagePath)?.annotations ?? const <AnnotationRegion>[]
        : const <AnnotationRegion>[];

    return LabelPage(
      status: status,
      images: project.images,
      selectedImage: selectedImage,
      selectedImageIndex: project.selectedImageIndex,
      unauthorized: collaboration.clientMode && !authorized,
      zoom: viewport.zoom,
      viewportOffset: viewport.offset,
      activeTool: navigation.activeTool,
      activeMode: navigation.annotationMode,
      imageSplit: project.selectedImageSplit,
      activeClassId: project.activeClassId,
      labelClasses: project.labelClasses,
      annotationsByImage: project.annotationsByImage,
      annotations: authorized ? project.currentAnnotations : const [],
      sam3ClickPrompts: prompts,
      sam3PreviewAnnotations: preview,
      selectedAnnotationId: project.selectedAnnotationId,
      showClassLabels: navigation.showClassLabels,
      aiPanelVisible: aiPanelVisible,
      classesEditable: !collaboration.clientMode,
      onImageSelected: actions.onImageSelected,
      onImageContextMenu: actions.onImageContextMenu,
      onPointerSignal: actions.onPointerSignal,
      onViewportOffsetChanged: actions.onViewportOffsetChanged,
      onToolSelected: actions.onToolSelected,
      onSelectMode: actions.onSelectMode,
      onModeSelected: actions.onModeSelected,
      onImageSplitChanged: actions.onImageSplitChanged,
      onEnsureClass: actions.onEnsureClass,
      onAnnotationCreated: actions.onAnnotationCreated,
      onSegAnnotationCreated: actions.onSegAnnotationCreated,
      onAnnotationSelected: actions.onAnnotationSelected,
      onAnnotationUpdated: actions.onAnnotationUpdated,
      onAnnotationDeleted: actions.onAnnotationDeleted,
      onAnnotationDragStarted: actions.onAnnotationDragStarted,
      onClassSelected: actions.onClassSelected,
      onClassAdded: actions.onClassAdded,
      onClassEdited: actions.onClassEdited,
      onClassColorChanged: actions.onClassColorChanged,
      onClassDeleted: actions.onClassDeleted,
      onClassReordered: actions.onClassReordered,
      onToggleClassLabels: actions.onToggleClassLabels,
      onAnnotationClassChanged: actions.onAnnotationClassChanged,
      onAiConfigPressed: actions.onAiConfigPressed,
      onSam3ClickPrompt: actions.onSam3ClickPrompt,
      onImageDisplaySizeChanged: actions.onImageDisplaySizeChanged,
    );
  }
}
