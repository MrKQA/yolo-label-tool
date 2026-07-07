// Small support types for the label page image canvas.

part of '../../main.dart';

class _SampledImage {
  const _SampledImage({
    required this.image,
    required this.size,
    required this.bytes,
  });

  final ui.Image image;
  final Size size;
  final Uint8List bytes;
}

class _CancelDraftIntent extends Intent {
  const _CancelDraftIntent();
}

class _ResizeHandle {
  const _ResizeHandle(this.annotationId, this.cornerIndex);

  final String annotationId;
  final int cornerIndex;
}

class _SegVertexHandle {
  const _SegVertexHandle(this.annotationId, this.pointIndex);

  final String annotationId;
  final int pointIndex;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _SegVertexHandle &&
          other.annotationId == annotationId &&
          other.pointIndex == pointIndex;

  @override
  int get hashCode => Object.hash(annotationId, pointIndex);
}
