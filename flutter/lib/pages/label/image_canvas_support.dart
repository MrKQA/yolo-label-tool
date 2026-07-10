// Small support types for the label page image canvas.

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
