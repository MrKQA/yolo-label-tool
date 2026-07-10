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
  const AiModelClassesResult({required this.task, required this.classes});

  final String task;
  final List<AiModelClass> classes;
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
