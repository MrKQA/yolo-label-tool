// =============================================================================
// rust_ffi.dart - Rust FFI Bindings / Rust FFI 底层绑定
// =============================================================================
// Raw FFI bindings to yolo_label_bridge.dll: function typedefs, dynamic library
// lookup, RustVideoBindings class, and WindowsHeapAllocator for cross-boundary
// memory management.
//
// yolo_label_bridge.dll 的原始 FFI 绑定：函数 typedef、动态库查找、
// RustVideoBindings 类和跨边界内存管理的 WindowsHeapAllocator。
// =============================================================================

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'rust_library_loader.dart';

final class RustVideoByteBuffer extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> ptr;

  @ffi.IntPtr()
  external int len;

  @ffi.IntPtr()
  external int cap;
}

typedef _VideoInfoJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef VideoInfoJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);

typedef _DecodeVideoFrameNative =
    RustVideoByteBuffer Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.IntPtr,
      ffi.Double,
      ffi.Uint32,
    );
typedef DecodeVideoFrameDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int, double, int);
typedef _DetectJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef DetectJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DetectModelTaskJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef DetectModelTaskJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef AiModelClassesJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef AiModelClassesJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _ExportModelJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef ExportModelJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _AiAnnotateImageJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef AiAnnotateImageJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _AiAnnotateImagesJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef AiAnnotateImagesJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _PreloadYoloPythonJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef PreloadYoloPythonJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _TrainingLogTailJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef TrainingLogTailJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _TrainingResourceUsageJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef TrainingResourceUsageJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _ShutdownPythonJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef ShutdownPythonJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DbSaveSnapshotJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef DbSaveSnapshotJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DbLoadSnapshotJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef DbLoadSnapshotJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DbSaveConfigJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef DbSaveConfigJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DbLoadConfigJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef DbLoadConfigJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DbDeleteConfigJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef DbDeleteConfigJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DbAppendLogsJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef DbAppendLogsJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DbLogDatesJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef DbLogDatesJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DbReadLogsJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef DbReadLogsJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DbDeleteLogsJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef DbDeleteLogsJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DbOverviewJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef DbOverviewJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DbTableJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef DbTableJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DbSqlQueryJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef DbSqlQueryJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _TrainingLogDatesJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef TrainingLogDatesJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _ReadTrainingLogJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef ReadTrainingLogJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _DeleteTrainingLogsJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef DeleteTrainingLogsJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _CollabCommandJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef CollabCommandJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);
typedef _CollabPollJsonNative =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef CollabPollJsonDart =
    RustVideoByteBuffer Function(ffi.Pointer<ffi.Uint8>, int);

typedef _FreeByteBufferNative = ffi.Void Function(RustVideoByteBuffer);
typedef FreeByteBufferDart = void Function(RustVideoByteBuffer);

class RustVideoBindings {
  RustVideoBindings._(ffi.DynamicLibrary library)
    : allocator = WindowsHeapAllocator(),
      videoInfoJson = library
          .lookupFunction<_VideoInfoJsonNative, VideoInfoJsonDart>(
            'rust_label_video_info_json',
          ),
      decodeVideoFramePng = library
          .lookupFunction<_DecodeVideoFrameNative, DecodeVideoFrameDart>(
            'rust_label_decode_video_frame_png',
          ),
      detectJson = library.lookupFunction<_DetectJsonNative, DetectJsonDart>(
        'rust_label_detect_json',
      ),
      detectModelTaskJson = library
          .lookupFunction<_DetectModelTaskJsonNative, DetectModelTaskJsonDart>(
            'rust_label_detect_model_task_json',
          ),
      aiModelClassesJson = library
          .lookupFunction<AiModelClassesJsonNative, AiModelClassesJsonDart>(
            'rust_label_ai_model_classes_json',
          ),
      exportModelJson = library
          .lookupFunction<_ExportModelJsonNative, ExportModelJsonDart>(
            'rust_label_export_model_json',
          ),
      aiAnnotateImageJson = library
          .lookupFunction<_AiAnnotateImageJsonNative, AiAnnotateImageJsonDart>(
            'rust_label_ai_annotate_image_json',
          ),
      aiAnnotateImagesJson = library
          .lookupFunction<
            _AiAnnotateImagesJsonNative,
            AiAnnotateImagesJsonDart
          >('rust_label_ai_annotate_images_json'),
      preloadYoloPythonJson = library
          .lookupFunction<
            _PreloadYoloPythonJsonNative,
            PreloadYoloPythonJsonDart
          >('rust_label_preload_yolo_python_json'),
      trainingLogTailJson = library
          .lookupFunction<_TrainingLogTailJsonNative, TrainingLogTailJsonDart>(
            'rust_label_training_log_tail_json',
          ),
      trainingResourceUsageJson = library
          .lookupFunction<
            _TrainingResourceUsageJsonNative,
            TrainingResourceUsageJsonDart
          >('rust_label_training_resource_usage_json'),
      shutdownPythonJson = library
          .lookupFunction<_ShutdownPythonJsonNative, ShutdownPythonJsonDart>(
            'rust_label_shutdown_python_json',
          ),
      dbSaveSnapshotJson = library
          .lookupFunction<_DbSaveSnapshotJsonNative, DbSaveSnapshotJsonDart>(
            'rust_label_db_save_snapshot_json',
          ),
      dbLoadSnapshotJson = library
          .lookupFunction<_DbLoadSnapshotJsonNative, DbLoadSnapshotJsonDart>(
            'rust_label_db_load_snapshot_json',
          ),
      dbSaveConfigJson = library
          .lookupFunction<_DbSaveConfigJsonNative, DbSaveConfigJsonDart>(
            'rust_label_db_save_config_json',
          ),
      dbLoadConfigJson = library
          .lookupFunction<_DbLoadConfigJsonNative, DbLoadConfigJsonDart>(
            'rust_label_db_load_config_json',
          ),
      dbDeleteConfigJson = library
          .lookupFunction<_DbDeleteConfigJsonNative, DbDeleteConfigJsonDart>(
            'rust_label_db_delete_config_json',
          ),
      dbAppendLogsJson = library
          .lookupFunction<_DbAppendLogsJsonNative, DbAppendLogsJsonDart>(
            'rust_label_db_append_logs_json',
          ),
      dbLogDatesJson = library
          .lookupFunction<_DbLogDatesJsonNative, DbLogDatesJsonDart>(
            'rust_label_db_log_dates_json',
          ),
      dbReadLogsJson = library
          .lookupFunction<_DbReadLogsJsonNative, DbReadLogsJsonDart>(
            'rust_label_db_read_logs_json',
          ),
      dbDeleteLogsJson = library
          .lookupFunction<_DbDeleteLogsJsonNative, DbDeleteLogsJsonDart>(
            'rust_label_db_delete_logs_json',
          ),
      dbOverviewJson = library
          .lookupFunction<_DbOverviewJsonNative, DbOverviewJsonDart>(
            'rust_label_db_overview_json',
          ),
      dbTableJson = library
          .lookupFunction<_DbTableJsonNative, DbTableJsonDart>(
            'rust_label_db_table_json',
          ),
      dbSqlQueryJson = library
          .lookupFunction<_DbSqlQueryJsonNative, DbSqlQueryJsonDart>(
            'rust_label_db_sql_query_json',
          ),
      trainingLogDatesJson = library
          .lookupFunction<
            _TrainingLogDatesJsonNative,
            TrainingLogDatesJsonDart
          >('rust_label_training_log_dates_json'),
      readTrainingLogJson = library
          .lookupFunction<_ReadTrainingLogJsonNative, ReadTrainingLogJsonDart>(
            'rust_label_read_training_log_json',
          ),
      deleteTrainingLogsJson = library
          .lookupFunction<
            _DeleteTrainingLogsJsonNative,
            DeleteTrainingLogsJsonDart
          >('rust_label_delete_training_logs_json'),
      collabCommandJson = library
          .lookupFunction<_CollabCommandJsonNative, CollabCommandJsonDart>(
            'rust_label_collab_command_json',
          ),
      collabPollJson = library
          .lookupFunction<_CollabPollJsonNative, CollabPollJsonDart>(
            'rust_label_collab_poll_json',
          ),
      _freeByteBuffer = library
          .lookupFunction<_FreeByteBufferNative, FreeByteBufferDart>(
            'rust_label_free_byte_buffer',
          );

  final WindowsHeapAllocator allocator;
  final VideoInfoJsonDart videoInfoJson;
  final DecodeVideoFrameDart decodeVideoFramePng;
  final DetectJsonDart detectJson;
  final DetectModelTaskJsonDart detectModelTaskJson;
  final AiModelClassesJsonDart aiModelClassesJson;
  final ExportModelJsonDart exportModelJson;
  final AiAnnotateImageJsonDart aiAnnotateImageJson;
  final AiAnnotateImagesJsonDart aiAnnotateImagesJson;
  final PreloadYoloPythonJsonDart preloadYoloPythonJson;
  final TrainingLogTailJsonDart trainingLogTailJson;
  final TrainingResourceUsageJsonDart trainingResourceUsageJson;
  final ShutdownPythonJsonDart shutdownPythonJson;
  final DbSaveSnapshotJsonDart dbSaveSnapshotJson;
  final DbLoadSnapshotJsonDart dbLoadSnapshotJson;
  final DbSaveConfigJsonDart dbSaveConfigJson;
  final DbLoadConfigJsonDart dbLoadConfigJson;
  final DbDeleteConfigJsonDart dbDeleteConfigJson;
  final DbAppendLogsJsonDart dbAppendLogsJson;
  final DbLogDatesJsonDart dbLogDatesJson;
  final DbReadLogsJsonDart dbReadLogsJson;
  final DbDeleteLogsJsonDart dbDeleteLogsJson;
  final DbOverviewJsonDart dbOverviewJson;
  final DbTableJsonDart dbTableJson;
  final DbSqlQueryJsonDart dbSqlQueryJson;
  final TrainingLogDatesJsonDart trainingLogDatesJson;
  final ReadTrainingLogJsonDart readTrainingLogJson;
  final DeleteTrainingLogsJsonDart deleteTrainingLogsJson;
  final CollabCommandJsonDart collabCommandJson;
  final CollabPollJsonDart collabPollJson;
  final FreeByteBufferDart _freeByteBuffer;

  static RustVideoBindings open() {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'Rust video backend is currently wired for Windows',
      );
    }
    for (final path in const RustLibraryLoader().libraryCandidates()) {
      if (File(path).existsSync()) {
        return RustVideoBindings._(ffi.DynamicLibrary.open(path));
      }
    }
    throw StateError('yolo_label_bridge.dll was not found');
  }

  Uint8List takeBytes(RustVideoByteBuffer buffer) {
    if (buffer.ptr == ffi.nullptr || buffer.len <= 0) {
      return Uint8List(0);
    }
    try {
      return Uint8List.fromList(buffer.ptr.asTypedList(buffer.len));
    } finally {
      _freeByteBuffer(buffer);
    }
  }

  String takeUtf8(RustVideoByteBuffer buffer) {
    final bytes = takeBytes(buffer);
    if (bytes.isEmpty) {
      return '';
    }
    return utf8.decode(bytes);
  }
}

typedef _GetProcessHeapNative = ffi.Pointer<ffi.Void> Function();
typedef GetProcessHeapDart = ffi.Pointer<ffi.Void> Function();

typedef _HeapAllocNative =
    ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<ffi.Void>,
      ffi.Uint32,
      ffi.IntPtr,
    );
typedef HeapAllocDart =
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, int, int);

typedef _HeapFreeNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Uint32,
      ffi.Pointer<ffi.Void>,
    );
typedef HeapFreeDart =
    int Function(ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Void>);

class WindowsHeapAllocator {
  WindowsHeapAllocator()
    : _kernel32 = ffi.DynamicLibrary.open('kernel32.dll') {
    _getProcessHeap = _kernel32
        .lookupFunction<_GetProcessHeapNative, GetProcessHeapDart>(
          'GetProcessHeap',
        );
    _heapAlloc = _kernel32.lookupFunction<_HeapAllocNative, HeapAllocDart>(
      'HeapAlloc',
    );
    _heapFree = _kernel32.lookupFunction<_HeapFreeNative, HeapFreeDart>(
      'HeapFree',
    );
    _heap = _getProcessHeap();
  }

  final ffi.DynamicLibrary _kernel32;
  late final GetProcessHeapDart _getProcessHeap;
  late final HeapAllocDart _heapAlloc;
  late final HeapFreeDart _heapFree;
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
