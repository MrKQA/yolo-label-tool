// =============================================================================
// logger.dart - Application Logging System / 应用日志系统
// =============================================================================
// Configurable log levels (debug/info/warning/error), deferred persistence
// via ConfigStore, and convenience helpers for tagged multi-line logging.
//
// 可配置日志级别，通过 ConfigStore 延迟持久化，支持带标签的多行日志。
// =============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

enum AppLogLevel { debug, info, warning, error }

typedef AppLogPersist = void Function(List<String> lines);

class AppLogger {
  AppLogger({
    required this.persistLines,
    void Function(String line)? printLine,
    this.flushDelay = const Duration(seconds: 3),
    this.minLevel = AppLogLevel.warning,
  }) : printLine = printLine ?? _defaultPrintLine;

  final AppLogPersist persistLines;
  final void Function(String line) printLine;
  final Duration flushDelay;

  AppLogLevel minLevel;
  final List<String> _pendingLines = [];
  Timer? _flushTimer;

  void log(String tag, String message, {AppLogLevel level = AppLogLevel.info}) {
    if (level.index < minLevel.index) {
      return;
    }
    _appendLine(tag, message, level: level);
  }

  void logMultiline(
    String tag,
    String message, {
    AppLogLevel level = AppLogLevel.info,
    String prefix = '',
  }) {
    if (level.index < minLevel.index) {
      return;
    }
    final normalized = message.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    for (final line in normalized.split('\n')) {
      _appendLine(tag, '$prefix$line', level: level);
    }
  }

  void setLevel(AppLogLevel level, {bool writeLog = false}) {
    minLevel = level;
    if (writeLog) {
      log('LOG', 'Log level set to ${level.name}', level: AppLogLevel.info);
    }
  }

  void flush() {
    if (_pendingLines.isEmpty) {
      return;
    }
    try {
      persistLines(List<String>.unmodifiable(_pendingLines));
      _pendingLines.clear();
    } on Object {
      // Keep pending lines for the next flush attempt.
    }
  }

  void dispose() {
    _flushTimer?.cancel();
    flush();
  }

  void _appendLine(String tag, String message, {required AppLogLevel level}) {
    final ts = DateTime.now()
        .toIso8601String()
        .substring(0, 19)
        .replaceAll('T', ' ');
    final line = '[$ts] [${level.name.toUpperCase()}] [$tag] $message';
    printLine(line);
    _pendingLines.add(line);
    _flushTimer?.cancel();
    _flushTimer = Timer(flushDelay, flush);
  }
}

void _defaultPrintLine(String line) => debugPrint(line);
