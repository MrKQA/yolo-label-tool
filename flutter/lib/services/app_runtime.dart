// =============================================================================
// app_runtime.dart - Application Runtime Globals / 应用运行时全局状态
// =============================================================================
// Global singletons: theme mode notifier, application logger instance, and
// convenience log/logMultiline functions used across the entire app.
//
// 全局单例：主题模式通知器、应用日志实例和全局便捷日志函数。
// =============================================================================

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'config_store.dart';
import 'logger.dart';

final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
  ThemeMode.light,
);

final GlobalKey appThemeCaptureBoundaryKey = GlobalKey(
  debugLabel: 'app-theme-capture-boundary',
);

final ValueNotifier<AppThemeTransitionSnapshot?>
appThemeTransitionSnapshotNotifier = ValueNotifier<AppThemeTransitionSnapshot?>(
  null,
);

bool _themeCapturePending = false;
ThemeMode _requestedThemeMode = ThemeMode.light;

class AppThemeTransitionSnapshot {
  const AppThemeTransitionSnapshot({
    required this.image,
    required this.pixelRatio,
  });

  final ui.Image image;
  final double pixelRatio;
}

void initializeAppThemeMode(bool darkMode) {
  final mode = darkMode ? ThemeMode.dark : ThemeMode.light;
  _requestedThemeMode = mode;
  themeModeNotifier.value = mode;
}

void requestAppThemeMode(bool darkMode) {
  _requestedThemeMode = darkMode ? ThemeMode.dark : ThemeMode.light;
  if (_requestedThemeMode == themeModeNotifier.value) {
    return;
  }
  if (_themeCapturePending ||
      appThemeTransitionSnapshotNotifier.value != null) {
    themeModeNotifier.value = _requestedThemeMode;
    return;
  }
  unawaited(_applyRequestedThemeMode());
}

Future<void> _applyRequestedThemeMode() async {
  _themeCapturePending = true;
  AppThemeTransitionSnapshot? snapshot;
  try {
    final context = appThemeCaptureBoundaryKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (context != null &&
        renderObject is RenderRepaintBoundary &&
        !renderObject.debugNeedsPaint) {
      final devicePixelRatio = View.of(context).devicePixelRatio;
      final pixelRatio = devicePixelRatio.clamp(1.0, 1.5).toDouble();
      snapshot = AppThemeTransitionSnapshot(
        image: await renderObject.toImage(pixelRatio: pixelRatio),
        pixelRatio: pixelRatio,
      );
    }
  } on Object catch (error) {
    debugPrint('Theme transition capture failed: $error');
  } finally {
    _themeCapturePending = false;
  }

  final requestedMode = _requestedThemeMode;
  if (requestedMode == themeModeNotifier.value) {
    snapshot?.image.dispose();
    return;
  }
  if (snapshot != null) {
    appThemeTransitionSnapshotNotifier.value = snapshot;
  }
  themeModeNotifier.value = requestedMode;
}

void completeAppThemeTransition(AppThemeTransitionSnapshot snapshot) {
  if (identical(appThemeTransitionSnapshotNotifier.value, snapshot)) {
    appThemeTransitionSnapshotNotifier.value = null;
  }
  snapshot.image.dispose();
}

final AppLogger appLogger = AppLogger(
  persistLines: (lines) => ConfigStore.appendLogLines(lines.join('\n')),
);

void logApp(
  String tag,
  String message, {
  AppLogLevel level = AppLogLevel.info,
}) {
  appLogger.log(tag, message, level: level);
}

void logAppMultiline(
  String tag,
  String message, {
  AppLogLevel level = AppLogLevel.info,
  String prefix = '',
}) {
  appLogger.logMultiline(tag, message, level: level, prefix: prefix);
}

void flushAppLogs() => appLogger.flush();

void setAppLogLevel(AppLogLevel level, {bool writeLog = false}) {
  appLogger.setLevel(level, writeLog: writeLog);
}

AppLogLevel appLogLevelFromIndex(int index) {
  return AppLogLevel.values[index
      .clamp(0, AppLogLevel.values.length - 1)
      .toInt()];
}
