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
      _freeByteBuffer = library
          .lookupFunction<_FreeByteBufferNative, _FreeByteBufferDart>(
            'rust_label_free_byte_buffer',
          );

  final _WindowsHeapAllocator allocator;
  final _VideoInfoJsonDart videoInfoJson;
  final _DecodeVideoFrameDart decodeVideoFramePng;
  final _DetectJsonDart detectJson;
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
