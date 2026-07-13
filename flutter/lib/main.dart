// =============================================================================
// main.dart - Application Entry Point / 应用入口
// =============================================================================
// Initializes the Rust backend, loads localized strings, registers platform
// plugins, and launches the Flutter app.
//
// 初始化 Rust 后端、加载本地化字符串、注册平台插件并启动 Flutter 应用。
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:video_player_win/video_player_win.dart' as video_player_win;

import 'app.dart';
import 'services/app_runtime.dart';
import 'services/config_store.dart';
import 'services/i18n.dart';
import 'services/rust_library_loader.dart';
import 'src/rust/frb_generated.dart';

String? _rustBackendInitError;
const RustLibraryLoader _rustLibraryLoader = RustLibraryLoader();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    video_player_win.WindowsVideoPlayer.registerWith();
  }
  setCurrentLanguageStrings(
    await AppLanguageStrings.load(appDefaultLanguageCode),
  );
  await _initializeRustBackend();
  ConfigStore.ensureDefaultConfig();
  initializeAppThemeMode(ConfigStore.loadSettings().darkMode);
  runApp(const YoloLabelApp());
}

Future<void> _initializeRustBackend() async {
  try {
    final externalLibrary = _openRustLibrary();
    if (externalLibrary == null) {
      throw StateError(
        _rustBackendInitError ?? 'yolo_label_bridge.dll was not found',
      );
    }
    await RustLib.init(externalLibrary: externalLibrary);
    _rustBackendInitError = null;
  } on Object catch (error) {
    _rustBackendInitError = '$error';
    debugPrint('Rust backend init failed: $error');
  }
}

ExternalLibrary? _openRustLibrary() {
  final result = _rustLibraryLoader.openLibrary();
  _rustBackendInitError = result.error;
  return result.library;
}
