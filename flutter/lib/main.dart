import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:video_player_win/video_player_win.dart' as video_player_win;

import 'src/rust/api.dart';
import 'src/rust/frb_generated.dart';
import 'dialogs/about_dialog.dart';
import 'dialogs/color_picker_dialog.dart';
import 'dialogs/export_dialog.dart';
import 'dialogs/log_viewer_dialog.dart';
import 'dialogs/sam3_runtime_dialog.dart';
import 'dialogs/settings_dialog.dart';
import 'dialogs/shortcut_dialog.dart';
import 'dialogs/training_history_dialog.dart';
import 'dialogs/yolo_export_settings_dialog.dart';
import 'models/ai_assist.dart';
import 'models/annotation.dart';
import 'models/config.dart';
import 'models/detection.dart';
import 'models/export.dart';
import 'models/imported_dataset.dart';
import 'models/shortcut.dart';
import 'models/training.dart';
import 'pages/crop_page.dart';
import 'pages/database_page.dart';
import 'pages/label/image_canvas_support.dart';
import 'pages/label/ai_toolbar.dart';
import 'pages/label/annotation_list_panel.dart';
import 'pages/label/bottom_controls.dart';
import 'pages/label/class_manager.dart';
import 'pages/label/image_preview_pane.dart';
import 'pages/label/viewport_pan_button.dart';
import 'services/ai_error_utils.dart';
import 'services/ai_geometry.dart';
import 'services/collection_utils.dart';
import 'services/collaboration_codec.dart';
import 'services/config_store.dart';
import 'services/export_dataset.dart';
import 'services/i18n.dart';
import 'services/input_utils.dart';
import 'services/image_size.dart';
import 'services/import_dataset.dart';
import 'services/logger.dart';
import 'services/path_utils.dart';
import 'services/python_environment.dart';
import 'services/rust_backend.dart';
import 'services/rust_library_loader.dart';
import 'services/training_dataset_summary.dart';
import 'theme/colors.dart' as colors;
import 'theme/dimensions.dart' as dimensions;
import 'theme/theme_helpers.dart' as theme_helpers;
import 'widgets/common/floating_message.dart';
import 'widgets/common/overlays.dart';
import 'widgets/database/database_detail_widgets.dart';
import 'widgets/database/database_sidebar.dart';
import 'widgets/database/database_table_panel.dart';
import 'widgets/detect/detect_support.dart';
import 'widgets/label/canvas_grid_painter.dart';
import 'widgets/label/tool_spec.dart';
import 'widgets/train/dataset_summary_panel.dart';
import 'widgets/train/train_runtime_support.dart';
import 'widgets/train/training_parameter_panel.dart';
import 'widgets/train/training_progress_panel.dart';

part 'app.dart';
part 'pages/label_page.dart';
part 'pages/label/canvas_stage.dart';
part 'pages/train_page.dart';
part 'pages/detect_video_page.dart';
part 'pages/collaboration_page.dart';
part 'services/annotation_database_codec.dart';
part 'widgets/common/navigation.dart';
part 'widgets/common/workspace_annotation_actions.dart';
part 'widgets/common/workspace_collaboration_actions.dart';
part 'widgets/common/workspace_export_actions.dart';
part 'widgets/common/workspace_settings_actions.dart';
part 'widgets/common/workspace_shell.dart';
part 'widgets/detect/detect_panels.dart';
part 'widgets/detect/detect_playback_surface.dart';
part 'widgets/detect/prediction_sequence.dart';
part 'widgets/detect/video_player_widgets.dart';
part 'widgets/label/ai_assist_panel.dart';

const _brandColor = colors.appBrandColor;
const _darkBrandColor = colors.appDarkBrandColor;
const _workspaceBackground = colors.appWorkspaceBackground;
const _darkAppBackground = colors.appDarkAppBackground;
const _darkPanelBackground = colors.appDarkPanelBackground;
const _darkControlBackground = colors.appDarkControlBackground;
const _darkBorderColor = colors.appDarkBorderColor;
const _darkTextColor = colors.appDarkTextColor;
const _annotationWorkspaceWidth = dimensions.annotationWorkspaceWidth;
const _annotationWorkspaceHeight = dimensions.annotationWorkspaceHeight;
const _toolbarWidth = dimensions.toolbarWidth;
const _topMenuHeight = dimensions.topMenuHeight;
const _topMenuCollapsedHeight = dimensions.topMenuCollapsedHeight;
const _topMenuAutoHideDelay = dimensions.topMenuAutoHideDelay;
const _bottomBarHeight = dimensions.bottomBarHeight;
const _paneHeaderHeight = dimensions.paneHeaderHeight;
const _expandedSidebarWidth = dimensions.expandedSidebarWidth;
const _collapsedSidebarWidth = dimensions.collapsedSidebarWidth;
const _aiAssistPanelMinWidth = dimensions.aiAssistPanelMinWidth;
const _aiAssistPanelMinHeight = dimensions.aiAssistPanelMinHeight;
const _aiAssistPanelMaxWidth = dimensions.aiAssistPanelMaxWidth;
const _aiAssistPanelMaxHeight = dimensions.aiAssistPanelMaxHeight;
const _aiAssistPanelMargin = dimensions.aiAssistPanelMargin;
const _recentMenuVisibleCount = 5;
const _languageCode = appDefaultLanguageCode;

const _labelColorPalette = colors.labelColorPalette;

String _newCollaborationId(String prefix) {
  final millis = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final random = math.Random().nextInt(0xFFFFF).toRadixString(36);
  return '$prefix-$millis-$random';
}

String _shortCollaborationId(String id) {
  final normalized = id.trim();
  if (normalized.length <= 6) {
    return normalized;
  }
  return normalized.substring(normalized.length - 6).toUpperCase();
}

String _collaborationPeerIdFor(String hostId, String userId) {
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

Color _collaborationColorForId(String id) {
  var hash = 0;
  for (final unit in id.codeUnits) {
    hash = ((hash * 31) + unit) & 0x7FFFFFFF;
  }
  return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.68, 0.48).toColor();
}

final ValueNotifier<ThemeMode> _themeModeNotifier = ValueNotifier(
  ThemeMode.light,
);

String? _rustBackendInitError;
const RustLibraryLoader _rustLibraryLoader = RustLibraryLoader();

const _imageTypeGroup = XTypeGroup(
  label: 'Images',
  extensions: ['jpg', 'jpeg', 'png', 'bmp', 'webp'],
);
const _yamlTypeGroup = XTypeGroup(label: 'YAML', extensions: ['yaml', 'yml']);


// Logging
// Logs are written to logs/app/ with date-based filenames.
enum _LogLevel { debug, info, warning, error }

_LogLevel _logLevel = _LogLevel.warning;
final AppLogger _appLogger = AppLogger(
  persistLines: (lines) => ConfigStore.appendLogLines(lines.join('\n')),
);

void _log(String tag, String message, {_LogLevel level = _LogLevel.info}) {
  _appLogger.log(tag, message, level: _toAppLogLevel(level));
}

void _logMultiline(
  String tag,
  String message, {
  _LogLevel level = _LogLevel.info,
  String prefix = '',
}) {
  _appLogger.logMultiline(
    tag,
    message,
    level: _toAppLogLevel(level),
    prefix: prefix,
  );
}

void _flushLogs() {
  _appLogger.flush();
}

void _setLogLevel(_LogLevel level, {bool writeLog = false}) {
  _logLevel = level;
  _appLogger.setLevel(_toAppLogLevel(level), writeLog: writeLog);
}

_LogLevel _logLevelFromIndex(int index) {
  return _LogLevel.values[index.clamp(0, _LogLevel.values.length - 1)];
}

AppLogLevel _toAppLogLevel(_LogLevel level) {
  return AppLogLevel.values[level.index];
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    video_player_win.WindowsVideoPlayer.registerWith();
  }
  setCurrentLanguageStrings(await AppLanguageStrings.load(_languageCode));
  await _initializeRustBackend();
  ConfigStore.ensureDefaultConfig();
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

bool _isDarkMode(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color _panelColor(BuildContext context) =>
    theme_helpers.appPanelColor(_isDarkMode(context));

Color _controlColor(BuildContext context) =>
    theme_helpers.appControlColor(_isDarkMode(context));

Color _canvasColor(BuildContext context) =>
    theme_helpers.appCanvasColor(_isDarkMode(context));

Color _workspaceColor(BuildContext context) =>
    theme_helpers.appWorkspaceColor(_isDarkMode(context));

Color _borderColor(BuildContext context) =>
    theme_helpers.appBorderColor(_isDarkMode(context));

Color _primaryTextColor(BuildContext context) =>
    theme_helpers.appTextColor(_isDarkMode(context));
