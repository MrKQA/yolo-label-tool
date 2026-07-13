import 'package:flutter/foundation.dart';

import '../models/ai_assist.dart';
import '../models/detection.dart';
import '../services/path_utils.dart';
import '../services/rust_backend.dart';

class AiSingleInferenceRequest {
  const AiSingleInferenceRequest({
    required this.config,
    required this.pythonPath,
    required this.inputPath,
    this.clickPointsText = '',
    this.outputModeOverride,
  });

  final AiAssistConfig config;
  final String pythonPath;
  final String inputPath;
  final String clickPointsText;
  final AiSam3OutputMode? outputModeOverride;
}

class AiBatchInferenceRequest {
  const AiBatchInferenceRequest({
    required this.config,
    required this.pythonPath,
    required this.inputPaths,
    this.clickPointsText = '',
    this.promptFrameIndex = 0,
  });

  final AiAssistConfig config;
  final String pythonPath;
  final List<String> inputPaths;
  final String clickPointsText;
  final int promptFrameIndex;
}

typedef AiSingleInferenceRunner =
    Future<AiAnnotationResult> Function(AiSingleInferenceRequest request);
typedef AiBatchInferenceRunner =
    Future<List<AiAnnotationResult>> Function(AiBatchInferenceRequest request);

/// Owns AI annotation runtime state and translates app config into inference
/// requests for YOLO and SAM3 backends.
class AiAnnotationController extends ChangeNotifier {
  AiAnnotationController({
    AiSingleInferenceRunner? singleRunner,
    AiBatchInferenceRunner? batchRunner,
  }) : _singleRunner = singleRunner ?? _runSingle,
       _batchRunner = batchRunner ?? _runBatch;

  final AiSingleInferenceRunner _singleRunner;
  final AiBatchInferenceRunner _batchRunner;
  final Map<String, List<Sam3ClickPromptPoint>> clickPromptsByImage = {};
  final Map<String, Sam3ClickPreviewState> clickPreviewsByImage = {};
  final Map<String, Set<String>> clickAnnotationIdsByImage = {};

  AiAssistConfig? config;
  bool annotating = false;
  bool _disposed = false;

  void updateConfig(AiAssistConfig value) {
    config = value;
    _notifyChanged();
  }

  List<Sam3ClickPromptPoint> promptsFor(String imagePath) {
    return clickPromptsByImage[pathKey(imagePath)] ?? const [];
  }

  String clickPointsTextFor(String imagePath) {
    return promptsFor(imagePath).map((point) => point.wireLine).join('\n');
  }

  bool hasPositivePoint(String imagePath) {
    return promptsFor(imagePath).any((point) => point.positive);
  }

  int addClickPrompt(String imagePath, Sam3ClickPromptPoint point) {
    final points = clickPromptsByImage.putIfAbsent(
      pathKey(imagePath),
      () => [],
    );
    points.add(point);
    _notifyChanged();
    return points.length;
  }

  Sam3ClickPreviewState? previewFor(String imagePath) {
    return clickPreviewsByImage[pathKey(imagePath)];
  }

  void setPreview(String imagePath, Sam3ClickPreviewState preview) {
    clickPreviewsByImage[pathKey(imagePath)] = preview;
    _notifyChanged();
  }

  void removePreview(String imagePath) {
    if (clickPreviewsByImage.remove(pathKey(imagePath)) != null) {
      _notifyChanged();
    }
  }

  Set<String> takeGeneratedAnnotationIds(String imagePath) {
    return clickAnnotationIdsByImage.remove(pathKey(imagePath)) ?? const {};
  }

  void setGeneratedAnnotationIds(String imagePath, Set<String> ids) {
    clickAnnotationIdsByImage[pathKey(imagePath)] = Set<String>.of(ids);
  }

  void clearImage(String imagePath) {
    final key = pathKey(imagePath);
    clickPromptsByImage.remove(key);
    clickPreviewsByImage.remove(key);
    clickAnnotationIdsByImage.remove(key);
    _notifyChanged();
  }

  void clearProject() {
    clickPromptsByImage.clear();
    clickPreviewsByImage.clear();
    clickAnnotationIdsByImage.clear();
    _notifyChanged();
  }

  Future<T> runTask<T>(Future<T> Function() task) async {
    if (annotating) {
      throw StateError('AI annotation is already running');
    }
    annotating = true;
    _notifyChanged();
    try {
      return await task();
    } finally {
      annotating = false;
      _notifyChanged();
    }
  }

  Future<AiAnnotationResult> annotateImage(AiSingleInferenceRequest request) {
    return _singleRunner(request);
  }

  Future<List<AiAnnotationResult>> annotateImages(
    AiBatchInferenceRequest request,
  ) {
    return _batchRunner(request);
  }

  static Future<AiAnnotationResult> _runSingle(
    AiSingleInferenceRequest request,
  ) {
    final config = request.config;
    return RustBackend.aiAnnotateImage(
      backend: config.backend.wireName,
      pythonPath: request.pythonPath,
      modelPath: config.modelPath,
      inputPath: request.inputPath,
      classIds: config.selectedClassIds.toList()..sort(),
      confThreshold: config.confThreshold,
      iouThreshold: 0.45,
      imgsz: config.imageSize,
      device: 'auto',
      samMode: (request.outputModeOverride ?? config.sam3OutputMode).wireName,
      samPromptMode: config.sam3PromptMode.wireName,
      promptsText: config.sam3PromptText,
      samClickPointsText: request.clickPointsText,
      samPrecision: config.sam3Runtime.precision,
      samEncoder: config.sam3Runtime.encoder,
      samImageBatchSize: config.sam3Runtime.imageBatchSize,
      samVideoBatchSize: config.sam3Runtime.videoBatchSize,
      samInteractiveBatchSize: config.sam3Runtime.interactiveBatchSize,
      samMaxImageWidth: config.sam3Runtime.maxImageWidth,
      samMaxImageHeight: config.sam3Runtime.maxImageHeight,
      samResizeMethod: config.sam3Runtime.resizeMethod,
      samCompile: config.sam3Runtime.compile,
    );
  }

  static Future<List<AiAnnotationResult>> _runBatch(
    AiBatchInferenceRequest request,
  ) {
    final config = request.config;
    return RustBackend.aiAnnotateImages(
      backend: config.backend.wireName,
      pythonPath: request.pythonPath,
      modelPath: config.modelPath,
      inputPaths: request.inputPaths,
      classIds: config.selectedClassIds.toList()..sort(),
      confThreshold: config.confThreshold,
      iouThreshold: 0.45,
      imgsz: config.imageSize,
      device: 'auto',
      samMode: config.sam3OutputMode.wireName,
      samPromptMode: config.sam3PromptMode.wireName,
      promptsText: config.sam3PromptText,
      samClickPointsText: request.clickPointsText,
      samPromptFrameIndex: request.promptFrameIndex,
      samPrecision: config.sam3Runtime.precision,
      samEncoder: config.sam3Runtime.encoder,
      samImageBatchSize: config.sam3Runtime.imageBatchSize,
      samVideoBatchSize: config.sam3Runtime.videoBatchSize,
      samInteractiveBatchSize: config.sam3Runtime.interactiveBatchSize,
      samMaxImageWidth: config.sam3Runtime.maxImageWidth,
      samMaxImageHeight: config.sam3Runtime.maxImageHeight,
      samResizeMethod: config.sam3Runtime.resizeMethod,
      samCompile: config.sam3Runtime.compile,
    );
  }

  void _notifyChanged() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
