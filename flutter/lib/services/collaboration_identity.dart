// =============================================================================
// collaboration_identity.dart - Collaboration Identity Helpers / 协作身份工具
// =============================================================================
// Generates stable host/user identity IDs, short display labels, and
// deterministic color values for collaboration peers.
//
// 生成稳定的主机/用户身份 ID、短显示标签和协作节点颜色值。
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

String newCollaborationId(String prefix) {
  final millis = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final random = math.Random().nextInt(0xFFFFF).toRadixString(36);
  return '$prefix-$millis-$random';
}

String shortCollaborationId(String id) {
  final normalized = id.trim();
  if (normalized.length <= 6) {
    return normalized;
  }
  return normalized.substring(normalized.length - 6).toUpperCase();
}

String collaborationPeerIdFor(String hostId, String userId) {
  final normalizedHost = hostId.trim();
  final normalizedUser = userId.trim();
  if (normalizedHost.isEmpty) {
    return normalizedUser;
  }
  if (normalizedUser.isEmpty) {
    return normalizedHost;
  }
  return '$normalizedUser@$normalizedHost';
}

Color collaborationColorForId(String id) {
  var hash = 0;
  for (final unit in id.codeUnits) {
    hash = ((hash * 31) + unit) & 0x7FFFFFFF;
  }
  return HSLColor.fromAHSL(
    1,
    (hash % 360).toDouble(),
    0.68,
    0.48,
  ).toColor();
}
