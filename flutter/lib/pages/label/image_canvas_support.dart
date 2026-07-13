// =============================================================================
// image_canvas_support.dart - Canvas Support Types / 画布辅助类型
// =============================================================================
// Helper types for the image canvas: resize handles, segment vertex handles,
// cancel-draft intent, and sampled image data for crosshair color sampling.
//
// 画布辅助类型：调整手柄、分割顶点手柄、取消绘制 Intent 和十字准星颜色采样。
// =============================================================================

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

class SampledImage {
  const SampledImage({
    required this.image,
    required this.size,
    required this.bytes,
  });

  final ui.Image image;
  final Size size;
  final Uint8List bytes;
}

class CancelDraftIntent extends Intent {
  const CancelDraftIntent();
}

class ResizeHandle {
  const ResizeHandle(this.annotationId, this.cornerIndex);

  final String annotationId;
  final int cornerIndex;
}

class SegVertexHandle {
  const SegVertexHandle(this.annotationId, this.pointIndex);

  final String annotationId;
  final int pointIndex;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SegVertexHandle &&
          other.annotationId == annotationId &&
          other.pointIndex == pointIndex;

  @override
  int get hashCode => Object.hash(annotationId, pointIndex);
}
