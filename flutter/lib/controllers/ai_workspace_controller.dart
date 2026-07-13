import '../models/ai_assist.dart';
import '../services/ai_annotation_result_mapper.dart';
import '../services/ai_error_utils.dart';
import '../services/app_runtime.dart';
import '../services/config_store.dart';
import '../services/logger.dart';
import '../services/path_utils.dart';
import 'ai_annotation_controller.dart';
import 'ai_annotation_workflow_controller.dart';
import 'annotation_database_controller.dart';
import 'collaboration_controller.dart';
import 'collaboration_sync_controller.dart';
import 'project_controller.dart';

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
  const AiWorkspaceController({
    required this.runtime,
    required this.workflow,
    required this.project,
    required this.collaboration,
    required this.collaborationSync,
    required this.annotationDatabase,
  });

  final AiAnnotationController runtime;
  final AiAnnotationWorkflowController workflow;
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
      final result = await workflow.run(
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
    final added = workflow.applyResult(
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
