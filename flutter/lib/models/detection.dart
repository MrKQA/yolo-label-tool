// =============================================================================
// detection.dart - Detection & Video Models / 检测与视频模型
// =============================================================================
// Models for detection results, video metadata, video play/predict session state,
// AI annotation results (boxes + masks), scale modes, and device info.
//
// 检测结果、视频元数据、视频播放/预测会话状态、AI 标注结果、缩放模式和设备信息。
// =============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

class DetectResult {
  const DetectResult({
    required this.ok,
    required this.outputPath,
    required this.error,
    required this.labelCount,
  });

  final bool ok;
  final String outputPath;
  final String? error;
  final int labelCount;
}

class BatchDetectItem {
  const BatchDetectItem({
    required this.inputPath,
    required this.outputPath,
    required this.labelCount,
  });

  final String inputPath;
  final String outputPath;
  final int labelCount;
}

class BatchDetectResult {
  const BatchDetectResult({
    required this.items,
    required this.labelCount,
    required this.device,
  });

  final List<BatchDetectItem> items;
  final int labelCount;
  final String device;
}

class DetectModelTaskResult {
  const DetectModelTaskResult({
    required this.ok,
    required this.task,
    required this.folder,
    required this.error,
  });

  final bool ok;
  final String task;
  final String folder;
  final String? error;
}

class CamAnalysisOutput {
  const CamAnalysisOutput({
    required this.id,
    required this.label,
    required this.path,
    required this.durationMs,
    required this.targetLayerIndex,
    required this.targetLayerName,
  });

  final String id;
  final String label;
  final String path;
  final int durationMs;
  final int targetLayerIndex;
  final String targetLayerName;
}

class CamAnalysisOptions {
  const CamAnalysisOptions({
    required this.mode,
    required this.smoothing,
    required this.targetClassId,
    required this.threshold,
  });

  final String mode;
  final String smoothing;
  final int targetClassId;
  final double threshold;
}

class CamTargetLayerOption {
  const CamTargetLayerOption({
    required this.index,
    required this.moduleIndex,
    required this.name,
  });

  final int index;
  final int moduleIndex;
  final String name;
}

class CamAnalysisResult {
  const CamAnalysisResult({
    required this.family,
    required this.task,
    required this.device,
    required this.ultralyticsVersion,
    required this.targetLayers,
    required this.availableTargetLayers,
    required this.targetLayerIndex,
    required this.outputs,
    required this.durationMs,
    required this.detectedBoxes,
    required this.analyzedBoxes,
    required this.minimumMatchIou,
    required this.mode,
    required this.smoothing,
    required this.targetClassId,
    required this.targetClassName,
    required this.threshold,
  });

  final String family;
  final String task;
  final String device;
  final String ultralyticsVersion;
  final List<String> targetLayers;
  final List<String> availableTargetLayers;
  final int targetLayerIndex;
  final List<CamAnalysisOutput> outputs;
  final int durationMs;
  final int detectedBoxes;
  final int analyzedBoxes;
  final double minimumMatchIou;
  final String mode;
  final String smoothing;
  final int targetClassId;
  final String targetClassName;
  final double threshold;
}

class ModelExportResult {
  const ModelExportResult({
    required this.format,
    required this.outputPath,
    required this.stdout,
    required this.stderr,
  });

  final String format;
  final String outputPath;
  final String stdout;
  final String stderr;
}

class AiModelClass {
  const AiModelClass({required this.id, required this.name});

  final int id;
  final String name;
}

class AiModelClassesResult {
  const AiModelClassesResult({
    required this.task,
    required this.classes,
    this.targetLayers = const [],
  });

  final String task;
  final List<AiModelClass> classes;
  final List<CamTargetLayerOption> targetLayers;
}

class AiPredictionBox {
  const AiPredictionBox({
    required this.classId,
    required this.className,
    required this.confidence,
    required this.rect,
  });

  final int classId;
  final String className;
  final double confidence;
  final Rect rect;
}

class AiPredictionMask {
  const AiPredictionMask({
    required this.classId,
    required this.className,
    required this.confidence,
    required this.points,
  });

  final int classId;
  final String className;
  final double confidence;
  final List<Offset> points;
}

class AiAnnotationResult {
  const AiAnnotationResult({
    required this.inputPath,
    required this.width,
    required this.height,
    required this.boxes,
    this.masks = const [],
  });

  final String inputPath;
  final double width;
  final double height;
  final List<AiPredictionBox> boxes;
  final List<AiPredictionMask> masks;
}

class RustVideoInfo {
  const RustVideoInfo({
    required this.width,
    required this.height,
    required this.durationSeconds,
    required this.fps,
    required this.frameCount,
    required this.decoderLabel,
  });

  final int width;
  final int height;
  final double durationSeconds;
  final double fps;
  final int frameCount;
  final String decoderLabel;

  double get safeDurationSeconds {
    if (durationSeconds.isFinite && durationSeconds > 0) {
      return durationSeconds;
    }
    if (frameCount > 0 && safeFps > 0) {
      return frameCount / safeFps;
    }
    return 0;
  }

  double get safeFps =>
      fps.isFinite && fps > 0 ? fps.clamp(1, 60).toDouble() : 25;
}

class PredictionFrameManifest {
  const PredictionFrameManifest({
    required this.fps,
    required this.totalFrames,
    required this.startFrame,
    required this.complete,
    required this.canceled,
    required this.frames,
  });

  final double fps;
  final int totalFrames;
  final int startFrame;
  final bool complete;
  final bool canceled;
  final List<PredictionFrameInfo> frames;

  static PredictionFrameManifest load(String path) {
    final decoded = jsonDecode(File(path).readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Invalid prediction manifest');
    }
    final rawFrames = decoded['frames'];
    if (rawFrames is! List) {
      throw StateError('Prediction manifest has no frames');
    }
    return PredictionFrameManifest(
      fps: (decoded['fps'] as num?)?.toDouble() ?? 25.0,
      totalFrames: (decoded['totalFrames'] as num?)?.round() ?? 0,
      startFrame: (decoded['startFrame'] as num?)?.round() ?? 0,
      complete: decoded['complete'] == true,
      canceled: decoded['canceled'] == true,
      frames: [
        for (final item in rawFrames)
          if (item is Map)
            PredictionFrameInfo(
              path: '${item['path'] ?? ''}'.replaceAll('/', '\\'),
              frameNumber: (item['frameNumber'] as num?)?.round() ?? 0,
              preprocessMs: (item['preprocessMs'] as num?)?.toDouble() ?? 0,
              inferenceMs: (item['inferenceMs'] as num?)?.toDouble() ?? 0,
              postprocessMs: (item['postprocessMs'] as num?)?.toDouble() ?? 0,
            ),
      ],
    );
  }
}

class PredictionFrameInfo {
  const PredictionFrameInfo({
    required this.path,
    required this.frameNumber,
    required this.preprocessMs,
    required this.inferenceMs,
    required this.postprocessMs,
  });

  final String path;
  final int frameNumber;
  final double preprocessMs;
  final double inferenceMs;
  final double postprocessMs;
}
