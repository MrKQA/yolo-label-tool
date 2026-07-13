// =============================================================================
// image_size.dart - Image Size Computation / 图片尺寸计算
// =============================================================================
// Decodes image dimensions (width/height) from files while fitting into the
// annotation workspace dimensions, with optional error handling.
//
// 从文件解码图片宽高，按标注工作区尺寸缩放适配，支持错误处理回调。
// =============================================================================

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import '../theme/dimensions.dart' as dimensions;

typedef ImageSizeDecodeErrorHandler =
    void Function(String imagePath, Object error);

Future<Size> computeImageDisplaySizeForPath(
  String imagePath, {
  ImageSizeDecodeErrorHandler? onDecodeError,
}) async {
  try {
    final file = File(imagePath);
    final bytes = await file.readAsBytes();
    final codec = await instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    image.dispose();
    codec.dispose();
    if (w <= 0 || h <= 0) return const Size(1, 1);
    final scale = math.min(
      dimensions.annotationWorkspaceWidth / w,
      dimensions.annotationWorkspaceHeight / h,
    );
    return Size(w * scale, h * scale);
  } on Object catch (error) {
    onDecodeError?.call(imagePath, error);
    return const Size(1, 1);
  }
}
