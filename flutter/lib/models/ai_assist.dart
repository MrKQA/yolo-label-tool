// =============================================================================
// ai_assist.dart - AI-Assisted Annotation Models / AI 辅助标注模型
// =============================================================================
// Enums and config classes for AI backends (YOLO / SAM3), output modes (HBB/OBB/SEG),
// prompt modes (text/click), SAM3 runtime settings, and click prompt points.
//
// AI 后端枚举与配置：YOLO/SAM3、输出模式、提示模式、SAM3 运行时参数和点击提示点。
// =============================================================================

import 'dart:ui';

import 'annotation.dart';
import 'detection.dart';

enum AiAssistBackend { yolo, sam3 }

enum AiSam3OutputMode { hbb, obb, seg }

enum AiSam3PromptMode { text, click }

extension AiAssistBackendMeta on AiAssistBackend {
  String get wireName => switch (this) {
    AiAssistBackend.yolo => 'yolo',
    AiAssistBackend.sam3 => 'sam3',
  };
}

extension AiSam3OutputModeMeta on AiSam3OutputMode {
  String get wireName => switch (this) {
    AiSam3OutputMode.hbb => 'hbb',
    AiSam3OutputMode.obb => 'obb',
    AiSam3OutputMode.seg => 'seg',
  };

  AnnotationMode get annotationMode => switch (this) {
    AiSam3OutputMode.hbb => AnnotationMode.hbb,
    AiSam3OutputMode.obb => AnnotationMode.obb,
    AiSam3OutputMode.seg => AnnotationMode.seg,
  };
}

extension AiSam3PromptModeMeta on AiSam3PromptMode {
  String get wireName => switch (this) {
    AiSam3PromptMode.text => 'text',
    AiSam3PromptMode.click => 'click',
  };
}

class AiSam3RuntimeConfig {
  const AiSam3RuntimeConfig({
    this.precision = 'fp16',
    this.encoder = 'vit_b',
    this.imageBatchSize = 1,
    this.videoBatchSize = 1,
    this.interactiveBatchSize = 1,
    this.maxImageWidth = 1024,
    this.maxImageHeight = 768,
    this.resizeMethod = 'shorter_side',
    this.compile = false,
  });

  final String precision;
  final String encoder;
  final int imageBatchSize;
  final int videoBatchSize;
  final int interactiveBatchSize;
  final int maxImageWidth;
  final int maxImageHeight;
  final String resizeMethod;
  final bool compile;

  AiSam3RuntimeConfig copyWith({
    String? precision,
    String? encoder,
    int? imageBatchSize,
    int? videoBatchSize,
    int? interactiveBatchSize,
    int? maxImageWidth,
    int? maxImageHeight,
    String? resizeMethod,
    bool? compile,
  }) {
    return AiSam3RuntimeConfig(
      precision: precision ?? this.precision,
      encoder: encoder ?? this.encoder,
      imageBatchSize: imageBatchSize ?? this.imageBatchSize,
      videoBatchSize: videoBatchSize ?? this.videoBatchSize,
      interactiveBatchSize: interactiveBatchSize ?? this.interactiveBatchSize,
      maxImageWidth: maxImageWidth ?? this.maxImageWidth,
      maxImageHeight: maxImageHeight ?? this.maxImageHeight,
      resizeMethod: resizeMethod ?? this.resizeMethod,
      compile: compile ?? this.compile,
    );
  }

  String get logSummary =>
      'precision=$precision, encoder=$encoder, compile=$compile, batch=image:$imageBatchSize/video:$videoBatchSize/interactive:$interactiveBatchSize, preResize=${maxImageWidth}x$maxImageHeight, resize=$resizeMethod, processor=1008';
}

class AiAssistConfig {
  const AiAssistConfig({
    this.backend = AiAssistBackend.yolo,
    required this.modelPath,
    required this.classes,
    required this.selectedClassIds,
    required this.startIndex,
    required this.endIndex,
    this.confThreshold = 0.25,
    this.imageSize = 640,
    this.sam3OutputMode = AiSam3OutputMode.seg,
    this.sam3PromptMode = AiSam3PromptMode.text,
    this.sam3PromptText = '',
    this.sam3Runtime = const AiSam3RuntimeConfig(),
  });

  final AiAssistBackend backend;
  final String modelPath;
  final List<AiModelClass> classes;
  final Set<int> selectedClassIds;
  final int startIndex;
  final int endIndex;
  final double confThreshold;
  final int imageSize;
  final AiSam3OutputMode sam3OutputMode;
  final AiSam3PromptMode sam3PromptMode;
  final String sam3PromptText;
  final AiSam3RuntimeConfig sam3Runtime;
}

class Sam3ClickPromptPoint {
  const Sam3ClickPromptPoint({
    required this.x,
    required this.y,
    required this.positive,
  });

  final double x;
  final double y;
  final bool positive;

  String get wireLine =>
      '${x.toStringAsFixed(6)},${y.toStringAsFixed(6)},${positive ? 1 : 0}';
}

class Sam3ClickPreviewState {
  const Sam3ClickPreviewState({
    required this.result,
    required this.displaySize,
    required this.annotations,
  });

  final AiAnnotationResult result;
  final Size displaySize;
  final List<AnnotationRegion> annotations;
}

double normalizeAiConfidence(double value) {
  if (!value.isFinite) {
    return 0.25;
  }
  return ((value / 0.05).round() * 0.05).clamp(0.05, 0.95).toDouble();
}

