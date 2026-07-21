import 'package:flutter/material.dart';

import '../../controllers/annotation_database_controller.dart';
import '../../controllers/annotation_editing_controller.dart';
import '../../controllers/project_controller.dart';
import '../../controllers/workspace_navigation_controller.dart';
import '../../dialogs/color_picker_dialog.dart';
import '../../dialogs/label_class_dialog.dart';
import '../../models/annotation.dart';
import '../../services/app_runtime.dart';
import '../../services/i18n.dart';
import '../../services/logger.dart';
import '../../theme/colors.dart';

/// Coordinates annotation commands that need both controllers and dialogs.
class WorkspaceAnnotationActions {
  const WorkspaceAnnotationActions({
    required this.project,
    required this.editing,
    required this.database,
    required this.navigation,
    required this.context,
    required this.projectChangeBlocked,
    required this.showMessage,
    required this.showModeIncompatibleMessage,
    required this.showExport,
    required this.showClearItems,
  });

  final ProjectController project;
  final AnnotationEditingController editing;
  final AnnotationDatabaseController database;
  final WorkspaceNavigationController navigation;
  final BuildContext Function() context;
  final bool Function() projectChangeBlocked;
  final ValueChanged<String> showMessage;
  final ValueChanged<String> showModeIncompatibleMessage;
  final VoidCallback showExport;
  final VoidCallback showClearItems;

  void pushSnapshot() => project.pushAnnotationSnapshot();

  int nextClassColorValue() {
    return labelColorPalette[project.labelClasses.length %
            labelColorPalette.length]
        .toARGB32();
  }

  void undo() {
    if (project.undoAnnotations()) database.scheduleSave();
  }

  void redo() {
    if (project.redoAnnotations()) database.scheduleSave();
  }

  void activateMode(AnnotationMode mode) {
    if (!_guardAnnotationMode(mode)) return;
    navigation.activateAnnotationMode(mode);
    project.selectAnnotation(null);
  }

  bool _guardAnnotationMode(AnnotationMode requestedMode) {
    final establishedMode = project.projectAnnotationMode;
    if (establishedMode == null || establishedMode == requestedMode) {
      return true;
    }
    navigation.activateAnnotationMode(establishedMode);
    project.selectAnnotation(null);
    showModeIncompatibleMessage(
      '${t('label.annotationModeIncompatible')} ${establishedMode.label}',
    );
    logApp(
      'ANNOTATION',
      'Rejected incompatible annotation mode: requested=${requestedMode.name}, project=${establishedMode.name}',
      level: AppLogLevel.warning,
    );
    return false;
  }

  void selectTool(String tool) {
    switch (tool) {
      case 'undo':
        undo();
        return;
      case 'redo':
        redo();
        return;
      case 'copy':
        copySelected();
        return;
      case 'paste':
        paste();
        return;
      case 'delete':
        deleteSelected();
        return;
      case 'export':
        showExport();
        return;
      case 'clear':
        showClearItems();
        return;
      default:
        navigation.activeTool = tool;
    }
  }

  Future<int?> ensureActiveClass() async {
    final activeId = project.activeClassId;
    if (activeId != null && project.classById(activeId) != null) {
      return activeId;
    }
    if (project.labelClasses.isNotEmpty) {
      final firstId = project.labelClasses.first.id;
      project.selectLabelClass(firstId);
      return firstId;
    }
    return addLabelClass();
  }

  Future<int?> addLabelClass() async {
    if (projectChangeBlocked()) return null;
    final name = await showLabelClassNameDialog(
      context: context(),
      initialName: 'class_${project.labelClasses.length}',
      title: t('label.createClassPrompt'),
    );
    if (name == null || name.trim().isEmpty) return null;
    return editing.addLabelClass(
      name: name.trim(),
      colorValue: nextClassColorValue(),
    );
  }

  Future<void> editLabelClass(LabelClass labelClass) async {
    if (projectChangeBlocked()) return;
    final name = await showLabelClassNameDialog(
      context: context(),
      initialName: labelClass.name,
      title: t('label.editClass'),
    );
    if (name == null || name.trim().isEmpty) return;
    editing.updateLabelClass(
      labelClass.copyWith(name: name.trim()),
      reason: 'class renamed',
    );
  }

  Future<void> chooseLabelClassColor(LabelClass labelClass) async {
    if (projectChangeBlocked()) return;
    final currentColor = labelClass.color;
    final selected = await showWheelColorDialog(
      context: context(),
      initialColor: currentColor,
      title: t('label.classColor'),
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
    );
    if (selected == null || selected.toARGB32() == currentColor.toARGB32()) {
      return;
    }
    editing.updateLabelClass(
      labelClass.copyWith(colorValue: selected.toARGB32()),
      reason: 'class color changed',
    );
  }

  void deleteLabelClass(LabelClass labelClass) {
    if (!projectChangeBlocked()) editing.deleteLabelClass(labelClass.id);
  }

  void reorderLabelClass(int oldIndex, int newIndex) {
    if (!projectChangeBlocked()) {
      editing.reorderLabelClass(oldIndex, newIndex);
    }
  }

  void selectLabelClass(int id) => project.selectLabelClass(id);

  void createAnnotation(Rect rect, int classId) {
    if (!_guardAnnotationMode(navigation.annotationMode)) return;
    final annotation = editing.createRect(
      rect: rect,
      classId: classId,
      mode: navigation.annotationMode,
    );
    if (annotation == null) return;
    navigation.activeTool = 'draw';
    logApp(
      'ANNOTATION',
      'Created ${annotation.mode.name}: image=${project.selectedImage?.name ?? '-'}, classId=$classId',
      level: AppLogLevel.debug,
    );
  }

  void createSegAnnotation(List<Offset> points, int classId) {
    if (!_guardAnnotationMode(AnnotationMode.seg)) return;
    final annotation = editing.createSeg(points: points, classId: classId);
    if (annotation == null) return;
    navigation.activeTool = 'draw';
    logApp(
      'ANNOTATION',
      'Created seg: image=${project.selectedImage?.name ?? '-'}, classId=$classId, points=${points.length}',
      level: AppLogLevel.debug,
    );
  }

  void selectAnnotation(String? id) => editing.selectAnnotation(id);

  void updateAnnotation(AnnotationRegion annotation) {
    editing.updateAnnotation(annotation);
  }

  void changeAnnotationClass(String annotationId, int classId) {
    _showPermissionError(editing.changeAnnotationClass(annotationId, classId));
  }

  void deleteAnnotation(String id) {
    _showPermissionError(editing.deleteAnnotation(id));
  }

  void deleteSelected() {
    final id = project.selectedAnnotationId;
    if (id != null) deleteAnnotation(id);
  }

  void copySelected() {
    if (project.selectedAnnotationId == null) return;
    if (editing.copySelectedAnnotation() != null) {
      showMessage(t('feedback.copiedAnnotation'));
    }
  }

  void paste() => editing.pasteAnnotation();

  void rotateSelected(double deltaDegrees) {
    _showPermissionError(
      editing.rotateSelectedAnnotation(
        deltaDegrees,
        imageSize: project.imageDisplaySize,
      ),
    );
  }

  void _showPermissionError(AnnotationEditResult result) {
    if (result == AnnotationEditResult.permissionDenied) {
      showMessage(t('collab.permissionDenied'));
    }
  }
}
