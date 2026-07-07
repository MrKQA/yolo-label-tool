part of '../main.dart';

Future<Size> _computeImageDisplaySizeForPath(String imagePath) async {
  try {
    final file = File(imagePath);
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    image.dispose();
    codec.dispose();
    if (w <= 0 || h <= 0) return const Size(1, 1);
    final scale = math.min(
      _annotationWorkspaceWidth / w,
      _annotationWorkspaceHeight / h,
    );
    return Size(w * scale, h * scale);
  } on Object catch (error) {
    _log(
      'LABEL',
      'Image size decode failed: $imagePath, error=$error',
      level: _LogLevel.warning,
    );
    return const Size(1, 1);
  }
}
