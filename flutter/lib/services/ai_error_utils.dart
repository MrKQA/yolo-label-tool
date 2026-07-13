// =============================================================================
// ai_error_utils.dart - AI Error Classification / AI 错误分类
// =============================================================================
// Classifies AI inference errors into categories (OOM, SAM3 resolution,
// missing modules, Python/Rust error, unknown) and extracts short user-readable
// messages from exception strings.
//
// 将 AI 推理错误分类为 OOM、SAM3 分辨率、模块缺失等类别，并提取用户可读的简短消息。
// =============================================================================

String classifyAiFailure(Object error) {
  final text = error.toString().toLowerCase();
  if (text.contains('out of memory') ||
      text.contains('cuda oom') ||
      text.contains('cublas_status_alloc_failed') ||
      text.contains('memoryerror')) {
    return 'oom';
  }
  if (text.contains('assertionerror') &&
      (text.contains('reshape_for_broadcast') ||
          text.contains('apply_rotary_enc'))) {
    return 'sam3-resolution';
  }
  if (text.contains('modulenotfounderror') ||
      text.contains('no module named') ||
      text.contains('dependency import failed')) {
    return 'dependency';
  }
  if (text.contains('sam3') && text.contains('click')) {
    return 'sam3-click-prompt';
  }
  if (text.contains('python start') || text.contains('python path')) {
    return 'python';
  }
  return 'runtime';
}

String shortAiError(Object error) {
  final normalized = error
      .toString()
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => 'unknown error');
  return normalized.length > 180
      ? '${normalized.substring(0, 180)}...'
      : normalized;
}
