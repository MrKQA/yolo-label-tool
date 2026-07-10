// ignore_for_file: file_names, unused_element, invalid_use_of_internal_member

import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import '../models/detection.dart';
import '../models/export.dart';
import '../models/training.dart';
import '../src/rust/api/training_mod.dart' show TrainingProgress;
import '../src/rust/frb_generated.dart';
import 'rust_ffi.dart';

/// 涓枃锛歊ust + FFmpeg 瑙嗛鎾斁鍚庣鐨勮交閲?FFI 灏佽銆?/// English: Lightweight FFI wrapper for the Rust + FFmpeg video backend.
class RustBackend {
  const RustBackend._();

  static Future<RustVideoInfo> loadInfo(String videoPath) {
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
    required int patience,
    required double hsvH,
    required double hsvS,
    required double hsvV,
    required double translate,
    required double scale,
    required double shear,
    required double flipud,
    required double fliplr,
    required double degrees,
    required double perspective,
    required double bgr,
    required double mosaic,
    required double mixup,
    required double cutmix,
    required double copyPaste,
    required String copyPasteMode,
    required String autoAugment,
    required double erasing,
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
    patience: patience,
    hsvH: hsvH,
    hsvS: hsvS,
    hsvV: hsvV,
    translate: translate,
    scale: scale,
    shear: shear,
    flipud: flipud,
    fliplr: fliplr,
    degrees: degrees,
    perspective: perspective,
    bgr: bgr,
    mosaic: mosaic,
    mixup: mixup,
    cutmix: cutmix,
    copyPaste: copyPaste,
    copyPasteMode: copyPasteMode,
    autoAugment: autoAugment,
    erasing: erasing,
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

  static Future<TrainingResourceUsage> trainingResourceUsage() {
    return Isolate.run(_trainingResourceUsageSync);
  }

  static Future<void> shutdownPython() {
    return Isolate.run(_shutdownPythonSync);
  }

  static Future<void> preloadYoloPython({required String pythonPath}) {
    return Isolate.run(() => _preloadYoloPythonSync(pythonPath: pythonPath));
  }

  static Future<Map<String, dynamic>> saveLabelDatabase({
    required String payload,
  }) {
    return Isolate.run(() => _labelDatabaseSync(payload: payload, save: true));
  }

  static Future<Map<String, dynamic>> loadLabelDatabase({
    required String payload,
  }) {
    return Isolate.run(() => _labelDatabaseSync(payload: payload, save: false));
  }

  static void saveConfigValue({required String key, required String value}) {
    _configDatabaseSync(key: key, value: value, mode: 'save');
  }

  static String loadConfigValue({required String key}) {
    final result = _configDatabaseSync(key: key, mode: 'load');
    return '${result['value'] ?? ''}';
  }

  static void deleteConfigValue({required String key}) {
    _configDatabaseSync(key: key, mode: 'delete');
  }

  static void appendLogLines({required String lines}) {
    _logDatabaseSync(lines: lines, mode: 'append');
  }

  static List<String> logDates() {
    final result = _logDatabaseSync(mode: 'dates');
    final dates = result['dates'];
    if (dates is! List) {
      return const [];
    }
    return dates.map((item) => '$item').toList(growable: false);
  }

  static String readLogsForDate(String date) {
    final result = _logDatabaseSync(date: date, mode: 'read');
    return '${result['text'] ?? ''}';
  }

  static int deleteLogsByDateRange({
    required String startDate,
    required String endDate,
  }) {
    final result = _logDatabaseSync(
      startDate: startDate,
      endDate: endDate,
      mode: 'delete',
    );
    return (result['deleted'] as num?)?.toInt() ?? 0;
  }

  static Future<Map<String, dynamic>> databaseOverview() {
    return Isolate.run(_databaseOverviewSync);
  }

  static Future<Map<String, dynamic>> databaseTable({
    required String table,
    String projectId = '',
    String imageId = '',
    int limit = 50,
    int offset = 0,
  }) {
    return Isolate.run(
      () => _databaseTableSync(
        table: table,
        projectId: projectId,
        imageId: imageId,
        limit: limit,
        offset: offset,
      ),
    );
  }

  static Future<Map<String, dynamic>> databaseSqlQuery({required String sql}) {
    return Isolate.run(() => _databaseSqlQuerySync(sql: sql));
  }

  static Future<Map<String, dynamic>> collaborationCommand({
    required Map<String, Object?> request,
  }) {
    return Isolate.run(() => _collaborationCommandSync(request: request));
  }

  static Future<List<Map<String, dynamic>>> collaborationPollEvents({
    int maxEvents = 50,
  }) {
    return Isolate.run(
      () => _collaborationPollEventsSync(maxEvents: maxEvents),
    );
  }

  static Future<List<String>> trainingLogDates() {
    return Isolate.run(() {
      final result = _trainingLogDatabaseSync(mode: 'dates');
      final dates = result['dates'];
      if (dates is! List) {
        return const <String>[];
      }
      return dates.map((item) => '$item').toList(growable: false);
    });
  }

  static Future<String> readTrainingLogForDate(String date) {
    return Isolate.run(() {
      final result = _trainingLogDatabaseSync(mode: 'read', date: date);
      return '${result['text'] ?? ''}';
    });
  }

  static Future<int> deleteTrainingLogsByDateRange({
    required String startDate,
    required String endDate,
  }) {
    return Isolate.run(() {
      final result = _trainingLogDatabaseSync(
        mode: 'delete',
        startDate: startDate,
        endDate: endDate,
      );
      return (result['deleted'] as num?)?.toInt() ?? 0;
    });
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

  static Future<DetectResult> detect({
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

  static Future<DetectModelTaskResult> detectModelTask({
    required String pythonPath,
    required String modelPath,
  }) {
    return Isolate.run(
      () => _detectModelTaskSync(pythonPath: pythonPath, modelPath: modelPath),
    );
  }

  static Future<ModelExportResult> exportYoloModel({
    required String pythonPath,
    required String modelPath,
    required YoloExportSettings settings,
  }) {
    final settingsJson = settings.toJson();
    return Isolate.run(
      () => _exportYoloModelSync(
        pythonPath: pythonPath,
        modelPath: modelPath,
        settingsJson: settingsJson,
      ),
    );
  }

  static Future<AiModelClassesResult> aiModelClasses({
    required String pythonPath,
    required String modelPath,
  }) {
    return Isolate.run(
      () => _aiModelClassesSync(pythonPath: pythonPath, modelPath: modelPath),
    );
  }

  static Future<AiAnnotationResult> aiAnnotateImage({
    required String backend,
    required String pythonPath,
    required String modelPath,
    required String inputPath,
    required List<int> classIds,
    required double confThreshold,
    required double iouThreshold,
    required int imgsz,
    required String device,
    String samMode = 'seg',
    String samPromptMode = 'text',
    String promptsText = '',
    String samClickPointsText = '',
    String samPrecision = 'fp16',
    String samEncoder = 'vit_b',
    int samImageBatchSize = 1,
    int samVideoBatchSize = 1,
    int samInteractiveBatchSize = 1,
    int samMaxImageWidth = 1024,
    int samMaxImageHeight = 768,
    String samResizeMethod = 'shorter_side',
    bool samCompile = false,
  }) {
    return Isolate.run(
      () => _aiAnnotateImageSync(
        backend: backend,
        pythonPath: pythonPath,
        modelPath: modelPath,
        inputPath: inputPath,
        classIds: classIds,
        confThreshold: confThreshold,
        iouThreshold: iouThreshold,
        imgsz: imgsz,
        device: device,
        samMode: samMode,
        samPromptMode: samPromptMode,
        promptsText: promptsText,
        samClickPointsText: samClickPointsText,
        samPrecision: samPrecision,
        samEncoder: samEncoder,
        samImageBatchSize: samImageBatchSize,
        samVideoBatchSize: samVideoBatchSize,
        samInteractiveBatchSize: samInteractiveBatchSize,
        samMaxImageWidth: samMaxImageWidth,
        samMaxImageHeight: samMaxImageHeight,
        samResizeMethod: samResizeMethod,
        samCompile: samCompile,
      ),
    );
  }

  static Future<List<AiAnnotationResult>> aiAnnotateImages({
    required String backend,
    required String pythonPath,
    required String modelPath,
    required List<String> inputPaths,
    required List<int> classIds,
    required double confThreshold,
    required double iouThreshold,
    required int imgsz,
    required String device,
    String samMode = 'seg',
    String samPromptMode = 'text',
    String promptsText = '',
    String samClickPointsText = '',
    int samPromptFrameIndex = 0,
    String samPrecision = 'fp16',
    String samEncoder = 'vit_b',
    int samImageBatchSize = 1,
    int samVideoBatchSize = 1,
    int samInteractiveBatchSize = 1,
    int samMaxImageWidth = 1024,
    int samMaxImageHeight = 768,
    String samResizeMethod = 'shorter_side',
    bool samCompile = false,
  }) {
    return Isolate.run(
      () => _aiAnnotateImagesSync(
        backend: backend,
        pythonPath: pythonPath,
        modelPath: modelPath,
        inputPaths: inputPaths,
        classIds: classIds,
        confThreshold: confThreshold,
        iouThreshold: iouThreshold,
        imgsz: imgsz,
        device: device,
        samMode: samMode,
        samPromptMode: samPromptMode,
        promptsText: promptsText,
        samClickPointsText: samClickPointsText,
        samPromptFrameIndex: samPromptFrameIndex,
        samPrecision: samPrecision,
        samEncoder: samEncoder,
        samImageBatchSize: samImageBatchSize,
        samVideoBatchSize: samVideoBatchSize,
        samInteractiveBatchSize: samInteractiveBatchSize,
        samMaxImageWidth: samMaxImageWidth,
        samMaxImageHeight: samMaxImageHeight,
        samResizeMethod: samResizeMethod,
        samCompile: samCompile,
      ),
    );
  }

  static RustVideoInfo _loadInfoSync(String videoPath) {
    final bindings = RustVideoBindings.open();
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
      return RustVideoInfo(
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
    final bindings = RustVideoBindings.open();
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

  static DetectResult _detectSync({
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
    final bindings = RustVideoBindings.open();
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
      return DetectResult(
        ok: decoded['ok'] == true,
        outputPath: '${decoded['outputPath'] ?? ''}',
        error: decoded['error']?.toString(),
        labelCount: (decoded['labelCount'] as num?)?.toInt() ?? 0,
      );
    } finally {
      bindings.allocator.free(requestPtr);
    }
  }

  static DetectModelTaskResult _detectModelTaskSync({
    required String pythonPath,
    required String modelPath,
  }) {
    final bindings = RustVideoBindings.open();
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
      return DetectModelTaskResult(
        ok: decoded['ok'] == true,
        task: '${decoded['task'] ?? ''}',
        folder: '${decoded['folder'] ?? 'hbb'}',
        error: decoded['error']?.toString(),
      );
    } finally {
      bindings.allocator.free(requestPtr);
    }
  }

  static ModelExportResult _exportYoloModelSync({
    required String pythonPath,
    required String modelPath,
    required Map<String, Object> settingsJson,
  }) {
    final settings = YoloExportSettings.fromJson(settingsJson);
    final bindings = RustVideoBindings.open();
    final request = jsonEncode({
      'pythonPath': pythonPath,
      'modelPath': modelPath,
      'format': settings.format,
      'imgsz': settings.imgsz,
      'batch': settings.batch,
      'quantize': settings.quantize,
      'dynamic': settings.dynamic,
      'nms': settings.nms,
      'data': settings.dataPath.trim(),
      'fraction': settings.fraction,
      'device': settings.device,
      'simplify': settings.simplify,
      'opset': settings.opset,
    });
    final requestBytes = Uint8List.fromList(utf8.encode(request));
    final requestPtr = bindings.allocator.allocate(requestBytes);
    try {
      final buffer = bindings.exportModelJson(requestPtr, requestBytes.length);
      final jsonText = bindings.takeUtf8(buffer);
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('Invalid export response');
      }
      if (decoded['ok'] != true) {
        throw StateError('${decoded['error'] ?? 'Model export failed'}');
      }
      return ModelExportResult(
        format: '${decoded['format'] ?? settings.format}',
        outputPath: '${decoded['outputPath'] ?? ''}',
        stdout: '${decoded['stdout'] ?? ''}',
        stderr: '${decoded['stderr'] ?? ''}',
      );
    } finally {
      bindings.allocator.free(requestPtr);
    }
  }

  static void _preloadYoloPythonSync({required String pythonPath}) {
    if (pythonPath.trim().isEmpty) {
      return;
    }
    final bindings = RustVideoBindings.open();
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
    final bindings = RustVideoBindings.open();
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

  static TrainingResourceUsage _trainingResourceUsageSync() {
    final bindings = RustVideoBindings.open();
    final requestBytes = Uint8List(0);
    final requestPtr = bindings.allocator.allocate(requestBytes);
    try {
      final buffer = bindings.trainingResourceUsageJson(
        requestPtr,
        requestBytes.length,
      );
      final jsonText = bindings.takeUtf8(buffer);
      final decoded = jsonDecode(jsonText);
      if (decoded is Map && decoded['ok'] == true) {
        return TrainingResourceUsage.fromJson(decoded);
      }
      throw StateError('${decoded is Map ? decoded['error'] : jsonText}');
    } finally {
      bindings.allocator.free(requestPtr);
    }
  }

  static void _shutdownPythonSync() {
    final bindings = RustVideoBindings.open();
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

  static Map<String, dynamic> _labelDatabaseSync({
    required String payload,
    required bool save,
  }) {
    final bindings = RustVideoBindings.open();
    final request = jsonEncode({'payload': payload});
    final requestBytes = Uint8List.fromList(utf8.encode(request));
    final requestPtr = bindings.allocator.allocate(requestBytes);
    try {
      final buffer = save
          ? bindings.dbSaveSnapshotJson(requestPtr, requestBytes.length)
          : bindings.dbLoadSnapshotJson(requestPtr, requestBytes.length);
      final jsonText = bindings.takeUtf8(buffer);
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('Invalid label database response');
      }
      if (decoded['ok'] != true) {
        throw StateError('${decoded['error'] ?? 'Label database failed'}');
      }
      return decoded;
    } finally {
      bindings.allocator.free(requestPtr);
    }
  }

  static Map<String, dynamic> _configDatabaseSync({
    required String key,
    String value = '',
    required String mode,
  }) {
    final bindings = RustVideoBindings.open();
    final request = jsonEncode({'key': key, 'value': value});
    final requestBytes = Uint8List.fromList(utf8.encode(request));
    final requestPtr = bindings.allocator.allocate(requestBytes);
    try {
      final buffer = switch (mode) {
        'save' => bindings.dbSaveConfigJson(requestPtr, requestBytes.length),
        'delete' => bindings.dbDeleteConfigJson(
          requestPtr,
          requestBytes.length,
        ),
        _ => bindings.dbLoadConfigJson(requestPtr, requestBytes.length),
      };
      return _decodeDbResponse(bindings, buffer, 'config database failed');
    } finally {
      bindings.allocator.free(requestPtr);
    }
  }

  static Map<String, dynamic> _logDatabaseSync({
    String lines = '',
    String date = '',
    String startDate = '',
    String endDate = '',
    required String mode,
  }) {
    final bindings = RustVideoBindings.open();
    final request = jsonEncode({
      'lines': lines,
      'date': date,
      'startDate': startDate,
      'endDate': endDate,
    });
    final requestBytes = Uint8List.fromList(utf8.encode(request));
    final requestPtr = bindings.allocator.allocate(requestBytes);
    try {
      final buffer = switch (mode) {
        'append' => bindings.dbAppendLogsJson(requestPtr, requestBytes.length),
        'read' => bindings.dbReadLogsJson(requestPtr, requestBytes.length),
        'delete' => bindings.dbDeleteLogsJson(requestPtr, requestBytes.length),
        _ => bindings.dbLogDatesJson(requestPtr, requestBytes.length),
      };
      return _decodeDbResponse(bindings, buffer, 'log database failed');
    } finally {
      bindings.allocator.free(requestPtr);
    }
  }

  static Map<String, dynamic> _databaseOverviewSync() {
    final bindings = RustVideoBindings.open();
    final requestBytes = Uint8List.fromList(utf8.encode('{}'));
    final requestPtr = bindings.allocator.allocate(requestBytes);
    try {
      final buffer = bindings.dbOverviewJson(requestPtr, requestBytes.length);
      return _decodeDbResponse(bindings, buffer, 'database overview failed');
    } finally {
      bindings.allocator.free(requestPtr);
    }
  }

  static Map<String, dynamic> _databaseTableSync({
    required String table,
    required String projectId,
    required String imageId,
    required int limit,
    required int offset,
  }) {
    final bindings = RustVideoBindings.open();
    final request = jsonEncode({
      'table': table,
      'projectId': projectId,
      'imageId': imageId,
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
    final requestBytes = Uint8List.fromList(utf8.encode(request));
    final requestPtr = bindings.allocator.allocate(requestBytes);
    try {
      final buffer = bindings.dbTableJson(requestPtr, requestBytes.length);
      return _decodeDbResponse(bindings, buffer, 'database table failed');
    } finally {
      bindings.allocator.free(requestPtr);
    }
  }

  static Map<String, dynamic> _databaseSqlQuerySync({required String sql}) {
    final bindings = RustVideoBindings.open();
    final request = jsonEncode({'sql': sql});
    final requestBytes = Uint8List.fromList(utf8.encode(request));
    final requestPtr = bindings.allocator.allocate(requestBytes);
    try {
      final buffer = bindings.dbSqlQueryJson(requestPtr, requestBytes.length);
      return _decodeDbResponse(bindings, buffer, 'database SQL query failed');
    } finally {
      bindings.allocator.free(requestPtr);
    }
  }

  static Map<String, dynamic> _collaborationCommandSync({
    required Map<String, Object?> request,
  }) {
    final bindings = RustVideoBindings.open();
    final requestBytes = Uint8List.fromList(utf8.encode(jsonEncode(request)));
    final requestPtr = bindings.allocator.allocate(requestBytes);
    try {
      final buffer = bindings.collabCommandJson(
        requestPtr,
        requestBytes.length,
      );
      return _decodeDbResponse(
        bindings,
        buffer,
        'collaboration command failed',
      );
    } finally {
      bindings.allocator.free(requestPtr);
    }
  }

  static List<Map<String, dynamic>> _collaborationPollEventsSync({
    required int maxEvents,
  }) {
    final bindings = RustVideoBindings.open();
    final request = jsonEncode({'maxEvents': maxEvents});
    final requestBytes = Uint8List.fromList(utf8.encode(request));
    final requestPtr = bindings.allocator.allocate(requestBytes);
    try {
      final buffer = bindings.collabPollJson(requestPtr, requestBytes.length);
      final decoded = _decodeDbResponse(
        bindings,
        buffer,
        'collaboration event poll failed',
      );
      final events = decoded['events'];
      if (events is! List) {
        return const <Map<String, dynamic>>[];
      }
      return events
          .whereType<Map>()
          .map(
            (event) =>
                event.map((key, value) => MapEntry(key.toString(), value)),
          )
          .toList(growable: false);
    } finally {
      bindings.allocator.free(requestPtr);
    }
  }

  static Map<String, dynamic> _trainingLogDatabaseSync({
    String date = '',
    String startDate = '',
    String endDate = '',
    required String mode,
  }) {
    final bindings = RustVideoBindings.open();
    final request = jsonEncode({
      'date': date,
      'startDate': startDate,
      'endDate': endDate,
    });
    final requestBytes = Uint8List.fromList(utf8.encode(request));
    final requestPtr = bindings.allocator.allocate(requestBytes);
    try {
      final buffer = switch (mode) {
        'read' => bindings.readTrainingLogJson(requestPtr, requestBytes.length),
        'delete' => bindings.deleteTrainingLogsJson(
          requestPtr,
          requestBytes.length,
        ),
        _ => bindings.trainingLogDatesJson(requestPtr, requestBytes.length),
      };
      return _decodeDbResponse(
        bindings,
        buffer,
        'training log database failed',
      );
    } finally {
      bindings.allocator.free(requestPtr);
    }
  }

  static Map<String, dynamic> _decodeDbResponse(
    RustVideoBindings bindings,
    RustVideoByteBuffer buffer,
    String fallbackError,
  ) {
    final jsonText = bindings.takeUtf8(buffer);
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Invalid database response');
    }
    if (decoded['ok'] != true) {
      throw StateError('${decoded['error'] ?? fallbackError}');
    }
    return decoded;
  }

  static AiModelClassesResult _aiModelClassesSync({
    required String pythonPath,
    required String modelPath,
  }) {
    final bindings = RustVideoBindings.open();
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
      final classes = <AiModelClass>[];
      final rawClasses = decoded['classes'];
      if (rawClasses is List) {
        for (final item in rawClasses) {
          if (item is Map) {
            classes.add(
              AiModelClass(
                id: (item['id'] as num?)?.toInt() ?? classes.length,
                name: '${item['name'] ?? 'class_${classes.length}'}',
              ),
            );
          }
        }
      }
      return AiModelClassesResult(
        task: '${decoded['task'] ?? 'detect'}',
        classes: classes,
      );
    } finally {
      bindings.allocator.free(requestPtr);
    }
  }

  static AiAnnotationResult _aiAnnotateImageSync({
    required String backend,
    required String pythonPath,
    required String modelPath,
    required String inputPath,
    required List<int> classIds,
    required double confThreshold,
    required double iouThreshold,
    required int imgsz,
    required String device,
    required String samMode,
    required String samPromptMode,
    required String promptsText,
    required String samClickPointsText,
    required String samPrecision,
    required String samEncoder,
    required int samImageBatchSize,
    required int samVideoBatchSize,
    required int samInteractiveBatchSize,
    required int samMaxImageWidth,
    required int samMaxImageHeight,
    required String samResizeMethod,
    required bool samCompile,
  }) {
    final bindings = RustVideoBindings.open();
    final request = jsonEncode({
      'backend': backend,
      'pythonPath': pythonPath,
      'modelPath': modelPath,
      'inputPath': inputPath,
      'classIdsCsv': classIds.join(','),
      'confThreshold': confThreshold,
      'iouThreshold': iouThreshold,
      'imgsz': imgsz,
      'device': device,
      'samMode': samMode,
      'samPromptMode': samPromptMode,
      'promptsText': promptsText,
      'samClickPointsText': samClickPointsText,
      'samPrecision': samPrecision,
      'samEncoder': samEncoder,
      'samImageBatchSize': samImageBatchSize,
      'samVideoBatchSize': samVideoBatchSize,
      'samInteractiveBatchSize': samInteractiveBatchSize,
      'samMaxImageWidth': samMaxImageWidth,
      'samMaxImageHeight': samMaxImageHeight,
      'samResizeMethod': samResizeMethod,
      'samCompile': samCompile,
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
      return AiAnnotationResult(
        inputPath: inputPath,
        width: (decoded['width'] as num?)?.toDouble() ?? 0,
        height: (decoded['height'] as num?)?.toDouble() ?? 0,
        boxes: _parseAiPredictionBoxes(decoded['boxes']),
        masks: _parseAiPredictionMasks(decoded['masks']),
      );
    } finally {
      bindings.allocator.free(requestPtr);
    }
  }

  static List<AiAnnotationResult> _aiAnnotateImagesSync({
    required String backend,
    required String pythonPath,
    required String modelPath,
    required List<String> inputPaths,
    required List<int> classIds,
    required double confThreshold,
    required double iouThreshold,
    required int imgsz,
    required String device,
    required String samMode,
    required String samPromptMode,
    required String promptsText,
    required String samClickPointsText,
    required int samPromptFrameIndex,
    required String samPrecision,
    required String samEncoder,
    required int samImageBatchSize,
    required int samVideoBatchSize,
    required int samInteractiveBatchSize,
    required int samMaxImageWidth,
    required int samMaxImageHeight,
    required String samResizeMethod,
    required bool samCompile,
  }) {
    final bindings = RustVideoBindings.open();
    final request = jsonEncode({
      'backend': backend,
      'pythonPath': pythonPath,
      'modelPath': modelPath,
      'inputPathsText': inputPaths.join('\n'),
      'classIdsCsv': classIds.join(','),
      'confThreshold': confThreshold,
      'iouThreshold': iouThreshold,
      'imgsz': imgsz,
      'device': device,
      'samMode': samMode,
      'samPromptMode': samPromptMode,
      'promptsText': promptsText,
      'samClickPointsText': samClickPointsText,
      'samPromptFrameIndex': samPromptFrameIndex,
      'samPrecision': samPrecision,
      'samEncoder': samEncoder,
      'samImageBatchSize': samImageBatchSize,
      'samVideoBatchSize': samVideoBatchSize,
      'samInteractiveBatchSize': samInteractiveBatchSize,
      'samMaxImageWidth': samMaxImageWidth,
      'samMaxImageHeight': samMaxImageHeight,
      'samResizeMethod': samResizeMethod,
      'samCompile': samCompile,
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
      final results = <AiAnnotationResult>[];
      final rawImages = decoded['images'];
      if (rawImages is List) {
        for (var index = 0; index < rawImages.length; index++) {
          final item = rawImages[index];
          if (item is Map) {
            results.add(
              AiAnnotationResult(
                inputPath:
                    '${item['inputPath'] ?? (index < inputPaths.length ? inputPaths[index] : '')}',
                width: (item['width'] as num?)?.toDouble() ?? 0,
                height: (item['height'] as num?)?.toDouble() ?? 0,
                boxes: _parseAiPredictionBoxes(item['boxes']),
                masks: _parseAiPredictionMasks(item['masks']),
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

  static List<AiPredictionBox> _parseAiPredictionBoxes(Object? rawBoxes) {
    final boxes = <AiPredictionBox>[];
    if (rawBoxes is List) {
      for (final item in rawBoxes) {
        if (item is Map) {
          boxes.add(
            AiPredictionBox(
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

  static List<AiPredictionMask> _parseAiPredictionMasks(Object? rawMasks) {
    final masks = <AiPredictionMask>[];
    if (rawMasks is List) {
      for (final item in rawMasks) {
        if (item is! Map) {
          continue;
        }
        final points = <Offset>[];
        final rawPoints = item['points'];
        if (rawPoints is List) {
          for (final rawPoint in rawPoints) {
            if (rawPoint is List && rawPoint.length >= 2) {
              points.add(
                Offset(
                  (rawPoint[0] as num?)?.toDouble() ?? 0,
                  (rawPoint[1] as num?)?.toDouble() ?? 0,
                ),
              );
            } else if (rawPoint is Map) {
              points.add(
                Offset(
                  (rawPoint['x'] as num?)?.toDouble() ?? 0,
                  (rawPoint['y'] as num?)?.toDouble() ?? 0,
                ),
              );
            }
          }
        }
        masks.add(
          AiPredictionMask(
            classId: (item['classId'] as num?)?.toInt() ?? 0,
            className: '${item['className'] ?? 'class'}',
            confidence: (item['confidence'] as num?)?.toDouble() ?? 0,
            points: points,
          ),
        );
      }
    }
    return masks;
  }
}
