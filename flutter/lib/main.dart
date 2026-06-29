import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:video_player_win/video_player_win.dart' as video_player_win;

import 'src/rust/api.dart';
import 'src/rust/api/training_mod.dart' show TrainingProgress;
import 'src/rust/frb_generated.dart';

part 'LabelPage.dart';
part 'TrainPage.dart';
part 'DetectVideoPage.dart';
part 'RustVideoBackend.dart';
part 'ExportDialog.dart';
part 'CropPage.dart';
part 'DatabasePage.dart';
part 'CollaborationPage.dart';
part 'AnnotationModels.dart';
part 'ConfigStore.dart';
part 'FloatingMessage.dart';
part 'SettingsDialog.dart';
part 'ShortcutModels.dart';

const _brandColor = Color(0xFF2563EB);
const _darkBrandColor = Color(0xFF8B7CFF);
const _panelBorderColor = Color(0xFFE5E7EB);
const _workspaceBackground = Color(0xFFF8FAFC);
const _darkAppBackground = Color(0xFF140B2A);
const _darkWorkspaceBackground = Color(0xFF1A1035);
const _darkPanelBackground = Color(0xFF241544);
const _darkControlBackground = Color(0xFF30205A);
const _darkCanvasBackground = Color(0xFF1D1438);
const _darkBorderColor = Color(0xFF6D5BD0);
const _darkTextColor = Color(0xFFF8F7FF);
const _mutedLightTextColor = Color(0xFF334155);
const _previewPaneWidth = 188.0;
const _previewPaneMinWidth = 128.0;
const _annotationWorkspaceWidth = 960.0;
const _annotationWorkspaceHeight = 620.0;
const _toolbarWidth = 184.0;
const _topMenuHeight = 42.0;
const _topMenuCollapsedHeight = 6.0;
const _topMenuAutoHideDelay = Duration(seconds: 3);
const _bottomBarHeight = 80.0;
const _paneHeaderHeight = 52.0;
const _previewPaneHeaderHeight = 64.0;
const _expandedSidebarWidth = 112.0;
const _collapsedSidebarWidth = 56.0;
const _aiAssistPanelMinWidth = 320.0;
const _aiAssistPanelMinHeight = 360.0;
const _aiAssistPanelMaxWidth = 640.0;
const _aiAssistPanelMaxHeight = 760.0;
const _aiAssistPanelMargin = 12.0;
const _recentHistoryLimit = 20;
const _recentMenuVisibleCount = 5;
const _fontFamily = 'Microsoft YaHei';
const _languageCode = 'zh_cn';
const _languageAssetDirectory = 'lib/language';

const _labelColorPalette = [
  Color(0xFF2563EB),
  Color(0xFFDC2626),
  Color(0xFF16A34A),
  Color(0xFF9333EA),
  Color(0xFFEA580C),
  Color(0xFF0891B2),
  Color(0xFFDB2777),
  Color(0xFF4F46E5),
  Color(0xFF65A30D),
  Color(0xFFB45309),
];

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

bool _rustBackendAvailable = false;
String? _rustBackendInitError;

_LanguageStrings _appText = _LanguageStrings.fallback();
final ValueNotifier<_LanguageStrings> _languageStringsNotifier = ValueNotifier(
  _appText,
);

const _imageTypeGroup = XTypeGroup(
  label: 'Images',
  extensions: ['jpg', 'jpeg', 'png', 'bmp', 'gif', 'webp'],
);
const _yamlTypeGroup = XTypeGroup(label: 'YAML', extensions: ['yaml', 'yml']);
const _datasetSplits = ['train', 'val', 'test'];

const _imageExtensions = {'jpg', 'jpeg', 'png', 'bmp', 'gif', 'webp'};

// Logging / 日志系统
// Logs are written to logs/app/ with date-based filenames.
// 日志写入 logs/app/ 目录，按日期分文件。
enum _LogLevel { debug, info, warning, error }

_LogLevel _logLevel = _LogLevel.warning;
final List<String> _pendingLogs = [];
Timer? _logFlushTimer;

void _log(String tag, String message, {_LogLevel level = _LogLevel.info}) {
  if (level.index < _logLevel.index) return;
  _appendLogLine(tag, message, level: level);
}

void _logMultiline(
  String tag,
  String message, {
  _LogLevel level = _LogLevel.info,
  String prefix = '',
}) {
  if (level.index < _logLevel.index) return;
  final normalized = message.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  for (final line in lines) {
    _appendLogLine(tag, '$prefix$line', level: level);
  }
}

void _appendLogLine(String tag, String message, {required _LogLevel level}) {
  final ts = DateTime.now()
      .toIso8601String()
      .substring(0, 19)
      .replaceAll('T', ' ');
  final line = '[$ts] [${level.name.toUpperCase()}] [$tag] $message';
  debugPrint(line);
  _pendingLogs.add(line);
  _logFlushTimer?.cancel();
  _logFlushTimer = Timer(const Duration(seconds: 3), _flushLogs);
}

void _flushLogs() {
  if (_pendingLogs.isEmpty) return;
  try {
    _ConfigStore.appendLogLines(_pendingLogs.join('\n'));
    _pendingLogs.clear();
  } on Object {
    // silently ignore write failures / 写入失败静默忽略
  }
}

void _setLogLevel(_LogLevel level, {bool writeLog = false}) {
  _logLevel = level;
  if (writeLog) {
    _log('LOG', 'Log level set to ${level.name}', level: _LogLevel.info);
  }
}

_LogLevel _logLevelFromIndex(int index) {
  return _LogLevel.values[index.clamp(0, _LogLevel.values.length - 1)];
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    video_player_win.WindowsVideoPlayer.registerWith();
  }
  _appText = await _LanguageStrings.load(_languageCode);
  _languageStringsNotifier.value = _appText;
  await _initializeRustBackend();
  _ConfigStore.ensureDefaultConfig();
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
    _rustBackendAvailable = true;
    _rustBackendInitError = null;
  } on Object catch (error) {
    _rustBackendAvailable = false;
    _rustBackendInitError = '$error';
    debugPrint('Rust backend init failed: $error');
  }
}

ExternalLibrary? _openRustLibrary() {
  if (!Platform.isWindows) {
    return null;
  }
  Object? lastError;
  for (final path in _rustLibraryCandidates()) {
    if (File(path).existsSync()) {
      try {
        return ExternalLibrary.open(path);
      } on Object catch (error) {
        lastError = error;
        debugPrint('Failed to open Rust backend $path: $error');
      }
    }
  }
  if (lastError != null) {
    _rustBackendInitError = '$lastError';
  }
  return null;
}

String _rustBackendUnavailableMessage(String feature) {
  final detail = _rustBackendInitError?.trim();
  if (detail == null || detail.isEmpty) {
    return '$feature不可用：Rust/Python 后端未初始化';
  }
  return '$feature不可用：Rust/Python 后端初始化失败，$detail';
}

List<String> _rustLibraryCandidates() {
  final executableDirectory = File(Platform.resolvedExecutable).parent.path;
  final current = Directory.current.path;
  final currentParent = Directory.current.parent.path;
  final candidates = [
    '$executableDirectory\\yolo_label_bridge.dll',
    '$current\\yolo_label_bridge.dll',
    '$current\\target\\release\\yolo_label_bridge.dll',
    '$current\\target\\debug\\yolo_label_bridge.dll',
    '$currentParent\\target\\release\\yolo_label_bridge.dll',
    '$currentParent\\target\\debug\\yolo_label_bridge.dll',
  ];
  return _dedupePaths(candidates);
}

String t(String key) => _appText.text(key);

class _LanguageStrings {
  const _LanguageStrings(this._values);

  factory _LanguageStrings.fallback() => const _LanguageStrings(_fallback);

  final Map<String, String> _values;

  String text(String key) => _values[key] ?? _fallback[key] ?? key;

  static Future<_LanguageStrings> load(String code) async {
    try {
      final source = await rootBundle.loadString(
        '$_languageAssetDirectory/$code.json',
      );
      final decoded = jsonDecode(source);
      if (decoded is! Map) {
        return _LanguageStrings.fallback();
      }
      return _LanguageStrings(
        decoded.map((key, value) => MapEntry(key.toString(), value.toString())),
      );
    } on Object {
      return _LanguageStrings.fallback();
    }
  }

  static const _fallback = {
    'app.title': 'YOLO Label Tool',
    'language.name': '简体中文',
    'app.bridgeError': 'Rust bridge failed',
    'menu.file': '文件',
    'menu.edit': '编辑',
    'menu.settings': '设置',
    'menu.help': '说明',
    'menu.viewLogs': '查看日志',
    'menu.openFile': '打开文件',
    'menu.openFolder': '打开文件夹',
    'menu.openRecent': '打开最近的文件',
    'menu.exit': '退出',
    'menu.undo': '撤销',
    'menu.restore': '恢复',
    'menu.copy': '复制',
    'menu.paste': '粘贴',
    'menu.redo': '重做',
    'menu.resetZoom': '重置缩放',
    'menu.shortcutHelp': '快捷键说明',
    'menu.about': '关于',
    'about.title': '关于 YOLO Label Tool',
    'about.version': '版本 0.1.0',
    'about.licenseTitle': 'LICENSE 说明',
    'about.licenseBody':
        '本项目使用 GNU General Public License v3.0（GPLv3）开源协议，具体权利与义务以仓库根目录 LICENSE 文件为准。复制、修改、分发或二次发布本软件时，请遵守 GPLv3 的源代码开放、版权声明和协议继承要求。',
    'about.opensourceTitle': '开源初衷',
    'about.opensourceBody':
        '本工具用于学习、研究和改进 YOLO 数据标注、训练、预测与辅助标注流程，降低本地视觉数据处理门槛，也方便开发者审查实现、复现实验并共同改进。',
    'about.warningTitle': '侵权与合规警告',
    'about.warningBody':
        '请仅处理你拥有合法权利或已获授权的数据、模型、图片、视频和标注结果。禁止将本工具用于侵犯版权、肖像权、隐私权、商业秘密、数据集许可或模型许可的行为；由用户导入、训练、导出、发布或商用产生的法律责任由用户自行承担。',
    'settings.language': '语言',
    'settings.preferences': '首选项',
    'settings.clearCache': '清空缓存',
    'settings.title': '设置',
    'settings.configPath': '配置数据库',
    'settings.pythonPath': 'Python 环境路径',
    'settings.outputPath': '训练结果保存位置',
    'settings.choosePython': '选择 Python',
    'settings.chooseFolder': '选择文件夹',
    'settings.pythonChecking': '正在识别 Python 环境...',
    'settings.pythonValid': 'Python 环境识别成功',
    'settings.pythonNotFound': '未找到 python.exe，请选择 Python 环境文件夹或 python.exe',
    'settings.pythonInvalid': 'Python 环境识别失败，请确认已安装 torch',
    'settings.pythonTimeout': 'Python 环境识别超时',
    'path.model': '模型路径',
    'path.trainingOutput': '训练结果路径',
    'settings.cacheSize': '当前缓存大小',
    'settings.clearCacheConfirm': '确认清空历史、类别和临时标注数据？',
    'settings.saved': '设置已保存',
    'recent.noFolders': '暂无最近文件夹',
    'recent.noFiles': '暂无最近文件',
    'recent.moreFolders': '更多文件夹',
    'recent.moreFiles': '更多文件',
    'recent.moreOptions': '更多选项',
    'recent.clear': '清除最近打开的...',
    'recent.missingFolder': '文件夹不存在，已从历史记录移除',
    'recent.missingFile': '文件不存在，已从历史记录移除',
    'context.addImage': '添加图片',
    'context.deleteImage': '删除图片',
    'context.rotateLeft': '逆时针旋转',
    'context.rotateRight': '顺时针旋转',
    'sidebar.label': '标注',
    'sidebar.train': '训练',
    'sidebar.browse': '浏览',
    'sidebar.database': '数据库',
    'sidebar.expand': '展开侧边栏',
    'sidebar.collapse': '收起侧边栏',
    'label.previewEmpty': '右键或菜单添加图片',
    'label.previewFilterAll': '全部',
    'label.previewFilterUnlabeled': '未标注',
    'label.workspace': '标注工作区',
    'label.openPrompt': '请打开文件或文件夹',
    'label.imageError': '图片无法预览',
    'label.ai': 'AI',
    'label.annotations': '标注',
    'label.showTools': '显示工具',
    'label.showAnnotations': '显示标注列表',
    'label.noAnnotations': '暂无标注',
    'label.classes': '类别',
    'label.addClass': '添加类别',
    'label.editClass': '编辑类别',
    'label.deleteClass': '删除类别',
    'label.className': '类别名称',
    'label.classColor': '类别颜色',
    'label.noClasses': '暂无类别',
    'label.createClassPrompt': '请先创建一个类别',
    'label.saveAnnotation': '完成',
    'label.cancelAnnotation': '取消',
    'label.hideNames': '隐藏类别名',
    'label.showNames': '显示类别名',
    'label.drawMode': '绘制',
    'label.selectMode': '选择',
    'tool.select': '选择',
    'tool.box': '框选',
    'tool.copy': '复制',
    'tool.paste': '粘贴',
    'tool.undo': '撤销',
    'tool.redo': '重做',
    'tool.delete': '删除',
    'feedback.copiedAnnotation': '已复制标注框',
    'import.waiting': '请等待导入完成',
    'bottom.zoomOut': '缩小',
    'bottom.lockZoom': '锁定缩放',
    'bottom.zoomIn': '放大',
    'bottom.reset': '重置',
    'bottom.dayMode': '白天模式',
    'bottom.nightMode': '夜间模式',
    'bottom.shortcuts': '自定义按键',
    'shortcut.title': '自定义按键',
    'shortcut.previousImage': '上一张图片',
    'shortcut.nextImage': '下一张图片',
    'shortcut.zoomIn': '放大图片',
    'shortcut.zoomOut': '缩小图片',
    'shortcut.hbbMode': 'HBB 标注框',
    'shortcut.obbMode': 'OBB 旋转框',
    'shortcut.segMode': 'SEG 实例分割',
    'shortcut.deleteSelected': '删除选中标注',
    'shortcut.hideClassLabels': '显示/隐藏类别名',
    'shortcut.rotateObbLeft5': 'OBB 逆时针 5°',
    'shortcut.rotateObbLeft1': 'OBB 逆时针 1°',
    'shortcut.rotateObbRight1': 'OBB 顺时针 1°',
    'shortcut.rotateObbRight5': 'OBB 顺时针 5°',
    'shortcut.browsePreviousMedia': '浏览上一媒体',
    'shortcut.browseNextMedia': '浏览下一媒体',
    'shortcut.browseFullscreen': '浏览全屏',
    'shortcut.browseVolumeUp': '浏览音量增加',
    'shortcut.browseVolumeDown': '浏览音量降低',
    'shortcut.videoPlayPause': '视频播放 / 暂停',
    'shortcut.videoRewind': '视频回退',
    'shortcut.videoFastForward': '视频三倍速快进',
    'shortcut.aiAnnotateCurrent': '当前 AI 标注',
    'shortcut.aiAnnotateAll': '所有 AI 标注',
    'shortcut.scopeGlobal': '全局',
    'shortcut.scopeLabel': '标注页面',
    'shortcut.scopeBrowse': '浏览页面',
    'shortcut.scopeTrain': '训练页面',
    'shortcut.noItems': '暂无可配置快捷键',
    'shortcut.normalGroup': '普通功能',
    'shortcut.aiGroup': 'AI 功能',
    'shortcut.note': '鼠标滚轮缩放、右键图片添加/删除保持固定。',
    'shortcut.waiting': '按下键盘...',
    'ai.configTitle': 'AI 辅助标注配置',
    'ai.chooseModel': '选择模型',
    'ai.noModel': '未选择模型',
    'ai.onnxNotSupported': 'ONNX 模型暂未适配，请先选择 PT 模型',
    'ai.readClassesFailed': '读取模型类别失败',
    'ai.chooseModelFirst': '请先选择模型',
    'ai.classes': '参与辅助标注的类别',
    'ai.selectAllClasses': '全选类别',
    'ai.confidence': '置信度',
    'ai.startImageIndex': '图片索引',
    'ai.endImageIndex': '图片索引',
    'ai.annotateCurrent': '当前图片单次标注',
    'ai.annotateAll': '按索引全部标注',
    'ai.noSelectedClasses': '请至少选择一个类别',
    'ai.sam3PromptText': '文本提示词',
    'ai.sam3PromptClick': '点击',
    'ai.sam3PromptLabel': '文本提示词',
    'ai.sam3PromptHint': '每行一个目标，例如 mask 或 person',
    'ai.sam3ClickHint': '点击模式仅用于标注页面交互：左键添加目标点，右键添加排除点。',
    'ai.sam3PromptRequired': '请先输入 SAM3 文本提示词',
    'ai.sam3RuntimeConfig': 'SAM3 低显存配置',
    'ai.sam3Precision': '精度',
    'ai.sam3Encoder': '编码器',
    'ai.sam3BatchImage': '图片 batch',
    'ai.sam3BatchVideo': '视频 batch',
    'ai.sam3BatchInteractive': '交互 batch',
    'ai.sam3MaxWidth': '预缩放宽度',
    'ai.sam3MaxHeight': '预缩放高度',
    'ai.sam3ResizeMethod': '缩放方式',
    'ai.sam3ResizeShorterSide': 'shorter_side',
    'ai.annotating': 'AI 辅助标注中...',
    'ai.done': 'AI 标注完成',
    'ai.failed': 'AI 标注失败',
    'train.title': '训练',
    'train.parameters': '超参数',
    'train.chooseModel': '选择 PT 模型',
    'train.refreshModels': '刷新模型',
    'train.chooseDataset': '选择数据集',
    'train.loadingDataset': '请等待数据集统计完成',
    'train.datasetLoadFailed': '数据集统计失败',
    'train.start': '开始训练',
    'train.stop': '停止',
    'train.stopping': '停止中',
    'train.continueTraining': '继续训练',
    'train.startFailed': '训练启动失败',
    'train.pythonNotConfigured': '请先在设置中配置 Python 环境路径',
    'train.datasetPath': '数据集路径',
    'train.invalidModel': '模型文件异常，请选择 YOLO PT 模型。',
    'train.noModels': 'models 文件夹中没有可用的 YOLO PT 模型。',
    'train.datasetSummaryEmpty': '请选择 data.yaml 后显示 classes、train、val 数量。',
    'train.classes': '类别',
    'train.trainCount': 'train 数量',
    'train.valCount': 'val 数量',
    'train.testCount': 'test 数量',
    'train.imbalanceRatio': '类别不均衡比例',
    'train.clsPwAuto': '自动 cls_pw',
    'train.resume': '恢复中断训练',
    'train.resumeAvailable': '可恢复训练',
    'train.resumeNoCheckpoint': '未找到 last.pt',
    'train.resumeInvalidLayout': 'last.pt 不在 weights 目录中',
    'train.resumeNoResults': '未找到 results.csv',
    'train.resumeUnknownProgress': '无法读取训练进度',
    'train.resumeDataMismatch': 'last.pt 对应的数据集与当前 data.yaml 不一致',
    'train.resumeAlreadyDone': '该训练记录看起来已经完成',
    'train.commandPreview': '训练命令',
    'train.currentEpoch': '当前轮次',
    'train.notStarted': '未开始',
    'train.historyTitle': '最近训练记录',
    'train.historyStart': '开始',
    'train.historyResume': '继续',
    'train.historyStop': '停止',
    'train.historyTimePoint': '时间点',
    'train.coreParameters': '核心参数',
    'train.batchFixed': '固定批次',
    'train.batchAuto60': '自动 60%',
    'train.batchRatio': '显存比例',
    'train.batchAuto60Help': '将传递 batch=-1，由 Ultralytics 自动选择约 60% CUDA 显存利用率。',
    'train.noGpuDetected': '未检测到 NVIDIA GPU，当前使用 CPU。',
    'train.tuningTitle': '调参说明',
    'train.tuningTips':
        '提升 YOLO 训练效果通常先检查数据质量和标注一致性，再调整 imgsz、batch、lr0、momentum 与增强参数。batch 越大梯度越稳定但更占显存；lr0 控制初始学习速度；momentum 控制更新惯性；imgsz 越大越利于小目标但训练更慢。',
    'train.chartPlaceholder': '训练开始后显示 loss、mAP、precision、recall 等曲线。',
    'train.chart': '曲线',
    'train.terminal': '终端',
    'train.terminalPlaceholder': '训练终端输出会显示在这里。',
    'logs.title': '日志查看',
    'logs.openFolder': '打开日志文件夹',
    'logs.date': '日期',
    'logs.noLogs': '暂无日志',
    'logs.readFailed': '日志读取失败',
    'logs.deleteRange': '删除日志',
    'logs.deleted': '已删除日志',
    'logs.selectDeleteRange': '选择要删除的日期范围',
    'database.title': '数据库管理',
    'database.refresh': '刷新',
    'database.overview': '数据库概览',
    'database.path': '文件位置',
    'database.size': '文件大小',
    'database.tables': '数据表',
    'database.appLogs': '应用日志',
    'database.trainingTerminal': '训练终端',
    'database.configKeys': '配置键',
    'database.updatedAt': '更新时间',
    'database.noConfigKeys': '暂无配置键',
    'database.noTrainingLogs': '暂无训练终端记录',
    'database.projects': '项目',
    'database.allProjects': '全部项目',
    'database.rows': '行数',
    'database.rowsPerPage': '行',
    'database.page': '页',
    'database.previousPage': '上一页',
    'database.nextPage': '下一页',
    'database.noRows': '暂无数据',
    'database.selectRow': '选择一行查看详情',
    'database.rowDetail': '行详情',
    'database.projectFilter': '项目',
    'database.imageFilter': '图片',
    'database.viewImageAnnotations': '查看该图片标注',
    'database.clearImageFilter': '清除图片过滤',
    'database.cleanedImages': '清理缺失图片',
    'database.cleanedProjects': '清理空项目',
    'database.browse': '浏览',
    'database.structure': '结构',
    'database.sql': 'SQL',
    'database.sqlResult': 'SQL 查询结果',
    'database.runSql': '运行 SQL',
    'database.sqlHelp': '仅允许只读 SELECT/WITH 和查看结构的 PRAGMA 语句。',
    'database.sqlRows': '返回行数',
    'database.truncated': '结果已截断',
    'database.virtualTable': '虚拟表，不直接存在于 AnnotationConfig.db',
    'database.table.projects': 'projects',
    'database.table.images': 'images',
    'database.table.classes': 'classes',
    'database.table.annotations': 'annotations',
    'database.table.app_config': 'app_config',
    'database.table.app_logs': 'app_logs',
    'database.table.training_terminal_logs': 'training_terminal_logs',
    'detect.title': '浏览 / 视频检测',
    'detect.chooseImage': '选择图片',
    'detect.chooseFile': '选择文件',
    'detect.chooseFolder': '选择文件夹',
    'detect.playVideo': '播放视频',
    'detect.predictVideo': '预测视频',
    'detect.predictAll': '全部',
    'detect.saveResult': '保存结果',
    'detect.saveCurrent': '单次保存',
    'detect.saveAll': '全部保存',
    'detect.predict': '预测',
    'detect.chooseModel': '选择模型',
    'detect.resetEffect': '重置效果',
    'detect.parameters': '预测参数',
    'detect.actions': '操作',
    'detect.inferenceParams': '推理参数',
    'detect.predicting': '预测中',
    'detect.predictingFrame': '预测中...',
    'detect.noImageTargets': '没有可预测的图片',
    'detect.showOriginal': '查看原图',
    'detect.showPredicted': '查看预测',
    'detect.imgsz': '尺寸',
    'detect.conf': '置信度',
    'detect.device': '设备',
    'detect.deviceAuto': '自动',
    'detect.deviceNvUnavailable': '未检测到 NVIDIA 显卡',
    'detect.deviceCpu': 'CPU',
    'detect.deviceHelp':
        '自动会优先使用 NVIDIA CUDA，检测不到或预测失败会回退 CPU，并显示当前自动选择的硬件；中间项显示检测到的 NVIDIA 显卡型号；CPU 只使用处理器。',
    'detect.pythonNotConfigured': '请先在设置中配置 Python 环境路径',
    'detect.detectDone': '预测完成',
    'detect.saveDone': '保存完成',
    'detect.detectFailed': '预测失败',
    'detect.detectCount': '目标数',
    'detect.model': '检测模型',
    'detect.fileName': '文件名',
    'detect.paused': '已暂停',
    'detect.playing': '播放中',
    'detect.resultVisible': '显示预测结果',
    'detect.resultHidden': '隐藏预测结果',
    'detect.clickToggleResult': '点击显示区域切换预测结果显示。',
    'detect.placeholder': '检测结果、视频播放和预测导出将在这里显示。',
    'detect.loadingVideo': '正在加载视频',
    'detect.videoBackend': '视频后端',
    'detect.decodeFailed': '视频解码失败',
    'detect.hudFullscreen': '全屏',
    'detect.hudExitFullscreen': '退出全屏',
    'detect.hudPrevious': '上一项',
    'detect.hudNext': '下一项',
    'detect.hudNoPrevious': '前面已经没有了~',
    'detect.hudNoNext': '后面已经没有了~',
    'detect.hudVolume': '音量',
    'detect.speed': '速度',
    'detect.scaleMode': '画面模式',
    'detect.scaleAuto': '自动',
    'detect.scale4x3': '4:3',
    'detect.scale16x9': '16:9',
    'detect.scaleFitWidth': '等宽',
    'detect.scaleFitHeight': '等高',
    'detect.scaleOriginal': '原始',
    'detect.volumeWheelHint': '鼠标滚轮调节音量',
    'action.reset': '重置',
    'action.close': '关闭',
    'action.save': '保存',
    'action.cancel': '取消',
    'action.delete': '删除',
    'action.clear': '清空',
  };
}

class _LanguageOption {
  const _LanguageOption({required this.code, required this.label});

  final String code;
  final String label;

  static Future<List<_LanguageOption>> loadAvailable() async {
    final codes = await _loadLanguageCodes();
    final options = <_LanguageOption>[];
    for (final code in codes) {
      final strings = await _LanguageStrings.load(code);
      final label = strings.text('language.name');
      options.add(_LanguageOption(code: code, label: label));
    }
    options.sort((a, b) => _naturalCompare(a.label, b.label));
    return options;
  }

  static Future<List<String>> _loadLanguageCodes() async {
    final codes = <String>{};
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      _addLanguageCodesFromPaths(codes, manifest.listAssets());
    } on Object {
      try {
        final source = await rootBundle.loadString('AssetManifest.json');
        final decoded = jsonDecode(source);
        if (decoded is Map) {
          _addLanguageCodesFromPaths(codes, decoded.keys.map((key) => '$key'));
        }
      } on Object {
        // Keep the default language when the asset manifest is unavailable.
      }
    }
    if (codes.isEmpty) {
      codes.add(_languageCode);
    }
    return codes.toList()..sort(_naturalCompare);
  }

  static void _addLanguageCodesFromPaths(
    Set<String> codes,
    Iterable<String> paths,
  ) {
    const prefix = '$_languageAssetDirectory/';
    for (final path in paths) {
      if (!path.startsWith(prefix) || !path.endsWith('.json')) {
        continue;
      }
      final filename = path.substring(prefix.length);
      codes.add(filename.substring(0, filename.length - '.json'.length));
    }
  }
}

bool _isDarkMode(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color _panelColor(BuildContext context) =>
    _isDarkMode(context) ? _darkPanelBackground : Colors.white;

Color _controlColor(BuildContext context) =>
    _isDarkMode(context) ? _darkControlBackground : Colors.white;

Color _canvasColor(BuildContext context) =>
    _isDarkMode(context) ? _darkCanvasBackground : Colors.white;

Color _workspaceColor(BuildContext context) =>
    _isDarkMode(context) ? _darkWorkspaceBackground : _workspaceBackground;

Color _borderColor(BuildContext context) =>
    _isDarkMode(context) ? _darkBorderColor : _panelBorderColor;

Color _primaryTextColor(BuildContext context) =>
    _isDarkMode(context) ? _darkTextColor : _mutedLightTextColor;

class YoloLabelApp extends StatelessWidget {
  const YoloLabelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_LanguageStrings>(
      valueListenable: _languageStringsNotifier,
      builder: (context, language, _) {
        _appText = language;
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: _themeModeNotifier,
          builder: (context, themeMode, _) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              title: t('app.title'),
              themeMode: themeMode,
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(seedColor: _brandColor),
                fontFamily: _fontFamily,
                scaffoldBackgroundColor: _workspaceBackground,
                useMaterial3: true,
              ),
              darkTheme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: _darkBrandColor,
                  brightness: Brightness.dark,
                ),
                brightness: Brightness.dark,
                fontFamily: _fontFamily,
                scaffoldBackgroundColor: _darkAppBackground,
                dialogTheme: const DialogThemeData(
                  backgroundColor: _darkPanelBackground,
                  titleTextStyle: TextStyle(
                    color: _darkTextColor,
                    fontFamily: _fontFamily,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                dividerTheme: const DividerThemeData(color: _darkBorderColor),
                menuTheme: const MenuThemeData(
                  style: MenuStyle(
                    backgroundColor: WidgetStatePropertyAll(
                      _darkPanelBackground,
                    ),
                    surfaceTintColor: WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                  ),
                ),
                outlinedButtonTheme: OutlinedButtonThemeData(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _darkControlBackground,
                    foregroundColor: _darkTextColor,
                    side: const BorderSide(color: _darkBorderColor),
                  ),
                ),
                textButtonTheme: TextButtonThemeData(
                  style: TextButton.styleFrom(foregroundColor: _darkBrandColor),
                ),
                useMaterial3: true,
              ),
              home: const HomePage(),
            );
          },
        );
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final Future<_BridgeStatus> _status = _loadStatus();

  Future<_BridgeStatus> _loadStatus() async {
    final greeting = await rustGreeting(name: 'Flutter');
    final modes = await supportedAnnotationModes();
    return _BridgeStatus(greeting: greeting, modes: modes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<_BridgeStatus>(
        future: _status,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SelectableText(
                  '${t('app.bridgeError')}:\n${snapshot.error}',
                ),
              ),
            );
          }

          return _WorkspaceShell(status: snapshot.data!);
        },
      ),
    );
  }
}

class _BridgeStatus {
  const _BridgeStatus({required this.greeting, required this.modes});

  final String greeting;
  final List<String> modes;
}

class _WorkspaceShell extends StatefulWidget {
  const _WorkspaceShell({required this.status});

  final _BridgeStatus status;

  @override
  State<_WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<_WorkspaceShell> {
  final FocusNode _keyboardFocusNode = FocusNode(debugLabel: 'workspace');
  final _DetectVideoSession _detectVideoSession = _DetectVideoSession();
  final GlobalKey<_TrainPageState> _trainPageKey = GlobalKey<_TrainPageState>();
  Timer? _topMenuHideTimer;
  Timer? _databaseSaveTimer;
  Timer? _labelResumeSaveTimer;
  Timer? _collaborationPollTimer;

  final List<_ImageItem> _images = [];
  final List<_RecentEntry> _recentFolders = [];
  final List<_RecentEntry> _recentFiles = [];
  final List<_LabelClass> _labelClasses = [];
  final Map<String, List<_AnnotationRegion>> _annotationsByImage = {};
  final Map<String, String> _imageSplits = {};
  final List<List<_AnnotationRegion>> _undoStack = [];
  final List<List<_AnnotationRegion>> _redoStack = [];
  List<_LanguageOption> _languageOptions = const [
    _LanguageOption(code: _languageCode, label: '简体中文'),
  ];

  bool _sidebarCollapsed = false;
  bool _darkMode = false;
  bool _shortcutDialogOpen = false;
  bool _importingDataset = false;
  bool _databaseApplying = false;
  bool _topMenuVisible = true;
  bool _videoFullscreenVisible = false;
  bool _zoomLocked = false;
  String _pythonPreloadInFlightPath = '';
  String _preloadedPythonPath = '';
  double _zoom = 100;
  Offset _labelViewportOffset = Offset.zero;
  int _selectedImageIndex = 0;
  String _activeSection = 'label';
  String _activeTool = 'select';
  String _activeLanguageCode = _languageCode;
  String? _selectedAnnotationId;
  bool _showClassLabels = true;
  bool _aiPanelVisible = false;
  int? _activeClassId;
  int _classSerial = 1;
  int _annotationSerial = 1;
  _AnnotationMode _activeAnnotationMode = _AnnotationMode.hbb;
  _AnnotationRegion? _copiedAnnotation;
  Size? _imageDisplaySize;
  final Map<String, Size> _imageDisplaySizes = {};
  _ShortcutConfig _shortcutConfig = _ShortcutConfig.defaults();
  _AppSettings _appSettings = _AppSettings.empty();
  _ImportedDataset? _importedDataset;
  _AiAssistConfig? _aiAssistConfig;
  bool _aiAnnotating = false;
  final Map<String, List<_Sam3ClickPromptPoint>> _sam3ClickPromptsByImage = {};
  final Map<String, Set<String>> _sam3ClickAnnotationIdsByImage = {};
  Offset? _aiAssistPanelOffset;
  Size _aiAssistPanelSize = const Size(320, 360);
  _CollaborationMode _collaborationMode = _CollaborationMode.off;
  String _collaborationHostId = _newCollaborationId('host');
  String _collaborationUserId = _newCollaborationId('user');
  String _collaborationUserName =
      Platform.environment['USERNAME']?.trim().isNotEmpty == true
      ? Platform.environment['USERNAME']!.trim()
      : 'User';
  int _collaborationPort = 8765;
  int _collaborationStartIndex = 1;
  int _collaborationEndIndex = 1;
  _CollaborationPermissions _collaborationSelfPermissions =
      const _CollaborationPermissions();
  final List<_CollaborationPeer> _collaborationPeers = [];
  final List<_CollaborationDiscoveredHost> _collaborationDiscoveredHosts = [];
  final Set<String> _pendingCollaborationJoinRequests = {};
  String? _selectedCollaborationHostId;
  bool _collaborationPollInFlight = false;
  bool _applyingCollaborationAnnotationSnapshot = false;
  bool _collaborationJoining = false;
  bool _collaborationReconnecting = false;
  int _collaborationReconnectAttempts = 0;
  Timer? _collaborationReconnectTimer;
  _CollaborationDiscoveredHost? _connectedCollaborationHost;

  _ImageItem? get _selectedImage {
    if (_images.isEmpty) {
      return null;
    }
    return _images[_selectedImageIndex.clamp(0, _images.length - 1)];
  }

  bool get _collaborationClientMode =>
      _collaborationMode == _CollaborationMode.client;

  String get _currentAnnotatorName {
    final name = _collaborationUserName.trim();
    return name.isEmpty ? 'User' : name;
  }

  int get _currentAnnotatorColorValue =>
      _collaborationColorForId(_collaborationAuthorId).toARGB32();

  String get _currentAnnotatorLabel =>
      '$_currentAnnotatorName#${_shortCollaborationId(_collaborationAuthorId)}';

  String get _collaborationAuthorId =>
      _collaborationPeerIdFor(_collaborationHostId, _collaborationUserId);

  bool get _selectedImageAuthorized =>
      _isImageIndexAuthorized(_selectedImageIndex);

  bool get _projectLockedByCollaboration =>
      _collaborationMode == _CollaborationMode.client;

  _ImageItem? get _selectedImageForLabel {
    if (!_selectedImageAuthorized) {
      return null;
    }
    return _selectedImage;
  }

  List<_AnnotationRegion> get _currentAnnotationsForLabel {
    if (!_selectedImageAuthorized) {
      return const [];
    }
    return _currentAnnotations;
  }

  bool _isImageIndexAuthorized(int zeroBasedIndex) {
    if (!_collaborationClientMode) {
      return true;
    }
    if (_images.isEmpty) {
      return false;
    }
    final start = _collaborationStartIndex.clamp(1, _images.length);
    final end = _collaborationEndIndex.clamp(start, _images.length);
    final index = zeroBasedIndex + 1;
    return index >= start && index <= end;
  }

  void _moveToFirstAuthorizedCollaborationImage() {
    if (!_collaborationClientMode || _images.isEmpty) {
      return;
    }
    final start = _collaborationStartIndex.clamp(1, _images.length).toInt();
    final end = _collaborationEndIndex.clamp(start, _images.length).toInt();
    _collaborationStartIndex = start;
    _collaborationEndIndex = end;
    if (!_isImageIndexAuthorized(_selectedImageIndex)) {
      _selectedImageIndex = start - 1;
      _selectedAnnotationId = null;
    }
  }

  bool _guardProjectChangeBlocked() {
    if (!_projectLockedByCollaboration) {
      return false;
    }
    _showFloatingMessage(t('collab.disconnectFirst'));
    return true;
  }

  void _clearCurrentProjectState() {
    _labelResumeSaveTimer?.cancel();
    _images.clear();
    _labelClasses.clear();
    _annotationsByImage.clear();
    _imageSplits.clear();
    _imageDisplaySizes.clear();
    _undoStack.clear();
    _redoStack.clear();
    _importedDataset = null;
    _copiedAnnotation = null;
    _selectedImageIndex = 0;
    _selectedAnnotationId = null;
    _activeClassId = null;
    _classSerial = 1;
    _annotationSerial = 1;
    _imageDisplaySize = null;
    _labelViewportOffset = Offset.zero;
    _zoom = 100;
    _activeSection = 'label';
  }

  String? get _selectedImageKey {
    final image = _selectedImage;
    return image == null ? null : _pathKey(image.path);
  }

  List<_AnnotationRegion> get _currentAnnotations {
    final imageKey = _selectedImageKey;
    if (imageKey == null) {
      return const [];
    }
    return _annotationsByImage[imageKey] ?? const [];
  }

  String get _selectedImageSplit {
    final image = _selectedImage;
    if (image == null) {
      return 'train';
    }
    return _imageSplits[_pathKey(image.path)] ?? 'train';
  }

  List<_AnnotationRegion> _annotationsForImagePath(String path) {
    return _annotationsByImage[_pathKey(path)] ?? const [];
  }

  Size? _displaySizeForImagePath(String path) {
    final key = _pathKey(path);
    return _imageDisplaySizes[key] ?? _imageDisplaySizes[path];
  }

  String _databasePayload({
    bool includeClasses = true,
    bool includeAnnotations = true,
  }) {
    final lines = <String>['PROJECT\t${_databaseField(_databaseProjectKey())}'];
    if (includeClasses) {
      for (final labelClass in _labelClasses) {
        lines.add(
          [
            'CLASS',
            labelClass.id,
            labelClass.name,
            labelClass.colorValue,
          ].map(_databaseField).join('\t'),
        );
      }
    }

    for (var index = 0; index < _images.length; index++) {
      final image = _images[index];
      final imageKey = _pathKey(image.path);
      final size = _displaySizeForImagePath(image.path) ?? Size.zero;
      lines.add(
        [
          'IMAGE',
          image.path,
          image.name,
          _imageSplits[imageKey] ?? 'train',
          _databaseNumber(size.width),
          _databaseNumber(size.height),
          index,
        ].map(_databaseField).join('\t'),
      );
    }

    if (includeAnnotations) {
      for (final image in _images) {
        final imageKey = _pathKey(image.path);
        final annotations = _annotationsByImage[imageKey] ?? const [];
        for (final annotation in annotations) {
          final rect = annotation.rect;
          lines.add(
            [
              'ANNOTATION',
              image.path,
              annotation.id,
              annotation.mode.name,
              annotation.classId,
              _databaseNumber(rect.left),
              _databaseNumber(rect.top),
              _databaseNumber(rect.right),
              _databaseNumber(rect.bottom),
              _databaseNumber(annotation.rotationDegrees),
              _annotationPointsForDatabase(annotation),
              annotation.authorId.isEmpty ? 'manual' : 'collab',
              '0',
              annotation.authorId,
              annotation.authorName,
              annotation.authorColorValue,
            ].map(_databaseField).join('\t'),
          );
        }
      }
    }
    final selfPermissions = _collaborationMode == _CollaborationMode.client
        ? _collaborationSelfPermissions
        : const _CollaborationPermissions(
            canEditOthers: true,
            canDeleteOthers: true,
            canChangeClass: true,
          );
    lines.add(
      [
        'COLLAB_USER',
        _collaborationAuthorId,
        _currentAnnotatorName,
        _currentAnnotatorColorValue,
        selfPermissions.canEditOthers ? '1' : '0',
        selfPermissions.canDeleteOthers ? '1' : '0',
        selfPermissions.canChangeClass ? '1' : '0',
        _collaborationStartIndex,
        _collaborationEndIndex,
      ].map(_databaseField).join('\t'),
    );
    for (final peer in _collaborationPeers) {
      if (peer.userId == _collaborationAuthorId) {
        continue;
      }
      final permissions = peer.permissions;
      lines.add(
        [
          'COLLAB_USER',
          peer.userId,
          peer.userName,
          peer.colorValue,
          permissions.canEditOthers ? '1' : '0',
          permissions.canDeleteOthers ? '1' : '0',
          permissions.canChangeClass ? '1' : '0',
          peer.assignmentStart,
          peer.assignmentEnd,
        ].map(_databaseField).join('\t'),
      );
    }
    return lines.join('\n');
  }

  String _databaseField(Object? value) {
    return '${value ?? ''}'
        .replaceAll('\t', ' ')
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ');
  }

  String _databaseProjectKey() {
    final imported = _importedDataset;
    if (imported != null) {
      return 'dataset:${_pathKey(imported.dataYamlPath)}';
    }
    if (_images.isEmpty) {
      return 'default';
    }
    final directories = {
      for (final image in _images) _pathKey(_directoryName(image.path)),
    }.toList()..sort();
    if (directories.length == 1) {
      return 'folder:${directories.first}';
    }
    return 'workspace:${directories.join('|')}';
  }

  String _databaseNumber(num value) {
    if (!value.isFinite) {
      return '0';
    }
    return value.toStringAsFixed(6);
  }

  String _annotationPointsForDatabase(_AnnotationRegion annotation) {
    final points = annotation.mode == _AnnotationMode.seg
        ? annotation.points
        : const <Offset>[];
    return points
        .map(
          (point) =>
              '${_databaseNumber(point.dx)},${_databaseNumber(point.dy)}',
        )
        .join(';');
  }

  List<Offset> _annotationPointsFromDatabase(String raw) {
    final points = <Offset>[];
    for (final token in raw.split(';')) {
      final parts = token.split(',');
      if (parts.length != 2) {
        continue;
      }
      final x = double.tryParse(parts[0]);
      final y = double.tryParse(parts[1]);
      if (x != null && y != null) {
        points.add(Offset(x, y));
      }
    }
    return points;
  }

  _AnnotationMode _annotationModeFromDatabase(String raw) {
    return switch (raw.toLowerCase()) {
      'obb' => _AnnotationMode.obb,
      'seg' => _AnnotationMode.seg,
      _ => _AnnotationMode.hbb,
    };
  }

  void _scheduleAnnotationDatabaseSave() {
    if (_databaseApplying || _images.isEmpty) {
      return;
    }
    _databaseSaveTimer?.cancel();
    _databaseSaveTimer = Timer(const Duration(milliseconds: 700), () {
      unawaited(_saveAnnotationDatabaseNow());
    });
  }

  Future<void> _saveAnnotationDatabaseNow() async {
    if (_databaseApplying || _images.isEmpty) {
      return;
    }
    if (_collaborationMode == _CollaborationMode.client) {
      if (!_applyingCollaborationAnnotationSnapshot) {
        _publishCurrentCollaborationAnnotations();
      }
      return;
    }
    try {
      final result = await _RustVideoBackend.saveLabelDatabase(
        payload: _databasePayload(),
      );
      _log(
        'DB',
        'Label database saved: images=${result['images'] ?? '-'}, classes=${result['classes'] ?? '-'}, annotations=${result['annotations'] ?? '-'}',
        level: _LogLevel.debug,
      );
      if (!_applyingCollaborationAnnotationSnapshot) {
        _publishCurrentCollaborationAnnotations();
      }
    } on Object catch (error) {
      _log('DB', 'Label database save failed: $error', level: _LogLevel.error);
    }
  }

  Future<void> _saveCollaborationAnnotationDatabaseNow(String reason) async {
    if (_images.isEmpty || _collaborationMode == _CollaborationMode.client) {
      return;
    }
    final previousApplying = _applyingCollaborationAnnotationSnapshot;
    _applyingCollaborationAnnotationSnapshot = true;
    try {
      final result = await _RustVideoBackend.saveLabelDatabase(
        payload: _databasePayload(),
      );
      _log(
        'COLLAB',
        'Collaboration data saved: reason=$reason, images=${result['images'] ?? '-'}, classes=${result['classes'] ?? '-'}, annotations=${result['annotations'] ?? '-'}',
        level: _LogLevel.debug,
      );
    } on Object catch (error) {
      _log(
        'COLLAB',
        'Collaboration data save failed: reason=$reason, error=$error',
        level: _LogLevel.error,
      );
    } finally {
      _applyingCollaborationAnnotationSnapshot = previousApplying;
    }
  }

  Future<void> _loadAnnotationDatabaseForCurrentImages() async {
    if (_images.isEmpty) {
      return;
    }
    _databaseSaveTimer?.cancel();
    _databaseApplying = true;
    try {
      final result = await _RustVideoBackend.loadLabelDatabase(
        payload: _databasePayload(
          includeClasses: false,
          includeAnnotations: false,
        ),
      );
      final loadedClasses = _labelClassesFromDatabase(result['classes']);
      final loadedAnnotations = _annotationsFromDatabase(result['annotations']);
      if (!mounted) {
        return;
      }
      setState(() {
        _labelClasses
          ..clear()
          ..addAll(loadedClasses);
        if (loadedClasses.isNotEmpty) {
          var maxClassId = -1;
          for (final labelClass in loadedClasses) {
            if (labelClass.id > maxClassId) {
              maxClassId = labelClass.id;
            }
          }
          _classSerial = maxClassId + 1;
          if (_activeClassId == null ||
              !_labelClasses.any((item) => item.id == _activeClassId)) {
            _activeClassId = _labelClasses.first.id;
          }
        } else {
          _classSerial = 1;
          _activeClassId = null;
        }

        for (final image in _images) {
          final imageKey = _pathKey(image.path);
          final annotations = loadedAnnotations[imageKey];
          if (annotations == null || annotations.isEmpty) {
            _annotationsByImage.remove(imageKey);
          } else {
            _annotationsByImage[imageKey] = annotations;
          }
        }
        _annotationSerial = _nextAnnotationSerial();
        _selectedAnnotationId = null;
        _undoStack.clear();
        _redoStack.clear();
      });
      final count = loadedAnnotations.values.fold<int>(
        0,
        (sum, annotations) => sum + annotations.length,
      );
      _log(
        'DB',
        'Label database loaded: classes=${loadedClasses.length}, annotations=$count',
        level: _LogLevel.debug,
      );
    } on Object catch (error) {
      _log('DB', 'Label database load failed: $error', level: _LogLevel.error);
    } finally {
      _databaseApplying = false;
    }
  }

  List<_LabelClass> _labelClassesFromDatabase(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    final classes = <_LabelClass>[];
    for (final item in raw) {
      if (item is! Map) {
        continue;
      }
      final id = (item['id'] as num?)?.toInt();
      final name = '${item['name'] ?? ''}'.trim();
      final color = (item['color'] as num?)?.toInt();
      if (id == null || name.isEmpty || color == null) {
        continue;
      }
      classes.add(_LabelClass(id: id, name: name, colorValue: color));
    }
    classes.sort((a, b) => a.id.compareTo(b.id));
    return classes;
  }

  Map<String, List<_AnnotationRegion>> _annotationsFromDatabase(Object? raw) {
    final result = <String, List<_AnnotationRegion>>{};
    if (raw is! List) {
      return result;
    }
    final openImageKeys = {for (final image in _images) _pathKey(image.path)};
    for (final item in raw) {
      if (item is! Map) {
        continue;
      }
      final imagePath = '${item['imagePath'] ?? ''}';
      final imageKey = _pathKey(imagePath);
      if (!openImageKeys.contains(imageKey)) {
        continue;
      }
      final id = '${item['id'] ?? ''}';
      final classId = (item['classId'] as num?)?.toInt();
      if (id.isEmpty || classId == null) {
        continue;
      }
      final mode = _annotationModeFromDatabase('${item['kind'] ?? ''}');
      final rect = Rect.fromLTRB(
        ((item['left'] as num?) ?? 0).toDouble(),
        ((item['top'] as num?) ?? 0).toDouble(),
        ((item['right'] as num?) ?? 0).toDouble(),
        ((item['bottom'] as num?) ?? 0).toDouble(),
      );
      final points = mode == _AnnotationMode.seg
          ? _annotationPointsFromDatabase('${item['points'] ?? ''}')
          : const <Offset>[];
      result
          .putIfAbsent(imageKey, () => [])
          .add(
            _AnnotationRegion(
              id: id,
              mode: mode,
              rect: _normalizeRect(rect),
              classId: classId,
              rotationDegrees: ((item['rotation'] as num?) ?? 0).toDouble(),
              points: points,
              authorId: '${item['authorId'] ?? ''}',
              authorName: '${item['authorName'] ?? ''}',
              authorColorValue: (item['authorColor'] as num?)?.toInt() ?? 0,
            ),
          );
    }
    return result;
  }

  int _nextAnnotationSerial() {
    var next = 1;
    final pattern = RegExp(r'^ann_(\d+)$');
    for (final annotations in _annotationsByImage.values) {
      for (final annotation in annotations) {
        final match = pattern.firstMatch(annotation.id);
        if (match == null) {
          next += 1;
          continue;
        }
        final value = int.tryParse(match.group(1) ?? '');
        if (value != null && value >= next) {
          next = value + 1;
        }
      }
    }
    return next;
  }

  @override
  void initState() {
    super.initState();
    _detectVideoSession.addListener(_handleDetectVideoSessionChanged);
    _loadPersistedConfig();
    _loadAvailableLanguages();
    _startCollaborationPolling();
    _resetCollaborationRuntimeForStartup();
    _scheduleTopMenuHide();
  }

  void _resetCollaborationRuntimeForStartup() {
    unawaited(
      _RustVideoBackend.collaborationCommand(request: const {'action': 'stop'})
          .catchError((Object error) {
            _log(
              'COLLAB',
              'Startup collaboration reset failed: $error',
              level: _LogLevel.debug,
            );
            return <String, dynamic>{};
          })
          .whenComplete(_restartCollaborationDiscovery),
    );
  }

  @override
  void dispose() {
    _log('APP', 'Shutdown requested');
    _topMenuHideTimer?.cancel();
    _databaseSaveTimer?.cancel();
    _labelResumeSaveTimer?.cancel();
    _collaborationPollTimer?.cancel();
    _collaborationReconnectTimer?.cancel();
    unawaited(
      _RustVideoBackend.collaborationCommand(
        request: const {'action': 'stop'},
      ).catchError((Object error) {
        _log(
          'COLLAB',
          'Stop on dispose failed: $error',
          level: _LogLevel.debug,
        );
        return <String, dynamic>{};
      }),
    );
    unawaited(_saveAnnotationDatabaseNow());
    _saveLabelResumePositionNow();
    _logFlushTimer?.cancel();
    _flushLogs();
    _detectVideoSession.removeListener(_handleDetectVideoSessionChanged);
    _detectVideoSession.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _handleDetectVideoSessionChanged() {
    final visible =
        _detectVideoSession.fullscreen &&
        _detectVideoSession.hasInitializedVideo;
    if (visible == _videoFullscreenVisible || !mounted) {
      return;
    }
    setState(() => _videoFullscreenVisible = visible);
  }

  void _loadPersistedConfig() {
    final history = _ConfigStore.loadHistory();
    final keybindings = _ConfigStore.loadKeybindings();
    final settings = _ConfigStore.loadSettings();
    setState(() {
      _recentFolders
        ..clear()
        ..addAll(history.folders);
      _recentFiles
        ..clear()
        ..addAll(history.files);
      _shortcutConfig = keybindings;
      _appSettings = settings;
      _darkMode = settings.darkMode;
      _collaborationHostId = settings.collaborationHostId;
      _collaborationUserId = settings.collaborationUserId;
    });
    _ConfigStore.saveSettings(settings);
    _themeModeNotifier.value = settings.darkMode
        ? ThemeMode.dark
        : ThemeMode.light;
    _setLogLevel(_logLevelFromIndex(settings.logLevelIndex));
    _log(
      'APP',
      'Config loaded: recentFolders=${_recentFolders.length}, recentFiles=${_recentFiles.length}, logLevel=${_logLevel.name}',
      level: _LogLevel.debug,
    );
    _preloadConfiguredPython(settings);
  }

  Future<void> _loadAvailableLanguages() async {
    final options = await _LanguageOption.loadAvailable();
    if (!mounted) {
      return;
    }
    setState(() => _languageOptions = options);
  }

  Future<void> _changeLanguage(String code) async {
    if (code == _activeLanguageCode) {
      return;
    }
    final strings = await _LanguageStrings.load(code);
    if (!mounted) {
      return;
    }
    _appText = strings;
    _languageStringsNotifier.value = strings;
    setState(() => _activeLanguageCode = code);
    _log('SETTINGS', 'Language changed: $code');
    _showTopMenu();
  }

  void _saveHistory() {
    _ConfigStore.saveHistory(
      _HistoryConfig(folders: _recentFolders, files: _recentFiles),
    );
  }

  void _saveKeybindings() {
    _ConfigStore.saveKeybindings(_shortcutConfig);
  }

  void _saveAppSettings(_AppSettings settings) {
    final nextSettings = settings.copyWith(
      collaborationHostId: _collaborationHostId,
      collaborationUserId: _collaborationUserId,
    );
    setState(() {
      _appSettings = nextSettings;
      _darkMode = nextSettings.darkMode;
    });
    _themeModeNotifier.value = nextSettings.darkMode
        ? ThemeMode.dark
        : ThemeMode.light;
    _ConfigStore.saveSettings(nextSettings);
    _preloadConfiguredPython(nextSettings);
  }

  void _preloadConfiguredPython(_AppSettings settings) {
    final configuredPath = settings.pythonPath.trim();
    if (configuredPath.isEmpty) {
      return;
    }
    final pythonPath = _resolvePythonExecutable(configuredPath);
    if (pythonPath == null) {
      _log(
        'PYTHON',
        'YOLO Python preload skipped: configured path does not exist: $configuredPath',
        level: _LogLevel.warning,
      );
      return;
    }
    if (_pythonPreloadInFlightPath == pythonPath ||
        _preloadedPythonPath == pythonPath) {
      return;
    }
    if (_pythonPreloadInFlightPath.isNotEmpty) {
      _log(
        'PYTHON',
        'YOLO Python preload already running for $_pythonPreloadInFlightPath',
        level: _LogLevel.debug,
      );
      return;
    }

    _pythonPreloadInFlightPath = pythonPath;
    _log(
      'PYTHON',
      'YOLO Python preload started from saved settings: $pythonPath',
      level: _LogLevel.info,
    );
    unawaited(
      _RustVideoBackend.preloadYoloPython(pythonPath: pythonPath)
          .then((_) {
            _preloadedPythonPath = pythonPath;
            _log(
              'PYTHON',
              'YOLO Python preload completed: $pythonPath',
              level: _LogLevel.info,
            );
          })
          .catchError((Object error) {
            final errorText = error.toString();
            _log(
              'PYTHON',
              'YOLO Python preload failed; SAM3 uses the configured Python executable separately.',
              level: _LogLevel.warning,
            );
            _logMultiline(
              'PYTHON',
              errorText,
              level: _LogLevel.warning,
              prefix: 'detail: ',
            );
          })
          .whenComplete(() {
            if (_pythonPreloadInFlightPath == pythonPath) {
              _pythonPreloadInFlightPath = '';
            }
          }),
    );
  }

  void _setZoom(double value) {
    if (_zoomLocked) {
      return;
    }
    setState(() => _zoom = value.clamp(25, 400).toDouble());
  }

  void _setLabelViewportOffset(Offset offset) {
    if (_labelViewportOffset == offset) {
      return;
    }
    setState(() => _labelViewportOffset = offset);
  }

  void _resetZoomAndViewport() {
    if (_zoomLocked) {
      return;
    }
    setState(() {
      _zoom = 100;
      _labelViewportOffset = Offset.zero;
    });
  }

  void _toggleZoomLock() {
    setState(() => _zoomLocked = !_zoomLocked);
  }

  void _scheduleLabelResumePositionSave() {
    if (_images.isEmpty || _collaborationClientMode) {
      return;
    }
    _labelResumeSaveTimer?.cancel();
    _labelResumeSaveTimer = Timer(const Duration(milliseconds: 350), () {
      _saveLabelResumePositionNow();
    });
  }

  void _saveLabelResumePositionNow() {
    if (_images.isEmpty || _collaborationClientMode) {
      return;
    }
    final image = _selectedImage;
    if (image == null) {
      return;
    }
    try {
      _ConfigStore.saveLabelResumePosition(
        _LabelResumePosition(
          projectKey: _databaseProjectKey(),
          imagePath: image.path,
          imageIndex: _selectedImageIndex,
          updatedAt: DateTime.now(),
        ),
      );
    } on Object catch (error) {
      _log(
        'LABEL',
        'Save resume position failed: $error',
        level: _LogLevel.debug,
      );
    }
  }

  void _restoreLabelResumePosition() {
    if (_images.isEmpty || _collaborationClientMode) {
      return;
    }
    try {
      final position = _ConfigStore.loadLabelResumePosition(
        _databaseProjectKey(),
      );
      if (position == null) {
        return;
      }
      final pathIndex = _imageIndexOfPath(position.imagePath);
      final nextIndex = pathIndex >= 0
          ? pathIndex
          : position.imageIndex.clamp(0, _images.length - 1).toInt();
      if (nextIndex == _selectedImageIndex) {
        return;
      }
      setState(() {
        _selectedImageIndex = nextIndex;
        _selectedAnnotationId = null;
        _undoStack.clear();
        _redoStack.clear();
      });
      _log(
        'LABEL',
        'Restored image position: ${nextIndex + 1}/${_images.length}',
        level: _LogLevel.debug,
      );
    } on Object catch (error) {
      _log(
        'LABEL',
        'Restore resume position failed: $error',
        level: _LogLevel.debug,
      );
    }
  }

  void _selectImage(int index) {
    if (index < 0 || index >= _images.length) {
      return;
    }
    setState(() {
      _selectedImageIndex = index;
      _selectedAnnotationId = null;
      _undoStack.clear();
      _redoStack.clear();
    });
    _scheduleLabelResumePositionSave();
  }

  bool _selectPreviousImage({int step = 1}) {
    if (_images.isEmpty) {
      return false;
    }
    final nextIndex = (_selectedImageIndex - step).clamp(0, _images.length - 1);
    if (nextIndex == _selectedImageIndex) {
      return false;
    }
    _selectImage(nextIndex);
    return true;
  }

  bool _selectNextImage({int step = 1}) {
    if (_images.isEmpty) {
      return false;
    }
    final nextIndex = (_selectedImageIndex + step).clamp(0, _images.length - 1);
    if (nextIndex == _selectedImageIndex) {
      return false;
    }
    _selectImage(nextIndex);
    return true;
  }

  Future<void> _openImageFile({int? insertAfterIndex}) async {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    final file = await openFile(acceptedTypeGroups: [_imageTypeGroup]);
    if (file == null) {
      return;
    }
    _log('LABEL', 'Open image file: ${file.path}');

    final existingIndex = _imageIndexOfPath(file.path);
    if (existingIndex >= 0) {
      if (_touchRecent(_recentFiles, file.path)) {
        _saveHistory();
      }
      _selectImage(existingIndex);
      return;
    }

    if (_touchRecent(_recentFiles, file.path)) {
      _saveHistory();
    }
    _importedDataset = null;
    _insertImages([file.path], insertAfterIndex: insertAfterIndex);
    await _loadAnnotationDatabaseForCurrentImages();
  }

  Future<void> _openImageFolder([String? path]) async {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    final folderPath = path ?? await getDirectoryPath();
    if (folderPath == null) {
      return;
    }

    final files = _imageFilesInDirectory(folderPath);
    _log(
      'LABEL',
      'Open image folder: $folderPath, images=${files.length}',
      level: files.isEmpty ? _LogLevel.warning : _LogLevel.info,
    );
    if (_touchRecent(_recentFolders, folderPath)) {
      _saveHistory();
    }
    setState(() {
      _images
        ..clear()
        ..addAll(files.map(_ImageItem.fromPath));
      _imageSplits.clear();
      _labelClasses.clear();
      _annotationsByImage.clear();
      _importedDataset = null;
      _selectedImageIndex = 0;
      _selectedAnnotationId = null;
      _activeClassId = null;
      _classSerial = 1;
      _annotationSerial = 1;
      _undoStack.clear();
      _redoStack.clear();
      _activeSection = 'label';
    });
    await _loadAnnotationDatabaseForCurrentImages();
    _restoreLabelResumePosition();
  }

  Future<void> _openRecentFolder(String path) async {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    if (!Directory(path).existsSync()) {
      setState(() {
        _recentFolders.removeWhere(
          (entry) => _pathKey(entry.path) == _pathKey(path),
        );
      });
      _saveHistory();
      _log(
        'HISTORY',
        'Removed missing recent folder: $path',
        level: _LogLevel.warning,
      );
      _showFloatingMessage(t('recent.missingFolder'));
      return;
    }
    await _openImageFolder(path);
  }

  void _openRecentFile(String path) {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    _log('LABEL', 'Open recent file: $path');
    if (!File(path).existsSync()) {
      setState(() {
        _recentFiles.removeWhere(
          (entry) => _pathKey(entry.path) == _pathKey(path),
        );
      });
      _saveHistory();
      _log(
        'HISTORY',
        'Removed missing recent file: $path',
        level: _LogLevel.warning,
      );
      _showFloatingMessage(t('recent.missingFile'));
      return;
    }
    if (_touchRecent(_recentFiles, path)) {
      _saveHistory();
    }
    final existingIndex = _imageIndexOfPath(path);
    if (existingIndex >= 0) {
      _selectImage(existingIndex);
      return;
    }
    _importedDataset = null;
    _insertImages([path]);
    unawaited(_loadAnnotationDatabaseForCurrentImages());
  }

  void _insertImages(List<String> paths, {int? insertAfterIndex}) {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    final newPaths = paths
        .where((path) => _imageIndexOfPath(path) < 0)
        .toList(growable: false);
    if (newPaths.isEmpty) {
      return;
    }
    final insertIndex = insertAfterIndex == null
        ? _images.length
        : (insertAfterIndex + 1).clamp(0, _images.length);

    setState(() {
      _images.insertAll(insertIndex, newPaths.map(_ImageItem.fromPath));
      for (final path in newPaths) {
        _imageSplits.putIfAbsent(_pathKey(path), () => 'train');
      }
      _selectedImageIndex = insertIndex;
      _selectedAnnotationId = null;
      _undoStack.clear();
      _redoStack.clear();
      _activeSection = 'label';
    });
    _log(
      'LABEL',
      'Images inserted: count=${newPaths.length}, total=${_images.length}',
    );
    _broadcastCollaborationProjectSnapshot('images inserted');
    _scheduleLabelResumePositionSave();
    _scheduleAnnotationDatabaseSave();
  }

  int _imageIndexOfPath(String path) {
    final key = _pathKey(path);
    return _images.indexWhere((image) => _pathKey(image.path) == key);
  }

  void _deleteImage(int index) {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    if (index < 0 || index >= _images.length) {
      return;
    }

    final removedPath = _images[index].path;
    setState(() {
      final removed = _images.removeAt(index);
      _imageSplits.remove(_pathKey(removed.path));
      _annotationsByImage.remove(_pathKey(removed.path));
      _selectedImageIndex = _images.isEmpty
          ? 0
          : _selectedImageIndex.clamp(0, _images.length - 1);
      _selectedAnnotationId = null;
      _undoStack.clear();
      _redoStack.clear();
    });
    _log('LABEL', 'Image removed: $removedPath, total=${_images.length}');
    _broadcastCollaborationProjectSnapshot('image deleted');
    _scheduleLabelResumePositionSave();
    _scheduleAnnotationDatabaseSave();
  }

  void _setSelectedImageSplit(String split) {
    final imageKey = _selectedImageKey;
    if (imageKey == null || !_datasetSplits.contains(split)) {
      return;
    }
    setState(() => _imageSplits[imageKey] = split);
    _scheduleAnnotationDatabaseSave();
  }

  Future<void> _showImageContextMenu(TapDownDetails details, int? index) async {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(details.globalPosition, details.globalPosition),
      Offset.zero & overlay.size,
    );
    final action = await showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(value: 'add', child: Text(t('context.addImage'))),
        PopupMenuItem(value: 'delete', child: Text(t('context.deleteImage'))),
      ],
    );

    if (action == 'add') {
      await _openImageFile(insertAfterIndex: index);
    } else if (action == 'delete' && index != null) {
      _deleteImage(index);
    }
  }

  void _showTrainingHistoryDialog() {
    final history = _ConfigStore.loadTrainingHistory().entries;
    if (history.isEmpty) {
      _showFloatingMessage(t('train.noHistory'));
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('menu.trainingHistory')),
        content: SizedBox(
          width: 560,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: history.length,
            itemBuilder: (context, index) {
              final entry = history[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    entry.action == _TrainingHistoryAction.stop
                        ? Icons.stop_circle_outlined
                        : Icons.play_circle_outline,
                  ),
                  title: Text(
                    '${_trainingActionLabel(entry.action)}  '
                    '${entry.epoch}/${entry.targetEpochs}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${t('train.historyTimePoint')}: '
                    '${_formatTrainingHistoryTime(entry.timestamp)}\n'
                    '${t('path.model')}: ${_fileName(entry.modelPath)}\n'
                    '${t('train.datasetPath')}: ${entry.datasetPath}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('action.close')),
          ),
        ],
      ),
    );
  }

  Future<void> _importYoloDataset() async {
    if (_importingDataset) {
      return;
    }
    if (_guardProjectChangeBlocked()) {
      return;
    }
    final file = await openFile(acceptedTypeGroups: [_yamlTypeGroup]);
    if (file == null) {
      return;
    }
    if (!mounted) {
      return;
    }

    setState(() => _importingDataset = true);
    await WidgetsBinding.instance.endOfFrame;
    try {
      _log('IMPORT', 'Dataset import started: ${file.path}');
      final parsed = _parseImportYoloDataYaml(file.path);
      final imageEntries = <_DatasetImageEntry>[];
      for (final split in _datasetSplits) {
        final sources = parsed.splitSources[split] ?? const [];
        for (final source in sources) {
          imageEntries.addAll(
            _imagePathsFromDatasetSource(
              parsed.rootPath,
              source,
            ).map((path) => _DatasetImageEntry(path: path, split: split)),
          );
        }
      }

      final uniqueEntries = _dedupeDatasetEntries(imageEntries);
      if (uniqueEntries.isEmpty) {
        _log(
          'IMPORT',
          'Dataset import found no images: ${file.path}',
          level: _LogLevel.warning,
        );
        _showFloatingMessage(t('import.noImages'));
        return;
      }

      final importedClasses = <_LabelClass>[];
      int ensureClass(int classIndex) {
        while (importedClasses.length <= classIndex) {
          final index = importedClasses.length;
          final name = index < parsed.names.length
              ? parsed.names[index]
              : 'class_$index';
          importedClasses.add(
            _LabelClass(
              id: index,
              name: name,
              colorValue: _labelColorPalette[index % _labelColorPalette.length]
                  .toARGB32(),
            ),
          );
        }
        return importedClasses[classIndex].id;
      }

      final importedAnnotations = <String, List<_AnnotationRegion>>{};
      final importedSplits = <String, String>{};
      var annotationSerial = 1;
      for (final entry in uniqueEntries) {
        final displaySize = await _computeImageDisplaySize(entry.path);
        importedSplits[_pathKey(entry.path)] = entry.split;
        importedAnnotations[_pathKey(entry.path)] = _readYoloAnnotations(
          imagePath: entry.path,
          imageSize: displaySize,
          ensureClass: ensureClass,
          nextId: () => 'ann_${annotationSerial++}',
        );
      }

      if (parsed.names.isNotEmpty) {
        for (var i = 0; i < parsed.names.length; i++) {
          ensureClass(i);
        }
      }

      setState(() {
        _images
          ..clear()
          ..addAll(
            uniqueEntries.map((entry) => _ImageItem.fromPath(entry.path)),
          );
        _annotationsByImage
          ..clear()
          ..addAll(importedAnnotations);
        _imageSplits
          ..clear()
          ..addAll(importedSplits);
        _labelClasses
          ..clear()
          ..addAll(importedClasses);
        _importedDataset = _ImportedDataset(
          dataYamlPath: file.path,
          rootPath: parsed.rootPath,
          splitImageDirs: parsed.splitImageDirs,
        );
        _classSerial = importedClasses.length;
        _annotationSerial = annotationSerial;
        _activeClassId = importedClasses.isEmpty
            ? null
            : importedClasses.first.id;
        _selectedImageIndex = 0;
        _selectedAnnotationId = null;
        _undoStack.clear();
        _redoStack.clear();
        _activeSection = 'label';
      });
      final annotationCount = importedAnnotations.values.fold<int>(
        0,
        (sum, annotations) => sum + annotations.length,
      );
      _log(
        'IMPORT',
        'Dataset import completed: images=${uniqueEntries.length}, classes=${importedClasses.length}, annotations=$annotationCount, yaml=${file.path}',
      );
      _restoreLabelResumePosition();
      unawaited(_saveAnnotationDatabaseNow());
      _showFloatingMessage('${t('import.done')} (${uniqueEntries.length})');
    } on Object catch (error) {
      _log(
        'IMPORT',
        'Dataset import failed: ${file.path}, error=$error',
        level: _LogLevel.error,
      );
      _showFloatingMessage(t('import.failed'));
    } finally {
      if (mounted) {
        setState(() => _importingDataset = false);
      }
    }
  }

  List<_AnnotationRegion> _readYoloAnnotations({
    required String imagePath,
    required Size imageSize,
    required int Function(int classIndex) ensureClass,
    required String Function() nextId,
  }) {
    final labelFile = File(_labelPathForImagePath(imagePath));
    if (!labelFile.existsSync()) {
      return const [];
    }
    final result = <_AnnotationRegion>[];
    for (final rawLine in labelFile.readAsLinesSync()) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 5) {
        continue;
      }
      final classIndex = int.tryParse(parts.first);
      if (classIndex == null || classIndex < 0) {
        continue;
      }
      final values = parts
          .skip(1)
          .map(double.tryParse)
          .whereType<double>()
          .toList(growable: false);
      if (values.length != parts.length - 1) {
        continue;
      }
      final classId = ensureClass(classIndex);
      final annotation = _annotationFromYoloValues(
        id: nextId(),
        values: values,
        classId: classId,
        imageSize: imageSize,
      );
      if (annotation != null) {
        result.add(annotation);
      }
    }
    return result;
  }

  void _pushAnnotationSnapshot() {
    _undoStack.add(List<_AnnotationRegion>.of(_currentAnnotations));
    if (_undoStack.length > 50) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void _restoreCurrentImageAnnotations(List<_AnnotationRegion> snapshot) {
    final imageKey = _selectedImageKey;
    if (imageKey == null) {
      return;
    }
    _annotationsByImage[imageKey] = List<_AnnotationRegion>.of(snapshot);
    if (_selectedAnnotationId != null &&
        !_currentAnnotations.any(
          (annotation) => annotation.id == _selectedAnnotationId,
        )) {
      _selectedAnnotationId = null;
    }
  }

  void _undoAnnotationChange() {
    if (_undoStack.isEmpty) {
      return;
    }
    final snapshot = _undoStack.removeLast();
    _redoStack.add(List<_AnnotationRegion>.of(_currentAnnotations));
    setState(() => _restoreCurrentImageAnnotations(snapshot));
    _scheduleAnnotationDatabaseSave();
  }

  void _redoAnnotationChange() {
    if (_redoStack.isEmpty) {
      return;
    }
    final snapshot = _redoStack.removeLast();
    _undoStack.add(List<_AnnotationRegion>.of(_currentAnnotations));
    setState(() => _restoreCurrentImageAnnotations(snapshot));
    _scheduleAnnotationDatabaseSave();
  }

  void _activateAnnotationMode(_AnnotationMode mode) {
    setState(() {
      _activeAnnotationMode = mode;
      _activeTool = 'draw';
      _selectedAnnotationId = null;
    });
  }

  void _selectTool(String tool) {
    if (tool == 'undo') {
      _undoAnnotationChange();
      return;
    }
    if (tool == 'redo') {
      _redoAnnotationChange();
      return;
    }
    if (tool == 'copy') {
      _copySelectedAnnotation();
      return;
    }
    if (tool == 'paste') {
      _pasteAnnotation();
      return;
    }
    if (tool == 'delete') {
      _deleteSelectedAnnotation();
      return;
    }
    if (tool == 'export') {
      _showExportDialog();
      return;
    }
    setState(() => _activeTool = tool);
  }

  _LabelClass? _classById(int id) {
    for (final labelClass in _labelClasses) {
      if (labelClass.id == id) {
        return labelClass;
      }
    }
    return null;
  }

  Color _nextClassColor() {
    return _labelColorPalette[_labelClasses.length % _labelColorPalette.length];
  }

  Future<int?> _ensureActiveClass() async {
    if (_activeClassId != null && _classById(_activeClassId!) != null) {
      return _activeClassId;
    }
    if (_labelClasses.isNotEmpty) {
      setState(() => _activeClassId = _labelClasses.first.id);
      return _activeClassId;
    }
    return _addLabelClass();
  }

  Future<int?> _addLabelClass() async {
    if (_guardProjectChangeBlocked()) {
      return null;
    }
    final name = await _requestClassName(
      initialName: 'class_${_labelClasses.length}',
      title: t('label.createClassPrompt'),
    );
    if (name == null || name.trim().isEmpty) {
      return null;
    }
    final id = _classSerial++;
    final labelClass = _LabelClass(
      id: id,
      name: name.trim(),
      colorValue: _nextClassColor().toARGB32(),
    );
    setState(() {
      _labelClasses.add(labelClass);
      _activeClassId = id;
    });
    _broadcastCollaborationClassSnapshot('class added');
    _scheduleAnnotationDatabaseSave();
    return id;
  }

  Future<void> _editLabelClass(_LabelClass labelClass) async {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    final name = await _requestClassName(
      initialName: labelClass.name,
      title: t('label.editClass'),
    );
    if (name == null || name.trim().isEmpty) {
      return;
    }
    setState(() {
      final index = _labelClasses.indexWhere(
        (item) => item.id == labelClass.id,
      );
      if (index >= 0) {
        _labelClasses[index] = labelClass.copyWith(name: name.trim());
      }
    });
    _broadcastCollaborationClassSnapshot('class renamed');
    _scheduleAnnotationDatabaseSave();
  }

  Future<String?> _requestClassName({
    required String initialName,
    required String title,
  }) async {
    final controller = TextEditingController(text: initialName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: t('label.className')),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('label.cancelAnnotation')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(t('label.saveAnnotation')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _chooseLabelClassColor(_LabelClass labelClass) async {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    final currentColor = labelClass.color;
    final selected = await _showWheelColorDialog(
      context: context,
      initialColor: currentColor,
      title: t('label.classColor'),
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
    );
    if (selected == null) {
      return;
    }
    if (selected.toARGB32() == currentColor.toARGB32()) {
      return;
    }
    setState(() {
      final index = _labelClasses.indexWhere(
        (item) => item.id == labelClass.id,
      );
      if (index >= 0) {
        _labelClasses[index] = labelClass.copyWith(
          colorValue: selected.toARGB32(),
        );
      }
    });
    _broadcastCollaborationClassSnapshot('class color changed');
    _scheduleAnnotationDatabaseSave();
  }

  void _deleteLabelClass(_LabelClass labelClass) {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    _pushAnnotationSnapshot();
    setState(() {
      _labelClasses.removeWhere((item) => item.id == labelClass.id);
      for (final entry in _annotationsByImage.entries) {
        entry.value.removeWhere(
          (annotation) => annotation.classId == labelClass.id,
        );
      }
      if (_activeClassId == labelClass.id) {
        _activeClassId = _labelClasses.isEmpty ? null : _labelClasses.first.id;
      }
      _selectedAnnotationId = null;
    });
    _broadcastCollaborationClassSnapshot('class deleted');
    _broadcastCollaborationAllAnnotations('class deleted');
    _scheduleAnnotationDatabaseSave();
  }

  void _reorderLabelClass(int oldIndex, int newIndex) {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    setState(() {
      final item = _labelClasses.removeAt(oldIndex);
      _labelClasses.insert(newIndex, item);
    });
    _broadcastCollaborationClassSnapshot('class reordered');
    _scheduleAnnotationDatabaseSave();
  }

  void _selectLabelClass(int id) {
    setState(() => _activeClassId = id);
  }

  void _createAnnotation(Rect rect, int classId) {
    final imageKey = _selectedImageKey;
    if (imageKey == null ||
        !_selectedImageAuthorized ||
        rect.width.abs() < 4 ||
        rect.height.abs() < 4) {
      return;
    }
    _pushAnnotationSnapshot();
    final annotation = _AnnotationRegion.fromRect(
      id: 'ann_${_annotationSerial++}',
      mode: _activeAnnotationMode,
      rect: rect,
      classId: classId,
      authorId: _collaborationAuthorId,
      authorName: _currentAnnotatorName,
      authorColorValue: _currentAnnotatorColorValue,
    );
    setState(() {
      _annotationsByImage.putIfAbsent(imageKey, () => []).add(annotation);
      _selectedAnnotationId = null;
      _activeTool = 'draw';
    });
    _log(
      'ANNOTATION',
      'Created ${annotation.mode.name}: image=${_selectedImage?.name ?? '-'}, classId=$classId',
      level: _LogLevel.debug,
    );
    _scheduleAnnotationDatabaseSave();
  }

  void _createSegAnnotation(List<Offset> points, int classId) {
    final imageKey = _selectedImageKey;
    if (imageKey == null || !_selectedImageAuthorized || points.length < 3) {
      return;
    }
    _pushAnnotationSnapshot();
    final left = points.map((point) => point.dx).reduce(math.min);
    final top = points.map((point) => point.dy).reduce(math.min);
    final right = points.map((point) => point.dx).reduce(math.max);
    final bottom = points.map((point) => point.dy).reduce(math.max);
    final annotation = _AnnotationRegion(
      id: 'ann_${_annotationSerial++}',
      mode: _AnnotationMode.seg,
      rect: Rect.fromLTRB(left, top, right, bottom),
      classId: classId,
      points: List<Offset>.of(points),
      authorId: _collaborationAuthorId,
      authorName: _currentAnnotatorName,
      authorColorValue: _currentAnnotatorColorValue,
    );
    setState(() {
      _annotationsByImage.putIfAbsent(imageKey, () => []).add(annotation);
      _selectedAnnotationId = null;
      _activeTool = 'draw';
    });
    _log(
      'ANNOTATION',
      'Created seg: image=${_selectedImage?.name ?? '-'}, classId=$classId, points=${points.length}',
      level: _LogLevel.debug,
    );
    _scheduleAnnotationDatabaseSave();
  }

  void _selectAnnotation(String? id) {
    if (!_selectedImageAuthorized) {
      setState(() => _selectedAnnotationId = null);
      return;
    }
    final annotation = id == null
        ? null
        : _currentAnnotations
              .where((annotation) => annotation.id == id)
              .firstOrNullValue;
    setState(() {
      _selectedAnnotationId = id;
      if (annotation != null) {
        _activeClassId = annotation.classId;
      }
    });
  }

  bool _canModifyAnnotation(
    _AnnotationRegion annotation, {
    required String action,
  }) {
    if (_collaborationMode != _CollaborationMode.client) {
      return true;
    }
    if (annotation.authorId == _collaborationAuthorId) {
      return true;
    }
    return switch (action) {
      'edit' => _collaborationSelfPermissions.canEditOthers,
      'delete' => _collaborationSelfPermissions.canDeleteOthers,
      'class' => _collaborationSelfPermissions.canChangeClass,
      _ => false,
    };
  }

  void _updateAnnotation(_AnnotationRegion annotation) {
    final imageKey = _selectedImageKey;
    if (imageKey == null || !_selectedImageAuthorized) {
      return;
    }
    final existing = _currentAnnotations
        .where((item) => item.id == annotation.id)
        .firstOrNullValue;
    if (existing != null && !_canModifyAnnotation(existing, action: 'edit')) {
      return;
    }
    setState(() {
      final annotations = _annotationsByImage[imageKey];
      if (annotations == null) {
        return;
      }
      final index = annotations.indexWhere((item) => item.id == annotation.id);
      if (index >= 0) {
        annotations[index] = annotation;
      }
    });
    _scheduleAnnotationDatabaseSave();
  }

  void _changeAnnotationClass(String annotationId, int classId) {
    final imageKey = _selectedImageKey;
    if (imageKey == null || !_selectedImageAuthorized) {
      return;
    }
    final existing = _currentAnnotations
        .where((item) => item.id == annotationId)
        .firstOrNullValue;
    if (existing != null && !_canModifyAnnotation(existing, action: 'class')) {
      _showFloatingMessage(t('collab.permissionDenied'));
      return;
    }
    _pushAnnotationSnapshot();
    var changed = false;
    setState(() {
      final annotations = _annotationsByImage[imageKey];
      if (annotations == null) {
        return;
      }
      final index = annotations.indexWhere((item) => item.id == annotationId);
      if (index >= 0) {
        annotations[index] = annotations[index].copyWith(classId: classId);
        _activeClassId = classId;
        changed = true;
      }
    });
    if (changed) {
      _log(
        'ANNOTATION',
        'Class changed: annotation=$annotationId, classId=$classId',
        level: _LogLevel.debug,
      );
      _scheduleAnnotationDatabaseSave();
    }
  }

  void _deleteAnnotation(String id) {
    final imageKey = _selectedImageKey;
    if (imageKey == null || !_selectedImageAuthorized) {
      return;
    }
    final existing = _currentAnnotations
        .where((item) => item.id == id)
        .firstOrNullValue;
    if (existing != null && !_canModifyAnnotation(existing, action: 'delete')) {
      _showFloatingMessage(t('collab.permissionDenied'));
      return;
    }
    _pushAnnotationSnapshot();
    setState(() {
      _annotationsByImage[imageKey]?.removeWhere(
        (annotation) => annotation.id == id,
      );
      if (_selectedAnnotationId == id) {
        _selectedAnnotationId = null;
      }
    });
    _log('ANNOTATION', 'Deleted annotation: $id', level: _LogLevel.debug);
    _scheduleAnnotationDatabaseSave();
  }

  void _deleteSelectedAnnotation() {
    final selectedId = _selectedAnnotationId;
    if (selectedId == null) {
      return;
    }
    _deleteAnnotation(selectedId);
  }

  void _copySelectedAnnotation() {
    final selectedId = _selectedAnnotationId;
    if (selectedId == null) {
      return;
    }
    final selected = _currentAnnotations
        .where((annotation) => annotation.id == selectedId)
        .firstOrNullValue;
    if (selected != null) {
      setState(() => _copiedAnnotation = selected);
      _showFloatingMessage(t('feedback.copiedAnnotation'));
    }
  }

  void _showFloatingMessage(String message) {
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;
    entry = OverlayEntry(builder: (_) => _FloatingMessage(message: message));
    overlay.insert(entry);
    Future<void>.delayed(const Duration(milliseconds: 950), () {
      entry.remove();
    });
  }

  Size _clampAiAssistPanelSize(Size size, Size viewport) {
    final maxWidth = math.min(
      _aiAssistPanelMaxWidth,
      math.max(
        _aiAssistPanelMinWidth,
        viewport.width - _aiAssistPanelMargin * 2,
      ),
    );
    final maxHeight = math.min(
      _aiAssistPanelMaxHeight,
      math.max(
        _aiAssistPanelMinHeight,
        viewport.height - _aiAssistPanelMargin * 2,
      ),
    );
    return Size(
      size.width.clamp(_aiAssistPanelMinWidth, maxWidth).toDouble(),
      size.height.clamp(_aiAssistPanelMinHeight, maxHeight).toDouble(),
    );
  }

  Offset _clampAiAssistPanelOffset(
    Offset offset,
    Size viewport,
    Size panelSize,
  ) {
    final maxX = math.max(
      _aiAssistPanelMargin,
      viewport.width - panelSize.width - _aiAssistPanelMargin,
    );
    final maxY = math.max(
      _aiAssistPanelMargin,
      viewport.height - panelSize.height - _aiAssistPanelMargin,
    );
    return Offset(
      offset.dx.clamp(_aiAssistPanelMargin, maxX).toDouble(),
      offset.dy.clamp(_aiAssistPanelMargin, maxY).toDouble(),
    );
  }

  void _moveAiAssistPanel(
    Offset delta,
    Size viewport,
    Size panelSize,
    Offset fallbackOffset,
  ) {
    setState(() {
      final current = _aiAssistPanelOffset ?? fallbackOffset;
      _aiAssistPanelOffset = _clampAiAssistPanelOffset(
        current + delta,
        viewport,
        panelSize,
      );
    });
  }

  void _resizeAiAssistPanel(
    Offset delta,
    Size viewport,
    Size panelSize,
    Offset fallbackOffset,
  ) {
    setState(() {
      final currentOffset = _aiAssistPanelOffset ?? fallbackOffset;
      final nextSize = _clampAiAssistPanelSize(
        Size(panelSize.width + delta.dx, panelSize.height + delta.dy),
        viewport,
      );
      _aiAssistPanelSize = nextSize;
      _aiAssistPanelOffset = _clampAiAssistPanelOffset(
        currentOffset,
        viewport,
        nextSize,
      );
    });
  }

  void _saveAiAssistConfig(_AiAssistConfig config) {
    setState(() => _aiAssistConfig = config);
    if (config.backend == _AiAssistBackend.sam3) {
      _ConfigStore.saveLastSam3ModelPath(config.modelPath);
    }
    final sam3Detail = config.backend == _AiAssistBackend.sam3
        ? ', sam3Mode=${config.sam3OutputMode.wireName}, prompt=${config.sam3PromptMode.wireName}, ${config.sam3Runtime.logSummary}'
        : '';
    _log(
      'AI',
      'AI assist config saved: backend=${config.backend.wireName}, model=${_fileName(config.modelPath)}, classes=${config.selectedClassIds.length}, conf=${config.confThreshold.toStringAsFixed(2)}, imgsz=${config.imageSize}, range=${config.startIndex}-${config.endIndex}$sam3Detail',
    );
  }

  Future<_AiAssistConfig?> _ensureAiAssistConfig() async {
    final config = _aiAssistConfig;
    if (config != null) {
      return config;
    }
    setState(() => _aiPanelVisible = true);
    _showFloatingMessage(t('ai.chooseModelFirst'));
    return null;
  }

  Future<void> _runAiAnnotateCurrent() async {
    final config = await _ensureAiAssistConfig();
    if (config == null) {
      return;
    }
    await _runAiAnnotateCurrentWithConfig(config);
  }

  Future<void> _runAiAnnotateCurrentWithConfig(_AiAssistConfig config) async {
    if (_selectedImage == null) {
      return;
    }
    await _runAiAnnotateForIndices([_selectedImageIndex], config);
  }

  Future<void> _runAiAnnotateAll() async {
    final config = await _ensureAiAssistConfig();
    if (config == null) {
      return;
    }
    await _runAiAnnotateAllWithConfig(config);
  }

  Future<void> _runAiAnnotateAllWithConfig(_AiAssistConfig config) async {
    if (_images.isEmpty) {
      return;
    }
    final start = (config.startIndex - 1).clamp(0, _images.length - 1);
    final end = (config.endIndex - 1).clamp(0, _images.length - 1);
    if (start > end) {
      return;
    }
    await _runAiAnnotateForIndices([
      for (var index = start; index <= end; index++) index,
    ], config);
  }

  String _sam3ClickPointsTextForImage(String imagePath) {
    final points = _sam3ClickPromptsByImage[_pathKey(imagePath)] ?? const [];
    return points.map((point) => point.wireLine).join('\n');
  }

  Future<bool> _handleSam3ClickPrompt(
    Offset imagePoint,
    Size imageDisplaySize,
    bool positive,
  ) async {
    final config = _aiAssistConfig;
    final image = _selectedImage;
    final imageKey = _selectedImageKey;
    if (!_aiPanelVisible ||
        config == null ||
        config.backend != _AiAssistBackend.sam3 ||
        config.sam3PromptMode != _AiSam3PromptMode.click ||
        image == null ||
        imageKey == null ||
        !_selectedImageAuthorized ||
        imageDisplaySize.width <= 0 ||
        imageDisplaySize.height <= 0) {
      return false;
    }
    if (_aiAnnotating) {
      _showFloatingMessage(t('ai.annotating'));
      return true;
    }
    final point = _Sam3ClickPromptPoint(
      x: (imagePoint.dx / imageDisplaySize.width).clamp(0.0, 1.0).toDouble(),
      y: (imagePoint.dy / imageDisplaySize.height).clamp(0.0, 1.0).toDouble(),
      positive: positive,
    );
    final points = _sam3ClickPromptsByImage.putIfAbsent(imageKey, () => []);
    points.add(point);
    _log(
      'AI',
      'SAM3 click prompt added: image=${image.name}, point=${point.x.toStringAsFixed(4)},${point.y.toStringAsFixed(4)}, positive=$positive, total=${points.length}',
      level: _LogLevel.debug,
    );
    await _runAiAnnotateCurrentWithConfig(config);
    return true;
  }

  Future<void> _runAiAnnotateForIndices(
    List<int> indices,
    _AiAssistConfig config,
  ) async {
    if (_aiAnnotating || indices.isEmpty) {
      return;
    }
    if (_appSettings.pythonPath.trim().isEmpty) {
      _log(
        'AI',
        'AI annotation blocked: Python path is empty',
        level: _LogLevel.warning,
      );
      _showFloatingMessage(t('detect.pythonNotConfigured'));
      return;
    }
    if (config.backend == _AiAssistBackend.yolo &&
        config.selectedClassIds.isEmpty) {
      _log(
        'AI',
        'AI annotation blocked: no classes selected',
        level: _LogLevel.warning,
      );
      _showFloatingMessage(t('ai.noSelectedClasses'));
      return;
    }
    if (config.backend == _AiAssistBackend.sam3 &&
        config.sam3PromptMode == _AiSam3PromptMode.text &&
        config.sam3PromptText.trim().isEmpty) {
      _log(
        'AI',
        'SAM3 annotation blocked: text prompt is empty',
        level: _LogLevel.warning,
      );
      _showFloatingMessage(t('ai.sam3PromptRequired'));
      return;
    }
    final targetIndices = [
      for (final index in indices)
        if (index >= 0 && index < _images.length) index,
    ];
    if (targetIndices.isEmpty) {
      _log(
        'AI',
        'AI annotation blocked: no valid target indices',
        level: _LogLevel.warning,
      );
      return;
    }
    var samClickPointsText = '';
    final isSam3ClickMode =
        config.backend == _AiAssistBackend.sam3 &&
        config.sam3PromptMode == _AiSam3PromptMode.click;
    if (isSam3ClickMode) {
      if (targetIndices.length != 1 ||
          targetIndices.first != _selectedImageIndex) {
        _log(
          'AI',
          'SAM3 click annotation blocked: click mode only supports the current image',
          level: _LogLevel.warning,
        );
        _showFloatingMessage(t('ai.sam3ClickCurrentOnly'));
        return;
      }
      samClickPointsText = _sam3ClickPointsTextForImage(
        _images[targetIndices.first].path,
      );
      if (samClickPointsText.trim().isEmpty) {
        _log(
          'AI',
          'SAM3 click annotation blocked: no click prompt points',
          level: _LogLevel.warning,
        );
        _showFloatingMessage(t('ai.sam3ClickRequired'));
        return;
      }
    }
    _log(
      'AI',
      'AI annotation started: backend=${config.backend.wireName}, targets=${targetIndices.length}, model=${_fileName(config.modelPath)}, classes=${config.selectedClassIds.length}, conf=${config.confThreshold.toStringAsFixed(2)}, imgsz=${config.imageSize}, sam3Mode=${config.sam3OutputMode.wireName}, prompt=${config.sam3PromptMode.wireName}, clickPoints=${samClickPointsText.trim().isEmpty ? 0 : samClickPointsText.trim().split('\n').length}, ${config.sam3Runtime.logSummary}',
    );

    setState(() => _aiAnnotating = true);
    await WidgetsBinding.instance.endOfFrame;
    var added = 0;
    final classCountBefore = _labelClasses.length;
    try {
      if (targetIndices.length == 1 &&
          targetIndices.first == _selectedImageIndex) {
        _pushAnnotationSnapshot();
      }
      if (targetIndices.length == 1) {
        final image = _images[targetIndices.first];
        final result = await _RustVideoBackend.aiAnnotateImage(
          backend: config.backend.wireName,
          pythonPath: _appSettings.pythonPath.trim(),
          modelPath: config.modelPath,
          inputPath: image.path,
          classIds: config.selectedClassIds.toList()..sort(),
          confThreshold: config.confThreshold,
          iouThreshold: 0.45,
          imgsz: config.imageSize,
          device: 'auto',
          samMode: config.sam3OutputMode.wireName,
          samPromptMode: config.sam3PromptMode.wireName,
          promptsText: config.sam3PromptText,
          samClickPointsText: samClickPointsText,
          samPrecision: config.sam3Runtime.precision,
          samEncoder: config.sam3Runtime.encoder,
          samImageBatchSize: config.sam3Runtime.imageBatchSize,
          samVideoBatchSize: config.sam3Runtime.videoBatchSize,
          samInteractiveBatchSize: config.sam3Runtime.interactiveBatchSize,
          samMaxImageWidth: config.sam3Runtime.maxImageWidth,
          samMaxImageHeight: config.sam3Runtime.maxImageHeight,
          samResizeMethod: config.sam3Runtime.resizeMethod,
        );
        final displaySize = await _computeImageDisplaySize(image.path);
        added += _applyAiAnnotationResult(
          imagePath: image.path,
          displaySize: displaySize,
          result: result,
          config: config,
        );
      } else if (targetIndices.isNotEmpty) {
        final targetImages = [
          for (final index in targetIndices) _images[index],
        ];
        final results = await _RustVideoBackend.aiAnnotateImages(
          backend: config.backend.wireName,
          pythonPath: _appSettings.pythonPath.trim(),
          modelPath: config.modelPath,
          inputPaths: [for (final image in targetImages) image.path],
          classIds: config.selectedClassIds.toList()..sort(),
          confThreshold: config.confThreshold,
          iouThreshold: 0.45,
          imgsz: config.imageSize,
          device: 'auto',
          samMode: config.sam3OutputMode.wireName,
          samPromptMode: config.sam3PromptMode.wireName,
          promptsText: config.sam3PromptText,
          samClickPointsText: '',
          samPrecision: config.sam3Runtime.precision,
          samEncoder: config.sam3Runtime.encoder,
          samImageBatchSize: config.sam3Runtime.imageBatchSize,
          samVideoBatchSize: config.sam3Runtime.videoBatchSize,
          samInteractiveBatchSize: config.sam3Runtime.interactiveBatchSize,
          samMaxImageWidth: config.sam3Runtime.maxImageWidth,
          samMaxImageHeight: config.sam3Runtime.maxImageHeight,
          samResizeMethod: config.sam3Runtime.resizeMethod,
        );
        for (final result in results) {
          final imagePath = result.inputPath.isEmpty ? null : result.inputPath;
          if (imagePath == null || !File(imagePath).existsSync()) {
            continue;
          }
          final displaySize = await _computeImageDisplaySize(imagePath);
          added += _applyAiAnnotationResult(
            imagePath: imagePath,
            displaySize: displaySize,
            result: result,
            config: config,
          );
        }
      }
      if (mounted) {
        setState(() {});
      }
      _log(
        'AI',
        'AI annotation completed: targets=${targetIndices.length}, added=$added',
      );
      final classesChanged = _labelClasses.length != classCountBefore;
      if (classesChanged) {
        _broadcastCollaborationClassSnapshot('ai classes changed');
      }
      if (added > 0 || classesChanged || isSam3ClickMode) {
        _scheduleAnnotationDatabaseSave();
      }
      _showFloatingMessage('${t('ai.done')} ($added)');
    } on Object catch (error) {
      final failure = _classifyAiFailure(error);
      _log(
        'AI',
        'AI annotation failed: backend=${config.backend.wireName}, failure=$failure',
        level: _LogLevel.error,
      );
      _logMultiline(
        'AI',
        error.toString(),
        level: _LogLevel.error,
        prefix: 'detail: ',
      );
      _showFloatingMessage('${t('ai.failed')}: ${_shortAiError(error)}');
    } finally {
      if (mounted) {
        setState(() => _aiAnnotating = false);
      }
    }
  }

  int _applyAiAnnotationResult({
    required String imagePath,
    required Size displaySize,
    required _AiAnnotationResult result,
    required _AiAssistConfig config,
  }) {
    if (result.width <= 0 || result.height <= 0) {
      return 0;
    }
    final imageKey = _pathKey(imagePath);
    final annotations = _annotationsByImage.putIfAbsent(imageKey, () => []);
    var count = 0;
    if (config.backend == _AiAssistBackend.sam3) {
      final replaceSam3ClickAnnotations =
          config.sam3PromptMode == _AiSam3PromptMode.click;
      final generatedClickIds = <String>{};
      if (replaceSam3ClickAnnotations) {
        final previousIds = _sam3ClickAnnotationIdsByImage.remove(imageKey);
        if (previousIds != null && previousIds.isNotEmpty) {
          annotations.removeWhere((annotation) => previousIds.contains(annotation.id));
        }
      }
      for (final mask in result.masks) {
        final points = _scaleAiPoints(
          mask.points,
          sourceSize: Size(result.width, result.height),
          displaySize: displaySize,
        );
        if (points.length < 3) {
          continue;
        }
        final classId = _ensureLabelClassByName(mask.className);
        final bounds = _pointsBounds(
          points,
        ).intersect(Offset.zero & displaySize);
        if (bounds.width < 2 || bounds.height < 2) {
          continue;
        }
        final mode = config.sam3OutputMode.annotationMode;
        final id = 'ann_${_annotationSerial++}';
        if (mode == _AnnotationMode.seg) {
          annotations.add(
            _AnnotationRegion(
              id: id,
              mode: _AnnotationMode.seg,
              rect: bounds,
              classId: classId,
              points: points,
              authorId: _collaborationAuthorId,
              authorName: _currentAnnotatorName,
              authorColorValue: _currentAnnotatorColorValue,
            ),
          );
        } else if (mode == _AnnotationMode.obb) {
          final oriented = _minimumAreaRect(points);
          annotations.add(
            _AnnotationRegion.fromRect(
              id: id,
              mode: _AnnotationMode.obb,
              rect: oriented.rect.intersect(Offset.zero & displaySize),
              classId: classId,
              authorId: _collaborationAuthorId,
              authorName: _currentAnnotatorName,
              authorColorValue: _currentAnnotatorColorValue,
            ).copyWith(rotationDegrees: oriented.rotationDegrees),
          );
        } else {
          annotations.add(
            _AnnotationRegion.fromRect(
              id: id,
              mode: _AnnotationMode.hbb,
              rect: bounds,
              classId: classId,
              authorId: _collaborationAuthorId,
              authorName: _currentAnnotatorName,
              authorColorValue: _currentAnnotatorColorValue,
            ),
          );
        }
        if (replaceSam3ClickAnnotations) {
          generatedClickIds.add(id);
        }
        count += 1;
      }
      if (replaceSam3ClickAnnotations) {
        _sam3ClickAnnotationIdsByImage[imageKey] = generatedClickIds;
      }
      _log(
        'AI',
        'SAM3 annotations applied: image=${_fileName(imagePath)}, mode=${config.sam3OutputMode.wireName}, prompt=${config.sam3PromptMode.wireName}, masks=${result.masks.length}, added=$count',
        level: _LogLevel.debug,
      );
      return count;
    }
    for (final box in result.boxes) {
      final annotation = _annotationFromAiBox(
        box: box,
        sourceSize: Size(result.width, result.height),
        displaySize: displaySize,
      );
      if (annotation == null) {
        continue;
      }
      annotations.add(annotation);
      count += 1;
    }
    return count;
  }

  _AnnotationRegion? _annotationFromAiBox({
    required _AiPredictionBox box,
    required Size sourceSize,
    required Size displaySize,
  }) {
    final classId = _ensureLabelClassByName(box.className);
    final rect = Rect.fromLTRB(
      box.rect.left / sourceSize.width * displaySize.width,
      box.rect.top / sourceSize.height * displaySize.height,
      box.rect.right / sourceSize.width * displaySize.width,
      box.rect.bottom / sourceSize.height * displaySize.height,
    ).intersect(Offset.zero & displaySize);
    if (rect.width < 2 || rect.height < 2) {
      return null;
    }
    return _AnnotationRegion.fromRect(
      id: 'ann_${_annotationSerial++}',
      mode: _AnnotationMode.hbb,
      rect: rect,
      classId: classId,
      authorId: _collaborationAuthorId,
      authorName: _currentAnnotatorName,
      authorColorValue: _currentAnnotatorColorValue,
    );
  }

  int _ensureLabelClassByName(String rawName) {
    final name = rawName.trim().isEmpty
        ? 'class_${_labelClasses.length}'
        : rawName.trim();
    for (final labelClass in _labelClasses) {
      if (labelClass.name.toLowerCase() == name.toLowerCase()) {
        return labelClass.id;
      }
    }
    final id = _classSerial++;
    _labelClasses.add(
      _LabelClass(id: id, name: name, colorValue: _nextClassColor().toARGB32()),
    );
    _activeClassId ??= id;
    return id;
  }

  String _classifyAiFailure(Object error) {
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

  String _shortAiError(Object error) {
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

  List<Offset> _scaleAiPoints(
    List<Offset> points, {
    required Size sourceSize,
    required Size displaySize,
  }) {
    if (sourceSize.width <= 0 || sourceSize.height <= 0) {
      return const [];
    }
    return [
      for (final point in points)
        Offset(
          point.dx / sourceSize.width * displaySize.width,
          point.dy / sourceSize.height * displaySize.height,
        ),
    ];
  }

  Rect _pointsBounds(List<Offset> points) {
    if (points.isEmpty) {
      return Rect.zero;
    }
    var minX = points.first.dx;
    var minY = points.first.dy;
    var maxX = points.first.dx;
    var maxY = points.first.dy;
    for (final point in points.skip(1)) {
      minX = math.min(minX, point.dx);
      minY = math.min(minY, point.dy);
      maxX = math.max(maxX, point.dx);
      maxY = math.max(maxY, point.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  _AiOrientedRect _minimumAreaRect(List<Offset> points) {
    if (points.length < 3) {
      return _AiOrientedRect(rect: _pointsBounds(points), rotationDegrees: 0);
    }
    final hull = _convexHull(points);
    if (hull.length < 3) {
      return _AiOrientedRect(rect: _pointsBounds(points), rotationDegrees: 0);
    }
    var bestArea = double.infinity;
    Rect bestRect = _pointsBounds(points);
    var bestAngle = 0.0;
    for (var i = 0; i < hull.length; i++) {
      final current = hull[i];
      final next = hull[(i + 1) % hull.length];
      final angle = math.atan2(next.dy - current.dy, next.dx - current.dx);
      final rotated = [for (final point in hull) _rotateOffset(point, -angle)];
      final rect = _pointsBounds(rotated);
      final area = rect.width * rect.height;
      if (area >= bestArea) {
        continue;
      }
      bestArea = area;
      bestAngle = angle;
      final center = _rotateOffset(rect.center, angle);
      bestRect = Rect.fromCenter(
        center: center,
        width: rect.width,
        height: rect.height,
      );
    }
    return _AiOrientedRect(
      rect: bestRect,
      rotationDegrees: bestAngle * 180 / math.pi,
    );
  }

  List<Offset> _convexHull(List<Offset> points) {
    final sorted = List<Offset>.of(points)
      ..sort((a, b) {
        final x = a.dx.compareTo(b.dx);
        return x != 0 ? x : a.dy.compareTo(b.dy);
      });
    if (sorted.length <= 1) {
      return sorted;
    }
    final lower = <Offset>[];
    for (final point in sorted) {
      while (lower.length >= 2 &&
          _cross(lower[lower.length - 2], lower.last, point) <= 0) {
        lower.removeLast();
      }
      lower.add(point);
    }
    final upper = <Offset>[];
    for (final point in sorted.reversed) {
      while (upper.length >= 2 &&
          _cross(upper[upper.length - 2], upper.last, point) <= 0) {
        upper.removeLast();
      }
      upper.add(point);
    }
    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  double _cross(Offset origin, Offset a, Offset b) {
    return (a.dx - origin.dx) * (b.dy - origin.dy) -
        (a.dy - origin.dy) * (b.dx - origin.dx);
  }

  Offset _rotateOffset(Offset point, double radians) {
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    return Offset(
      point.dx * cos - point.dy * sin,
      point.dx * sin + point.dy * cos,
    );
  }

  Future<void> _showExportDialog() async {
    final config = await showDialog<_ExportConfig>(
      context: context,
      builder: (context) => _ExportDialog(exportPath: _appSettings.exportPath),
    );
    if (config == null || !mounted) return;
    final importedDataset = _importedDataset;
    String? dataYamlPath;
    if (importedDataset != null) {
      final overwrite = await _confirmOverwriteImportedDataset();
      if (overwrite == null || !mounted) {
        return;
      }
      if (overwrite) {
        dataYamlPath = await _exportImportedDataset(config, importedDataset);
      } else {
        dataYamlPath = await _exportAnnotations(config);
      }
    } else {
      dataYamlPath = await _exportAnnotations(config);
    }
    if (config.trainAfterExport && dataYamlPath != null && mounted) {
      await _trainFromExportedDataset(dataYamlPath);
    }
  }

  Future<void> _trainFromExportedDataset(String dataYamlPath) async {
    _log('EXPORT', 'Export auto training requested: data_yaml=$dataYamlPath');
    setState(() => _activeSection = 'train');
    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return;
    }
    final trainPage = _trainPageKey.currentState;
    if (trainPage == null) {
      _log(
        'EXPORT',
        'Export auto training skipped: training page is not ready',
        level: _LogLevel.warning,
      );
      return;
    }
    await trainPage._loadExportedDatasetAndStartTraining(dataYamlPath);
  }

  Future<bool?> _confirmOverwriteImportedDataset() async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('export.overwriteTitle')),
        content: Text(t('export.overwriteMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(t('action.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t('export.keepNew')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t('export.overwriteOriginal')),
          ),
        ],
      ),
    );
  }

  Future<Size> _computeImageDisplaySize(String imagePath) async {
    try {
      final file = File(imagePath);
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final w = image.width.toDouble();
      final h = image.height.toDouble();
      image.dispose();
      codec.dispose();
      if (w <= 0 || h <= 0) return const Size(1, 1);
      final scale = math.min(
        _annotationWorkspaceWidth / w,
        _annotationWorkspaceHeight / h,
      );
      final displaySize = Size(w * scale, h * scale);
      _imageDisplaySizes[_pathKey(imagePath)] = displaySize;
      return displaySize;
    } on Object catch (error) {
      _log(
        'LABEL',
        'Image size decode failed: $imagePath, error=$error',
        level: _LogLevel.warning,
      );
      return const Size(1, 1);
    }
  }

  Future<String?> _exportAnnotations(_ExportConfig config) async {
    _log(
      'EXPORT',
      'Export started: ${config.folderName} (train=${config.trainRatio.toStringAsFixed(0)}% val=${config.valRatio.toStringAsFixed(0)}% test=${config.testRatio.toStringAsFixed(0)}%)',
    );
    final exportRoot = _appSettings.exportPath;
    final baseDir = Directory('$exportRoot\\${config.folderName}');
    if (baseDir.existsSync()) {
      baseDir.deleteSync(recursive: true);
    }

    // Export every selected image; skipEmpty only controls empty label files.
    final entries = <_ExportEntry>[];
    for (final image in _images) {
      final annotations = _annotationsForImagePath(image.path);
      entries.add(_ExportEntry(image.path, annotations.toList()));
      if (_displaySizeForImagePath(image.path) == null) {
        await _computeImageDisplaySize(image.path);
      }
    }
    if (entries.isEmpty) {
      _log(
        'EXPORT',
        'Export skipped: no images or annotations to export',
        level: _LogLevel.warning,
      );
      _showFloatingMessage(t('export.noData'));
      return null;
    }

    // Class-balanced split: track which classes each image belongs to
    final imageClasses = <String, Set<int>>{};
    for (final entry in entries) {
      imageClasses[entry.path] = entry.annotations
          .map((a) => a.classId)
          .toSet();
    }

    // Assign each class's images to train/val/test
    final assigned = <String>{};
    final trainSet = <String>{};
    final valSet = <String>{};
    final testSet = <String>{};

    // Collect all unique class IDs
    final allClassIds = <int>{};
    for (final entry in entries) {
      for (final a in entry.annotations) {
        allClassIds.add(a.classId);
      }
    }

    for (final classId in allClassIds) {
      final classImages = entries
          .where((e) => e.annotations.any((a) => a.classId == classId))
          .toList();
      classImages.sort((a, b) => a.path.compareTo(b.path));

      final total = classImages.length;
      final valCount = (total * config.valRatio).round();
      final testCount = (total * config.testRatio).round();

      for (var i = 0; i < classImages.length; i++) {
        final path = classImages[i].path;
        if (assigned.contains(path)) continue;
        if (i < total - valCount - testCount) {
          trainSet.add(path);
        } else if (i < total - testCount) {
          valSet.add(path);
        } else {
          testSet.add(path);
        }
        assigned.add(path);
      }
    }

    // Assign any remaining unassigned images to train
    for (final entry in entries) {
      if (!assigned.contains(entry.path)) {
        trainSet.add(entry.path);
      }
    }

    final splitDirs = <String, Directory>{};
    void makeDirs(String split) {
      splitDirs['${split}_images'] = Directory(
        '${baseDir.path}\\$split\\images',
      )..createSync(recursive: true);
      splitDirs['${split}_labels'] = Directory(
        '${baseDir.path}\\$split\\labels',
      )..createSync(recursive: true);
    }

    makeDirs('train');
    makeDirs('val');
    if (testSet.isNotEmpty) makeDirs('test');

    final pathToEntry = <String, _ExportEntry>{};
    for (final entry in entries) {
      pathToEntry[entry.path] = entry;
    }

    void writeLabels(Set<String> paths, String split) {
      for (final path in paths) {
        final entry = pathToEntry[path]!;
        final baseName = _fileName(path).replaceAll(RegExp(r'\.[^.]+$'), '');
        final labelDir = splitDirs['${split}_labels']!;
        final labelFile = File('${labelDir.path}\\$baseName.txt');
        final lines = <String>[];
        for (final annotation in entry.annotations) {
          final classIdx = _labelClasses.indexWhere(
            (c) => c.id == annotation.classId,
          );
          if (classIdx < 0) continue;
          final imageSize = _displaySizeForImagePath(path) ?? const Size(1, 1);
          lines.add(
            annotation.toUltralyticsLabelLine(
              classIndex: classIdx,
              imageSize: imageSize,
            ),
          );
        }
        if (lines.isNotEmpty || !config.skipEmpty) {
          labelFile.writeAsStringSync(
            lines.isEmpty ? '' : '${lines.join('\n')}\n',
          );
        } else if (labelFile.existsSync()) {
          labelFile.deleteSync();
        }
      }
    }

    writeLabels(trainSet, 'train');
    writeLabels(valSet, 'val');
    writeLabels(testSet, 'test');

    // Write data.yaml
    final names = <String, String>{};
    for (var i = 0; i < _labelClasses.length; i++) {
      names['$i'] = _labelClasses[i].name;
    }
    final yamlLines = <String>[
      'path: ${baseDir.path.replaceAll('\\', '/')}',
      'train: train/images',
      'val: val/images',
      if (testSet.isNotEmpty) 'test: test/images',
      '',
      'nc: ${_labelClasses.length}',
      'names:',
      for (final entry in names.entries) '  ${entry.key}: ${entry.value}',
    ];
    final dataYamlPath = '${baseDir.path}\\data.yaml';
    File(dataYamlPath).writeAsStringSync('${yamlLines.join('\n')}\n');

    // Copy images if enabled
    if (config.exportImages) {
      void copyImages(Set<String> paths, String split) {
        for (final path in paths) {
          final name = _fileName(path);
          final imgDir = splitDirs['${split}_images']!;
          _copyFileOverwrite(path, '${imgDir.path}\\$name');
        }
      }

      copyImages(trainSet, 'train');
      copyImages(valSet, 'val');
      if (testSet.isNotEmpty) copyImages(testSet, 'test');
    }

    final annotationCount = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.annotations.length,
    );
    _log(
      'EXPORT',
      'Export completed: path=${baseDir.path}, images=${entries.length}, annotations=$annotationCount, train=${trainSet.length}, val=${valSet.length}, test=${testSet.length}, exportImages=${config.exportImages}, skipEmpty=${config.skipEmpty}',
    );
    _showFloatingMessage(
      '${t('export.done')} (${t('export.folderName')}: ${config.folderName})',
    );
    return dataYamlPath;
  }

  Future<String?> _exportImportedDataset(
    _ExportConfig config,
    _ImportedDataset dataset,
  ) async {
    _log(
      'EXPORT',
      'Overwrite imported dataset started: yaml=${dataset.dataYamlPath}',
    );
    final entries = <_ExportEntry>[
      for (final image in _images)
        _ExportEntry(image.path, _annotationsForImagePath(image.path).toList()),
    ];
    if (entries.isEmpty) {
      _log(
        'EXPORT',
        'Overwrite imported dataset skipped: no data',
        level: _LogLevel.warning,
      );
      _showFloatingMessage(t('export.noData'));
      return null;
    }

    for (final entry in entries) {
      if (_displaySizeForImagePath(entry.path) == null) {
        await _computeImageDisplaySize(entry.path);
      }
    }

    final grouped = <String, Set<String>>{
      for (final split in _datasetSplits) split: <String>{},
    };
    for (final entry in entries) {
      final split = _imageSplits[_pathKey(entry.path)] ?? 'train';
      grouped[_datasetSplits.contains(split) ? split : 'train']!.add(
        entry.path,
      );
    }

    final pathToEntry = <String, _ExportEntry>{
      for (final entry in entries) entry.path: entry,
    };

    void writeLabels(Set<String> paths, String split) {
      final labelDir = Directory(dataset.labelDirForSplit(split))
        ..createSync(recursive: true);
      for (final path in paths) {
        final entry = pathToEntry[path]!;
        final baseName = _baseNameWithoutExtension(path);
        final labelFile = File('${labelDir.path}\\$baseName.txt');
        final lines = <String>[];
        for (final annotation in entry.annotations) {
          final classIdx = _labelClasses.indexWhere(
            (c) => c.id == annotation.classId,
          );
          if (classIdx < 0) continue;
          final imageSize = _displaySizeForImagePath(path) ?? const Size(1, 1);
          lines.add(
            annotation.toUltralyticsLabelLine(
              classIndex: classIdx,
              imageSize: imageSize,
            ),
          );
        }
        if (lines.isNotEmpty || !config.skipEmpty) {
          labelFile.writeAsStringSync(
            lines.isEmpty ? '' : '${lines.join('\n')}\n',
          );
        } else if (labelFile.existsSync()) {
          labelFile.deleteSync();
        }
      }
    }

    for (final split in _datasetSplits) {
      writeLabels(grouped[split]!, split);
    }

    if (config.exportImages) {
      for (final split in _datasetSplits) {
        final imageDir = Directory(dataset.imageDirForSplit(split))
          ..createSync(recursive: true);
        for (final path in grouped[split]!) {
          final target = '${imageDir.path}\\${_fileName(path)}';
          if (_pathKey(path) != _pathKey(target)) {
            _copyFileOverwrite(path, target);
          }
        }
      }
    }

    File(dataset.dataYamlPath).writeAsStringSync(
      '${_datasetYamlContent(dataset, grouped, _labelClasses)}\n',
    );
    final annotationCount = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.annotations.length,
    );
    _log(
      'EXPORT',
      'Overwrite imported dataset completed: yaml=${dataset.dataYamlPath}, images=${entries.length}, annotations=$annotationCount, train=${grouped['train']?.length ?? 0}, val=${grouped['val']?.length ?? 0}, test=${grouped['test']?.length ?? 0}, exportImages=${config.exportImages}, skipEmpty=${config.skipEmpty}',
    );
    _showFloatingMessage(t('export.done'));
    return dataset.dataYamlPath;
  }

  void _pasteAnnotation() {
    final imageKey = _selectedImageKey;
    final copied = _copiedAnnotation;
    if (imageKey == null || copied == null || !_selectedImageAuthorized) {
      return;
    }
    _pushAnnotationSnapshot();
    final pasted = copied
        .duplicate('ann_${_annotationSerial++}')
        .copyWith(
          authorId: _collaborationAuthorId,
          authorName: _currentAnnotatorName,
          authorColorValue: _currentAnnotatorColorValue,
        );
    setState(() {
      _annotationsByImage.putIfAbsent(imageKey, () => []).add(pasted);
      _selectedAnnotationId = pasted.id;
    });
    _log(
      'ANNOTATION',
      'Pasted annotation: source=${copied.id}, pasted=${pasted.id}',
      level: _LogLevel.debug,
    );
    _scheduleAnnotationDatabaseSave();
  }

  void _rotateSelectedAnnotation(double deltaDegrees) {
    final selectedId = _selectedAnnotationId;
    if (selectedId == null) {
      return;
    }
    final selected = _currentAnnotations
        .where((annotation) => annotation.id == selectedId)
        .firstOrNullValue;
    if (selected == null || selected.mode != _AnnotationMode.obb) {
      return;
    }
    if (!_canModifyAnnotation(selected, action: 'edit')) {
      _showFloatingMessage(t('collab.permissionDenied'));
      return;
    }
    _pushAnnotationSnapshot();
    final rotated = selected.rotated(deltaDegrees);
    final imageSize = _imageDisplaySize;
    _updateAnnotation(
      imageSize != null && imageSize != Size.zero
          ? rotated.clampObbToImage(imageSize)
          : rotated,
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (_activeSection != 'label' || _zoomLocked) {
      return;
    }
    if (event is PointerScrollEvent) {
      _setZoom(_zoom + (event.scrollDelta.dy < 0 ? 10 : -10));
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (_collaborationReconnecting) {
      return event is KeyDownEvent || event is KeyRepeatEvent
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }

    if (_importingDataset) {
      return event is KeyDownEvent || event is KeyRepeatEvent
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }

    if (_isEditableTextFocused()) {
      return KeyEventResult.ignored;
    }

    if (_activeSection == 'browse' && !_shortcutDialogOpen) {
      final result = _detectVideoSession.handleShortcutKey(
        event,
        _shortcutConfig,
      );
      if (result == KeyEventResult.handled) {
        return result;
      }
    }

    if ((event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        _activeSection != 'label' ||
        _shortcutDialogOpen) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final repeated = event is KeyRepeatEvent;
    final imageStep = repeated ? 3 : 1;
    if (HardwareKeyboard.instance.isControlPressed) {
      if (key == LogicalKeyboardKey.keyZ) {
        _undoAnnotationChange();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyY) {
        _redoAnnotationChange();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyC) {
        _copySelectedAnnotation();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyV) {
        _pasteAnnotation();
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.escape) {
      setState(() {
        _activeTool = 'select';
        _selectedAnnotationId = null;
      });
      return KeyEventResult.handled;
    }

    if (_shortcutConfig.matches(_ShortcutAction.previousImage, key)) {
      if (!_selectPreviousImage(step: imageStep)) {
        _showFloatingMessage(t('detect.hudNoPrevious'));
      }
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.nextImage, key)) {
      if (!_selectNextImage(step: imageStep)) {
        _showFloatingMessage(t('detect.hudNoNext'));
      }
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.zoomIn, key)) {
      _setZoom(_zoom + 10);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.zoomOut, key)) {
      _setZoom(_zoom - 10);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.hbbMode, key)) {
      _activateAnnotationMode(_AnnotationMode.hbb);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.obbMode, key)) {
      _activateAnnotationMode(_AnnotationMode.obb);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.segMode, key)) {
      _activateAnnotationMode(_AnnotationMode.seg);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.deleteSelected, key)) {
      _deleteSelectedAnnotation();
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.hideClassLabels, key)) {
      setState(() => _showClassLabels = !_showClassLabels);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.rotateObbLeft5, key)) {
      _rotateSelectedAnnotation(-5);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.rotateObbLeft1, key)) {
      _rotateSelectedAnnotation(-1);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.rotateObbRight1, key)) {
      _rotateSelectedAnnotation(1);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.rotateObbRight5, key)) {
      _rotateSelectedAnnotation(5);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.aiAnnotateCurrent, key)) {
      unawaited(_runAiAnnotateCurrent());
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.aiAnnotateAll, key)) {
      unawaited(_runAiAnnotateAll());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _toggleThemeMode() {
    final nextDarkMode = !_darkMode;
    setState(() {
      _darkMode = nextDarkMode;
      _appSettings = _appSettings.copyWith(darkMode: nextDarkMode);
    });
    _themeModeNotifier.value = nextDarkMode ? ThemeMode.dark : ThemeMode.light;
    _ConfigStore.saveSettings(_appSettings);
  }

  void _updateShortcut(_ShortcutAction action, LogicalKeyboardKey key) {
    setState(() {
      _shortcutConfig = _shortcutConfig.copyWith(action: action, key: key);
    });
    _saveKeybindings();
  }

  void _resetShortcuts() {
    setState(() => _shortcutConfig = _ShortcutConfig.defaults());
    _saveKeybindings();
  }

  void _clearRecentItems() {
    setState(() {
      _recentFolders.clear();
      _recentFiles.clear();
    });
    _saveHistory();
  }

  void _showTopMenu() {
    _topMenuHideTimer?.cancel();
    if (!_topMenuVisible) {
      setState(() => _topMenuVisible = true);
    }
  }

  void _scheduleTopMenuHide() {
    _topMenuHideTimer?.cancel();
    _topMenuHideTimer = Timer(_topMenuAutoHideDelay, () {
      if (!mounted || !_topMenuVisible) {
        return;
      }
      setState(() => _topMenuVisible = false);
    });
  }

  Future<void> _showKeySettings() async {
    setState(() => _shortcutDialogOpen = true);
    await showDialog<void>(
      context: context,
      builder: (context) => _ShortcutSettingsDialog(
        config: _shortcutConfig,
        onShortcutChanged: _updateShortcut,
        onReset: _resetShortcuts,
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() => _shortcutDialogOpen = false);
    _keyboardFocusNode.requestFocus();
  }

  Future<void> _showSettings() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _SettingsDialog(
        initialSettings: _appSettings,
        cacheSizeBytes: _ConfigStore.cacheSizeInBytes(),
        onSave: _saveAppSettings,
        onClearCache: _clearCacheData,
      ),
    );
    if (mounted) {
      _keyboardFocusNode.requestFocus();
    }
  }

  Future<void> _showAboutDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        Widget section(String titleKey, String bodyKey) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t(titleKey),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Text(t(bodyKey), style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          );
        }

        return AlertDialog(
          title: Text(t('about.title')),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t('about.version'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  section('about.licenseTitle', 'about.licenseBody'),
                  section('about.opensourceTitle', 'about.opensourceBody'),
                  section('about.warningTitle', 'about.warningBody'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t('action.close')),
            ),
          ],
        );
      },
    );
    if (mounted) {
      _keyboardFocusNode.requestFocus();
    }
  }

  Future<void> _showLogViewerDialog() async {
    String dateKey(DateTime value) => value.toIso8601String().substring(0, 10);

    _flushLogs();
    var dates = _ConfigStore.logDates();
    String? selectedDate = dates.isEmpty ? null : dates.first;
    String logText = selectedDate == null
        ? t('logs.noLogs')
        : _ConfigStore.readLogsForDate(selectedDate);
    final logScrollController = ScrollController();

    if (!mounted) return;
    try {
      await showDialog<void>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
          builder: (context, setDialogState) {
            void scrollLogToTop() {
              if (!logScrollController.hasClients) {
                return;
              }
              logScrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
              );
            }

            void scrollLogToBottom() {
              if (!logScrollController.hasClients) {
                return;
              }
              logScrollController.animateTo(
                logScrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
              );
            }

            Future<void> deleteLogRange() async {
              final now = DateTime.now();
              final parsedDates = dates
                  .map(DateTime.tryParse)
                  .whereType<DateTime>()
                  .toList();
              final firstDate = parsedDates.isEmpty
                  ? now.subtract(const Duration(days: 365))
                  : parsedDates.reduce((a, b) => a.isBefore(b) ? a : b);
              final lastDate = parsedDates.isEmpty
                  ? now
                  : parsedDates.reduce((a, b) => a.isAfter(b) ? a : b);
              final range = await showDateRangePicker(
                context: context,
                firstDate: firstDate,
                lastDate: lastDate.isBefore(now) ? now : lastDate,
                initialDateRange: DateTimeRange(
                  start: selectedDate == null
                      ? lastDate
                      : DateTime.tryParse(selectedDate!) ?? lastDate,
                  end: selectedDate == null
                      ? lastDate
                      : DateTime.tryParse(selectedDate!) ?? lastDate,
                ),
                helpText: t('logs.selectDeleteRange'),
              );
              if (range == null) {
                return;
              }
              final deleted = _ConfigStore.deleteLogsByDateRange(
                dateKey(range.start),
                dateKey(range.end),
              );
              dates = _ConfigStore.logDates();
              selectedDate = dates.contains(selectedDate)
                  ? selectedDate
                  : (dates.isEmpty ? null : dates.first);
              logText = selectedDate == null
                  ? t('logs.noLogs')
                  : _ConfigStore.readLogsForDate(selectedDate!);
              setDialogState(() {});
              _showFloatingMessage('${t('logs.deleted')}: $deleted');
            }

            return AlertDialog(
              title: Text(t('logs.title')),
              content: SizedBox(
                width: 760,
                height: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedDate,
                            decoration: InputDecoration(
                              labelText: t('logs.date'),
                              isDense: true,
                            ),
                            items: [
                              for (final date in dates)
                                DropdownMenuItem(
                                  value: date,
                                  child: Text(date),
                                ),
                            ],
                            onChanged: dates.isEmpty
                                ? null
                                : (value) {
                                    if (value == null) return;
                                    setDialogState(() {
                                      selectedDate = value;
                                      logText = _ConfigStore.readLogsForDate(
                                        value,
                                      );
                                    });
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          if (logScrollController.hasClients) {
                                            logScrollController.jumpTo(0);
                                          }
                                        });
                                  },
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: logText.isEmpty ? null : scrollLogToTop,
                          icon: const Icon(Icons.vertical_align_top),
                          label: Text(t('logs.top')),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: logText.isEmpty
                              ? null
                              : scrollLogToBottom,
                          icon: const Icon(Icons.vertical_align_bottom),
                          label: Text(t('logs.bottom')),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: dates.isEmpty ? null : deleteLogRange,
                          icon: const Icon(Icons.delete_outline),
                          label: Text(t('logs.deleteRange')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        color: _isDarkMode(context)
                            ? const Color(0xFF090515)
                            : Colors.black,
                        child: Scrollbar(
                          controller: logScrollController,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: logScrollController,
                            child: SelectableText(
                              logText,
                              style: const TextStyle(
                                color: Color(0xFFE5E7EB),
                                fontFamily: 'Consolas',
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(t('action.close')),
                ),
              ],
            );
          },
          );
        },
      );
    } finally {
      logScrollController.dispose();
    }
    if (mounted) {
      _keyboardFocusNode.requestFocus();
    }
  }

  Future<int> _clearCacheData() async {
    setState(() {
      _recentFolders.clear();
      _recentFiles.clear();
      _labelClasses.clear();
      _annotationsByImage.clear();
      _imageSplits.clear();
      _importedDataset = null;
      _undoStack.clear();
      _redoStack.clear();
      _activeClassId = null;
      _selectedAnnotationId = null;
    });
    _saveHistory();
    unawaited(_saveAnnotationDatabaseNow());
    return _ConfigStore.cacheSizeInBytes();
  }

  void _startCollaborationPolling() {
    _collaborationPollTimer?.cancel();
    _collaborationPollTimer = Timer.periodic(
      const Duration(milliseconds: 350),
      (_) => _pollCollaborationEvents(),
    );
  }

  void _restartCollaborationDiscovery() {
    if (_collaborationMode != _CollaborationMode.off) {
      return;
    }
    unawaited(
      _RustVideoBackend.collaborationCommand(
        request: {'action': 'start_discovery', 'port': _collaborationPort},
      ).catchError((Object error) {
        _log(
          'COLLAB',
          'Discovery start failed: $error',
          level: _LogLevel.warning,
        );
        return <String, dynamic>{};
      }),
    );
  }

  Future<void> _pollCollaborationEvents() async {
    if (_collaborationPollInFlight) {
      return;
    }
    _collaborationPollInFlight = true;
    try {
      final events = await _RustVideoBackend.collaborationPollEvents(
        maxEvents: 50,
      );
      if (!mounted || events.isEmpty) {
        return;
      }
      for (final event in events) {
        _handleCollaborationEvent(event);
      }
    } on Object catch (error) {
      _log('COLLAB', 'Event poll failed: $error', level: _LogLevel.debug);
    } finally {
      _collaborationPollInFlight = false;
    }
  }

  void _handleCollaborationEvent(Map<String, dynamic> event) {
    switch (_collaborationString(event, 'type')) {
      case 'host_found':
        _upsertDiscoveredHost(event);
        break;
      case 'join_request':
        _handleCollaborationJoinRequest(event);
        break;
      case 'tcp_message':
        _handleCollaborationTcpMessage(event);
        break;
      case 'client_disconnected':
        _markCollaborationPeerOffline(_collaborationString(event, 'userId'));
        break;
      case 'host_disconnected':
        if (_collaborationMode == _CollaborationMode.client) {
          _startCollaborationReconnect();
        }
        break;
      case 'network_error':
        _log(
          'COLLAB',
          'Network error: ${event['scope'] ?? '-'} ${event['error'] ?? ''}',
          level: _LogLevel.warning,
        );
        if (_collaborationMode == _CollaborationMode.host &&
            _collaborationString(event, 'scope') == 'host_tcp') {
          setState(() {
            _collaborationMode = _CollaborationMode.off;
            _collaborationPeers.clear();
            _pendingCollaborationJoinRequests.clear();
          });
          _showFloatingMessage(t('collab.networkError'));
          unawaited(
            _RustVideoBackend.collaborationCommand(
                  request: const {'action': 'stop'},
                )
                .catchError((Object error) {
                  _log(
                    'COLLAB',
                    'Stop after host TCP error failed: $error',
                    level: _LogLevel.debug,
                  );
                  return <String, dynamic>{};
                })
                .whenComplete(_restartCollaborationDiscovery),
          );
        }
        break;
      default:
        break;
    }
  }

  void _upsertDiscoveredHost(Map<String, dynamic> event) {
    if (_collaborationMode == _CollaborationMode.host) {
      return;
    }
    final hostId = _collaborationString(event, 'hostId');
    if (hostId.isEmpty || hostId == _collaborationHostId) {
      return;
    }
    final host = _CollaborationDiscoveredHost(
      hostId: hostId,
      hostName: _collaborationString(event, 'hostName').trim().isEmpty
          ? 'Host'
          : _collaborationString(event, 'hostName'),
      address: _collaborationString(event, 'address'),
      port: _collaborationInt(event, 'port', fallback: _collaborationPort),
      online: true,
    );
    setState(() {
      final index = _collaborationDiscoveredHosts.indexWhere(
        (item) => item.hostId == host.hostId,
      );
      if (index >= 0) {
        _collaborationDiscoveredHosts[index] = host;
      } else {
        _collaborationDiscoveredHosts.add(host);
      }
      if (_selectedCollaborationHostId == null ||
          !_collaborationDiscoveredHosts.any(
            (item) => item.hostId == _selectedCollaborationHostId,
          )) {
        _selectedCollaborationHostId = host.hostId;
      }
      _collaborationDiscoveredHosts.sort(
        (a, b) => a.hostName.toLowerCase().compareTo(b.hostName.toLowerCase()),
      );
    });
  }

  void _handleCollaborationJoinRequest(Map<String, dynamic> event) {
    if (_collaborationMode != _CollaborationMode.host) {
      return;
    }
    final userId = _collaborationString(event, 'userId');
    if (userId.isEmpty || _pendingCollaborationJoinRequests.contains(userId)) {
      return;
    }
    _pendingCollaborationJoinRequests.add(userId);
    unawaited(_confirmCollaborationJoin(event));
  }

  Future<void> _confirmCollaborationJoin(Map<String, dynamic> event) async {
    final userId = _collaborationString(event, 'userId');
    final userName = _collaborationString(event, 'userName').trim().isEmpty
        ? 'User'
        : _collaborationString(event, 'userName');
    final address = _collaborationString(event, 'address');
    final colorValue = _collaborationInt(
      event,
      'colorValue',
      fallback: _collaborationColorForId(userId).toARGB32(),
    );
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('collab.joinRequestTitle')),
        content: Text(
          '${t('collab.joinRequestBody')}\n$userName#${_shortCollaborationId(userId)}\n$address',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t('collab.reject')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t('collab.allow')),
          ),
        ],
      ),
    );
    _pendingCollaborationJoinRequests.remove(userId);
    if (!mounted) {
      return;
    }
    if (allow == true) {
      final permissions = const _CollaborationPermissions();
      final assignmentStart = _collaborationStartIndex
          .clamp(1, math.max(1, _images.length))
          .toInt();
      final assignmentEnd = _collaborationEndIndex
          .clamp(assignmentStart, math.max(1, _images.length))
          .toInt();
      setState(() {
        _upsertCollaborationPeer(
          _CollaborationPeer(
            userId: userId,
            userName: userName,
            colorValue: colorValue,
            address: address,
            online: true,
            assignmentStart: assignmentStart,
            assignmentEnd: assignmentEnd,
            permissions: permissions,
          ),
        );
      });
      await _sendCollaborationCommand({
        'action': 'host_accept',
        'userId': userId,
        'hostId': _collaborationHostId,
        'assignmentStart': assignmentStart,
        'assignmentEnd': assignmentEnd,
        'canEditOthers': permissions.canEditOthers,
        'canDeleteOthers': permissions.canDeleteOthers,
        'canChangeClass': permissions.canChangeClass,
      });
      _sendCollaborationMessageToPeer(
        userId,
        _collaborationProjectSnapshotMessage(
          assignmentStart: assignmentStart,
          assignmentEnd: assignmentEnd,
        ),
      );
      _broadcastCollaborationMessage({
        'type': 'peer_joined',
        'userId': userId,
        'userName': userName,
        'colorValue': colorValue,
        'address': address,
      });
      _scheduleAnnotationDatabaseSave();
      _showFloatingMessage(t('collab.joinAccepted'));
      _log('COLLAB', 'Join accepted: user=$userId, address=$address');
    } else {
      await _sendCollaborationCommand({
        'action': 'host_reject',
        'userId': userId,
        'reason': 'rejected',
      });
      _log('COLLAB', 'Join rejected: user=$userId, address=$address');
    }
  }

  void _handleCollaborationTcpMessage(Map<String, dynamic> event) {
    final message = _collaborationMap(event['message']);
    switch (_collaborationString(message, 'type')) {
      case 'join_accepted':
        setState(() {
          _collaborationMode = _CollaborationMode.client;
          _collaborationJoining = false;
          _collaborationReconnecting = false;
          _collaborationReconnectAttempts = 0;
          _collaborationReconnectTimer?.cancel();
          _collaborationStartIndex = _collaborationInt(
            message,
            'assignmentStart',
            fallback: 1,
          );
          _collaborationEndIndex = _collaborationInt(
            message,
            'assignmentEnd',
            fallback: math.max(1, _images.length),
          );
          final permissions = _collaborationMap(message['permissions']);
          _collaborationSelfPermissions = _CollaborationPermissions(
            canEditOthers: _collaborationBool(permissions, 'canEditOthers'),
            canDeleteOthers: _collaborationBool(permissions, 'canDeleteOthers'),
            canChangeClass: _collaborationBool(permissions, 'canChangeClass'),
          );
          final host = _connectedCollaborationHost;
          if (host != null) {
            _upsertCollaborationPeer(
              _CollaborationPeer(
                userId: host.hostId,
                userName: host.hostName,
                address: '${host.address}:${host.port}',
                colorValue: _collaborationColorForId(host.hostId).toARGB32(),
                online: true,
              ),
            );
          }
        });
        unawaited(_saveCollaborationAnnotationDatabaseNow('join accepted'));
        _showFloatingMessage(t('collab.joined'));
        _log('COLLAB', 'Join accepted by host');
        break;
      case 'join_rejected':
        setState(() => _collaborationJoining = false);
        _showFloatingMessage(t('collab.joinRejected'));
        _disconnectCollaborationClient(clearProject: true);
        break;
      case 'permission_update':
        final permissions = _collaborationMap(message['permissions']);
        setState(() {
          _collaborationSelfPermissions = _CollaborationPermissions(
            canEditOthers: _collaborationBool(permissions, 'canEditOthers'),
            canDeleteOthers: _collaborationBool(permissions, 'canDeleteOthers'),
            canChangeClass: _collaborationBool(permissions, 'canChangeClass'),
          );
          _collaborationStartIndex = _collaborationInt(
            message,
            'assignmentStart',
            fallback: _collaborationStartIndex,
          );
          _collaborationEndIndex = _collaborationInt(
            message,
            'assignmentEnd',
            fallback: _collaborationEndIndex,
          );
          _moveToFirstAuthorizedCollaborationImage();
        });
        unawaited(
          _saveCollaborationAnnotationDatabaseNow('permissions updated'),
        );
        _showFloatingMessage(t('collab.permissionsUpdated'));
        break;
      case 'assignment_update':
        setState(() {
          _collaborationStartIndex = _collaborationInt(
            message,
            'assignmentStart',
            fallback: _collaborationStartIndex,
          );
          _collaborationEndIndex = _collaborationInt(
            message,
            'assignmentEnd',
            fallback: _collaborationEndIndex,
          );
          _moveToFirstAuthorizedCollaborationImage();
        });
        unawaited(
          _saveCollaborationAnnotationDatabaseNow('assignment updated'),
        );
        break;
      case 'peer_joined':
        final userId = _collaborationString(message, 'userId');
        if (userId.isNotEmpty && userId != _collaborationAuthorId) {
          setState(() {
            _upsertCollaborationPeer(
              _CollaborationPeer(
                userId: userId,
                userName: _collaborationString(message, 'userName'),
                colorValue: _collaborationInt(
                  message,
                  'colorValue',
                  fallback: _collaborationColorForId(userId).toARGB32(),
                ),
                address: _collaborationString(message, 'address'),
                online: true,
              ),
            );
          });
          unawaited(_saveCollaborationAnnotationDatabaseNow('peer joined'));
        }
        break;
      case 'annotation_snapshot':
        _applyCollaborationAnnotationSnapshot(
          message,
          fromUserId: _collaborationString(event, 'fromUserId'),
        );
        break;
      case 'class_snapshot':
        if (_collaborationMode == _CollaborationMode.client) {
          _applyCollaborationClassSnapshot(message);
        }
        break;
      case 'project_snapshot':
        if (_collaborationMode == _CollaborationMode.client) {
          _applyCollaborationProjectSnapshot(message);
        }
        break;
      default:
        break;
    }
  }

  void _publishCurrentCollaborationAnnotations() {
    if (_collaborationMode == _CollaborationMode.off ||
        !_selectedImageAuthorized) {
      return;
    }
    final image = _selectedImage;
    if (image == null) {
      return;
    }
    final limitedToOwnAnnotations =
        _collaborationMode == _CollaborationMode.client &&
        !_collaborationSelfPermissions.canEditOthers &&
        !_collaborationSelfPermissions.canDeleteOthers &&
        !_collaborationSelfPermissions.canChangeClass;
    final annotations = limitedToOwnAnnotations
        ? _currentAnnotations
              .where(
                (annotation) =>
                    annotation.authorId.isEmpty ||
                    annotation.authorId == _collaborationAuthorId,
              )
              .toList(growable: false)
        : _currentAnnotations;
    final message = <String, Object?>{
      'type': 'annotation_snapshot',
      'imagePath': image.path,
      'imageIndex': _selectedImageIndex + 1,
      'sourceUserId': _collaborationAuthorId,
      'authoritative': !limitedToOwnAnnotations,
      if (limitedToOwnAnnotations) 'authorScope': _collaborationAuthorId,
      if (_collaborationMode == _CollaborationMode.host)
        'classes': _collaborationClassesPayload(),
      'annotations': [
        for (final annotation in annotations)
          _collaborationAnnotationToJson(annotation),
      ],
    };
    if (_collaborationMode == _CollaborationMode.host) {
      _sendCollaborationMessageToAuthorizedPeers(message, _selectedImageIndex);
    } else {
      unawaited(
        _sendCollaborationCommand({
          'action': 'send_host',
          'message': jsonEncode(message),
        }),
      );
    }
  }

  Map<String, Object?> _collaborationProjectSnapshotMessage({
    int? assignmentStart,
    int? assignmentEnd,
  }) {
    final start = assignmentStart ?? _collaborationStartIndex;
    final end = assignmentEnd ?? _collaborationEndIndex;
    return {
      'type': 'project_snapshot',
      'projectKey': _databaseProjectKey(),
      'assignmentStart': start,
      'assignmentEnd': end,
      'images': [
        for (var index = 0; index < _images.length; index++)
          {
            'path': _images[index].path,
            'name': _images[index].name,
            'split': _imageSplits[_pathKey(_images[index].path)] ?? 'train',
            'width':
                (_displaySizeForImagePath(_images[index].path) ?? Size.zero)
                    .width,
            'height':
                (_displaySizeForImagePath(_images[index].path) ?? Size.zero)
                    .height,
            'index': index + 1,
            if (index + 1 >= start && index + 1 <= end)
              'bytesBase64': _collaborationImageBytesBase64(
                _images[index].path,
              ),
          },
      ],
      'classes': _collaborationClassesPayload(),
      'annotationsByImage': [
        for (var index = 0; index < _images.length; index++)
          if (index + 1 >= start && index + 1 <= end)
            {
              'imageIndex': index + 1,
              'imagePath': _images[index].path,
              'annotations': [
                for (final annotation in _annotationsForImagePath(
                  _images[index].path,
                ))
                  _collaborationAnnotationToJson(annotation),
              ],
            },
      ],
    };
  }

  List<Map<String, Object?>> _collaborationClassesPayload() {
    return [
      for (final labelClass in _labelClasses)
        {
          'id': labelClass.id,
          'name': labelClass.name,
          'color': labelClass.colorValue,
        },
    ];
  }

  Map<String, Object?> _collaborationClassSnapshotMessage() {
    return {
      'type': 'class_snapshot',
      'classes': _collaborationClassesPayload(),
    };
  }

  List<_LabelClass> _collaborationClassesFromJson(Object? value) {
    final rawClasses = value;
    if (rawClasses is! List) {
      return const [];
    }
    final classes = <_LabelClass>[];
    final seenIds = <int>{};
    for (final rawClass in rawClasses) {
      final labelClass = _collaborationMap(rawClass);
      final classId = _collaborationInt(
        labelClass,
        'id',
        fallback: classes.length,
      );
      if (!seenIds.add(classId)) {
        continue;
      }
      classes.add(
        _LabelClass(
          id: classId,
          name: _collaborationString(labelClass, 'name').trim().isEmpty
              ? 'class_${classes.length}'
              : _collaborationString(labelClass, 'name'),
          colorValue: _collaborationInt(
            labelClass,
            'color',
            fallback:
                _labelColorPalette[classes.length % _labelColorPalette.length]
                    .toARGB32(),
          ),
        ),
      );
    }
    return classes;
  }

  int _nextClassSerialFor(Iterable<_LabelClass> classes) {
    var next = 1;
    for (final labelClass in classes) {
      if (labelClass.id >= next) {
        next = labelClass.id + 1;
      }
    }
    return next;
  }

  void _replaceLabelClassesFromCollaboration(List<_LabelClass> classes) {
    _labelClasses
      ..clear()
      ..addAll(classes);
    if (_activeClassId == null ||
        !_labelClasses.any((item) => item.id == _activeClassId)) {
      _activeClassId = _labelClasses.isEmpty ? null : _labelClasses.first.id;
    }
    _classSerial = math.max(_classSerial, _nextClassSerialFor(classes));
  }

  String _collaborationImageBytesBase64(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        return '';
      }
      return base64Encode(file.readAsBytesSync());
    } on Object catch (error) {
      _log(
        'COLLAB',
        'Image payload read failed: path=$path, error=$error',
        level: _LogLevel.warning,
      );
      return '';
    }
  }

  String _collaborationLocalImagePath({
    required String remotePath,
    required String name,
    required String bytesBase64,
  }) {
    if (File(remotePath).existsSync() || bytesBase64.trim().isEmpty) {
      return remotePath;
    }
    try {
      final bytes = base64Decode(bytesBase64);
      final cacheDir = Directory(
        '${_ConfigStore.projectDirectory.path}\\collaboration_cache',
      );
      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }
      final fileName = _collaborationCacheFileName(remotePath, name);
      final file = File('${cacheDir.path}\\$fileName');
      file.writeAsBytesSync(bytes);
      return file.path;
    } on Object catch (error) {
      _log(
        'COLLAB',
        'Image payload write failed: path=$remotePath, error=$error',
        level: _LogLevel.warning,
      );
      return remotePath;
    }
  }

  String _collaborationCacheFileName(String remotePath, String name) {
    final rawName = name.trim().isEmpty ? _fileName(remotePath) : name.trim();
    final safeName = rawName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    final displayName = safeName.isEmpty ? 'image' : safeName;
    return '${_stableCollaborationHash(remotePath)}_$displayName';
  }

  String _stableCollaborationHash(String value) {
    var hash = 2166136261;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  void _applyCollaborationProjectSnapshot(Map<String, dynamic> message) {
    final rawImages = message['images'];
    if (rawImages is! List) {
      return;
    }

    final nextImages = <_ImageItem>[];
    final nextSplits = <String, String>{};
    final nextSizes = <String, Size>{};
    final remoteToLocalImagePath = <String, String>{};
    for (final rawImage in rawImages) {
      final image = _collaborationMap(rawImage);
      final path = _collaborationString(image, 'path');
      if (path.isEmpty) {
        continue;
      }
      final name = _collaborationString(image, 'name').trim().isEmpty
          ? _fileName(path)
          : _collaborationString(image, 'name');
      final localPath = _collaborationLocalImagePath(
        remotePath: path,
        name: name,
        bytesBase64: _collaborationString(image, 'bytesBase64'),
      );
      final imageKey = _pathKey(localPath);
      remoteToLocalImagePath[_pathKey(path)] = localPath;
      nextImages.add(_ImageItem(path: localPath, name: name));
      nextSplits[imageKey] = _collaborationString(image, 'split').trim().isEmpty
          ? 'train'
          : _collaborationString(image, 'split');
      nextSizes[imageKey] = Size(
        _collaborationDouble(image, 'width'),
        _collaborationDouble(image, 'height'),
      );
    }
    if (nextImages.isEmpty) {
      return;
    }

    final nextClasses = _collaborationClassesFromJson(message['classes']);
    final nextClassSerial = _nextClassSerialFor(nextClasses);

    final nextAnnotations = <String, List<_AnnotationRegion>>{};
    var maxAnnotationSerial = _annotationSerial;
    final rawAnnotationsByImage = message['annotationsByImage'];
    if (rawAnnotationsByImage is List) {
      for (final rawEntry in rawAnnotationsByImage) {
        final entry = _collaborationMap(rawEntry);
        final imagePath = _collaborationString(entry, 'imagePath');
        final imageIndex =
            _collaborationInt(entry, 'imageIndex', fallback: 0) - 1;
        final localImagePath = imageIndex >= 0 && imageIndex < nextImages.length
            ? nextImages[imageIndex].path
            : remoteToLocalImagePath[_pathKey(imagePath)] ?? imagePath;
        if (localImagePath.isEmpty) {
          continue;
        }
        final rawAnnotations = entry['annotations'];
        if (rawAnnotations is! List) {
          continue;
        }
        final annotations = rawAnnotations
            .map(_collaborationAnnotationFromJson)
            .whereType<_AnnotationRegion>()
            .toList();
        for (final annotation in annotations) {
          final match = RegExp(r'^ann_(\d+)$').firstMatch(annotation.id);
          if (match != null) {
            final serial = int.tryParse(match.group(1) ?? '');
            if (serial != null && serial >= maxAnnotationSerial) {
              maxAnnotationSerial = serial + 1;
            }
          }
        }
        nextAnnotations[_pathKey(localImagePath)] = annotations;
      }
    }

    final snapshotStart = _collaborationInt(
      message,
      'assignmentStart',
      fallback: _collaborationStartIndex,
    );
    final snapshotEnd = _collaborationInt(
      message,
      'assignmentEnd',
      fallback: _collaborationEndIndex,
    );
    final firstAuthorizedIndex = (snapshotStart - 1)
        .clamp(0, nextImages.length - 1)
        .toInt();
    setState(() {
      _collaborationStartIndex = snapshotStart;
      _collaborationEndIndex = snapshotEnd;
      _images
        ..clear()
        ..addAll(nextImages);
      _imageSplits
        ..clear()
        ..addAll(nextSplits);
      _imageDisplaySizes
        ..clear()
        ..addAll(nextSizes);
      _replaceLabelClassesFromCollaboration(nextClasses);
      _annotationsByImage
        ..clear()
        ..addAll(nextAnnotations);
      _importedDataset = null;
      _selectedImageIndex = firstAuthorizedIndex;
      _selectedAnnotationId = null;
      _activeClassId = nextClasses.isEmpty ? null : nextClasses.first.id;
      _classSerial = math.max(_classSerial, nextClassSerial);
      _annotationSerial = math.max(_annotationSerial, maxAnnotationSerial);
      _undoStack.clear();
      _redoStack.clear();
      _moveToFirstAuthorizedCollaborationImage();
      _activeSection = 'label';
    });
    unawaited(_saveCollaborationAnnotationDatabaseNow('project snapshot'));
  }

  void _applyCollaborationClassSnapshot(Map<String, dynamic> message) {
    if (message['classes'] is! List) {
      return;
    }
    final nextClasses = _collaborationClassesFromJson(message['classes']);
    setState(() {
      _replaceLabelClassesFromCollaboration(nextClasses);
    });
    unawaited(_saveCollaborationAnnotationDatabaseNow('class snapshot'));
  }

  Map<String, Object?> _collaborationAnnotationToJson(
    _AnnotationRegion annotation,
  ) {
    final rect = annotation.rect;
    final authorId = annotation.authorId.trim().isEmpty
        ? _collaborationAuthorId
        : annotation.authorId;
    final authorName = annotation.authorName.trim().isEmpty
        ? _currentAnnotatorName
        : annotation.authorName;
    final authorColor = annotation.authorColorValue == 0
        ? _currentAnnotatorColorValue
        : annotation.authorColorValue;
    return {
      'id': annotation.id,
      'mode': annotation.mode.name,
      'classId': annotation.classId,
      'left': rect.left,
      'top': rect.top,
      'right': rect.right,
      'bottom': rect.bottom,
      'rotation': annotation.rotationDegrees,
      'points': [
        for (final point in annotation.points) {'x': point.dx, 'y': point.dy},
      ],
      'authorId': authorId,
      'authorName': authorName,
      'authorColor': authorColor,
    };
  }

  _AnnotationRegion? _collaborationAnnotationFromJson(Object? value) {
    final data = _collaborationMap(value);
    final id = _collaborationString(data, 'id');
    if (id.isEmpty) {
      return null;
    }
    final mode = _annotationModeFromDatabase(
      _collaborationString(data, 'mode'),
    );
    final points = <Offset>[];
    final rawPoints = data['points'];
    if (rawPoints is List) {
      for (final rawPoint in rawPoints) {
        final point = _collaborationMap(rawPoint);
        points.add(
          Offset(
            _collaborationDouble(point, 'x'),
            _collaborationDouble(point, 'y'),
          ),
        );
      }
    }
    return _AnnotationRegion(
      id: id,
      mode: mode,
      rect: Rect.fromLTRB(
        _collaborationDouble(data, 'left'),
        _collaborationDouble(data, 'top'),
        _collaborationDouble(data, 'right'),
        _collaborationDouble(data, 'bottom'),
      ),
      classId: _collaborationInt(data, 'classId', fallback: 0),
      rotationDegrees: _collaborationDouble(data, 'rotation'),
      points: points,
      authorId: _collaborationString(data, 'authorId'),
      authorName: _collaborationString(data, 'authorName'),
      authorColorValue: _collaborationInt(data, 'authorColor', fallback: 0),
    );
  }

  _AnnotationRegion _withCollaborationAuthorFallback(
    _AnnotationRegion annotation,
    String fallbackUserId,
  ) {
    final userId = annotation.authorId.trim().isEmpty
        ? fallbackUserId.trim()
        : annotation.authorId;
    if (userId.isEmpty) {
      return annotation;
    }
    final peer = _collaborationPeers
        .where((item) => item.userId == userId)
        .firstOrNullValue;
    final peerName = peer?.userName.trim() ?? '';
    final peerColor = peer?.colorValue;
    final authorName = annotation.authorName.trim().isEmpty
        ? userId == _collaborationAuthorId
              ? _currentAnnotatorName
              : (peerName.isNotEmpty ? peerName : 'User')
        : annotation.authorName;
    final authorColor = annotation.authorColorValue == 0
        ? userId == _collaborationAuthorId
              ? _currentAnnotatorColorValue
              : (peerColor ?? _collaborationColorForId(userId).toARGB32())
        : annotation.authorColorValue;
    return annotation.copyWith(
      authorId: userId,
      authorName: authorName,
      authorColorValue: authorColor,
    );
  }

  void _applyCollaborationAnnotationSnapshot(
    Map<String, dynamic> message, {
    required String fromUserId,
  }) {
    if (_collaborationMode == _CollaborationMode.off) {
      return;
    }
    final imageIndex =
        _collaborationInt(message, 'imageIndex', fallback: 0) - 1;
    if (imageIndex < 0 || imageIndex >= _images.length) {
      return;
    }
    if (_collaborationMode == _CollaborationMode.host &&
        fromUserId.isNotEmpty) {
      final peer = _collaborationPeers
          .where((item) => item.userId == fromUserId)
          .firstOrNullValue;
      if (peer == null || !_collaborationPeerCanAccessImage(peer, imageIndex)) {
        return;
      }
    }
    if (_collaborationMode == _CollaborationMode.client &&
        !_isImageIndexAuthorized(imageIndex)) {
      return;
    }
    final rawAnnotations = message['annotations'];
    if (rawAnnotations is! List) {
      return;
    }
    final hasClassPayload = message['classes'] is List;
    final nextClasses = hasClassPayload
        ? _collaborationClassesFromJson(message['classes'])
        : const <_LabelClass>[];
    final sourceUserId = fromUserId.trim().isNotEmpty
        ? fromUserId.trim()
        : _collaborationString(message, 'sourceUserId').trim();
    final authorScope = _collaborationString(message, 'authorScope').trim();
    final authoritative = _collaborationBool(message, 'authoritative');
    final incoming = rawAnnotations
        .map(_collaborationAnnotationFromJson)
        .whereType<_AnnotationRegion>()
        .map(
          (annotation) =>
              _withCollaborationAuthorFallback(annotation, sourceUserId),
        )
        .toList(growable: false);
    final imageKey = _pathKey(_images[imageIndex].path);
    final incomingIds = {for (final item in incoming) item.id};
    final incomingAuthors = {
      for (final item in incoming)
        if (item.authorId.isNotEmpty) item.authorId,
    };
    setState(() {
      if (hasClassPayload) {
        _replaceLabelClassesFromCollaboration(nextClasses);
      }
      final annotations = _annotationsByImage.putIfAbsent(imageKey, () => []);
      if (authoritative) {
        annotations.removeWhere((item) => !incomingIds.contains(item.id));
      } else {
        final scopedAuthors = {
          ...incomingAuthors,
          if (authorScope.isNotEmpty) authorScope,
          if (authorScope.isEmpty && sourceUserId.isNotEmpty) sourceUserId,
        };
        annotations.removeWhere(
          (item) =>
              scopedAuthors.contains(item.authorId) &&
              !incomingIds.contains(item.id),
        );
      }
      for (final annotation in incoming) {
        final index = annotations.indexWhere(
          (item) => item.id == annotation.id,
        );
        if (index >= 0) {
          annotations[index] = annotation;
        } else {
          annotations.add(annotation);
        }
      }
    });
    unawaited(_saveCollaborationAnnotationDatabaseNow('annotation snapshot'));
    if (_collaborationMode == _CollaborationMode.host) {
      _sendCollaborationMessageToAuthorizedPeers(
        {
          ...message,
          'sourceUserId': fromUserId,
          'classes': _collaborationClassesPayload(),
        },
        imageIndex,
        excludeUserId: fromUserId,
      );
    }
  }

  void _upsertCollaborationPeer(_CollaborationPeer peer) {
    final index = _collaborationPeers.indexWhere(
      (item) => item.userId == peer.userId,
    );
    if (index >= 0) {
      _collaborationPeers[index] = _collaborationPeers[index].copyWith(
        userName: peer.userName,
        colorValue: peer.colorValue,
        address: peer.address,
        online: peer.online,
        assignmentStart: peer.assignmentStart,
        assignmentEnd: peer.assignmentEnd,
        permissions: peer.permissions,
      );
    } else {
      _collaborationPeers.add(peer);
    }
  }

  void _markCollaborationPeerOffline(String userId) {
    if (userId.isEmpty) {
      return;
    }
    setState(() {
      final index = _collaborationPeers.indexWhere(
        (peer) => peer.userId == userId,
      );
      if (index >= 0) {
        _collaborationPeers[index] = _collaborationPeers[index].copyWith(
          online: false,
        );
      }
    });
  }

  Future<void> _sendCollaborationCommand(Map<String, Object?> request) async {
    try {
      await _RustVideoBackend.collaborationCommand(request: request);
    } on Object catch (error) {
      _log(
        'COLLAB',
        'Command failed: ${request['action'] ?? '-'} $error',
        level: _LogLevel.warning,
      );
      if (mounted) {
        _showFloatingMessage(t('collab.networkError'));
      }
    }
  }

  void _sendCollaborationMessageToPeer(
    String userId,
    Map<String, Object?> message,
  ) {
    unawaited(
      _sendCollaborationCommand({
        'action': 'send_peer',
        'userId': userId,
        'message': jsonEncode(message),
      }),
    );
  }

  void _broadcastCollaborationMessage(Map<String, Object?> message) {
    if (_collaborationMode != _CollaborationMode.host) {
      return;
    }
    unawaited(
      _sendCollaborationCommand({
        'action': 'broadcast',
        'message': jsonEncode(message),
      }),
    );
  }

  void _broadcastCollaborationClassSnapshot(String reason) {
    if (_collaborationMode != _CollaborationMode.host) {
      return;
    }
    _broadcastCollaborationMessage(_collaborationClassSnapshotMessage());
    _log(
      'COLLAB',
      'Class snapshot broadcast: reason=$reason, classes=${_labelClasses.length}',
      level: _LogLevel.debug,
    );
  }

  void _broadcastCollaborationProjectSnapshot(String reason) {
    if (_collaborationMode != _CollaborationMode.host) {
      return;
    }
    var count = 0;
    for (final peer in _collaborationPeers) {
      if (!peer.online) {
        continue;
      }
      _sendCollaborationMessageToPeer(
        peer.userId,
        _collaborationProjectSnapshotMessage(
          assignmentStart: peer.assignmentStart,
          assignmentEnd: peer.assignmentEnd,
        ),
      );
      count += 1;
    }
    _log(
      'COLLAB',
      'Project snapshot broadcast: reason=$reason, peers=$count, images=${_images.length}',
      level: _LogLevel.debug,
    );
  }

  void _broadcastCollaborationAllAnnotations(String reason) {
    if (_collaborationMode != _CollaborationMode.host || _images.isEmpty) {
      return;
    }
    for (var index = 0; index < _images.length; index++) {
      final image = _images[index];
      _sendCollaborationMessageToAuthorizedPeers({
        'type': 'annotation_snapshot',
        'imagePath': image.path,
        'imageIndex': index + 1,
        'sourceUserId': _collaborationAuthorId,
        'authoritative': true,
        'classes': _collaborationClassesPayload(),
        'annotations': [
          for (final annotation in _annotationsForImagePath(image.path))
            _collaborationAnnotationToJson(annotation),
        ],
      }, index);
    }
    _log(
      'COLLAB',
      'Annotation snapshots broadcast: reason=$reason, images=${_images.length}',
      level: _LogLevel.debug,
    );
  }

  bool _collaborationPeerCanAccessImage(
    _CollaborationPeer peer,
    int zeroBasedIndex,
  ) {
    if (!peer.online || _images.isEmpty) {
      return false;
    }
    final start = peer.assignmentStart.clamp(1, _images.length).toInt();
    final end = peer.assignmentEnd.clamp(start, _images.length).toInt();
    final imageIndex = zeroBasedIndex + 1;
    return imageIndex >= start && imageIndex <= end;
  }

  void _sendCollaborationMessageToAuthorizedPeers(
    Map<String, Object?> message,
    int zeroBasedImageIndex, {
    String? excludeUserId,
  }) {
    if (_collaborationMode != _CollaborationMode.host) {
      return;
    }
    for (final peer in _collaborationPeers) {
      if (peer.userId == excludeUserId) {
        continue;
      }
      if (!_collaborationPeerCanAccessImage(peer, zeroBasedImageIndex)) {
        continue;
      }
      _sendCollaborationMessageToPeer(peer.userId, message);
    }
  }

  Map<String, dynamic> _collaborationMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return const {};
  }

  String _collaborationString(Map<String, dynamic> map, String key) =>
      '${map[key] ?? ''}';

  int _collaborationInt(
    Map<String, dynamic> map,
    String key, {
    required int fallback,
  }) {
    final value = map[key];
    if (value is num) {
      return value.round();
    }
    return int.tryParse('$value') ?? fallback;
  }

  bool _collaborationBool(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is bool) {
      return value;
    }
    return '$value'.toLowerCase() == 'true' || '$value' == '1';
  }

  double _collaborationDouble(
    Map<String, dynamic> map,
    String key, {
    double fallback = 0,
  }) {
    final value = map[key];
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('$value') ?? fallback;
  }

  void _setCollaborationUserName(String value) {
    setState(() => _collaborationUserName = value.trim());
  }

  void _setCollaborationPort(int value) {
    setState(() => _collaborationPort = value);
    _restartCollaborationDiscovery();
  }

  void _startCollaborationHost() {
    if (_images.isEmpty) {
      _showFloatingMessage(t('collab.openProjectFirst'));
      return;
    }
    final imageCount = _images.length;
    setState(() {
      _collaborationMode = _CollaborationMode.host;
      _collaborationJoining = false;
      _collaborationPeers.clear();
      _collaborationStartIndex = 1;
      _collaborationEndIndex = math.max(1, imageCount);
    });
    unawaited(_startCollaborationHostNetwork(imageCount));
  }

  Future<void> _startCollaborationHostNetwork(int imageCount) async {
    try {
      await _RustVideoBackend.collaborationCommand(
        request: {
          'action': 'start_host',
          'hostId': _collaborationHostId,
          'hostName': _currentAnnotatorName,
          'userId': _collaborationAuthorId,
          'userName': _currentAnnotatorName,
          'port': _collaborationPort,
          'projectId': _databaseProjectKey(),
          'imageCount': imageCount,
        },
      );
      _log(
        'COLLAB',
        'Host mode enabled: hostId=$_collaborationHostId, port=$_collaborationPort',
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _collaborationMode = _CollaborationMode.off);
      _showFloatingMessage(t('collab.networkError'));
      _log('COLLAB', 'Host start failed: $error', level: _LogLevel.error);
      _restartCollaborationDiscovery();
    }
  }

  void _joinCollaborationHost() {
    if (_collaborationJoining) {
      return;
    }
    final selectedHost = _collaborationDiscoveredHosts
        .where((host) => host.hostId == _selectedCollaborationHostId)
        .firstOrNullValue;
    if (selectedHost == null) {
      _showFloatingMessage(t('collab.selectHostFirst'));
      return;
    }
    unawaited(_joinCollaborationHostNetwork(selectedHost));
  }

  Future<void> _joinCollaborationHostNetwork(
    _CollaborationDiscoveredHost selectedHost,
  ) async {
    setState(() => _collaborationJoining = true);
    try {
      _connectedCollaborationHost = selectedHost;
      await _RustVideoBackend.collaborationCommand(
        request: {
          'action': 'join_host',
          'hostId': selectedHost.hostId,
          'address': selectedHost.address,
          'port': selectedHost.port,
          'userId': _collaborationAuthorId,
          'userName': _currentAnnotatorName,
          'colorValue': _currentAnnotatorColorValue,
        },
      );
      if (!mounted) {
        return;
      }
      setState(() => _collaborationJoining = false);
      _log(
        'COLLAB',
        'Join request sent: user=$_currentAnnotatorLabel, host=${selectedHost.hostId}, address=${selectedHost.address}:${selectedHost.port}',
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      _connectedCollaborationHost = null;
      setState(() => _collaborationJoining = false);
      _showFloatingMessage(t('collab.networkError'));
      _log('COLLAB', 'Join failed: $error', level: _LogLevel.error);
      _restartCollaborationDiscovery();
    }
  }

  void _startCollaborationReconnect() {
    if (_collaborationReconnecting) {
      return;
    }
    final host = _connectedCollaborationHost;
    if (host == null) {
      _disconnectCollaborationClient(clearProject: true);
      return;
    }
    setState(() {
      _collaborationReconnecting = true;
      _collaborationReconnectAttempts = 0;
      _selectedAnnotationId = null;
    });
    _log(
      'COLLAB',
      'Host disconnected, reconnecting: host=${host.hostId}',
      level: _LogLevel.warning,
    );
    _scheduleCollaborationReconnectAttempt(immediate: true);
  }

  void _scheduleCollaborationReconnectAttempt({bool immediate = false}) {
    _collaborationReconnectTimer?.cancel();
    _collaborationReconnectTimer = Timer(
      immediate ? Duration.zero : const Duration(seconds: 3),
      _attemptCollaborationReconnect,
    );
  }

  Future<void> _attemptCollaborationReconnect() async {
    if (!_collaborationReconnecting) {
      return;
    }
    final host = _connectedCollaborationHost;
    if (host == null) {
      _disconnectCollaborationClient(clearProject: true);
      return;
    }
    if (_collaborationReconnectAttempts >= 5) {
      _showFloatingMessage(t('collab.reconnectFailed'));
      _disconnectCollaborationClient(clearProject: true);
      return;
    }
    setState(() => _collaborationReconnectAttempts += 1);
    try {
      await _RustVideoBackend.collaborationCommand(
        request: {
          'action': 'join_host',
          'hostId': host.hostId,
          'address': host.address,
          'port': host.port,
          'userId': _collaborationAuthorId,
          'userName': _currentAnnotatorName,
          'colorValue': _currentAnnotatorColorValue,
        },
      );
      _log(
        'COLLAB',
        'Reconnect attempt sent: ${_collaborationReconnectAttempts}/5',
        level: _LogLevel.warning,
      );
    } on Object catch (error) {
      _log(
        'COLLAB',
        'Reconnect attempt failed: ${_collaborationReconnectAttempts}/5, error=$error',
        level: _LogLevel.warning,
      );
    }
    if (_collaborationReconnecting) {
      _scheduleCollaborationReconnectAttempt();
    }
  }

  void _cancelCollaborationReconnect() {
    _showFloatingMessage(t('collab.reconnectCancelled'));
    _disconnectCollaborationClient(clearProject: true);
  }

  void _disconnectCollaborationClient({required bool clearProject}) {
    _collaborationReconnectTimer?.cancel();
    setState(() {
      _collaborationMode = _CollaborationMode.off;
      _collaborationJoining = false;
      _collaborationReconnecting = false;
      _collaborationReconnectAttempts = 0;
      _collaborationPeers.clear();
      _pendingCollaborationJoinRequests.clear();
      _selectedCollaborationHostId = null;
      _connectedCollaborationHost = null;
      _collaborationSelfPermissions = const _CollaborationPermissions();
      _selectedAnnotationId = null;
      if (clearProject) {
        _clearCurrentProjectState();
      }
    });
    unawaited(
      _RustVideoBackend.collaborationCommand(request: const {'action': 'stop'})
          .catchError((Object error) {
            _log(
              'COLLAB',
              'Client disconnect stop failed: $error',
              level: _LogLevel.debug,
            );
            return <String, dynamic>{};
          })
          .whenComplete(_restartCollaborationDiscovery),
    );
  }

  void _stopCollaboration() {
    final wasClient = _collaborationMode == _CollaborationMode.client;
    if (!wasClient) {
      _databaseSaveTimer?.cancel();
      unawaited(_saveAnnotationDatabaseNow());
    }
    setState(() {
      _collaborationMode = _CollaborationMode.off;
      _collaborationJoining = false;
      _collaborationReconnecting = false;
      _collaborationReconnectAttempts = 0;
      _collaborationPeers.clear();
      _selectedCollaborationHostId = null;
      _connectedCollaborationHost = null;
      _pendingCollaborationJoinRequests.clear();
      _selectedAnnotationId = null;
      if (wasClient) {
        _clearCurrentProjectState();
      }
    });
    _collaborationReconnectTimer?.cancel();
    unawaited(
      _RustVideoBackend.collaborationCommand(request: const {'action': 'stop'})
          .catchError((Object error) {
            _log('COLLAB', 'Stop failed: $error', level: _LogLevel.warning);
            return <String, dynamic>{};
          })
          .whenComplete(_restartCollaborationDiscovery),
    );
    _log('COLLAB', 'Collaboration stopped');
  }

  void _setCollaborationPeerPermissions(
    _CollaborationPeerPermissionResult result,
  ) {
    final max = math.max(1, _images.length);
    final assignmentStart = result.assignmentStart.clamp(1, max).toInt();
    final assignmentEnd = result.assignmentEnd
        .clamp(assignmentStart, max)
        .toInt();
    setState(() {
      final index = _collaborationPeers.indexWhere(
        (peer) => peer.userId == result.userId,
      );
      if (index >= 0) {
        _collaborationPeers[index] = _collaborationPeers[index].copyWith(
          assignmentStart: assignmentStart,
          assignmentEnd: assignmentEnd,
          permissions: result.permissions,
        );
      }
    });
    _log(
      'COLLAB',
      'Peer permissions updated: user=${result.userId}, assignment=$assignmentStart-$assignmentEnd, edit=${result.permissions.canEditOthers}, delete=${result.permissions.canDeleteOthers}, class=${result.permissions.canChangeClass}',
      level: _LogLevel.debug,
    );
    _sendCollaborationMessageToPeer(result.userId, {
      'type': 'permission_update',
      'assignmentStart': assignmentStart,
      'assignmentEnd': assignmentEnd,
      'permissions': {
        'canEditOthers': result.permissions.canEditOthers,
        'canDeleteOthers': result.permissions.canDeleteOthers,
        'canChangeClass': result.permissions.canChangeClass,
      },
    });
    _sendCollaborationMessageToPeer(
      result.userId,
      _collaborationProjectSnapshotMessage(
        assignmentStart: assignmentStart,
        assignmentEnd: assignmentEnd,
      ),
    );
    _scheduleAnnotationDatabaseSave();
  }

  @override
  Widget build(BuildContext context) {
    final labelPage = _activeSection == 'label';

    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                _TopMenuBar(
                  visible: _topMenuVisible,
                  recentFolders: _recentFolders
                      .map((entry) => entry.path)
                      .toList(),
                  recentFiles: _recentFiles.map((entry) => entry.path).toList(),
                  languageOptions: _languageOptions,
                  activeLanguageCode: _activeLanguageCode,
                  projectActionsLocked: _projectLockedByCollaboration,
                  onOpenFile: () => _openImageFile(),
                  onOpenFolder: () => _openImageFolder(),
                  onOpenRecentFolder: (path) =>
                      unawaited(_openRecentFolder(path)),
                  onOpenRecentFile: _openRecentFile,
                  onClearRecent: _clearRecentItems,
                  onExit: () => SystemNavigator.pop(),
                  onImportDataset: _importYoloDataset,
                  onExportDataset: _showExportDialog,
                  onShowTrainingHistory: _showTrainingHistoryDialog,
                  onUndo: _undoAnnotationChange,
                  onRedo: _redoAnnotationChange,
                  onCopy: _copySelectedAnnotation,
                  onPaste: _pasteAnnotation,
                  onShowSettings: _showSettings,
                  onShowLogs: _showLogViewerDialog,
                  onShowHelp: _showKeySettings,
                  onShowAbout: _showAboutDialog,
                  onProjectActionBlocked: () =>
                      _showFloatingMessage(t('collab.disconnectFirst')),
                  onLanguageSelected: _changeLanguage,
                  onPointerEnter: _showTopMenu,
                  onPointerExit: _scheduleTopMenuHide,
                ),
                Expanded(
                  child: Row(
                    children: [
                      _PrimarySidebar(
                        activeSection: _activeSection,
                        collapsed: _sidebarCollapsed,
                        onCollapseChanged: (value) {
                          setState(() => _sidebarCollapsed = value);
                        },
                        onSectionSelected: (section) {
                          _log(
                            'NAV',
                            'Switched to: $section',
                            level: _LogLevel.debug,
                          );
                          setState(() => _activeSection = section);
                        },
                      ),
                      Expanded(
                        child: IndexedStack(
                          index: _activeSection == 'label'
                              ? 0
                              : _activeSection == 'train'
                              ? 1
                              : _activeSection == 'crop'
                              ? 2
                              : _activeSection == 'collaboration'
                              ? 3
                              : _activeSection == 'database'
                              ? 5
                              : 4,
                          children: [
                            _LabelPage(
                              status: widget.status,
                              images: _images,
                              selectedImage: _selectedImageForLabel,
                              selectedImageIndex: _selectedImageIndex,
                              unauthorized:
                                  _collaborationClientMode &&
                                  !_selectedImageAuthorized,
                              zoom: _zoom,
                              viewportOffset: _labelViewportOffset,
                              activeTool: _activeTool,
                              activeMode: _activeAnnotationMode,
                              imageSplit: _selectedImageSplit,
                              activeClassId: _activeClassId,
                              labelClasses: _labelClasses,
                              annotationsByImage: _annotationsByImage,
                              annotations: _currentAnnotationsForLabel,
                              selectedAnnotationId: _selectedAnnotationId,
                              showClassLabels: _showClassLabels,
                              classesEditable: !_collaborationClientMode,
                              onImageSelected: _selectImage,
                              onImageContextMenu: _showImageContextMenu,
                              onPointerSignal: _handlePointerSignal,
                              onViewportOffsetChanged: _setLabelViewportOffset,
                              onToolSelected: _selectTool,
                              onSelectMode: () => _selectTool('select'),
                              onModeSelected: _activateAnnotationMode,
                              onImageSplitChanged: _setSelectedImageSplit,
                              onEnsureClass: _ensureActiveClass,
                              onAnnotationCreated: _createAnnotation,
                              onSegAnnotationCreated: _createSegAnnotation,
                              onAnnotationSelected: _selectAnnotation,
                              onAnnotationUpdated: _updateAnnotation,
                              onAnnotationDeleted: _deleteAnnotation,
                              onAnnotationDragStarted: _pushAnnotationSnapshot,
                              onClassSelected: _selectLabelClass,
                              onClassAdded: () => _addLabelClass(),
                              onClassEdited: _editLabelClass,
                              onClassColorChanged: _chooseLabelClassColor,
                              onClassDeleted: _deleteLabelClass,
                              onClassReordered: _reorderLabelClass,
                              onToggleClassLabels: () => setState(
                                () => _showClassLabels = !_showClassLabels,
                              ),
                              onAnnotationClassChanged: _changeAnnotationClass,
                              onSam3ClickPrompt: _handleSam3ClickPrompt,
                              aiPanelVisible: _aiPanelVisible,
                              onAiConfigPressed: () {
                                setState(
                                  () => _aiPanelVisible = !_aiPanelVisible,
                                );
                              },
                              onImageDisplaySizeChanged: (size) {
                                _imageDisplaySize = size;
                                final key = _selectedImageKey;
                                if (key != null && size != Size.zero) {
                                  _imageDisplaySizes[key] = size;
                                  _scheduleAnnotationDatabaseSave();
                                }
                              },
                            ),
                            _TrainPage(
                              key: _trainPageKey,
                              settings: _appSettings,
                            ),
                            _CropPage(exportPath: _appSettings.exportPath),
                            _CollaborationPage(
                              mode: _collaborationMode,
                              hostId: _collaborationHostId,
                              userId: _collaborationUserId,
                              userName: _collaborationUserName,
                              userColor: Color(_currentAnnotatorColorValue),
                              port: _collaborationPort,
                              imageCount: _images.length,
                              assignmentStart: _collaborationStartIndex,
                              assignmentEnd: _collaborationEndIndex,
                              discoveredHosts: _collaborationDiscoveredHosts,
                              selectedHostId: _selectedCollaborationHostId,
                              joining: _collaborationJoining,
                              peers: _collaborationPeers,
                              onUserNameChanged: _setCollaborationUserName,
                              onPortChanged: _setCollaborationPort,
                              onHostSelected: (hostId) => setState(
                                () => _selectedCollaborationHostId = hostId,
                              ),
                              onStartHost: _startCollaborationHost,
                              onJoinClient: _joinCollaborationHost,
                              onStop: _stopCollaboration,
                              onPeerPermissionsChanged:
                                  _setCollaborationPeerPermissions,
                            ),
                            _DetectVideoPage(
                              settings: _appSettings,
                              shortcutConfig: _shortcutConfig,
                              session: _detectVideoSession,
                            ),
                            const _DatabasePage(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (labelPage)
                  _BottomControls(
                    zoom: _zoom,
                    zoomLocked: _zoomLocked,
                    darkMode: _darkMode,
                    onZoomChanged: _setZoom,
                    onResetView: _resetZoomAndViewport,
                    onToggleZoomLock: _toggleZoomLock,
                    onToggleThemeMode: _toggleThemeMode,
                    onOpenKeySettings: _showKeySettings,
                  ),
              ],
            ),
            if (labelPage && _aiPanelVisible)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final viewport = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    final panelSize = _clampAiAssistPanelSize(
                      _aiAssistPanelSize,
                      viewport,
                    );
                    final defaultOffset = Offset(
                      math.max(
                        _aiAssistPanelMargin,
                        constraints.maxWidth -
                            panelSize.width -
                            _toolbarWidth -
                            16,
                      ),
                      _topMenuHeight + 18,
                    );
                    final panelOffset = _clampAiAssistPanelOffset(
                      _aiAssistPanelOffset ?? defaultOffset,
                      viewport,
                      panelSize,
                    );
                    return Stack(
                      children: [
                        Positioned(
                          left: panelOffset.dx,
                          top: panelOffset.dy,
                          child: _AiAssistFloatingPanel(
                            width: panelSize.width,
                            height: panelSize.height,
                            initialConfig: _aiAssistConfig,
                            imageCount: _images.length,
                            pythonPath: _appSettings.pythonPath,
                            onClose: () =>
                                setState(() => _aiPanelVisible = false),
                            onDrag: (delta) => _moveAiAssistPanel(
                              delta,
                              viewport,
                              panelSize,
                              panelOffset,
                            ),
                            onResize: (delta) => _resizeAiAssistPanel(
                              delta,
                              viewport,
                              panelSize,
                              panelOffset,
                            ),
                            onConfigSaved: _saveAiAssistConfig,
                            onAnnotateCurrent: _runAiAnnotateCurrentWithConfig,
                            onAnnotateAll: _runAiAnnotateAllWithConfig,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            if (_importingDataset)
              const Positioned.fill(child: _ImportBlockingOverlay()),
            if (_aiAnnotating)
              Positioned.fill(
                child: _ImportBlockingOverlay(message: t('ai.annotating')),
              ),
            if (_collaborationReconnecting)
              Positioned.fill(
                child: _CollaborationReconnectOverlay(
                  attempts: _collaborationReconnectAttempts,
                  onCancel: _cancelCollaborationReconnect,
                ),
              ),
            if (_videoFullscreenVisible)
              Positioned.fill(
                child: _VideoFullscreenOverlay(
                  session: _detectVideoSession,
                  shortcutConfig: _shortcutConfig,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ImportBlockingOverlay extends StatelessWidget {
  const _ImportBlockingOverlay({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: true,
      child: ColoredBox(
        color: Colors.white.withValues(alpha: 0.78),
        child: Center(
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 220),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 42,
                    height: 42,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    message ?? t('import.waiting'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                      fontFamily: _fontFamily,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CollaborationReconnectOverlay extends StatelessWidget {
  const _CollaborationReconnectOverlay({
    required this.attempts,
    required this.onCancel,
  });

  final int attempts;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AbsorbPointer(
          absorbing: true,
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.32)),
        ),
        Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _panelColor(context),
              border: Border.all(color: _borderColor(context)),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '${t('collab.reconnecting')} ${attempts.clamp(1, 5)}/5',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: onCancel,
                    child: Text(t('action.cancel')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum _AiAssistBackend { yolo, sam3 }

enum _AiSam3OutputMode { hbb, obb, seg }

enum _AiSam3PromptMode { text, click }

extension _AiAssistBackendMeta on _AiAssistBackend {
  String get wireName => switch (this) {
    _AiAssistBackend.yolo => 'yolo',
    _AiAssistBackend.sam3 => 'sam3',
  };
}

extension _AiSam3OutputModeMeta on _AiSam3OutputMode {
  String get wireName => switch (this) {
    _AiSam3OutputMode.hbb => 'hbb',
    _AiSam3OutputMode.obb => 'obb',
    _AiSam3OutputMode.seg => 'seg',
  };

  _AnnotationMode get annotationMode => switch (this) {
    _AiSam3OutputMode.hbb => _AnnotationMode.hbb,
    _AiSam3OutputMode.obb => _AnnotationMode.obb,
    _AiSam3OutputMode.seg => _AnnotationMode.seg,
  };
}

extension _AiSam3PromptModeMeta on _AiSam3PromptMode {
  String get wireName => switch (this) {
    _AiSam3PromptMode.text => 'text',
    _AiSam3PromptMode.click => 'click',
  };
}

class _AiSam3RuntimeConfig {
  const _AiSam3RuntimeConfig({
    this.precision = 'fp16',
    this.encoder = 'vit_b',
    this.imageBatchSize = 1,
    this.videoBatchSize = 1,
    this.interactiveBatchSize = 1,
    this.maxImageWidth = 1024,
    this.maxImageHeight = 768,
    this.resizeMethod = 'shorter_side',
  });

  final String precision;
  final String encoder;
  final int imageBatchSize;
  final int videoBatchSize;
  final int interactiveBatchSize;
  final int maxImageWidth;
  final int maxImageHeight;
  final String resizeMethod;

  _AiSam3RuntimeConfig copyWith({
    String? precision,
    String? encoder,
    int? imageBatchSize,
    int? videoBatchSize,
    int? interactiveBatchSize,
    int? maxImageWidth,
    int? maxImageHeight,
    String? resizeMethod,
  }) {
    return _AiSam3RuntimeConfig(
      precision: precision ?? this.precision,
      encoder: encoder ?? this.encoder,
      imageBatchSize: imageBatchSize ?? this.imageBatchSize,
      videoBatchSize: videoBatchSize ?? this.videoBatchSize,
      interactiveBatchSize: interactiveBatchSize ?? this.interactiveBatchSize,
      maxImageWidth: maxImageWidth ?? this.maxImageWidth,
      maxImageHeight: maxImageHeight ?? this.maxImageHeight,
      resizeMethod: resizeMethod ?? this.resizeMethod,
    );
  }

  String get logSummary =>
      'precision=$precision, encoder=$encoder, batch=image:$imageBatchSize/video:$videoBatchSize/interactive:$interactiveBatchSize, preResize=${maxImageWidth}x$maxImageHeight, resize=$resizeMethod, processor=1008';
}

class _AiAssistConfig {
  const _AiAssistConfig({
    this.backend = _AiAssistBackend.yolo,
    required this.modelPath,
    required this.classes,
    required this.selectedClassIds,
    required this.startIndex,
    required this.endIndex,
    this.confThreshold = 0.25,
    this.imageSize = 640,
    this.sam3OutputMode = _AiSam3OutputMode.seg,
    this.sam3PromptMode = _AiSam3PromptMode.text,
    this.sam3PromptText = '',
    this.sam3Runtime = const _AiSam3RuntimeConfig(),
  });

  final _AiAssistBackend backend;
  final String modelPath;
  final List<_AiModelClass> classes;
  final Set<int> selectedClassIds;
  final int startIndex;
  final int endIndex;
  final double confThreshold;
  final int imageSize;
  final _AiSam3OutputMode sam3OutputMode;
  final _AiSam3PromptMode sam3PromptMode;
  final String sam3PromptText;
  final _AiSam3RuntimeConfig sam3Runtime;
}

class _Sam3ClickPromptPoint {
  const _Sam3ClickPromptPoint({
    required this.x,
    required this.y,
    required this.positive,
  });

  final double x;
  final double y;
  final bool positive;

  String get wireLine =>
      '${x.toStringAsFixed(6)},${y.toStringAsFixed(6)},${positive ? 1 : 0}';
}

double _normalizeAiConfidence(double value) {
  if (!value.isFinite) {
    return 0.25;
  }
  return ((value / 0.05).round() * 0.05).clamp(0.05, 0.95).toDouble();
}

class _AiAssistFloatingPanel extends StatefulWidget {
  const _AiAssistFloatingPanel({
    required this.initialConfig,
    required this.imageCount,
    required this.pythonPath,
    required this.width,
    required this.height,
    required this.onClose,
    required this.onDrag,
    required this.onResize,
    required this.onConfigSaved,
    required this.onAnnotateCurrent,
    required this.onAnnotateAll,
  });

  final _AiAssistConfig? initialConfig;
  final int imageCount;
  final String pythonPath;
  final double width;
  final double height;
  final VoidCallback onClose;
  final ValueChanged<Offset> onDrag;
  final ValueChanged<Offset> onResize;
  final ValueChanged<_AiAssistConfig> onConfigSaved;
  final Future<void> Function(_AiAssistConfig config) onAnnotateCurrent;
  final Future<void> Function(_AiAssistConfig config) onAnnotateAll;

  @override
  State<_AiAssistFloatingPanel> createState() => _AiAssistFloatingPanelState();
}

class _AiAssistFloatingPanelState extends State<_AiAssistFloatingPanel> {
  late final TextEditingController _startController;
  late final TextEditingController _endController;
  late final TextEditingController _sam3PromptController;
  _AiAssistBackend _backend = _AiAssistBackend.yolo;
  String? _yoloModelPath;
  String? _sam3ModelPath;
  List<_AiModelClass> _classes = const [];
  Set<int> _selectedClassIds = <int>{};
  double _confThreshold = 0.25;
  _AiSam3OutputMode _sam3OutputMode = _AiSam3OutputMode.seg;
  _AiSam3PromptMode _sam3PromptMode = _AiSam3PromptMode.text;
  _AiSam3RuntimeConfig _sam3Runtime = const _AiSam3RuntimeConfig();
  bool _loadingClasses = false;
  String? _error;

  String? get _modelPath =>
      _backend == _AiAssistBackend.sam3 ? _sam3ModelPath : _yoloModelPath;

  set _modelPath(String? value) {
    if (_backend == _AiAssistBackend.sam3) {
      _sam3ModelPath = value;
    } else {
      _yoloModelPath = value;
    }
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialConfig;
    _backend = initial?.backend ?? _AiAssistBackend.yolo;
    if (initial?.backend == _AiAssistBackend.sam3) {
      _sam3ModelPath = initial?.modelPath;
    } else {
      _yoloModelPath = initial?.modelPath;
    }
    final savedSam3ModelPath = _ConfigStore.loadLastSam3ModelPath();
    if (savedSam3ModelPath.isNotEmpty) {
      _sam3ModelPath = savedSam3ModelPath;
    }
    _classes = initial?.classes ?? const [];
    _selectedClassIds = initial?.selectedClassIds.toSet() ?? <int>{};
    _confThreshold = _normalizeAiConfidence(initial?.confThreshold ?? 0.25);
    _sam3OutputMode = initial?.sam3OutputMode ?? _AiSam3OutputMode.seg;
    _sam3PromptMode = initial?.sam3PromptMode ?? _AiSam3PromptMode.text;
    _sam3Runtime = initial?.sam3Runtime ?? const _AiSam3RuntimeConfig();
    _startController = TextEditingController(
      text: (initial?.startIndex ?? 1).toString(),
    );
    _endController = TextEditingController(
      text: (initial?.endIndex ?? math.max(1, widget.imageCount)).toString(),
    );
    _sam3PromptController = TextEditingController(
      text: initial?.sam3PromptText ?? '',
    );
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    _sam3PromptController.dispose();
    super.dispose();
  }

  Future<void> _chooseModel() async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: _backend == _AiAssistBackend.sam3
              ? 'SAM3 checkpoint'
              : 'YOLO AI model',
          extensions: _backend == _AiAssistBackend.sam3
              ? const ['pt', 'pth', 'safetensors']
              : const ['pt', 'onnx'],
        ),
      ],
    );
    if (file == null) {
      return;
    }
    final path = file.path;
    if (_backend == _AiAssistBackend.yolo &&
        !path.toLowerCase().endsWith('.pt')) {
      setState(() {
        _modelPath = path;
        _classes = const [];
        _selectedClassIds = <int>{};
        _error = t('ai.onnxNotSupported');
      });
      return;
    }
    if (_backend == _AiAssistBackend.sam3) {
      setState(() {
        _modelPath = path;
        _error = null;
      });
      _ConfigStore.saveLastSam3ModelPath(path);
      _saveDraftIfValid();
      return;
    }
    final pythonPath = widget.pythonPath.trim();
    if (pythonPath.isEmpty) {
      setState(() => _error = t('detect.pythonNotConfigured'));
      return;
    }
    setState(() {
      _modelPath = path;
      _loadingClasses = true;
      _error = null;
    });
    try {
      final result = await _RustVideoBackend.aiModelClasses(
        pythonPath: pythonPath,
        modelPath: path,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _classes = result.classes;
        _selectedClassIds = result.classes.map((item) => item.id).toSet();
        _loadingClasses = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _classes = const [];
        _selectedClassIds = <int>{};
        _loadingClasses = false;
        _error = '${t('ai.readClassesFailed')}: $error';
      });
    }
  }

  _AiAssistConfig? _configFromFields({bool showErrors = true}) {
    final modelPath = _modelPath;
    if (modelPath == null || modelPath.trim().isEmpty) {
      if (showErrors) {
        setState(() => _error = t('ai.chooseModelFirst'));
      }
      return null;
    }
    if (_backend == _AiAssistBackend.yolo && _selectedClassIds.isEmpty) {
      if (showErrors) {
        setState(() => _error = t('ai.noSelectedClasses'));
      }
      return null;
    }
    if (_backend == _AiAssistBackend.sam3 &&
        _sam3PromptMode == _AiSam3PromptMode.text &&
        _sam3PromptController.text.trim().isEmpty) {
      if (showErrors) {
        setState(() => _error = t('ai.sam3PromptRequired'));
      }
      return null;
    }
    final start = int.tryParse(_startController.text.trim()) ?? 1;
    final end = int.tryParse(_endController.text.trim()) ?? start;
    final maxIndex = math.max(1, widget.imageCount);
    final normalizedStart = start.clamp(1, maxIndex).toInt();
    final normalizedEnd = end.clamp(normalizedStart, maxIndex).toInt();
    return _AiAssistConfig(
      backend: _backend,
      modelPath: modelPath,
      classes: _classes,
      selectedClassIds: _selectedClassIds.toSet(),
      startIndex: normalizedStart,
      endIndex: normalizedEnd,
      confThreshold: _normalizeAiConfidence(_confThreshold),
      imageSize: _backend == _AiAssistBackend.sam3
          ? math.max(_sam3Runtime.maxImageWidth, _sam3Runtime.maxImageHeight)
          : 640,
      sam3OutputMode: _sam3OutputMode,
      sam3PromptMode: _sam3PromptMode,
      sam3PromptText: _sam3PromptController.text,
      sam3Runtime: _sam3Runtime,
    );
  }

  void _saveDraftIfValid() {
    final config = _configFromFields(showErrors: false);
    if (config != null) {
      widget.onConfigSaved(config);
    }
  }

  void _save() {
    final config = _configFromFields();
    if (config == null) {
      return;
    }
    widget.onConfigSaved(config);
    setState(() => _error = null);
  }

  Future<void> _annotateCurrent() async {
    final config = _configFromFields();
    if (config == null) {
      return;
    }
    widget.onConfigSaved(config);
    setState(() => _error = null);
    await widget.onAnnotateCurrent(config);
  }

  Future<void> _annotateAll() async {
    final config = _configFromFields();
    if (config == null) {
      return;
    }
    widget.onConfigSaved(config);
    setState(() => _error = null);
    await widget.onAnnotateAll(config);
  }

  Future<void> _editSam3Runtime() async {
    final next = await showDialog<_AiSam3RuntimeConfig>(
      context: context,
      builder: (context) => _Sam3RuntimeDialog(initial: _sam3Runtime),
    );
    if (next == null || !mounted) {
      return;
    }
    setState(() {
      _sam3Runtime = next;
      _error = null;
    });
    _saveDraftIfValid();
  }

  Widget _rangeFields() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _startController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: t('ai.startImageIndex'),
              isDense: true,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('-'),
        ),
        Expanded(
          child: TextField(
            controller: _endController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: t('ai.endImageIndex'),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _confidenceSlider({required bool disabled}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${t('ai.confidence')} ${_confThreshold.toStringAsFixed(2)}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Slider(
          min: 0.05,
          max: 0.95,
          divisions: 18,
          value: _normalizeAiConfidence(_confThreshold),
          label: _normalizeAiConfidence(_confThreshold).toStringAsFixed(2),
          onChanged: disabled
              ? null
              : (value) {
                  setState(() {
                    _confThreshold = _normalizeAiConfidence(value);
                  });
                },
        ),
      ],
    );
  }

  Widget _modelRow({required bool disabled}) {
    final modelPath = _modelPath;
    return Row(
      children: [
        Expanded(
          child: Text(
            modelPath ?? t('ai.noModel'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: disabled ? null : _chooseModel,
          icon: const Icon(Icons.folder_open, size: 16),
          label: Text(t('ai.chooseModel')),
        ),
      ],
    );
  }

  Widget _yoloTab({required bool disabled}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _modelRow(disabled: disabled),
        const SizedBox(height: 14),
        _rangeFields(),
        const SizedBox(height: 14),
        _confidenceSlider(disabled: disabled),
        const SizedBox(height: 8),
        if (_loadingClasses)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: CircularProgressIndicator(),
            ),
          )
        else
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: _borderColor(context)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ExpansionTile(
              initiallyExpanded: true,
              title: Text(t('ai.classes')),
              subtitle: Text(
                '${_selectedClassIds.length} / ${_classes.length}',
              ),
              children: [
                CheckboxListTile(
                  dense: true,
                  value:
                      _classes.isNotEmpty &&
                      _selectedClassIds.length == _classes.length,
                  onChanged: _classes.isEmpty
                      ? null
                      : (value) {
                          setState(() {
                            _selectedClassIds = value == true
                                ? _classes.map((item) => item.id).toSet()
                                : <int>{};
                          });
                        },
                  title: Text(t('ai.selectAllClasses')),
                ),
                for (final item in _classes)
                  CheckboxListTile(
                    dense: true,
                    value: _selectedClassIds.contains(item.id),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedClassIds.add(item.id);
                        } else {
                          _selectedClassIds.remove(item.id);
                        }
                      });
                    },
                    title: Text('${item.id}: ${item.name}'),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _sam3Tab({required bool disabled}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _modelRow(disabled: disabled),
        const SizedBox(height: 14),
        _rangeFields(),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: SegmentedButton<_AiSam3OutputMode>(
                segments: const [
                  ButtonSegment(
                    value: _AiSam3OutputMode.hbb,
                    label: Text('HBB'),
                  ),
                  ButtonSegment(
                    value: _AiSam3OutputMode.obb,
                    label: Text('OBB'),
                  ),
                  ButtonSegment(
                    value: _AiSam3OutputMode.seg,
                    label: Text('SEG'),
                  ),
                ],
                selected: {_sam3OutputMode},
                onSelectionChanged: disabled
                    ? null
                    : (value) {
                        setState(() => _sam3OutputMode = value.first);
                        _saveDraftIfValid();
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SegmentedButton<_AiSam3PromptMode>(
          segments: [
            ButtonSegment(
              value: _AiSam3PromptMode.text,
              label: Text(t('ai.sam3PromptText')),
            ),
            ButtonSegment(
              value: _AiSam3PromptMode.click,
              label: Text(t('ai.sam3PromptClick')),
            ),
          ],
          selected: {_sam3PromptMode},
          onSelectionChanged: disabled
              ? null
              : (value) {
                  setState(() => _sam3PromptMode = value.first);
                  _saveDraftIfValid();
                },
        ),
        const SizedBox(height: 12),
        if (_sam3PromptMode == _AiSam3PromptMode.text)
          TextField(
            controller: _sam3PromptController,
            minLines: 3,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: t('ai.sam3PromptLabel'),
              hintText: t('ai.sam3PromptHint'),
              alignLabelWithHint: true,
            ),
          )
        else
          Text(
            t('ai.sam3ClickHint'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 12),
        _confidenceSlider(disabled: disabled),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: disabled ? null : _editSam3Runtime,
          icon: const Icon(Icons.tune, size: 16),
          label: Text(t('ai.sam3RuntimeConfig')),
        ),
        const SizedBox(height: 8),
        Text(
          _sam3Runtime.logSummary,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final disabled = _loadingClasses;

    return Material(
      elevation: 18,
      color: _panelColor(context),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: _borderColor(context)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DefaultTabController(
                  length: 2,
                  initialIndex: _backend.index,
                  child: Column(
                    children: [
                      MouseRegion(
                        cursor: SystemMouseCursors.move,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanUpdate: (details) =>
                              widget.onDrag(details.delta),
                          child: Container(
                            height: 46,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: _controlColor(context),
                              border: Border(
                                bottom: BorderSide(
                                  color: _borderColor(context),
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.auto_awesome, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    t('ai.configTitle'),
                                    style: textTheme.titleMedium,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  tooltip: t('action.close'),
                                  onPressed: widget.onClose,
                                  icon: const Icon(Icons.close, size: 18),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      TabBar(
                        onTap: (index) {
                          setState(() {
                            _backend = _AiAssistBackend.values[index];
                            _error = null;
                          });
                          _saveDraftIfValid();
                        },
                        tabs: const [
                          Tab(text: 'YOLO'),
                          Tab(text: 'SAM3'),
                        ],
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_backend == _AiAssistBackend.yolo)
                                _yoloTab(disabled: disabled)
                              else
                                _sam3Tab(disabled: disabled),
                              if (_error != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  _error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.tonalIcon(
                                    onPressed: disabled
                                        ? null
                                        : _annotateCurrent,
                                    icon: const Icon(
                                      Icons.image_search_outlined,
                                      size: 17,
                                    ),
                                    label: Text(t('ai.annotateCurrent')),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: disabled ? null : _annotateAll,
                                    icon: const Icon(
                                      Icons.auto_awesome_motion,
                                      size: 17,
                                    ),
                                    label: Text(t('ai.annotateAll')),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: widget.onClose,
                                  child: Text(t('action.cancel')),
                                ),
                                const SizedBox(width: 10),
                                OutlinedButton(
                                  onPressed: disabled ? null : _save,
                                  child: Text(t('action.save')),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpLeftDownRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) => widget.onResize(details.delta),
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.open_in_full,
                          size: 14,
                          color: _primaryTextColor(
                            context,
                          ).withValues(alpha: 0.72),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sam3RuntimeDialog extends StatefulWidget {
  const _Sam3RuntimeDialog({required this.initial});

  final _AiSam3RuntimeConfig initial;

  @override
  State<_Sam3RuntimeDialog> createState() => _Sam3RuntimeDialogState();
}

class _Sam3RuntimeDialogState extends State<_Sam3RuntimeDialog> {
  late String _precision;
  late String _encoder;
  late String _resizeMethod;
  late final TextEditingController _imageBatchController;
  late final TextEditingController _videoBatchController;
  late final TextEditingController _interactiveBatchController;
  late final TextEditingController _maxWidthController;
  late final TextEditingController _maxHeightController;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _precision = initial.precision;
    _encoder = initial.encoder;
    _resizeMethod = initial.resizeMethod == 'shorter_side'
        ? initial.resizeMethod
        : 'shorter_side';
    _imageBatchController = TextEditingController(
      text: initial.imageBatchSize.toString(),
    );
    _videoBatchController = TextEditingController(
      text: initial.videoBatchSize.toString(),
    );
    _interactiveBatchController = TextEditingController(
      text: initial.interactiveBatchSize.toString(),
    );
    _maxWidthController = TextEditingController(
      text: initial.maxImageWidth.toString(),
    );
    _maxHeightController = TextEditingController(
      text: initial.maxImageHeight.toString(),
    );
  }

  @override
  void dispose() {
    _imageBatchController.dispose();
    _videoBatchController.dispose();
    _interactiveBatchController.dispose();
    _maxWidthController.dispose();
    _maxHeightController.dispose();
    super.dispose();
  }

  int _intValue(TextEditingController controller, int fallback) {
    final value = int.tryParse(controller.text.trim()) ?? fallback;
    return value.clamp(1, 4096).toInt();
  }

  void _save() {
    Navigator.of(context).pop(
      _AiSam3RuntimeConfig(
        precision: _precision,
        encoder: _encoder,
        imageBatchSize: _intValue(_imageBatchController, 1),
        videoBatchSize: _intValue(_videoBatchController, 1),
        interactiveBatchSize: _intValue(_interactiveBatchController, 1),
        maxImageWidth: _intValue(_maxWidthController, 1024),
        maxImageHeight: _intValue(_maxHeightController, 768),
        resizeMethod: _resizeMethod,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t('ai.sam3RuntimeConfig')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _precision,
                decoration: InputDecoration(labelText: t('ai.sam3Precision')),
                items: const [
                  DropdownMenuItem(value: 'fp16', child: Text('fp16')),
                  DropdownMenuItem(value: 'bf16', child: Text('bf16')),
                  DropdownMenuItem(value: 'fp32', child: Text('fp32')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _precision = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _encoder,
                decoration: InputDecoration(labelText: t('ai.sam3Encoder')),
                items: const [
                  DropdownMenuItem(value: 'vit_b', child: Text('vit_b')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _encoder = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _resizeMethod,
                decoration: InputDecoration(
                  labelText: t('ai.sam3ResizeMethod'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'shorter_side',
                    child: Text(t('ai.sam3ResizeShorterSide')),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _resizeMethod = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _imageBatchController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: t('ai.sam3BatchImage'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _videoBatchController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: t('ai.sam3BatchVideo'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _interactiveBatchController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: t('ai.sam3BatchInteractive'),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _maxWidthController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: t('ai.sam3MaxWidth'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _maxHeightController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: t('ai.sam3MaxHeight'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t('action.cancel')),
        ),
        FilledButton(onPressed: _save, child: Text(t('action.save'))),
      ],
    );
  }
}

class _AiOrientedRect {
  const _AiOrientedRect({required this.rect, required this.rotationDegrees});

  final Rect rect;
  final double rotationDegrees;
}

class _TopMenuBar extends StatelessWidget {
  const _TopMenuBar({
    required this.visible,
    required this.recentFolders,
    required this.recentFiles,
    required this.languageOptions,
    required this.activeLanguageCode,
    required this.projectActionsLocked,
    required this.onOpenFile,
    required this.onOpenFolder,
    required this.onOpenRecentFolder,
    required this.onOpenRecentFile,
    required this.onClearRecent,
    required this.onExit,
    required this.onImportDataset,
    required this.onExportDataset,
    required this.onShowTrainingHistory,
    required this.onUndo,
    required this.onRedo,
    required this.onCopy,
    required this.onPaste,
    required this.onShowSettings,
    required this.onShowLogs,
    required this.onShowHelp,
    required this.onShowAbout,
    required this.onProjectActionBlocked,
    required this.onLanguageSelected,
    required this.onPointerEnter,
    required this.onPointerExit,
  });

  final bool visible;
  final List<String> recentFolders;
  final List<String> recentFiles;
  final List<_LanguageOption> languageOptions;
  final String activeLanguageCode;
  final bool projectActionsLocked;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenFolder;
  final ValueChanged<String> onOpenRecentFolder;
  final ValueChanged<String> onOpenRecentFile;
  final VoidCallback onClearRecent;
  final VoidCallback onExit;
  final VoidCallback onImportDataset;
  final VoidCallback onExportDataset;
  final VoidCallback onShowTrainingHistory;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onShowSettings;
  final VoidCallback onShowLogs;
  final VoidCallback onShowHelp;
  final VoidCallback onShowAbout;
  final VoidCallback onProjectActionBlocked;
  final Future<void> Function(String code) onLanguageSelected;
  final VoidCallback onPointerEnter;
  final VoidCallback onPointerExit;

  @override
  Widget build(BuildContext context) {
    final lockedColor = Theme.of(context).disabledColor;
    return MouseRegion(
      onEnter: (_) => onPointerEnter(),
      onHover: (_) => onPointerEnter(),
      onExit: (_) => onPointerExit(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: visible ? _topMenuHeight : _topMenuCollapsedHeight,
        decoration: BoxDecoration(
          color: _panelColor(context),
          border: Border(bottom: BorderSide(color: _borderColor(context))),
        ),
        child: ClipRect(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: visible ? 1 : 0,
            child: IgnorePointer(
              ignoring: !visible,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Text(
                    t('app.title'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(width: 16),
                  MenuBar(
                    style: MenuStyle(
                      backgroundColor: WidgetStatePropertyAll(
                        _panelColor(context),
                      ),
                      elevation: const WidgetStatePropertyAll(0),
                    ),
                    children: [
                      SubmenuButton(
                        menuChildren: [
                          MenuItemButton(
                            onPressed: _projectAction(onOpenFile),
                            leadingIcon: Icon(
                              Icons.image_outlined,
                              color: projectActionsLocked ? lockedColor : null,
                            ),
                            child: Text(
                              t('menu.openFile'),
                              style: _projectActionTextStyle(context),
                            ),
                          ),
                          MenuItemButton(
                            onPressed: _projectAction(onOpenFolder),
                            leadingIcon: Icon(
                              Icons.folder_open,
                              color: projectActionsLocked ? lockedColor : null,
                            ),
                            child: Text(
                              t('menu.openFolder'),
                              style: _projectActionTextStyle(context),
                            ),
                          ),
                          MenuItemButton(
                            onPressed: onShowTrainingHistory,
                            leadingIcon: const Icon(Icons.history),
                            child: Text(t('menu.trainingHistory')),
                          ),
                          _RecentFilesMenu(
                            recentFolders: recentFolders,
                            recentFiles: recentFiles,
                            projectActionsLocked: projectActionsLocked,
                            onOpenRecentFolder: onOpenRecentFolder,
                            onOpenRecentFile: onOpenRecentFile,
                            onProjectActionBlocked: onProjectActionBlocked,
                            onClearRecent: onClearRecent,
                          ),
                          const Divider(height: 1),
                          MenuItemButton(
                            onPressed: onExit,
                            leadingIcon: const Icon(Icons.exit_to_app),
                            child: Text(t('menu.exit')),
                          ),
                        ],
                        child: Text(t('menu.file')),
                      ),
                      SubmenuButton(
                        menuChildren: [
                          MenuItemButton(
                            onPressed: _projectAction(onImportDataset),
                            leadingIcon: Icon(
                              Icons.upload_file,
                              color: projectActionsLocked ? lockedColor : null,
                            ),
                            child: Text(
                              t('menu.import'),
                              style: _projectActionTextStyle(context),
                            ),
                          ),
                          MenuItemButton(
                            onPressed: onExportDataset,
                            leadingIcon: const Icon(Icons.file_download),
                            child: Text(t('menu.export')),
                          ),
                          const Divider(height: 1),
                          MenuItemButton(
                            onPressed: onUndo,
                            child: Text(t('menu.undo')),
                          ),
                          MenuItemButton(
                            onPressed: onRedo,
                            child: Text(t('menu.restore')),
                          ),
                          MenuItemButton(
                            onPressed: onCopy,
                            child: Text(t('menu.copy')),
                          ),
                          MenuItemButton(
                            onPressed: onPaste,
                            child: Text(t('menu.paste')),
                          ),
                        ],
                        child: Text(t('menu.edit')),
                      ),
                      SubmenuButton(
                        menuChildren: [
                          SubmenuButton(
                            menuChildren: [
                              for (final language in languageOptions)
                                MenuItemButton(
                                  onPressed: () =>
                                      onLanguageSelected(language.code),
                                  leadingIcon:
                                      language.code == activeLanguageCode
                                      ? const Icon(Icons.check)
                                      : const SizedBox(width: 24),
                                  child: Text(language.label),
                                ),
                            ],
                            child: Text(t('settings.language')),
                          ),
                          MenuItemButton(
                            onPressed: onShowSettings,
                            leadingIcon: const Icon(Icons.settings_outlined),
                            child: Text(t('settings.preferences')),
                          ),
                          MenuItemButton(
                            onPressed: onShowLogs,
                            leadingIcon: const Icon(Icons.article_outlined),
                            child: Text(t('menu.viewLogs')),
                          ),
                          MenuItemButton(
                            onPressed: onShowSettings,
                            leadingIcon: const Icon(
                              Icons.delete_sweep_outlined,
                            ),
                            child: Text(t('settings.clearCache')),
                          ),
                        ],
                        child: Text(t('menu.settings')),
                      ),
                      SubmenuButton(
                        menuChildren: [
                          MenuItemButton(
                            onPressed: onShowHelp,
                            child: Text(t('menu.shortcutHelp')),
                          ),
                          MenuItemButton(
                            onPressed: onShowAbout,
                            child: Text(t('menu.about')),
                          ),
                        ],
                        child: Text(t('menu.help')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  VoidCallback _projectAction(VoidCallback action) =>
      projectActionsLocked ? onProjectActionBlocked : action;

  TextStyle? _projectActionTextStyle(BuildContext context) =>
      projectActionsLocked
      ? TextStyle(color: Theme.of(context).disabledColor)
      : null;
}

class _RecentFilesMenu extends StatelessWidget {
  const _RecentFilesMenu({
    required this.recentFolders,
    required this.recentFiles,
    required this.projectActionsLocked,
    required this.onOpenRecentFolder,
    required this.onOpenRecentFile,
    required this.onProjectActionBlocked,
    required this.onClearRecent,
  });

  final List<String> recentFolders;
  final List<String> recentFiles;
  final bool projectActionsLocked;
  final ValueChanged<String> onOpenRecentFolder;
  final ValueChanged<String> onOpenRecentFile;
  final VoidCallback onProjectActionBlocked;
  final VoidCallback onClearRecent;

  @override
  Widget build(BuildContext context) {
    final visibleFolders = recentFolders.take(_recentMenuVisibleCount).toList();
    final moreFolders = recentFolders.skip(_recentMenuVisibleCount).toList();
    final visibleFiles = recentFiles.take(_recentMenuVisibleCount).toList();
    final moreFiles = recentFiles.skip(_recentMenuVisibleCount).toList();
    final hasMoreItems = moreFolders.isNotEmpty || moreFiles.isNotEmpty;

    return SubmenuButton(
      menuChildren: [
        if (recentFolders.isEmpty)
          MenuItemButton(onPressed: null, child: Text(t('recent.noFolders')))
        else
          for (final folder in visibleFolders) _folderMenuItem(folder),
        const Divider(height: 1),
        if (recentFiles.isEmpty)
          MenuItemButton(onPressed: null, child: Text(t('recent.noFiles')))
        else
          for (final file in visibleFiles) _fileMenuItem(file),
        if (hasMoreItems) ...[
          const Divider(height: 1),
          SubmenuButton(
            menuChildren: [
              if (moreFolders.isNotEmpty) ...[
                MenuItemButton(
                  onPressed: null,
                  child: Text(t('recent.moreFolders')),
                ),
                for (final folder in moreFolders) _folderMenuItem(folder),
              ],
              if (moreFolders.isNotEmpty && moreFiles.isNotEmpty)
                const Divider(height: 1),
              if (moreFiles.isNotEmpty) ...[
                MenuItemButton(
                  onPressed: null,
                  child: Text(t('recent.moreFiles')),
                ),
                for (final file in moreFiles) _fileMenuItem(file),
              ],
            ],
            child: Text(t('recent.moreOptions')),
          ),
        ],
        const Divider(height: 1),
        MenuItemButton(
          onPressed: onClearRecent,
          child: Text(t('recent.clear')),
        ),
      ],
      child: Text(t('menu.openRecent')),
    );
  }

  MenuItemButton _folderMenuItem(String folder) {
    final onPressed = projectActionsLocked
        ? onProjectActionBlocked
        : () => onOpenRecentFolder(folder);
    return MenuItemButton(
      onPressed: onPressed,
      leadingIcon: Builder(
        builder: (context) => Icon(
          Icons.folder_outlined,
          color: projectActionsLocked ? Theme.of(context).disabledColor : null,
        ),
      ),
      child: SizedBox(
        width: 260,
        child: Builder(
          builder: (context) => Text(
            folder,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: projectActionsLocked
                ? TextStyle(color: Theme.of(context).disabledColor)
                : null,
          ),
        ),
      ),
    );
  }

  MenuItemButton _fileMenuItem(String file) {
    final onPressed = projectActionsLocked
        ? onProjectActionBlocked
        : () => onOpenRecentFile(file);
    return MenuItemButton(
      onPressed: onPressed,
      leadingIcon: Builder(
        builder: (context) => Icon(
          Icons.image_outlined,
          color: projectActionsLocked ? Theme.of(context).disabledColor : null,
        ),
      ),
      child: SizedBox(
        width: 260,
        child: Builder(
          builder: (context) => Text(
            file,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: projectActionsLocked
                ? TextStyle(color: Theme.of(context).disabledColor)
                : null,
          ),
        ),
      ),
    );
  }
}

class _PrimarySidebar extends StatelessWidget {
  const _PrimarySidebar({
    required this.activeSection,
    required this.collapsed,
    required this.onCollapseChanged,
    required this.onSectionSelected,
  });

  final String activeSection;
  final bool collapsed;
  final ValueChanged<bool> onCollapseChanged;
  final ValueChanged<String> onSectionSelected;

  static const _sections = [
    _SectionSpec('label', Icons.edit_note, 'sidebar.label'),
    _SectionSpec('train', Icons.model_training, 'sidebar.train'),
    _SectionSpec('browse', Icons.photo_library_outlined, 'sidebar.browse'),
    _SectionSpec('crop', Icons.content_cut, 'sidebar.crop'),
    _SectionSpec('collaboration', Icons.groups_2_outlined, 'sidebar.collab'),
    _SectionSpec('database', Icons.storage_outlined, 'sidebar.database'),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: collapsed ? _collapsedSidebarWidth : _expandedSidebarWidth,
      decoration: BoxDecoration(
        color: _panelColor(context),
        border: Border(right: BorderSide(color: _borderColor(context))),
      ),
      child: Column(
        children: [
          SizedBox(
            height: _paneHeaderHeight,
            child: Center(
              child: Tooltip(
                message: collapsed
                    ? t('sidebar.expand')
                    : t('sidebar.collapse'),
                child: IconButton(
                  onPressed: () => onCollapseChanged(!collapsed),
                  icon: Icon(collapsed ? Icons.menu_open : Icons.menu),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 8),
          for (final section in _sections)
            _SidebarButton(
              section: section,
              collapsed: collapsed,
              selected: activeSection == section.id,
              onPressed: () => onSectionSelected(section.id),
            ),
        ],
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.section,
    required this.collapsed,
    required this.selected,
    required this.onPressed,
  });

  final _SectionSpec section;
  final bool collapsed;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = selected
        ? colorScheme.primary
        : _primaryTextColor(context);
    final background = selected
        ? (_isDarkMode(context)
              ? _darkControlBackground
              : const Color(0xFFEFF6FF))
        : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Tooltip(
        message: t(section.label),
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 44,
              child: Row(
                mainAxisAlignment: collapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  SizedBox(width: collapsed ? 0 : 12),
                  Icon(section.icon, color: foreground, size: 21),
                  if (!collapsed) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t(section.label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShortcutSettingsDialog extends StatefulWidget {
  const _ShortcutSettingsDialog({
    required this.config,
    required this.onShortcutChanged,
    required this.onReset,
  });

  final _ShortcutConfig config;
  final void Function(_ShortcutAction action, LogicalKeyboardKey key)
  onShortcutChanged;
  final VoidCallback onReset;

  @override
  State<_ShortcutSettingsDialog> createState() =>
      _ShortcutSettingsDialogState();
}

class _ShortcutSettingsDialogState extends State<_ShortcutSettingsDialog> {
  final FocusNode _captureFocusNode = FocusNode(debugLabel: 'shortcut-capture');
  late _ShortcutConfig _currentConfig;
  _ShortcutAction? _waitingAction;

  @override
  void initState() {
    super.initState();
    _currentConfig = widget.config;
  }

  @override
  void dispose() {
    _captureFocusNode.dispose();
    super.dispose();
  }

  KeyEventResult _captureKey(FocusNode node, KeyEvent event) {
    final action = _waitingAction;
    if (event is! KeyDownEvent || action == null) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _waitingAction = null);
      return KeyEventResult.handled;
    }

    widget.onShortcutChanged(action, event.logicalKey);
    setState(() {
      _currentConfig = _currentConfig.copyWith(
        action: action,
        key: event.logicalKey,
      );
      _waitingAction = null;
    });
    return KeyEventResult.handled;
  }

  void _startCapture(_ShortcutAction action) {
    setState(() => _waitingAction = action);
    _captureFocusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _captureFocusNode.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = _currentConfig;
    const scopes = _ShortcutScope.values;

    return AlertDialog(
      title: Text(t('shortcut.title')),
      content: Focus(
        focusNode: _captureFocusNode,
        autofocus: true,
        onKeyEvent: _captureKey,
        child: SizedBox(
          width: 480,
          height: 520,
          child: DefaultTabController(
            length: scopes.length,
            child: Column(
              children: [
                TabBar(
                  isScrollable: true,
                  tabs: [
                    for (final scope in scopes) Tab(text: t(scope.labelKey)),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TabBarView(
                    children: [
                      for (final scope in scopes)
                        _ShortcutScopePane(
                          scope: scope,
                          config: config,
                          waitingAction: _waitingAction,
                          onPressed: _startCapture,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(t('shortcut.note')),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onReset();
            setState(() {
              _currentConfig = _ShortcutConfig.defaults();
              _waitingAction = null;
            });
          },
          child: Text(t('action.reset')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t('action.close')),
        ),
      ],
    );
  }
}

class _ShortcutScopePane extends StatelessWidget {
  const _ShortcutScopePane({
    required this.scope,
    required this.config,
    required this.waitingAction,
    required this.onPressed,
  });

  final _ShortcutScope scope;
  final _ShortcutConfig config;
  final _ShortcutAction? waitingAction;
  final ValueChanged<_ShortcutAction> onPressed;

  @override
  Widget build(BuildContext context) {
    final actions = [
      for (final action in _ShortcutAction.values)
        if (action.scope == scope) action,
    ];
    if (actions.isEmpty) {
      return Center(child: Text(t('shortcut.noItems')));
    }
    final normalActions = actions.where((action) => !action.isAiAction);
    final aiActions = actions.where((action) => action.isAiAction);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (normalActions.isNotEmpty) ...[
            _ShortcutSectionTitle(title: t('shortcut.normalGroup')),
            for (final action in normalActions)
              _ShortcutEditRow(
                action: action,
                label: t(action.labelKey),
                shortcut: config.binding(action).displayLabel,
                waiting: waitingAction == action,
                onPressed: onPressed,
              ),
          ],
          if (aiActions.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ShortcutSectionTitle(title: t('shortcut.aiGroup')),
            for (final action in aiActions)
              _ShortcutEditRow(
                action: action,
                label: t(action.labelKey),
                shortcut: config.binding(action).displayLabel,
                waiting: waitingAction == action,
                onPressed: onPressed,
              ),
          ],
        ],
      ),
    );
  }
}

class _ShortcutSectionTitle extends StatelessWidget {
  const _ShortcutSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      ),
    );
  }
}

class _ShortcutEditRow extends StatelessWidget {
  const _ShortcutEditRow({
    required this.action,
    required this.label,
    required this.shortcut,
    required this.waiting,
    required this.onPressed,
  });

  final _ShortcutAction action;
  final String label;
  final String shortcut;
  final bool waiting;
  final ValueChanged<_ShortcutAction> onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          SizedBox(
            width: 136,
            child: OutlinedButton(
              onPressed: () => onPressed(action),
              child: Text(
                waiting ? t('shortcut.waiting') : shortcut,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionSpec {
  const _SectionSpec(this.id, this.icon, this.label);

  final String id;
  final IconData icon;
  final String label;
}

class _ToolSpec {
  const _ToolSpec(this.id, this.icon, this.label);

  final String id;
  final IconData icon;
  final String label;
}

class _CanvasGridPainter extends CustomPainter {
  const _CanvasGridPainter(this.darkMode);

  final bool darkMode;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = darkMode ? const Color(0xFF3B2A68) : const Color(0xFFE2E8F0)
      ..strokeWidth = 1;

    const step = 32.0;
    for (double x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasGridPainter oldDelegate) =>
      oldDelegate.darkMode != darkMode;
}

class _ParsedYoloData {
  const _ParsedYoloData({
    required this.rootPath,
    required this.names,
    required this.splitSources,
    required this.splitImageDirs,
  });

  final String rootPath;
  final List<String> names;
  final Map<String, List<String>> splitSources;
  final Map<String, String> splitImageDirs;
}

class _ImportedDataset {
  const _ImportedDataset({
    required this.dataYamlPath,
    required this.rootPath,
    required this.splitImageDirs,
  });

  final String dataYamlPath;
  final String rootPath;
  final Map<String, String> splitImageDirs;

  String imageDirForSplit(String split) {
    return splitImageDirs[split] ?? _joinPath(rootPath, 'images\\$split');
  }

  String labelDirForSplit(String split) {
    return _labelDirForImageDir(imageDirForSplit(split), rootPath, split);
  }
}

class _DatasetImageEntry {
  const _DatasetImageEntry({required this.path, required this.split});

  final String path;
  final String split;
}

_ParsedYoloData _parseImportYoloDataYaml(String yamlPath) {
  final lines = File(yamlPath).readAsLinesSync();
  final yamlDir = _directoryName(yamlPath);
  final pathValue = _importYamlScalar(lines, 'path');
  final rootPath = pathValue == null || pathValue.isEmpty
      ? yamlDir
      : _resolveImportDatasetPath(yamlDir, pathValue);
  final splitSources = <String, List<String>>{};
  final splitImageDirs = <String, String>{};
  for (final split in _datasetSplits) {
    final sources = _importYamlStringValues(lines, split);
    splitSources[split] = sources;
    if (sources.isNotEmpty) {
      splitImageDirs[split] = _firstImageDirectoryForSplit(
        rootPath,
        split,
        sources,
      );
    }
  }
  return _ParsedYoloData(
    rootPath: rootPath,
    names: _importYamlNames(lines),
    splitSources: splitSources,
    splitImageDirs: splitImageDirs,
  );
}

String _datasetYamlContent(
  _ImportedDataset dataset,
  Map<String, Set<String>> grouped,
  List<_LabelClass> labelClasses,
) {
  final lines = <String>[
    'path: ${dataset.rootPath.replaceAll('\\', '/')}',
    'train: ${_pathForDataYaml(dataset.rootPath, dataset.imageDirForSplit('train'))}',
    'val: ${_pathForDataYaml(dataset.rootPath, dataset.imageDirForSplit('val'))}',
    if ((grouped['test']?.isNotEmpty ?? false) ||
        dataset.splitImageDirs.containsKey('test'))
      'test: ${_pathForDataYaml(dataset.rootPath, dataset.imageDirForSplit('test'))}',
    '',
    'nc: ${labelClasses.length}',
    'names:',
    for (var i = 0; i < labelClasses.length; i++)
      '  $i: ${labelClasses[i].name}',
  ];
  return lines.join('\n');
}

List<_DatasetImageEntry> _dedupeDatasetEntries(
  List<_DatasetImageEntry> entries,
) {
  final seen = <String>{};
  final result = <_DatasetImageEntry>[];
  for (final entry in entries) {
    if (seen.add(_pathKey(entry.path))) {
      result.add(entry);
    }
  }
  return result;
}

List<String> _imagePathsFromDatasetSource(String rootPath, String source) {
  final resolved = _resolveImportDatasetSourcePath(rootPath, source);
  final directory = Directory(resolved);
  if (directory.existsSync()) {
    final paths = directory
        .listSync(recursive: true)
        .whereType<File>()
        .map<String>((file) => file.path)
        .where((path) => _isImagePath(path))
        .toList();
    paths.sort(_naturalPathCompare);
    return paths;
  }

  final file = File(resolved);
  if (!file.existsSync()) {
    return [];
  }
  if (_isImagePath(file.path)) {
    return [file.path];
  }

  final parent = _directoryName(file.path);
  final paths = file
      .readAsLinesSync()
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .map<String>((line) => _resolveImportDatasetSourcePath(parent, line))
      .where((path) => _isImagePath(path))
      .where((path) => File(path).existsSync())
      .toList();
  paths.sort(_naturalPathCompare);
  return paths;
}

_AnnotationRegion? _annotationFromYoloValues({
  required String id,
  required List<double> values,
  required int classId,
  required Size imageSize,
}) {
  final w = imageSize.width;
  final h = imageSize.height;
  if (w <= 0 || h <= 0) {
    return null;
  }
  if (values.length == 4) {
    final cx = values[0] * w;
    final cy = values[1] * h;
    final bw = values[2] * w;
    final bh = values[3] * h;
    return _AnnotationRegion.fromRect(
      id: id,
      mode: _AnnotationMode.hbb,
      rect: Rect.fromCenter(center: Offset(cx, cy), width: bw, height: bh),
      classId: classId,
    ).clampedTo(Rect.fromLTWH(0, 0, w, h));
  }
  if (values.length == 8) {
    final points = _normalizedPairsToPoints(values, imageSize);
    final width = (points[1] - points[0]).distance;
    final height = (points[2] - points[1]).distance;
    if (width <= 0 || height <= 0) {
      return null;
    }
    final center = points.reduce((a, b) => a + b) / points.length.toDouble();
    final rotation =
        math.atan2(points[1].dy - points[0].dy, points[1].dx - points[0].dx) *
        180 /
        math.pi;
    return _AnnotationRegion(
      id: id,
      mode: _AnnotationMode.obb,
      rect: Rect.fromCenter(center: center, width: width, height: height),
      classId: classId,
      rotationDegrees: rotation,
    ).clampObbToImage(imageSize);
  }
  if (values.length >= 6 && values.length.isEven) {
    final points = _normalizedPairsToPoints(values, imageSize);
    final xs = points.map((point) => point.dx);
    final ys = points.map((point) => point.dy);
    final bounds = Rect.fromLTRB(
      xs.reduce(math.min),
      ys.reduce(math.min),
      xs.reduce(math.max),
      ys.reduce(math.max),
    );
    return _AnnotationRegion(
      id: id,
      mode: _AnnotationMode.seg,
      rect: bounds,
      classId: classId,
      points: [
        for (final point in points)
          _clampOffset(point, Rect.fromLTWH(0, 0, w, h)),
      ],
    );
  }
  return null;
}

List<Offset> _normalizedPairsToPoints(List<double> values, Size imageSize) {
  return [
    for (var i = 0; i + 1 < values.length; i += 2)
      Offset(
        (values[i] * imageSize.width).clamp(0.0, imageSize.width).toDouble(),
        (values[i + 1] * imageSize.height)
            .clamp(0.0, imageSize.height)
            .toDouble(),
      ),
  ];
}

String _labelPathForImagePath(String imagePath) {
  final normalized = imagePath.replaceAll('\\', '/');
  final parts = normalized.split('/');
  for (var i = parts.length - 2; i >= 0; i--) {
    if (parts[i].toLowerCase() == 'images') {
      parts[i] = 'labels';
      return _replaceExtension(parts.join('\\'), '.txt');
    }
  }
  return _joinPath(
    _directoryName(imagePath),
    '${_baseNameWithoutExtension(imagePath)}.txt',
  );
}

String _labelDirForImageDir(String imageDir, String rootPath, String split) {
  final normalized = imageDir.replaceAll('\\', '/');
  final parts = normalized.split('/');
  for (var i = parts.length - 1; i >= 0; i--) {
    if (parts[i].toLowerCase() == 'images') {
      parts[i] = 'labels';
      return parts.join('\\');
    }
  }
  return _joinPath(rootPath, 'labels\\$split');
}

String _firstImageDirectoryForSplit(
  String rootPath,
  String split,
  List<String> sources,
) {
  for (final source in sources) {
    final resolved = _resolveImportDatasetSourcePath(rootPath, source);
    if (Directory(resolved).existsSync()) {
      return resolved;
    }
  }
  return _joinPath(rootPath, 'images\\$split');
}

String? _importYamlScalar(List<String> lines, String key) {
  for (final rawLine in lines) {
    final line = _stripImportYamlComment(rawLine).trimRight();
    if (!line.startsWith('$key:')) {
      continue;
    }
    final value = line.substring(key.length + 1).trim();
    return value.isEmpty ? null : _unquoteImportYamlValue(value);
  }
  return null;
}

List<String> _importYamlStringValues(List<String> lines, String key) {
  for (var i = 0; i < lines.length; i++) {
    final raw = _stripImportYamlComment(lines[i]);
    final line = raw.trimRight();
    final trimmed = line.trimLeft();
    if (!trimmed.startsWith('$key:')) {
      continue;
    }
    final value = trimmed.substring(key.length + 1).trim();
    if (value.isNotEmpty) {
      return _parseImportYamlValueList(value);
    }
    final result = <String>[];
    for (var j = i + 1; j < lines.length; j++) {
      final childRaw = _stripImportYamlComment(lines[j]);
      if (childRaw.trim().isEmpty) {
        continue;
      }
      if (!_hasImportYamlIndent(childRaw)) {
        break;
      }
      final child = childRaw.trim();
      if (child.startsWith('-')) {
        final item = child.substring(1).trim();
        if (item.isNotEmpty) {
          result.add(_unquoteImportYamlValue(item));
        }
      }
    }
    return result;
  }
  return const [];
}

List<String> _importYamlNames(List<String> lines) {
  for (var i = 0; i < lines.length; i++) {
    final raw = _stripImportYamlComment(lines[i]);
    final trimmed = raw.trimLeft();
    if (!trimmed.startsWith('names:')) {
      continue;
    }
    final value = trimmed.substring('names:'.length).trim();
    if (value.isNotEmpty) {
      return _parseImportYamlValueList(value);
    }
    final byIndex = <int, String>{};
    final list = <String>[];
    for (var j = i + 1; j < lines.length; j++) {
      final childRaw = _stripImportYamlComment(lines[j]);
      if (childRaw.trim().isEmpty) {
        continue;
      }
      if (!_hasImportYamlIndent(childRaw)) {
        break;
      }
      final child = childRaw.trim();
      if (child.startsWith('-')) {
        list.add(_unquoteImportYamlValue(child.substring(1).trim()));
        continue;
      }
      final colon = child.indexOf(':');
      if (colon > 0) {
        final index = int.tryParse(child.substring(0, colon).trim());
        final name = _unquoteImportYamlValue(child.substring(colon + 1).trim());
        if (index != null && name.isNotEmpty) {
          byIndex[index] = name;
        }
      }
    }
    if (byIndex.isNotEmpty) {
      final maxIndex = byIndex.keys.reduce(math.max);
      return [
        for (var index = 0; index <= maxIndex; index++)
          byIndex[index] ?? 'class_$index',
      ];
    }
    return list;
  }
  return const [];
}

List<String> _parseImportYamlValueList(String value) {
  final trimmed = value.trim();
  if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
    final content = trimmed.substring(1, trimmed.length - 1);
    return content
        .split(',')
        .map((item) => _unquoteImportYamlValue(item.trim()))
        .where((item) => item.isNotEmpty)
        .toList();
  }
  if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
    final content = trimmed.substring(1, trimmed.length - 1);
    final indexed = <int, String>{};
    for (final pair in content.split(',')) {
      final colon = pair.indexOf(':');
      if (colon < 0) {
        continue;
      }
      final index = int.tryParse(pair.substring(0, colon).trim());
      final name = _unquoteImportYamlValue(pair.substring(colon + 1).trim());
      if (index != null && name.isNotEmpty) {
        indexed[index] = name;
      }
    }
    if (indexed.isEmpty) {
      return const [];
    }
    final maxIndex = indexed.keys.reduce(math.max);
    return [
      for (var index = 0; index <= maxIndex; index++)
        indexed[index] ?? 'class_$index',
    ];
  }
  return [_unquoteImportYamlValue(trimmed)];
}

String _stripImportYamlComment(String line) {
  final index = line.indexOf('#');
  return index < 0 ? line : line.substring(0, index);
}

bool _hasImportYamlIndent(String line) {
  return line.startsWith(' ') || line.startsWith('\t');
}

String _unquoteImportYamlValue(String value) {
  final trimmed = value.trim();
  if (trimmed.length >= 2) {
    final first = trimmed[0];
    final last = trimmed[trimmed.length - 1];
    if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
      return trimmed.substring(1, trimmed.length - 1);
    }
  }
  return trimmed;
}

List<String> _imageFilesInDirectory(String folderPath) {
  final directory = Directory(folderPath);
  if (!directory.existsSync()) {
    return [];
  }

  final files =
      directory
          .listSync()
          .whereType<File>()
          .map((file) => file.path)
          .where(_isImagePath)
          .toList()
        ..sort(_naturalPathCompare);

  return files;
}

// 按文件名自然排序，保证 2 排在 10 前，图片02 排在 图片10 前。
// Natural-sort by filename so 2 comes before 10, and image02 before image10.
int _naturalPathCompare(String leftPath, String rightPath) {
  final result = _naturalCompare(_fileName(leftPath), _fileName(rightPath));
  if (result != 0) {
    return result;
  }
  return _pathKey(leftPath).compareTo(_pathKey(rightPath));
}

int _naturalCompare(String left, String right) {
  final leftLower = left.toLowerCase();
  final rightLower = right.toLowerCase();
  var leftIndex = 0;
  var rightIndex = 0;

  while (leftIndex < leftLower.length && rightIndex < rightLower.length) {
    final leftCode = leftLower.codeUnitAt(leftIndex);
    final rightCode = rightLower.codeUnitAt(rightIndex);
    final leftIsDigit = _isAsciiDigit(leftCode);
    final rightIsDigit = _isAsciiDigit(rightCode);

    if (leftIsDigit && rightIsDigit) {
      final leftStart = leftIndex;
      final rightStart = rightIndex;
      while (leftIndex < leftLower.length &&
          _isAsciiDigit(leftLower.codeUnitAt(leftIndex))) {
        leftIndex++;
      }
      while (rightIndex < rightLower.length &&
          _isAsciiDigit(rightLower.codeUnitAt(rightIndex))) {
        rightIndex++;
      }

      final numberCompare = _compareNumberText(
        leftLower.substring(leftStart, leftIndex),
        rightLower.substring(rightStart, rightIndex),
      );
      if (numberCompare != 0) {
        return numberCompare;
      }
      continue;
    }

    if (leftCode != rightCode) {
      return leftCode.compareTo(rightCode);
    }
    leftIndex++;
    rightIndex++;
  }

  final lengthCompare = leftLower.length.compareTo(rightLower.length);
  if (lengthCompare != 0) {
    return lengthCompare;
  }
  return left.compareTo(right);
}

int _compareNumberText(String left, String right) {
  final normalizedLeft = _trimLeadingZeros(left);
  final normalizedRight = _trimLeadingZeros(right);
  final lengthCompare = normalizedLeft.length.compareTo(normalizedRight.length);
  if (lengthCompare != 0) {
    return lengthCompare;
  }

  final valueCompare = normalizedLeft.compareTo(normalizedRight);
  if (valueCompare != 0) {
    return valueCompare;
  }
  return left.length.compareTo(right.length);
}

String _trimLeadingZeros(String value) {
  var index = 0;
  while (index < value.length - 1 && value.codeUnitAt(index) == 48) {
    index++;
  }
  return value.substring(index);
}

bool _isAsciiDigit(int codeUnit) => codeUnit >= 48 && codeUnit <= 57;

bool _isImagePath(String path) {
  final dotIndex = path.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == path.length - 1) {
    return false;
  }
  return _imageExtensions.contains(path.substring(dotIndex + 1).toLowerCase());
}

bool _touchRecent(List<_RecentEntry> items, String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  final key = _pathKey(trimmed);
  final existingIndex = items.indexWhere((item) => _pathKey(item.path) == key);
  if (existingIndex >= 0) {
    items.removeAt(existingIndex);
  }
  items.insert(0, _RecentEntry(path: trimmed, timestamp: DateTime.now()));
  if (items.length > _recentHistoryLimit) {
    items.removeRange(_recentHistoryLimit, items.length);
  }
  return true;
}

String _fileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slashIndex = normalized.lastIndexOf('/');
  return slashIndex < 0 ? normalized : normalized.substring(slashIndex + 1);
}

String _directoryName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slashIndex = normalized.lastIndexOf('/');
  if (slashIndex < 0) {
    return '.';
  }
  return normalized.substring(0, slashIndex).replaceAll('/', '\\');
}

String _baseNameWithoutExtension(String path) {
  final name = _fileName(path);
  final dotIndex = name.lastIndexOf('.');
  return dotIndex < 0 ? name : name.substring(0, dotIndex);
}

void _copyFileOverwrite(String sourcePath, String targetPath) {
  if (_pathKey(sourcePath) == _pathKey(targetPath)) {
    return;
  }
  final target = File(targetPath);
  target.parent.createSync(recursive: true);
  if (target.existsSync()) {
    target.deleteSync();
  }
  File(sourcePath).copySync(targetPath);
}

String _replaceExtension(String path, String extension) {
  final dotIndex = path.lastIndexOf('.');
  if (dotIndex < 0) {
    return '$path$extension';
  }
  return path.substring(0, dotIndex) + extension;
}

String _resolveImportDatasetPath(String rootPath, String value) {
  final path = value.replaceAll('/', '\\');
  if (_isAbsolutePath(path)) {
    return path;
  }
  return _joinPath(rootPath, path);
}

String _resolveImportDatasetSourcePath(String rootPath, String value) {
  final direct = _resolveImportDatasetPath(rootPath, value);
  if (_fileSystemPathExists(direct)) {
    return direct;
  }

  final roboflowPath = _resolveRoboflowDatasetSourcePath(rootPath, value);
  if (roboflowPath != null && _fileSystemPathExists(roboflowPath)) {
    return roboflowPath;
  }
  return direct;
}

String? _resolveRoboflowDatasetSourcePath(String rootPath, String value) {
  if (_isAbsolutePath(value)) {
    return null;
  }
  var normalized = value.replaceAll('\\', '/').trim();
  var strippedAnyParent = false;
  while (normalized.startsWith('../')) {
    normalized = normalized.substring(3);
    strippedAnyParent = true;
  }
  if (!strippedAnyParent || normalized.isEmpty) {
    return null;
  }
  return _resolveImportDatasetPath(rootPath, normalized);
}

bool _fileSystemPathExists(String path) {
  return Directory(path).existsSync() || File(path).existsSync();
}

String _pathForDataYaml(String rootPath, String path) {
  final root = rootPath.replaceAll('/', '\\');
  final normalized = path.replaceAll('/', '\\');
  final rootWithSlash = root.endsWith('\\') ? root : '$root\\';
  if (_pathKey(normalized).startsWith(_pathKey(rootWithSlash))) {
    return normalized.substring(rootWithSlash.length).replaceAll('\\', '/');
  }
  return normalized.replaceAll('\\', '/');
}

String _joinPath(String left, String right) {
  final normalizedLeft = left.replaceAll('/', '\\');
  final normalizedRight = right.replaceAll('/', '\\');
  if (normalizedLeft.endsWith('\\')) {
    return '$normalizedLeft$normalizedRight';
  }
  return '$normalizedLeft\\$normalizedRight';
}

bool _isAbsolutePath(String path) {
  if (path.startsWith('\\\\') || path.startsWith('\\')) {
    return true;
  }
  return path.length >= 3 &&
      _isAsciiLetter(path.codeUnitAt(0)) &&
      path.codeUnitAt(1) == 58 &&
      (path.codeUnitAt(2) == 92 || path.codeUnitAt(2) == 47);
}

bool _isAsciiLetter(int codeUnit) {
  return (codeUnit >= 65 && codeUnit <= 90) ||
      (codeUnit >= 97 && codeUnit <= 122);
}

String _pathKey(String path) => path.replaceAll('/', '\\').toLowerCase();

List<String> _stringListFromJson(Object? value) {
  if (value is! List) {
    return [];
  }
  return value.whereType<String>().toList();
}

List<String> _dedupePaths(List<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in values) {
    if (seen.add(_pathKey(value))) {
      result.add(value);
    }
  }
  return result;
}

Future<Color?> _showWheelColorDialog({
  required BuildContext context,
  required Color initialColor,
  required String title,
  BoxConstraints constraints = const BoxConstraints(maxWidth: 420),
}) {
  return showDialog<Color>(
    context: context,
    barrierColor: Colors.black26,
    builder: (dialogContext) {
      var selectedColor = initialColor;
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final colorScheme = Theme.of(context).colorScheme;
          return AlertDialog(
            title: Text(title),
            content: ConstrainedBox(
              constraints: constraints,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 260,
                    child: ColorWheelPicker(
                      color: selectedColor,
                      onChanged: (color) {
                        setDialogState(() => selectedColor = color);
                      },
                      onWheel: (_) {},
                      wheelWidth: 18,
                      hasBorder: true,
                      borderColor: colorScheme.outlineVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: selectedColor,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: colorScheme.outline),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _colorHex(selectedColor),
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(t('label.cancelAnnotation')),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(selectedColor),
                child: Text(t('label.saveAnnotation')),
              ),
            ],
          );
        },
      );
    },
  );
}

String _colorHex(Color color) {
  final value = color.toARGB32().toRadixString(16).padLeft(8, '0');
  return '0x${value.toUpperCase()}';
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNullValue {
    final iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }
}

bool _isEditableTextFocused() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) {
    return false;
  }
  if (context.widget is EditableText) {
    return true;
  }
  return context.findAncestorWidgetOfExactType<EditableText>() != null;
}

String _keyboardLabel(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.space) return 'Space';
  if (key == LogicalKeyboardKey.arrowLeft) return '←';
  if (key == LogicalKeyboardKey.arrowRight) return '→';
  if (key == LogicalKeyboardKey.arrowUp) return '↑';
  if (key == LogicalKeyboardKey.arrowDown) return '↓';
  if (key.keyLabel.isNotEmpty) {
    return key.keyLabel.toUpperCase();
  }
  return key.debugName ?? key.keyId.toString();
}
