import 'package:flutter/material.dart';

import '../../controllers/ai_annotation_controller.dart';
import '../../controllers/ai_workspace_controller.dart';
import '../../controllers/collaboration_controller.dart';
import '../../controllers/project_controller.dart';
import '../../controllers/workspace_settings_controller.dart';
import '../../dialogs/label_class_dialog.dart';
import '../../models/ai_assist.dart';
import '../../services/ai_error_utils.dart';
import '../../services/i18n.dart';
import 'workspace_annotation_actions.dart';

/// Coordinates AI annotation commands, prompts, previews, and feedback.
class WorkspaceAiActions {
  const WorkspaceAiActions({
    required this.ai,
    required this.workspace,
    required this.project,
    required this.collaboration,
    required this.settings,
    required this.annotationActions,
    required this.context,
    required this.mounted,
    required this.panelVisible,
    required this.showPanel,
    required this.showMessage,
  });

  final AiAnnotationController ai;
  final AiWorkspaceController workspace;
  final ProjectController project;
  final CollaborationController collaboration;
  final WorkspaceSettingsController settings;
  final WorkspaceAnnotationActions annotationActions;
  final BuildContext Function() context;
  final bool Function() mounted;
  final bool Function() panelVisible;
  final VoidCallback showPanel;
  final ValueChanged<String> showMessage;

  void saveConfig(AiAssistConfig config) => workspace.saveConfig(config);

  Future<void> annotateCurrent() async {
    final config = await _ensureConfig();
    if (config != null) await annotateCurrentWithConfig(config);
  }

  Future<void> annotateCurrentWithConfig(AiAssistConfig config) async {
    if (project.selectedImage == null) return;
    await _runForIndices([project.selectedImageIndex], config);
  }

  Future<void> annotateAll() async {
    final config = await _ensureConfig();
    if (config != null) await annotateAllWithConfig(config);
  }

  Future<void> annotateAllWithConfig(AiAssistConfig config) async {
    if (project.images.isEmpty) return;
    final start = (config.startIndex - 1).clamp(0, project.images.length - 1);
    final end = (config.endIndex - 1).clamp(0, project.images.length - 1);
    if (start > end) return;
    await _runForIndices([
      for (var index = start; index <= end; index++) index,
    ], config);
  }

  Future<bool> handleClickPrompt(
    Offset imagePoint,
    Size imageDisplaySize,
    bool positive,
  ) async {
    final config = ai.config;
    final image = project.selectedImage;
    if (!panelVisible() ||
        config == null ||
        config.backend != AiAssistBackend.sam3 ||
        config.sam3PromptMode != AiSam3PromptMode.click ||
        image == null ||
        project.selectedImageKey == null ||
        !_selectedImageAuthorized ||
        imageDisplaySize.width <= 0 ||
        imageDisplaySize.height <= 0) {
      return false;
    }
    if (ai.annotating) {
      showMessage(t('ai.annotating'));
      return true;
    }
    final addition = workspace.addClickPrompt(
      imagePath: image.path,
      imagePoint: imagePoint,
      displaySize: imageDisplaySize,
      positive: positive,
    );
    if (addition == null) return false;
    if (workspace.hasPositiveClickPoint(image.path)) {
      await runClickPreview(config);
    } else {
      showMessage(t('ai.sam3ClickRequired'));
    }
    return true;
  }

  Future<void> runClickPreview(AiAssistConfig config) async {
    final image = project.selectedImage;
    if (ai.annotating ||
        image == null ||
        project.selectedImageKey == null ||
        config.backend != AiAssistBackend.sam3 ||
        config.sam3PromptMode != AiSam3PromptMode.click) {
      return;
    }
    final result = await workspace.runClickPreview(
      config: config,
      pythonPath: settings.settings.pythonPath,
      imagePath: image.path,
      classId: project.activeClassId ?? -1,
      displaySizeResolver: project.ensureDisplaySizeForPath,
      beforeRun: () => WidgetsBinding.instance.endOfFrame,
    );
    switch (result.status) {
      case AiSam3PreviewStatus.updated:
      case AiSam3PreviewStatus.invalidConfig:
        return;
      case AiSam3PreviewStatus.busy:
        showMessage(t('ai.annotating'));
      case AiSam3PreviewStatus.pythonNotConfigured:
        showMessage(t('ai.pythonNotConfigured'));
      case AiSam3PreviewStatus.positivePointRequired:
        showMessage(t('ai.sam3ClickRequired'));
      case AiSam3PreviewStatus.failed:
        showMessage('${t('ai.failed')}: ${shortAiError(result.error!)}');
    }
  }

  Future<void> commitClickPreview(AiAssistConfig config) async {
    final image = project.selectedImage;
    if (ai.annotating || image == null || !_selectedImageAuthorized) return;
    if (!workspace.hasPositiveClickPoint(image.path)) {
      showMessage(t('ai.sam3ClickRequired'));
      return;
    }
    var preview = ai.previewFor(image.path);
    if (preview == null) {
      await runClickPreview(config);
      preview = ai.previewFor(image.path);
    }
    if (preview == null) return;
    if (preview.result.masks.isEmpty) {
      showMessage('${t('ai.done')} (0)');
      return;
    }
    final className = await _promptSaveClassName(config);
    if (className == null || className.trim().isEmpty) return;
    final added = workspace.commitClickPreview(
      config: config,
      imagePath: image.path,
      className: className,
      nextClassColorValue: annotationActions.nextClassColorValue,
    );
    showMessage('${t('ai.done')} ($added)');
  }

  Future<void> handleSave(AiAssistConfig config) async {
    if (config.backend == AiAssistBackend.sam3 &&
        config.sam3PromptMode == AiSam3PromptMode.click) {
      await commitClickPreview(config);
    }
  }

  bool get _selectedImageAuthorized => collaboration.isImageIndexAuthorized(
    project.selectedImageIndex,
    project.images.length,
  );

  Future<AiAssistConfig?> _ensureConfig() async {
    final config = ai.config;
    if (config != null) return config;
    showPanel();
    showMessage(t('ai.chooseModelFirst'));
    return null;
  }

  Future<String?> _promptSaveClassName(AiAssistConfig config) {
    final activeId = project.activeClassId;
    final activeClass = activeId == null ? null : project.classById(activeId);
    final firstPrompt = config.sam3PromptText
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .firstOrNull;
    final initialName =
        activeClass?.name ??
        (project.labelClasses.isNotEmpty
            ? project.labelClasses.first.name
            : null) ??
        firstPrompt ??
        'sam3_click';
    return showSam3SaveClassDialog(
      context: context(),
      initialName: initialName,
      labelClasses: project.labelClasses,
    );
  }

  Future<void> _runForIndices(List<int> indices, AiAssistConfig config) async {
    if (ai.annotating || indices.isEmpty) return;
    final planResult = workspace.createPlan(
      indices: indices,
      config: config,
      pythonPath: settings.settings.pythonPath,
      promptImageIndex: project.selectedImageIndex,
    );
    final plan = planResult.plan;
    if (plan == null) {
      _reportPlanFailure(planResult.failure!);
      return;
    }
    if (plan.previewOnly) {
      await runClickPreview(config);
      return;
    }
    String? classNameOverride;
    if (plan.sam3ClickMode) {
      classNameOverride = await _promptSaveClassName(config);
      if (classNameOverride == null || classNameOverride.trim().isEmpty) return;
    }
    final execution = await workspace.runPlan(
      plan: plan,
      displaySizeResolver: project.ensureDisplaySizeForPath,
      nextClassColorValue: annotationActions.nextClassColorValue,
      classNameOverride: classNameOverride,
      beforeRun: () => WidgetsBinding.instance.endOfFrame,
    );
    if (!mounted()) return;
    if (execution.workflowResult case final result?) {
      showMessage('${t('ai.done')} (${result.addedCount})');
    } else if (execution.error case final error?) {
      showMessage('${t('ai.failed')}: ${shortAiError(error)}');
    }
  }

  void _reportPlanFailure(AiAnnotationPlanFailure failure) {
    final key = workspace.reportPlanFailure(failure);
    if (key != null) showMessage(t(key));
  }
}
