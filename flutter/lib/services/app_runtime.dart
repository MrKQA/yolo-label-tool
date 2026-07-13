// =============================================================================
// app_runtime.dart - Application Runtime Globals / 应用运行时全局状态
// =============================================================================
// Global singletons: theme mode notifier, application logger instance, and
// convenience log/logMultiline functions used across the entire app.
//
// 全局单例：主题模式通知器、应用日志实例和全局便捷日志函数。
// =============================================================================

import 'package:flutter/material.dart';

import 'config_store.dart';
import 'logger.dart';

final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
  ThemeMode.light,
);

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
  return AppLogLevel
      .values[index.clamp(0, AppLogLevel.values.length - 1).toInt()];
}
