import 'dart:io';
import 'dart:ui';

import '../models/ai_assist.dart';
import '../models/annotation.dart';
import '../models/detection.dart';
import '../services/ai_annotation_result_mapper.dart';
import '../services/ai_error_utils.dart';
import '../services/app_runtime.dart';
import '../services/config_store.dart';
import '../services/logger.dart';
import '../services/path_utils.dart';
import 'ai_annotation_controller.dart';
import 'annotation_database_controller.dart';
import 'collaboration_controller.dart';
import 'collaboration_sync_controller.dart';
import 'project_controller.dart';

typedef AiDisplaySizeResolver = Future<Size> Function(String imagePath);
typedef AiClassColorFactory = int Function();

class AiAnnotationWorkflowResult {
  const AiAnnotationWorkflowResult({
    required this.targetCount,
    required this.addedCount,
    required this.classesChanged,
  });

  final int targetCount;
  final int addedCount;
  final bool classesChanged;
}

enum AiAnnotationPlanFailure {
  pythonNotConfigured,
  noSelectedClasses,
  sam3TextPromptRequired,
  noValidTargets,
  sam3PromptOutsideTargets,
  sam3PositivePointRequired,
}

class AiAnnotationPlan {
  const AiAnnotationPlan({
    required this.config,
    required this.pythonPath,
    required this.targetIndices,
    required this.sam3ClickMode,
    required this.clickPointsText,
    required this.promptFrameIndex,
    required this.previewOnly,
  });

  final AiAssistConfig config;
  final String pythonPath;
  final List<int> targetIndices;
  final bool sam3ClickMode;
  final String clickPointsText;
  final int promptFrameIndex;
  final bool previewOnly;
}

class AiAnnotationPlanResult {
  const AiAnnotationPlanResult.ready(AiAnnotationPlan this.plan)
    : failure = null;

  const AiAnnotationPlanResult.blocked(AiAnnotationPlanFailure this.failure)
    : plan = null;

  final AiAnnotationPlan? plan;
  final AiAnnotationPlanFailure? failure;
}

enum AiSam3PreviewStatus {
  updated,
  busy,
  invalidConfig,
  pythonNotConfigured,
  positivePointRequired,
  failed,
}

class AiSam3PreviewResult {
  const AiSam3PreviewResult(this.status, {this.error});

  final AiSam3PreviewStatus status;
  final Object? error;
}

class AiClickPromptAddition {
  const AiClickPromptAddition({required this.point, required this.count});

  final Sam3ClickPromptPoint point;
  final int count;
}

class AiWorkspaceExecutionResult {
  const AiWorkspaceExecutionResult.completed(this.workflowResult)
    : error = null;

  const AiWorkspaceExecutionResult.failed(this.error) : workflowResult = null;

  final AiAnnotationWorkflowResult? workflowResult;
  final Object? error;

  bool get succeeded => workflowResult != null;
}

/// Coordinates AI workflow side effects without depending on widget context.
class AiWorkspaceController {
  AiWorkspaceController({
    required this.runtime,
    required this.project,
    required this.collaboration,
    required this.collaborationSync,
    required this.annotationDatabase,
  });

  final AiAnnotationController runtime;
  final ProjectController project;
  final CollaborationController collaboration;
  final CollaborationSyncController collaborationSync;
  final AnnotationDatabaseController annotationDatabase;

  void saveConfig(AiAssistConfig config) {
    runtime.updateConfig(config);
    if (config.backend == AiAssistBackend.sam3) {
      ConfigStore.saveLastSam3ModelPath(config.modelPath);
    }
    final sam3Detail = config.backend == AiAssistBackend.sam3
        ? ', sam3Mode=${config.sam3OutputMode.wireName}, prompt=${config.sam3PromptMode.wireName}, ${config.sam3Runtime.logSummary}'
        : '';
    logApp(
      'AI',
      'AI assist config saved: backend=${config.backend.wireName}, model=${fileName(config.modelPath)}, classes=${config.selectedClassIds.length}, conf=${config.confThreshold.toStringAsFixed(2)}, imgsz=${config.imageSize}, range=${config.startIndex}-${config.endIndex}$sam3Detail',
    );
  }

  AiClickPromptAddition? addClickPrompt({
    required String imagePath,
    required Offset imagePoint,
    required Size displaySize,
    required bool positive,
  }) {
    if (displaySize.width <= 0 || displaySize.height <= 0) {
      return null;
    }
    final point = Sam3ClickPromptPoint(
      x: (imagePoint.dx / displaySize.width).clamp(0.0, 1.0).toDouble(),
      y: (imagePoint.dy / displaySize.height).clamp(0.0, 1.0).toDouble(),
      positive: positive,
    );
    final addition = AiClickPromptAddition(
      point: point,
      count: runtime.addClickPrompt(imagePath, point),
    );
    logApp(
      'AI',
      'SAM3 click prompt added: image=${fileName(imagePath)}, point=${point.x.toStringAsFixed(4)},${point.y.toStringAsFixed(4)}, positive=$positive, total=${addition.count}',
      level: AppLogLevel.debug,
    );
    return addition;
  }

  bool hasPositiveClickPoint(String imagePath) {
    return runtime.hasPositivePoint(imagePath);
  }

  Future<AiSam3PreviewResult> runClickPreview({
    required AiAssistConfig config,
    required String pythonPath,
    required String imagePath,
    required int classId,
    required AiDisplaySizeResolver displaySizeResolver,
    required Future<void> Function() beforeRun,
  }) async {
    if (runtime.annotating) {
      return const AiSam3PreviewResult(AiSam3PreviewStatus.busy);
    }
    if (config.backend != AiAssistBackend.sam3 ||
        config.sam3PromptMode != AiSam3PromptMode.click) {
      return const AiSam3PreviewResult(AiSam3PreviewStatus.invalidConfig);
    }
    final normalizedPythonPath = pythonPath.trim();
    if (normalizedPythonPath.isEmpty) {
      logApp(
        'AI',
        'SAM3 click preview blocked: Python path is empty',
        level: AppLogLevel.warning,
      );
      return const AiSam3PreviewResult(AiSam3PreviewStatus.pythonNotConfigured);
    }
    final clickPointsText = runtime.clickPointsTextFor(imagePath);
    if (clickPointsText.trim().isEmpty ||
        !runtime.hasPositivePoint(imagePath)) {
      logApp(
        'AI',
        'SAM3 click preview blocked: no positive click prompt points',
        level: AppLogLevel.warning,
      );
      return const AiSam3PreviewResult(
        AiSam3PreviewStatus.positivePointRequired,
      );
    }
    logApp(
      'AI',
      'SAM3 click preview started: image=${fileName(imagePath)}, mode=${config.sam3OutputMode.wireName}, clickPoints=${clickPointsText.trim().split('\n').length}, ${config.sam3Runtime.logSummary}',
    );
    try {
      await runtime.runTask(() async {
        await beforeRun();
        final result = await runtime.annotateImage(
          AiSingleInferenceRequest(
            config: config,
            pythonPath: normalizedPythonPath,
            inputPath: imagePath,
            clickPointsText: clickPointsText,
            outputModeOverride: AiSam3OutputMode.seg,
          ),
        );
        final displaySize = await displaySizeResolver(imagePath);
        final preview = Sam3ClickPreviewState(
          result: result,
          displaySize: displaySize,
          annotations: AiAnnotationResultMapper.sam3Preview(
            result: result,
            displaySize: displaySize,
            classId: classId,
          ),
        );
        runtime.setPreview(imagePath, preview);
        logApp(
          'AI',
          'SAM3 click preview updated: image=${fileName(imagePath)}, masks=${result.masks.length}, preview=${preview.annotations.length}',
        );
      });
      return const AiSam3PreviewResult(AiSam3PreviewStatus.updated);
    } on Object catch (error) {
      final failure = classifyAiFailure(error);
      logApp(
        'AI',
        'SAM3 click preview failed: failure=$failure',
        level: AppLogLevel.error,
      );
      logAppMultiline(
        'AI',
        error.toString(),
        level: AppLogLevel.error,
        prefix: 'detail: ',
      );
      return AiSam3PreviewResult(AiSam3PreviewStatus.failed, error: error);
    }
  }

  AiAnnotationPlanResult createPlan({
    required Iterable<int> indices,
    required AiAssistConfig config,
    required String pythonPath,
    required int promptImageIndex,
  }) {
    final normalizedPythonPath = pythonPath.trim();
    if (normalizedPythonPath.isEmpty) {
      return const AiAnnotationPlanResult.blocked(
        AiAnnotationPlanFailure.pythonNotConfigured,
      );
    }
    if (config.backend == AiAssistBackend.yolo &&
        config.selectedClassIds.isEmpty) {
      return const AiAnnotationPlanResult.blocked(
        AiAnnotationPlanFailure.noSelectedClasses,
      );
    }
    if (config.backend == AiAssistBackend.sam3 &&
        config.sam3PromptMode == AiSam3PromptMode.text &&
        config.sam3PromptText.trim().isEmpty) {
      return const AiAnnotationPlanResult.blocked(
        AiAnnotationPlanFailure.sam3TextPromptRequired,
      );
    }
    final targetIndices = [
      for (final index in indices)
        if (index >= 0 && index < project.images.length) index,
    ];
    if (targetIndices.isEmpty) {
      return const AiAnnotationPlanResult.blocked(
        AiAnnotationPlanFailure.noValidTargets,
      );
    }
    final sam3ClickMode =
        config.backend == AiAssistBackend.sam3 &&
        config.sam3PromptMode == AiSam3PromptMode.click;
    var clickPointsText = '';
    var promptFrameIndex = 0;
    var previewOnly = false;
    if (sam3ClickMode) {
      if (!targetIndices.contains(promptImageIndex)) {
        return const AiAnnotationPlanResult.blocked(
          AiAnnotationPlanFailure.sam3PromptOutsideTargets,
        );
      }
      final promptImage = project.images[promptImageIndex];
      promptFrameIndex = targetIndices.indexOf(promptImageIndex);
      clickPointsText = runtime.clickPointsTextFor(promptImage.path);
      if (clickPointsText.trim().isEmpty ||
          !runtime.hasPositivePoint(promptImage.path)) {
        return const AiAnnotationPlanResult.blocked(
          AiAnnotationPlanFailure.sam3PositivePointRequired,
        );
      }
      previewOnly =
          targetIndices.length == 1 && targetIndices.first == promptImageIndex;
    }
    return AiAnnotationPlanResult.ready(
      AiAnnotationPlan(
        config: config,
        pythonPath: normalizedPythonPath,
        targetIndices: List<int>.unmodifiable(targetIndices),
        sam3ClickMode: sam3ClickMode,
        clickPointsText: clickPointsText,
        promptFrameIndex: promptFrameIndex,
        previewOnly: previewOnly,
      ),
    );
  }

  String? reportPlanFailure(AiAnnotationPlanFailure failure) {
    final (message, translationKey) = switch (failure) {
      AiAnnotationPlanFailure.pythonNotConfigured => (
        'AI annotation blocked: Python path is empty',
        'detect.pythonNotConfigured',
      ),
      AiAnnotationPlanFailure.noSelectedClasses => (
        'AI annotation blocked: no classes selected',
        'ai.noSelectedClasses',
      ),
      AiAnnotationPlanFailure.sam3TextPromptRequired => (
        'SAM3 annotation blocked: text prompt is empty',
        'ai.sam3PromptRequired',
      ),
      AiAnnotationPlanFailure.noValidTargets => (
        'AI annotation blocked: no valid target indices',
        null,
      ),
      AiAnnotationPlanFailure.sam3PromptOutsideTargets => (
        'SAM3 click annotation blocked: prompt image is outside the target range',
        'ai.sam3ClickCurrentOnly',
      ),
      AiAnnotationPlanFailure.sam3PositivePointRequired => (
        'SAM3 click annotation blocked: no positive click prompt points',
        'ai.sam3ClickRequired',
      ),
    };
    logApp('AI', message, level: AppLogLevel.warning);
    return translationKey;
  }

  Future<AiWorkspaceExecutionResult> runPlan({
    required AiAnnotationPlan plan,
    required AiDisplaySizeResolver displaySizeResolver,
    required AiClassColorFactory nextClassColorValue,
    required Future<void> Function() beforeRun,
    String? classNameOverride,
  }) async {
    final config = plan.config;
    logApp(
      'AI',
      'AI annotation started: backend=${config.backend.wireName}, targets=${plan.targetIndices.length}, model=${fileName(config.modelPath)}, classes=${config.selectedClassIds.length}, conf=${config.confThreshold.toStringAsFixed(2)}, imgsz=${config.imageSize}, sam3Mode=${config.sam3OutputMode.wireName}, prompt=${config.sam3PromptMode.wireName}, clickPoints=${plan.clickPointsText.trim().isEmpty ? 0 : plan.clickPointsText.trim().split('\n').length}, samPromptFrame=${plan.promptFrameIndex}, ${config.sam3Runtime.logSummary}',
    );
    try {
      final result = await _runWorkflow(
        plan: plan,
        displaySizeResolver: displaySizeResolver,
        nextClassColorValue: nextClassColorValue,
        author: _author,
        classNameOverride: classNameOverride,
        beforeRun: beforeRun,
      );
      logApp(
        'AI',
        'AI annotation completed: targets=${result.targetCount}, added=${result.addedCount}',
      );
      if (result.classesChanged) {
        collaborationSync.broadcastClassSnapshot('ai classes changed');
      }
      if (result.addedCount > 0 ||
          result.classesChanged ||
          plan.sam3ClickMode) {
        annotationDatabase.scheduleSave();
      }
      return AiWorkspaceExecutionResult.completed(result);
    } on Object catch (error) {
      final failure = classifyAiFailure(error);
      logApp(
        'AI',
        'AI annotation failed: backend=${config.backend.wireName}, failure=$failure',
        level: AppLogLevel.error,
      );
      logAppMultiline(
        'AI',
        error.toString(),
        level: AppLogLevel.error,
        prefix: 'detail: ',
      );
      return AiWorkspaceExecutionResult.failed(error);
    }
  }

  Future<AiAnnotationWorkflowResult> _runWorkflow({
    required AiAnnotationPlan plan,
    required AiDisplaySizeResolver displaySizeResolver,
    required AiClassColorFactory nextClassColorValue,
    required AiAnnotationAuthor author,
    String? classNameOverride,
    Future<void> Function()? beforeRun,
  }) async {
    final targetIndices = plan.targetIndices;
    if (targetIndices.isEmpty) {
      return const AiAnnotationWorkflowResult(
        targetCount: 0,
        addedCount: 0,
        classesChanged: false,
      );
    }
    return runtime.runTask(() async {
      await beforeRun?.call();
      final classCountBefore = project.labelClasses.length;
      if (targetIndices.length == 1 &&
          targetIndices.first == project.selectedImageIndex) {
        project.pushAnnotationSnapshot();
      }
      var added = 0;
      if (targetIndices.length == 1) {
        final image = project.images[targetIndices.first];
        final result = await runtime.annotateImage(
          AiSingleInferenceRequest(
            config: plan.config,
            pythonPath: plan.pythonPath,
            inputPath: image.path,
            clickPointsText: plan.clickPointsText,
          ),
        );
        final displaySize = await displaySizeResolver(image.path);
        added += _applyResult(
          imagePath: image.path,
          displaySize: displaySize,
          result: result,
          config: plan.config,
          nextClassColorValue: nextClassColorValue,
          author: author,
          classNameOverride: classNameOverride,
        );
      } else {
        final targetImages = [
          for (final index in targetIndices) project.images[index],
        ];
        final results = await runtime.annotateImages(
          AiBatchInferenceRequest(
            config: plan.config,
            pythonPath: plan.pythonPath,
            inputPaths: [for (final image in targetImages) image.path],
            clickPointsText: plan.clickPointsText,
            promptFrameIndex: plan.promptFrameIndex,
          ),
        );
        for (final result in results) {
          final imagePath = result.inputPath;
          if (imagePath.isEmpty || !File(imagePath).existsSync()) {
            continue;
          }
          final displaySize = await displaySizeResolver(imagePath);
          added += _applyResult(
            imagePath: imagePath,
            displaySize: displaySize,
            result: result,
            config: plan.config,
            nextClassColorValue: nextClassColorValue,
            author: author,
            classNameOverride: classNameOverride,
          );
        }
      }
      return AiAnnotationWorkflowResult(
        targetCount: targetIndices.length,
        addedCount: added,
        classesChanged: project.labelClasses.length != classCountBefore,
      );
    });
  }

  int _applyResult({
    required String imagePath,
    required Size displaySize,
    required AiAnnotationResult result,
    required AiAssistConfig config,
    required AiClassColorFactory nextClassColorValue,
    required AiAnnotationAuthor author,
    String? classNameOverride,
  }) {
    final generated = AiAnnotationResultMapper.map(
      result: result,
      displaySize: displaySize,
      config: config,
      resolveClassId: (name) => _ensureLabelClassByName(
        name,
        nextClassColorValue: nextClassColorValue,
      ),
      nextAnnotationId: project.nextAnnotationId,
      classNameOverride: classNameOverride,
      author: author,
    );
    final count = generated.length;
    if (config.backend == AiAssistBackend.sam3) {
      final replaceClickAnnotations =
          config.sam3PromptMode == AiSam3PromptMode.click;
      final previousIds = replaceClickAnnotations
          ? runtime.takeGeneratedAnnotationIds(imagePath)
          : const <String>{};
      if (replaceClickAnnotations) {
        runtime.setGeneratedAnnotationIds(
          imagePath,
          generated.map((annotation) => annotation.id).toSet(),
        );
      }
      project.replaceGeneratedAnnotations(
        imagePath: imagePath,
        removeIds: previousIds,
        additions: generated,
      );
      logApp(
        'AI',
        'SAM3 annotations applied: image=${fileName(imagePath)}, mode=${config.sam3OutputMode.wireName}, prompt=${config.sam3PromptMode.wireName}, masks=${result.masks.length}, added=$count',
        level: AppLogLevel.debug,
      );
      return count;
    }
    project.addAnnotations(imagePath, generated);
    return count;
  }

  int _ensureLabelClassByName(
    String rawName, {
    required AiClassColorFactory nextClassColorValue,
  }) {
    final name = rawName.trim().isEmpty
        ? 'class_${project.labelClasses.length}'
        : rawName.trim();
    for (final labelClass in project.labelClasses) {
      if (labelClass.name.toLowerCase() == name.toLowerCase()) {
        return labelClass.id;
      }
    }
    final id = project.classSerial++;
    project.addLabelClass(
      LabelClass(id: id, name: name, colorValue: nextClassColorValue()),
    );
    return id;
  }

  int commitClickPreview({
    required AiAssistConfig config,
    required String imagePath,
    required String className,
    required AiClassColorFactory nextClassColorValue,
  }) {
    final preview = runtime.previewFor(imagePath);
    if (preview == null || preview.result.masks.isEmpty) {
      return 0;
    }
    final classCountBefore = project.labelClasses.length;
    project.pushAnnotationSnapshot();
    final added = _applyResult(
      imagePath: imagePath,
      displaySize: preview.displaySize,
      result: preview.result,
      config: config,
      nextClassColorValue: nextClassColorValue,
      author: _author,
      classNameOverride: className.trim(),
    );
    runtime.removePreview(imagePath);
    final classesChanged = project.labelClasses.length != classCountBefore;
    if (classesChanged) {
      collaborationSync.broadcastClassSnapshot('sam3 click preview saved');
    }
    if (added > 0 || classesChanged) {
      annotationDatabase.scheduleSave();
    }
    logApp(
      'AI',
      'SAM3 click preview saved: image=${fileName(imagePath)}, added=$added',
    );
    return added;
  }

  AiAnnotationAuthor get _author => AiAnnotationAuthor(
    id: collaboration.authorId,
    name: collaboration.annotatorName,
    colorValue: collaboration.annotatorColorValue,
  );
}
