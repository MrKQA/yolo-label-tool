import 'dart:io';
import 'dart:ui';

import '../models/ai_assist.dart';
import '../models/annotation.dart';
import '../models/detection.dart';
import '../services/ai_annotation_result_mapper.dart';
import '../services/app_runtime.dart';
import '../services/logger.dart';
import '../services/path_utils.dart';
import 'ai_annotation_controller.dart';
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

  bool get ready => plan != null;
}

/// Coordinates AI inference results with the active annotation project.
class AiAnnotationWorkflowController {
  const AiAnnotationWorkflowController({
    required this.runtime,
    required this.project,
  });

  final AiAnnotationController runtime;
  final ProjectController project;

  List<int> validTargetIndices(Iterable<int> indices) {
    return [
      for (final index in indices)
        if (index >= 0 && index < project.images.length) index,
    ];
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
    final targetIndices = validTargetIndices(indices);
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

  Future<AiAnnotationWorkflowResult> run({
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
        added += applyResult(
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
          added += applyResult(
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

  int applyResult({
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
}
