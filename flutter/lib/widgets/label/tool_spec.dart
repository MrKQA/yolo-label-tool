// =============================================================================
// tool_spec.dart - Annotation Tool Specs / 标注工具定义
// =============================================================================
// Defines the available annotation tools (select, box/obb/seg draw, copy,
// paste, undo, redo, delete, export) with icon and label metadata.
//
// 定义标注工具列表（选择、框选/旋转框/分割绘制、复制、粘贴、撤销、重做等）。
// =============================================================================

import 'package:flutter/widgets.dart';

class ToolSpec {
  const ToolSpec(this.id, this.icon, this.label);

  final String id;
  final IconData icon;
  final String label;
}
