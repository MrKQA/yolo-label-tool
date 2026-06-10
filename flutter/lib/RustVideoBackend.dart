// ignore_for_file: file_names, unused_element, invalid_use_of_internal_member

part of 'main.dart';

/// 中文：Rust + FFmpeg 视频播放后端的轻量 FFI 封装。
/// English: Lightweight FFI wrapper for the Rust + FFmpeg video backend.
class _RustVideoBackend {
  const _RustVideoBackend._();

  static Future<_RustVideoInfo> loadInfo(String videoPath) {
    return Isolate.run(() => _loadInfoSync(videoPath));
  }

  static Future<String> startYoloTraining({
    required String pythonPath,
    required String modelPath,
    required String dataYamlPath,
    required String projectDir,
    required String experimentName,
    required int epochs,
    required int imgsz,
    required String batch,
    required String device,
    required double lr0,
    required double momentum,
    required double hsvS,
    required double hsvV,
    required double translate,
    required double scale,
    required double shear,
    required double flipud,
    required double fliplr,
    required double degrees,
    required int workers,
    required bool amp,
    required bool resume,
    required double clsPw,
  }) => RustLib.instance.api.crateApiStartYoloTraining(
    pythonPath: pythonPath,
    modelPath: modelPath,
    dataYamlPath: dataYamlPath,
    projectDir: projectDir,
    experimentName: experimentName,
    epochs: epochs,
    imgsz: imgsz,
    batch: batch,
    device: device,
    lr0: lr0,
    momentum: momentum,
    hsvS: hsvS,
    hsvV: hsvV,
    translate: translate,
    scale: scale,
    shear: shear,
    flipud: flipud,
    fliplr: fliplr,
    degrees: degrees,
    workers: workers,
    amp: amp,
    resume: resume,
    clsPw: clsPw,
  );

  static Future<TrainingProgress?> pollYoloTrainingProgress() =>
      RustLib.instance.api.crateApiPollYoloTrainingProgress();

  static Future<String> stopYoloTraining() =>
      RustLib.instance.api.crateApiStopYoloTraining();

  static Future<String> trainingLogTail({int maxChars = 30 * 1024}) {
    return Isolate.run(() => _trainingLogTailSync(maxChars: maxChars));
  }

  static Future<void> shutdownPython() {
    return Isolate.run(_shutdownPythonSync);
  }

  static Future<void> preloadYoloPython({required String pythonPath}) {
    return Isolate.run(() => _preloadYoloPythonSync(pythonPath: pythonPath));
  }

  static Future<Uint8List> decodeFrame({
    required String videoPath,
    required double timestampSeconds,
    required int maxWidth,
  }) {
    return Isolate.run(
      () => _decodeFrameSync(
        videoPath: videoPath,
        timestampSeconds: timestampSeconds,
        maxWidth: maxWidth,
      ),
    );
  }

  static Future<_DetectResult> detect({
    required String mode,
    required String pythonPath,
    required String modelPath,
    required String inputPath,
    required String outputDir,
    required String outputName,
    required double confThreshold,
    required double iouThreshold,
    required int imgsz,
    required String device,
    bool previewFrames = false,
    String cancelPath = '',
    int startFrame = 0,
  }) {
    return Isolate.run(
      () => _detectSync(
        mode: mode,
        pythonPath: pythonPath,
        modelPath: modelPath,
        inputPath: inputPath,
        outputDir: outputDir,
        outputName: outputName,
        confThreshold: confThreshold,
        iouThreshold: iouThreshold,
        imgsz: imgsz,
        device: device,
        previewFrames: previewFrames,
        cancelPath: cancelPath,
        startFrame: startFrame,
      ),
    );
  }

  static Future<_DetectModelTaskResult> detectModelTask({
    required String pythonPath,
    required String modelPath,
  }) {
    return Isolate.run(
      () => _detectModelTaskSync(pythonPath: pythonPath, modelPath: modelPath),
    );
  }

  static Future<_AiModelClassesResult> aiModelClasses({
    required String pythonPath,
    required String modelPath,
  }) {
    return Isolate.run(
      () => _aiModelClassesSync(pythonPath: pythonPath, modelPath: modelPath),
    );
  }

  static Future<_AiAnnotationResult> aiAnnotateImage({
    required String pythonPath,
    required String modelPath,
    required String inputPath,
    required List<int> classIds,
    required double confThreshold,
    required double iouThreshold,
    required int imgsz,
    required String device,
  }) {
    return Isolate.run(
      () => _aiAnnotateImageSync(
        pythonPath: pythonPath,
        modelPath: modelPath,
        inputPath: inputPath,
        classIds: classIds,
        confThreshold: confThreshold,
        iouThreshold: iouThreshold,
        imgsz: imgsz,
        device: device,
      ),
    );
  }

  static Future<List<_AiAnnotationResult>> aiAnnotateImages({
    required String pythonPath,
    required String modelPath,
    required List<String> inputPaths,
    required List<int> classIds,
    required double confThreshold,
    required double iouThreshold,
    required int imgsz,
    required String device,
  }) {
    return Isolate.run(
      () => _aiAnnotateImagesSync(
        pythonPath: pythonPath,
        modelPath: modelPath,
        inputPaths: inputPaths,
        classIds: classIds,
        confThreshold: confThreshold,
        iouThreshold: iouThreshold,
        imgsz: imgsz,
        device: device,
      ),
    );
  }

  static _RustVideoInfo _loadInfoSync(String videoPath) {
    final bindings = _RustVideoBindings.open();
    final pathBytes = Uint8List.fromList(utf8.encode(videoPath));
    final pathPtr = bindings.allocator.allocate(pathBytes);
    try {
      final buffer = bindings.videoInfoJson(pathPtr, pathBytes.length);
      final jsonText = bindings.takeUtf8(buffer);
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('Invalid video metadata response');
      }
      if (decoded['ok'] != true) {
        throw StateError(
          '${decoded['error'] ?? 'Unknown video backend error'}',
        );
      }
      return _RustVideoInfo(
        width: (decoded['width'] as num?)?.toInt() ?? 0,
        height: (decoded['height'] as num?)?.toInt() ?? 0,
        durationSeconds: (decoded['durationSeconds'] as num?)?.toDouble() ?? 0,
        fps: (decoded['fps'] as num?)?.toDouble() ?? 25,
        frameCount: (decoded['frameCount'] as num?)?.toInt() ?? 0,
        decoderLabel: '${decoded['decoderLabel'] ?? 'Rust + FFmpeg'}',
      );
    } finally {
      bindings.allocator.free(pathPtr);
    }
  }

  static Uint8List _decodeFrameSync({
    required String videoPath,
    required double timestampSeconds,
    required int maxWidth,
  }) {
    final bindings = _RustVideoBindings.open();
    final pathBytes = Uint8List.fromList(utf8.encode(videoPath));
    final pathPtr = bindings.allocator.allocate(pathBytes);
    try {
      final buffer = bindings.decodeVideoFramePng(
        pathPtr,
        pathBytes.length,
        timestampSeconds,
        maxWidth,
      );
      return bindings.takeBytes(buffer);
    } finally {
      bindings.allocator.free(pathPtr);
    }
  }

  static _DetectResult _detectSync({
    required String mode,
    required String pythonPath,
    required String modelPath,
    required String inputPath,
    required String outputDir,
    required String outputName,
    required double confThreshold,
    required double iouThreshold,
    required int imgsz,
    required String device,
    required bool previewFrames,
    required String cancelPath,
    required int startFrame,
  }) {
    final bindings = _RustVideoBindings.open();
    final request = jsonEncode({
      'mode': mode,
      'pythonPath': pythonPath,
      'modelPath': modelPath,
      'inputPath': inputPath,
      'outputDir': outputDir,
      'outputName': outputName,
      'confThreshold': confThreshold,
      'iouThreshold': iouThreshold,
      'imgsz': imgsz,
      'device': device,
      'previewFrames': previewFrames,
      'cancelPath': cancelPath,
      'startFrame': startFrame,
    });
    final requestBytes = Uint8List.fromList(utf8.encode(request));
    final requestPtr = bindings.allocator.allocate(requestBytes);
    try {
      final buffer = bindings.detectJson(requestPtr, requestBytes.length);
      final jsonText = bindings.takeUtf8(buffer);
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('Invalid detection response');
      }
      return _DetectResult(
        ok: decoded['ok'] == true,
        outputPath: '${decoded['outputPath'] ?? ''}',
        error: decoded['error']?.toString(),
        labelCount: (decoded['labelCount'] as num?)?.toInt() ?? 0,
      );
    } finally {
      bindings.allocator.free(requestPtr);
    }
  }

  static _DetectModelTaskResult _detectModelTaskSync({
    required String pythonPath,
    required String modelPath,
  }) {
    final bindings = _RustVideoBindings.open();
    final request = jsonEncode({
      'pythonPath': pythonPath,
      'modelPath': modelPath,
    });
    final requestBytes = Uint8List.fromList(utf8.encode(request));
    final requestPtr = bindings.allocator.allocate(requestBytes);
    try {
      final buffer = bindings.detectModelTaskJson(
        requestPtr,
        requestBytes.length,
      );
      final jsonText = bindings.takeUtf8(buffer);
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('Invalid model task response');
      }
      return _DetectModelTaskResult(
        ok: decoded['ok'] == true,
        task: '${decoded['task'] ?? ''}',
        folder: '${decoded['folder'] ?? 'hbb'}',
        error: decoded['error']?.toString(),
      );
    } finally {
      bindings.allocator.free(requestPtr);
    }
  }

  static void _preloadYoloPythonSync({required String pythonPath}) {
    if (pythonPath.trim().isEmpty) {
      return;
    }
    final bindings = _RustVideoBindings.open();
    final request = jsonEncode({'pythonPath': pythonPath});
    final requestBytes = Uint8List.fromList(utf8.encode(request));
    final requestPtr = bindings.allocator.allocate(requestBytes);
    try {
      final buffer = bindings.preloadYoloPythonJson(
        requestPtr,
        requestBytes.length,
      );
      final jsonText = bindings.takeUtf8(buffer);
      final decoded = jsonDecode(jsonText);
      if (decoded is Map && decoded['ok'] == true) {
        return;
      }
      throw StateError('${decoded is Map ? decoded['error'] : jsonText}');
    } finally {
      bindings.allocator.free(requestPtr);
    }
  }

  static String _trainingLogTailSync({required int maxChars}) {
    final bindings = _RustVideoBindings.open();
    final request = jsonEncode({'maxChars': maxChars});
    final requestBytes = Uint8List.fromList(utf8.encode(request));
    final requestPtr = bindings.allocator.allocate(requestBytes);
    try {
      final buffer = bindings.trainingLogTailJson(
        requestPtr,
        requestBytes.length,
      );
      final jsonText = bindings.takeUtf8(buffer);
      final decoded = jsonDecode(jsonText);
      if (decoded is Map && decoded['ok'] == true) {
        return '${decoded['text'] ?? ''}';
      }
      throw StateError('${decoded is Map ? decoded['error'] : jsonText}');
    } finally {
      bindings.allocator.free(requestPtr);
    }
  }

  static void _shutdownPythonSync() {
    final bindings = _RustVideoBindings.open();
    final requestBytes = Uint8List(0);
    final requestPtr = bindings.allocator.allocate(requestBytes);
    try {
      final buffer = bindings.shutdownPythonJson(
        requestPtr,
        requestBytes.length,
      );
      final jsonText = bindings.takeUtf8(buffer);
      final decoded = jsonDecode(jsonText);
      if (decoded is Map && decoded['ok'] == true) {
        return;
      }
      throw StateError('${decoded is Map ? decoded['error'] : jsonText}');
    } finally {
      bindings.allocator.free(requestPtr);
    }
  }

  static _AiModelClassesResult _aiModelClassesSync({
    required String pythonPath,
    required String modelPath,
  }) {
    final bindings = _RustVideoBindings.open();
    final request = jsonEncode({
      'pythonPath': pythonPath,
      'modelPath': modelPath,
    });
    final requestBytes = Uint8List.fromList(utf8.encode(request));
    final requestPtr = bindings.allocator.allocate(requestBytes);
    try {
      final buffer = bindings.aiModelClassesJson(
        requestPtr,
        requestBytes.length,
      );
      final jsonText = bindings.takeUtf8(buffer);
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('Invalid AI model classes response');
      }
      if (decoded['ok'] != true) {
        throw StateError('${decoded['error'] ?? 'Failed to read classes'}');
      }
      final classes = <_AiModelClass>[];
      final rawClasses = decoded['classes'];
      if (rawClasses is List) {
        for (final item in rawClasses) {
          if (item is Map) {
            classes.add(
              _AiModelClass(
                id: (item['id'] as num?)?.toInt() ?? classes.length,
                name: '${item['name'] ?? 'class_${classes.length}'}',
              ),
            );
          }
        }
      }
      return _AiModelClassesResult(
        task: '${decoded['task'] ?? 'detect'}',
        classes: classes,
      );
    } finally {
      bindings.allocator.free(requestPtr);
    }
  }

  static _AiAnnotationResult _aiAnnotateImageSync({
    required String pythonPath,
    required String modelPath,
    required String inputPath,
    required List<int> classIds,
    required double confThreshold,
    required double iouThreshold,
    required int imgsz,
    required String device,
  }) {
    final bindings = _RustVideoBindings.open();
    final request = jsonEncode({
      'pythonPath': pythonPath,
      'modelPath': modelPath,
      'inputPath': inputPath,
      'classIdsCsv': classIds.join(','),
      'confThreshold': confThreshold,
      'iouThreshold': iouThreshold,
      'imgsz': imgsz,
      'device': device,
    });
    final requestBytes = Uint8List.fromList(utf8.encode(request));
    final requestPtr = bindings.allocator.allocate(requestBytes);
    try {
      final buffer = bindings.aiAnnotateImageJson(
        requestPtr,
        requestBytes.length,
      );
      final jsonText = bindings.takeUtf8(buffer);
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('Invalid AI annotation response');
      }
      if (decoded['ok'] != true) {
        throw StateError('${decoded['error'] ?? 'AI annotation failed'}');
      }
      return _AiAnnotationResult(
        inputPath: inputPath,
        width: (decoded['width'] as num?)?.toDouble() ?? 0,
        height: (decoded['height'] as num?)?.toDouble() ?? 0,
        boxes: _parseAiPredictionBoxes(decoded['boxes']),
      );
    } finally {
      bindings.allocator.free(requestPtr);
    }
  }

  static List<_AiAnnotationResult> _aiAnnotateImagesSync({
    required String pythonPath,
    required String modelPath,
    required List<String> inputPaths,
    required List<int> classIds,
    required double confThreshold,
    required double iouThreshold,
    required int imgsz,
    required String device,
  }) {
    final bindings = _RustVideoBindings.open();
    final request = jsonEncode({
      'pythonPath': pythonPath,
      'modelPath': modelPath,
      'inputPathsText': inputPaths.join('\n'),
      'classIdsCsv': classIds.join(','),
      'confThreshold': confThreshold,
      'iouThreshold': iouThreshold,
      'imgsz': imgsz,
      'device': device,
    });
    final requestBytes = Uint8List.fromList(utf8.encode(request));
    final requestPtr = bindings.allocator.allocate(requestBytes);
    try {
      final buffer = bindings.aiAnnotateImagesJson(
        requestPtr,
        requestBytes.length,
      );
      final jsonText = bindings.takeUtf8(buffer);
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('Invalid AI batch annotation response');
      }
      if (decoded['ok'] != true) {
        throw StateError('${decoded['error'] ?? 'AI batch annotation failed'}');
      }
      final results = <_AiAnnotationResult>[];
      final rawImages = decoded['images'];
      if (rawImages is List) {
        for (var index = 0; index < rawImages.length; index++) {
          final item = rawImages[index];
          if (item is Map) {
            results.add(
              _AiAnnotationResult(
                inputPath:
                    '${item['inputPath'] ?? (index < inputPaths.length ? inputPaths[index] : '')}',
                width: (item['width'] as num?)?.toDouble() ?? 0,
                height: (item['height'] as num?)?.toDouble() ?? 0,
                boxes: _parseAiPredictionBoxes(item['boxes']),
              ),
            );
          }
        }
      }
      return results;
    } finally {
      bindings.allocator.free(requestPtr);
    }
  }

  static List<_AiPredictionBox> _parseAiPredictionBoxes(Object? rawBoxes) {
    final boxes = <_AiPredictionBox>[];
    if (rawBoxes is List) {
      for (final item in rawBoxes) {
        if (item is Map) {
          boxes.add(
            _AiPredictionBox(
              classId: (item['classId'] as num?)?.toInt() ?? 0,
              className: '${item['className'] ?? 'class'}',
              confidence: (item['confidence'] as num?)?.toDouble() ?? 0,
              rect: Rect.fromLTRB(
                (item['left'] as num?)?.toDouble() ?? 0,
                (item['top'] as num?)?.toDouble() ?? 0,
                (item['right'] as num?)?.toDouble() ?? 0,
                (item['bottom'] as num?)?.toDouble() ?? 0,
              ),
            ),
          );
        }
      }
    }
    return boxes;
  }
}

class _DetectResult {
  const _DetectResult({
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

class _DetectModelTaskResult {
  const _DetectModelTaskResult({
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

class _AiModelClass {
  const _AiModelClass({required this.id, required this.name});

  final int id;
  final String name;
}

class _AiModelClassesResult {
  const _AiModelClassesResult({required this.task, required this.classes});

  final String task;
  final List<_AiModelClass> classes;
}

class _AiPredictionBox {
  const _AiPredictionBox({
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

class _AiAnnotationResult {
  const _AiAnnotationResult({
    required this.inputPath,
    required this.width,
    required this.height,
    required this.boxes,
  });

  final String inputPath;
  final double width;
  final double height;
  final List<_AiPredictionBox> boxes;
}

class _RustVideoInfo {
  const _RustVideoInfo({
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

final class _RustVideoByteBuffer extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> ptr;

  @ffi.IntPtr()
  external int len;

  @ffi.IntPtr()
  external int cap;
}

typedef _VideoInfoJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _VideoInfoJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);

typedef _DecodeVideoFrameNative =
    _RustVideoByteBuffer Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.IntPtr,
      ffi.Double,
      ffi.Uint32,
    );
typedef _DecodeVideoFrameDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int, double, int);
typedef _DetectJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _DetectJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DetectModelTaskJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _DetectModelTaskJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _AiModelClassesJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _AiModelClassesJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _AiAnnotateImageJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _AiAnnotateImageJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _AiAnnotateImagesJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _AiAnnotateImagesJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _PreloadYoloPythonJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _PreloadYoloPythonJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _TrainingLogTailJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _TrainingLogTailJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _ShutdownPythonJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _ShutdownPythonJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);

typedef _FreeByteBufferNative = ffi.Void Function(_RustVideoByteBuffer);
typedef _FreeByteBufferDart = void Function(_RustVideoByteBuffer);

class _RustVideoBindings {
  _RustVideoBindings._(ffi.DynamicLibrary library)
    : allocator = _WindowsHeapAllocator(),
      videoInfoJson = library
          .lookupFunction<_VideoInfoJsonNative, _VideoInfoJsonDart>(
            'rust_label_video_info_json',
          ),
      decodeVideoFramePng = library
          .lookupFunction<_DecodeVideoFrameNative, _DecodeVideoFrameDart>(
            'rust_label_decode_video_frame_png',
          ),
      detectJson = library.lookupFunction<_DetectJsonNative, _DetectJsonDart>(
        'rust_label_detect_json',
      ),
      detectModelTaskJson = library
          .lookupFunction<_DetectModelTaskJsonNative, _DetectModelTaskJsonDart>(
            'rust_label_detect_model_task_json',
          ),
      aiModelClassesJson = library
          .lookupFunction<_AiModelClassesJsonNative, _AiModelClassesJsonDart>(
            'rust_label_ai_model_classes_json',
          ),
      aiAnnotateImageJson = library
          .lookupFunction<_AiAnnotateImageJsonNative, _AiAnnotateImageJsonDart>(
            'rust_label_ai_annotate_image_json',
          ),
      aiAnnotateImagesJson = library
          .lookupFunction<
            _AiAnnotateImagesJsonNative,
            _AiAnnotateImagesJsonDart
          >('rust_label_ai_annotate_images_json'),
      preloadYoloPythonJson = library
          .lookupFunction<
            _PreloadYoloPythonJsonNative,
            _PreloadYoloPythonJsonDart
          >('rust_label_preload_yolo_python_json'),
      trainingLogTailJson = library
          .lookupFunction<_TrainingLogTailJsonNative, _TrainingLogTailJsonDart>(
            'rust_label_training_log_tail_json',
          ),
      shutdownPythonJson = library
          .lookupFunction<_ShutdownPythonJsonNative, _ShutdownPythonJsonDart>(
            'rust_label_shutdown_python_json',
          ),
      _freeByteBuffer = library
          .lookupFunction<_FreeByteBufferNative, _FreeByteBufferDart>(
            'rust_label_free_byte_buffer',
          );

  final _WindowsHeapAllocator allocator;
  final _VideoInfoJsonDart videoInfoJson;
  final _DecodeVideoFrameDart decodeVideoFramePng;
  final _DetectJsonDart detectJson;
  final _DetectModelTaskJsonDart detectModelTaskJson;
  final _AiModelClassesJsonDart aiModelClassesJson;
  final _AiAnnotateImageJsonDart aiAnnotateImageJson;
  final _AiAnnotateImagesJsonDart aiAnnotateImagesJson;
  final _PreloadYoloPythonJsonDart preloadYoloPythonJson;
  final _TrainingLogTailJsonDart trainingLogTailJson;
  final _ShutdownPythonJsonDart shutdownPythonJson;
  final _FreeByteBufferDart _freeByteBuffer;

  static _RustVideoBindings open() {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'Rust video backend is currently wired for Windows',
      );
    }
    for (final path in _rustLibraryCandidates()) {
      if (File(path).existsSync()) {
        return _RustVideoBindings._(ffi.DynamicLibrary.open(path));
      }
    }
    throw StateError('yolo_label_bridge.dll was not found');
  }

  Uint8List takeBytes(_RustVideoByteBuffer buffer) {
    if (buffer.ptr == ffi.nullptr || buffer.len <= 0) {
      return Uint8List(0);
    }
    try {
      return Uint8List.fromList(buffer.ptr.asTypedList(buffer.len));
    } finally {
      _freeByteBuffer(buffer);
    }
  }

  String takeUtf8(_RustVideoByteBuffer buffer) {
    final bytes = takeBytes(buffer);
    if (bytes.isEmpty) {
      return '';
    }
    return utf8.decode(bytes);
  }
}

typedef _GetProcessHeapNative = ffi.Pointer<ffi.Void> Function();
typedef _GetProcessHeapDart = ffi.Pointer<ffi.Void> Function();

typedef _HeapAllocNative =
    ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<ffi.Void>,
      ffi.Uint32,
      ffi.IntPtr,
    );
typedef _HeapAllocDart =
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, int, int);

typedef _HeapFreeNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Uint32,
      ffi.Pointer<ffi.Void>,
    );
typedef _HeapFreeDart =
    int Function(ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Void>);

class _WindowsHeapAllocator {
  _WindowsHeapAllocator()
    : _kernel32 = ffi.DynamicLibrary.open('kernel32.dll') {
    _getProcessHeap = _kernel32
        .lookupFunction<_GetProcessHeapNative, _GetProcessHeapDart>(
          'GetProcessHeap',
        );
    _heapAlloc = _kernel32.lookupFunction<_HeapAllocNative, _HeapAllocDart>(
      'HeapAlloc',
    );
    _heapFree = _kernel32.lookupFunction<_HeapFreeNative, _HeapFreeDart>(
      'HeapFree',
    );
    _heap = _getProcessHeap();
  }

  final ffi.DynamicLibrary _kernel32;
  late final _GetProcessHeapDart _getProcessHeap;
  late final _HeapAllocDart _heapAlloc;
  late final _HeapFreeDart _heapFree;
  late final ffi.Pointer<ffi.Void> _heap;

  ffi.Pointer<ffi.Uint8> allocate(Uint8List bytes) {
    final size = math.max(1, bytes.length);
    final pointer = _heapAlloc(_heap, 0, size).cast<ffi.Uint8>();
    if (pointer == ffi.nullptr) {
      throw StateError('HeapAlloc failed');
    }
    if (bytes.isNotEmpty) {
      pointer.asTypedList(bytes.length).setAll(0, bytes);
    }
    return pointer;
  }

  void free(ffi.Pointer<ffi.Uint8> pointer) {
    if (pointer == ffi.nullptr) {
      return;
    }
    _heapFree(_heap, 0, pointer.cast<ffi.Void>());
  }
}
