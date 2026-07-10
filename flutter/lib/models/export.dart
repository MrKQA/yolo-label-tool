class DatasetExportConfig {
  const DatasetExportConfig({
    required this.skipEmpty,
    required this.exportImages,
    required this.trainRatio,
    required this.valRatio,
    required this.testRatio,
    required this.folderName,
    required this.trainAfterExport,
  });

  final bool skipEmpty;
  final bool exportImages;
  final double trainRatio;
  final double valRatio;
  final double testRatio;
  final String folderName;
  final bool trainAfterExport;
}

class DatasetExportResult {
  const DatasetExportResult({
    required this.dataYamlPath,
    required this.outputPath,
    required this.imageCount,
    required this.annotationCount,
    required this.trainCount,
    required this.valCount,
    required this.testCount,
    required this.exportImages,
    required this.skipEmpty,
  });

  final String dataYamlPath;
  final String outputPath;
  final int imageCount;
  final int annotationCount;
  final int trainCount;
  final int valCount;
  final int testCount;
  final bool exportImages;
  final bool skipEmpty;
}

class YoloExportSettings {
  const YoloExportSettings({
    this.format = 'openvino',
    this.autoExportAfterTraining = false,
    this.imgsz = 640,
    this.batch = 1,
    this.quantize = '',
    this.dynamic = false,
    this.nms = false,
    this.dataPath = '',
    this.fraction = 1.0,
    this.device = '',
    this.simplify = true,
    this.opset = 0,
  });

  final String format;
  final bool autoExportAfterTraining;
  final int imgsz;
  final int batch;
  final String quantize;
  final bool dynamic;
  final bool nms;
  final String dataPath;
  final double fraction;
  final String device;
  final bool simplify;
  final int opset;

  YoloExportSettings copyWith({
    String? format,
    bool? autoExportAfterTraining,
    int? imgsz,
    int? batch,
    String? quantize,
    bool? dynamic,
    bool? nms,
    String? dataPath,
    double? fraction,
    String? device,
    bool? simplify,
    int? opset,
  }) {
    return YoloExportSettings(
      format: format ?? this.format,
      autoExportAfterTraining:
          autoExportAfterTraining ?? this.autoExportAfterTraining,
      imgsz: imgsz ?? this.imgsz,
      batch: batch ?? this.batch,
      quantize: quantize ?? this.quantize,
      dynamic: dynamic ?? this.dynamic,
      nms: nms ?? this.nms,
      dataPath: dataPath ?? this.dataPath,
      fraction: fraction ?? this.fraction,
      device: device ?? this.device,
      simplify: simplify ?? this.simplify,
      opset: opset ?? this.opset,
    );
  }

  Map<String, Object> toJson() => {
    'format': format,
    'autoExportAfterTraining': autoExportAfterTraining,
    'imgsz': imgsz,
    'batch': batch,
    'quantize': quantize,
    'dynamic': dynamic,
    'nms': nms,
    'dataPath': dataPath,
    'fraction': fraction,
    'device': device,
    'simplify': simplify,
    'opset': opset,
  };

  static YoloExportSettings fromJson(Object? value) {
    if (value is! Map) {
      return const YoloExportSettings();
    }
    final format = '${value['format'] ?? 'openvino'}'.toLowerCase();
    return YoloExportSettings(
      format: format == 'onnx' ? 'onnx' : 'openvino',
      autoExportAfterTraining: value['autoExportAfterTraining'] == true,
      imgsz: value['imgsz'] is num ? (value['imgsz'] as num).round() : 640,
      batch: value['batch'] is num ? (value['batch'] as num).round() : 1,
      quantize: value['quantize'] is String ? value['quantize'] as String : '',
      dynamic: value['dynamic'] == true,
      nms: value['nms'] == true,
      dataPath: value['dataPath'] is String ? value['dataPath'] as String : '',
      fraction: value['fraction'] is num
          ? (value['fraction'] as num).toDouble()
          : 1.0,
      device: value['device'] is String ? value['device'] as String : '',
      simplify: value['simplify'] != false,
      opset: value['opset'] is num ? (value['opset'] as num).round() : 0,
    );
  }
}
