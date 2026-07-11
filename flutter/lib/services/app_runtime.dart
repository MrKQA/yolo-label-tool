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
