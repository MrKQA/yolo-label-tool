import 'dart:ui';

import '../models/ai_assist.dart';
import '../services/ai_annotation_result_mapper.dart';
import '../services/app_runtime.dart';
import '../services/path_utils.dart';
import 'ai_annotation_controller.dart';

enum Sam3ClickWorkflowFailure {
  busy,
  invalidConfig,
  pythonNotConfigured,
  positivePointRequired,
}

class Sam3ClickWorkflowException implements Exception {
  const Sam3ClickWorkflowException(this.failure);

  final Sam3ClickWorkflowFailure failure;

  @override
  String toString() => 'SAM3 click workflow failed: ${failure.name}';
}

class Sam3ClickPromptAddition {
  const Sam3ClickPromptAddition({required this.point, required this.count});

  final Sam3ClickPromptPoint point;
  final int count;
}

/// Coordinates normalized SAM3 click prompts and interactive mask previews.
class Sam3ClickWorkflowController {
  const Sam3ClickWorkflowController({required this.runtime});

  final AiAnnotationController runtime;

  Sam3ClickPromptAddition? addPrompt({
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
    return Sam3ClickPromptAddition(
      point: point,
      count: runtime.addClickPrompt(imagePath, point),
    );
  }

  Future<Sam3ClickPreviewState> runPreview({
    required AiAssistConfig config,
    required String pythonPath,
    required String imagePath,
    required int classId,
    required Future<Size> Function(String imagePath) displaySizeResolver,
    Future<void> Function()? beforeRun,
  }) async {
    if (runtime.annotating) {
      throw const Sam3ClickWorkflowException(Sam3ClickWorkflowFailure.busy);
    }
    if (config.backend != AiAssistBackend.sam3 ||
        config.sam3PromptMode != AiSam3PromptMode.click) {
      throw const Sam3ClickWorkflowException(
        Sam3ClickWorkflowFailure.invalidConfig,
      );
    }
    final normalizedPythonPath = pythonPath.trim();
    if (normalizedPythonPath.isEmpty) {
      throw const Sam3ClickWorkflowException(
        Sam3ClickWorkflowFailure.pythonNotConfigured,
      );
    }
    final clickPointsText = runtime.clickPointsTextFor(imagePath);
    if (clickPointsText.trim().isEmpty ||
        !runtime.hasPositivePoint(imagePath)) {
      throw const Sam3ClickWorkflowException(
        Sam3ClickWorkflowFailure.positivePointRequired,
      );
    }
    logApp(
      'AI',
      'SAM3 click preview started: image=${fileName(imagePath)}, mode=${config.sam3OutputMode.wireName}, clickPoints=${clickPointsText.trim().split('\n').length}, ${config.sam3Runtime.logSummary}',
    );
    return runtime.runTask(() async {
      await beforeRun?.call();
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
      return preview;
    });
  }
}
