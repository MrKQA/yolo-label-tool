part of '../main.dart';

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
typedef _ExportModelJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _ExportModelJsonDart =
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
typedef _TrainingResourceUsageJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _TrainingResourceUsageJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _ShutdownPythonJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _ShutdownPythonJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DbSaveSnapshotJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _DbSaveSnapshotJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DbLoadSnapshotJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _DbLoadSnapshotJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DbSaveConfigJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _DbSaveConfigJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DbLoadConfigJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _DbLoadConfigJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DbDeleteConfigJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _DbDeleteConfigJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DbAppendLogsJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _DbAppendLogsJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DbLogDatesJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _DbLogDatesJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DbReadLogsJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _DbReadLogsJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DbDeleteLogsJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _DbDeleteLogsJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DbOverviewJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _DbOverviewJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DbTableJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _DbTableJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DbSqlQueryJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _DbSqlQueryJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _TrainingLogDatesJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _TrainingLogDatesJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _ReadTrainingLogJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _ReadTrainingLogJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DeleteTrainingLogsJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _DeleteTrainingLogsJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _CollabCommandJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _CollabCommandJsonDart =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _CollabPollJsonNative =
    _RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _CollabPollJsonDart =
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
      exportModelJson = library
          .lookupFunction<_ExportModelJsonNative, _ExportModelJsonDart>(
            'rust_label_export_model_json',
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
      trainingResourceUsageJson = library
          .lookupFunction<
            _TrainingResourceUsageJsonNative,
            _TrainingResourceUsageJsonDart
          >('rust_label_training_resource_usage_json'),
      shutdownPythonJson = library
          .lookupFunction<_ShutdownPythonJsonNative, _ShutdownPythonJsonDart>(
            'rust_label_shutdown_python_json',
          ),
      dbSaveSnapshotJson = library
          .lookupFunction<_DbSaveSnapshotJsonNative, _DbSaveSnapshotJsonDart>(
            'rust_label_db_save_snapshot_json',
          ),
      dbLoadSnapshotJson = library
          .lookupFunction<_DbLoadSnapshotJsonNative, _DbLoadSnapshotJsonDart>(
            'rust_label_db_load_snapshot_json',
          ),
      dbSaveConfigJson = library
          .lookupFunction<_DbSaveConfigJsonNative, _DbSaveConfigJsonDart>(
            'rust_label_db_save_config_json',
          ),
      dbLoadConfigJson = library
          .lookupFunction<_DbLoadConfigJsonNative, _DbLoadConfigJsonDart>(
            'rust_label_db_load_config_json',
          ),
      dbDeleteConfigJson = library
          .lookupFunction<_DbDeleteConfigJsonNative, _DbDeleteConfigJsonDart>(
            'rust_label_db_delete_config_json',
          ),
      dbAppendLogsJson = library
          .lookupFunction<_DbAppendLogsJsonNative, _DbAppendLogsJsonDart>(
            'rust_label_db_append_logs_json',
          ),
      dbLogDatesJson = library
          .lookupFunction<_DbLogDatesJsonNative, _DbLogDatesJsonDart>(
            'rust_label_db_log_dates_json',
          ),
      dbReadLogsJson = library
          .lookupFunction<_DbReadLogsJsonNative, _DbReadLogsJsonDart>(
            'rust_label_db_read_logs_json',
          ),
      dbDeleteLogsJson = library
          .lookupFunction<_DbDeleteLogsJsonNative, _DbDeleteLogsJsonDart>(
            'rust_label_db_delete_logs_json',
          ),
      dbOverviewJson = library
          .lookupFunction<_DbOverviewJsonNative, _DbOverviewJsonDart>(
            'rust_label_db_overview_json',
          ),
      dbTableJson = library
          .lookupFunction<_DbTableJsonNative, _DbTableJsonDart>(
            'rust_label_db_table_json',
          ),
      dbSqlQueryJson = library
          .lookupFunction<_DbSqlQueryJsonNative, _DbSqlQueryJsonDart>(
            'rust_label_db_sql_query_json',
          ),
      trainingLogDatesJson = library
          .lookupFunction<
            _TrainingLogDatesJsonNative,
            _TrainingLogDatesJsonDart
          >('rust_label_training_log_dates_json'),
      readTrainingLogJson = library
          .lookupFunction<_ReadTrainingLogJsonNative, _ReadTrainingLogJsonDart>(
            'rust_label_read_training_log_json',
          ),
      deleteTrainingLogsJson = library
          .lookupFunction<
            _DeleteTrainingLogsJsonNative,
            _DeleteTrainingLogsJsonDart
          >('rust_label_delete_training_logs_json'),
      collabCommandJson = library
          .lookupFunction<_CollabCommandJsonNative, _CollabCommandJsonDart>(
            'rust_label_collab_command_json',
          ),
      collabPollJson = library
          .lookupFunction<_CollabPollJsonNative, _CollabPollJsonDart>(
            'rust_label_collab_poll_json',
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
  final _ExportModelJsonDart exportModelJson;
  final _AiAnnotateImageJsonDart aiAnnotateImageJson;
  final _AiAnnotateImagesJsonDart aiAnnotateImagesJson;
  final _PreloadYoloPythonJsonDart preloadYoloPythonJson;
  final _TrainingLogTailJsonDart trainingLogTailJson;
  final _TrainingResourceUsageJsonDart trainingResourceUsageJson;
  final _ShutdownPythonJsonDart shutdownPythonJson;
  final _DbSaveSnapshotJsonDart dbSaveSnapshotJson;
  final _DbLoadSnapshotJsonDart dbLoadSnapshotJson;
  final _DbSaveConfigJsonDart dbSaveConfigJson;
  final _DbLoadConfigJsonDart dbLoadConfigJson;
  final _DbDeleteConfigJsonDart dbDeleteConfigJson;
  final _DbAppendLogsJsonDart dbAppendLogsJson;
  final _DbLogDatesJsonDart dbLogDatesJson;
  final _DbReadLogsJsonDart dbReadLogsJson;
  final _DbDeleteLogsJsonDart dbDeleteLogsJson;
  final _DbOverviewJsonDart dbOverviewJson;
  final _DbTableJsonDart dbTableJson;
  final _DbSqlQueryJsonDart dbSqlQueryJson;
  final _TrainingLogDatesJsonDart trainingLogDatesJson;
  final _ReadTrainingLogJsonDart readTrainingLogJson;
  final _DeleteTrainingLogsJsonDart deleteTrainingLogsJson;
  final _CollabCommandJsonDart collabCommandJson;
  final _CollabPollJsonDart collabPollJson;
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
