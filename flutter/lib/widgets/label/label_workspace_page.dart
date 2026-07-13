import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/ai_assist.dart';
import '../../models/annotation.dart';
import '../../models/app_status.dart';
import '../../pages/label_page.dart';

/// Immutable view data required by the annotation page.
class LabelWorkspaceData {
  const LabelWorkspaceData({
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
  });

  final BridgeStatus status;
  final List<ImageItem> images;
  final ImageItem? selectedImage;
  final int selectedImageIndex;
  final bool unauthorized;
  final double zoom;
  final Offset viewportOffset;
  final String activeTool;
  final AnnotationMode activeMode;
  final String imageSplit;
  final int? activeClassId;
  final List<LabelClass> labelClasses;
  final Map<String, List<AnnotationRegion>> annotationsByImage;
  final List<AnnotationRegion> annotations;
  final List<Sam3ClickPromptPoint> sam3ClickPrompts;
  final List<AnnotationRegion> sam3PreviewAnnotations;
  final String? selectedAnnotationId;
  final bool showClassLabels;
  final bool aiPanelVisible;
  final bool classesEditable;
}

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
    required this.data,
    required this.actions,
  });

  final LabelWorkspaceData data;
  final LabelWorkspaceActions actions;

  @override
  Widget build(BuildContext context) {
    return LabelPage(
      status: data.status,
      images: data.images,
      selectedImage: data.selectedImage,
      selectedImageIndex: data.selectedImageIndex,
      unauthorized: data.unauthorized,
      zoom: data.zoom,
      viewportOffset: data.viewportOffset,
      activeTool: data.activeTool,
      activeMode: data.activeMode,
      imageSplit: data.imageSplit,
      activeClassId: data.activeClassId,
      labelClasses: data.labelClasses,
      annotationsByImage: data.annotationsByImage,
      annotations: data.annotations,
      sam3ClickPrompts: data.sam3ClickPrompts,
      sam3PreviewAnnotations: data.sam3PreviewAnnotations,
      selectedAnnotationId: data.selectedAnnotationId,
      showClassLabels: data.showClassLabels,
      aiPanelVisible: data.aiPanelVisible,
      classesEditable: data.classesEditable,
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
