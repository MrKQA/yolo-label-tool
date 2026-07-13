// =============================================================================
// app_status.dart - Rust Bridge Status Model / Rust 桥接状态模型
// =============================================================================
// Simple value object carrying the Rust backend greeting and supported
// annotation mode flags from the native bridge initialization.
//
// 从 Rust 桥接初始化中获取的后端问候语和所支持的标注模式标志。
// =============================================================================

class BridgeStatus {
  const BridgeStatus({required this.greeting, required this.modes});

  final String greeting;
  final List<String> modes;
}
