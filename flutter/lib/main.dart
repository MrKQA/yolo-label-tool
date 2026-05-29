import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/rust/api.dart';
import 'src/rust/frb_generated.dart';

part 'LabelPage.dart';
part 'TrainPage.dart';
part 'DetectVideoPage.dart';
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
const _expandedSidebarWidth = 112.0;
const _collapsedSidebarWidth = 56.0;
const _recentHistoryLimit = 20;
const _recentMenuVisibleCount = 5;
const _fontFamily = 'Microsoft YaHei';
const _languageCode = 'zh_cn';
const _languageAssetDirectory = 'lib/language';
const _historyFileName = 'history.json';
const _keybindingsFileName = 'keybindings.json';
const _settingsFileName = 'settings.json';

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

final ValueNotifier<ThemeMode> _themeModeNotifier = ValueNotifier(
  ThemeMode.light,
);

_LanguageStrings _appText = _LanguageStrings.fallback();
final ValueNotifier<_LanguageStrings> _languageStringsNotifier = ValueNotifier(
  _appText,
);

const _imageTypeGroup = XTypeGroup(
  label: 'Images',
  extensions: ['jpg', 'jpeg', 'png', 'bmp', 'gif', 'webp'],
);

const _imageExtensions = {'jpg', 'jpeg', 'png', 'bmp', 'gif', 'webp'};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _appText = await _LanguageStrings.load(_languageCode);
  _languageStringsNotifier.value = _appText;
  await RustLib.init();
  runApp(const YoloLabelApp());
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
    'settings.language': '语言',
    'settings.preferences': '首选项',
    'settings.clearCache': '清空缓存',
    'settings.title': '设置',
    'settings.configPath': '配置目录',
    'settings.pythonPath': 'Python 环境路径',
    'settings.outputPath': '训练结果保存位置',
    'settings.choosePython': '选择 Python',
    'settings.chooseFolder': '选择文件夹',
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
    'context.addImage': '添加图片',
    'context.deleteImage': '删除图片',
    'context.rotateLeft': '逆时针旋转',
    'context.rotateRight': '顺时针旋转',
    'sidebar.label': '标注',
    'sidebar.train': '训练',
    'sidebar.browse': '浏览',
    'sidebar.expand': '展开侧边栏',
    'sidebar.collapse': '收起侧边栏',
    'label.previewEmpty': '右键或菜单添加图片',
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
    'shortcut.note': '鼠标滚轮缩放、右键图片添加/删除保持固定。',
    'shortcut.waiting': '按下键盘...',
    'train.title': '训练',
    'train.parameters': '超参数',
    'train.chooseModel': '选择 PT 模型',
    'train.refreshModels': '刷新模型',
    'train.chooseDataset': '选择数据集',
    'train.start': '开始训练',
    'train.datasetPath': '数据集路径',
    'train.invalidModel': '模型文件异常，请选择 YOLO PT 模型。',
    'train.noModels': 'models 文件夹中没有可用的 YOLO PT 模型。',
    'train.datasetSummaryEmpty': '请选择 data.yaml 后显示 classes、train、val 数量。',
    'train.classes': '类别',
    'train.trainCount': 'train 数量',
    'train.valCount': 'val 数量',
    'train.currentEpoch': '当前轮次',
    'train.notStarted': '未开始',
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
    'detect.title': '浏览 / 视频检测',
    'detect.chooseImage': '选择图片',
    'detect.chooseFile': '选择文件',
    'detect.chooseFolder': '选择文件夹',
    'detect.playVideo': '播放视频',
    'detect.predictVideo': '预测视频',
    'detect.predictAll': '全部预测',
    'detect.saveResult': '保存结果',
    'detect.model': '检测模型',
    'detect.fileName': '文件名',
    'detect.paused': '已暂停',
    'detect.playing': '播放中',
    'detect.resultVisible': '显示预测结果',
    'detect.resultHidden': '隐藏预测结果',
    'detect.clickToggleResult': '点击显示区域切换预测结果显示。',
    'detect.placeholder': '检测结果、视频播放和预测导出将在这里显示。',
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
  Timer? _topMenuHideTimer;

  final List<_ImageItem> _images = [];
  final List<String> _recentFolders = [];
  final List<String> _recentFiles = [];
  final List<_LabelClass> _labelClasses = [];
  final Map<String, List<_AnnotationRegion>> _annotationsByImage = {};
  final List<List<_AnnotationRegion>> _undoStack = [];
  final List<List<_AnnotationRegion>> _redoStack = [];
  List<_LanguageOption> _languageOptions = const [
    _LanguageOption(code: _languageCode, label: '简体中文'),
  ];

  bool _sidebarCollapsed = false;
  bool _darkMode = false;
  bool _shortcutDialogOpen = false;
  bool _topMenuVisible = true;
  bool _zoomLocked = false;
  double _zoom = 100;
  int _selectedImageIndex = 0;
  String _activeSection = 'label';
  String _activeTool = 'select';
  String _activeLanguageCode = _languageCode;
  String? _selectedAnnotationId;
  bool _showClassLabels = true;
  int? _activeClassId;
  int _classSerial = 1;
  int _annotationSerial = 1;
  _AnnotationMode _activeAnnotationMode = _AnnotationMode.hbb;
  _AnnotationRegion? _copiedAnnotation;
  _ShortcutConfig _shortcutConfig = _ShortcutConfig.defaults();
  _AppSettings _appSettings = _AppSettings.empty();

  _ImageItem? get _selectedImage {
    if (_images.isEmpty) {
      return null;
    }
    return _images[_selectedImageIndex.clamp(0, _images.length - 1)];
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

  @override
  void initState() {
    super.initState();
    _loadPersistedConfig();
    _loadAvailableLanguages();
    _scheduleTopMenuHide();
  }

  @override
  void dispose() {
    _topMenuHideTimer?.cancel();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _loadPersistedConfig() {
    final history = _ConfigStore.loadHistory();
    final keybindings = _ConfigStore.loadKeybindings();
    final settings = _ConfigStore.loadSettings();
    setState(() {
      _recentFolders
        ..clear()
        ..addAll(_dedupePaths(history.folders));
      _recentFiles
        ..clear()
        ..addAll(_dedupePaths(history.files));
      _shortcutConfig = keybindings;
      _appSettings = settings;
    });
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
    setState(() => _appSettings = settings);
    _ConfigStore.saveSettings(settings);
  }

  void _setZoom(double value) {
    if (_zoomLocked) {
      return;
    }
    setState(() => _zoom = value.clamp(25, 400).toDouble());
  }

  void _toggleZoomLock() {
    setState(() => _zoomLocked = !_zoomLocked);
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
  }

  void _selectPreviousImage({int step = 1}) {
    if (_images.isEmpty) {
      return;
    }
    _selectImage((_selectedImageIndex - step).clamp(0, _images.length - 1));
  }

  void _selectNextImage({int step = 1}) {
    if (_images.isEmpty) {
      return;
    }
    _selectImage((_selectedImageIndex + step).clamp(0, _images.length - 1));
  }

  Future<void> _openImageFile({int? insertAfterIndex}) async {
    final file = await openFile(acceptedTypeGroups: [_imageTypeGroup]);
    if (file == null) {
      return;
    }

    final existingIndex = _imageIndexOfPath(file.path);
    if (existingIndex >= 0) {
      _selectImage(existingIndex);
      return;
    }

    if (_addRecent(_recentFiles, file.path)) {
      _saveHistory();
    }
    _insertImages([file.path], insertAfterIndex: insertAfterIndex);
  }

  Future<void> _openImageFolder([String? path]) async {
    final folderPath = path ?? await getDirectoryPath();
    if (folderPath == null) {
      return;
    }

    final files = _imageFilesInDirectory(folderPath);
    if (_addRecent(_recentFolders, folderPath)) {
      _saveHistory();
    }
    setState(() {
      _images
        ..clear()
        ..addAll(files.map(_ImageItem.fromPath));
      _selectedImageIndex = 0;
      _selectedAnnotationId = null;
      _undoStack.clear();
      _redoStack.clear();
      _activeSection = 'label';
    });
  }

  void _openRecentFile(String path) {
    final existingIndex = _imageIndexOfPath(path);
    if (existingIndex >= 0) {
      _selectImage(existingIndex);
      return;
    }
    _insertImages([path]);
  }

  void _insertImages(List<String> paths, {int? insertAfterIndex}) {
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
      _selectedImageIndex = insertIndex;
      _selectedAnnotationId = null;
      _undoStack.clear();
      _redoStack.clear();
      _activeSection = 'label';
    });
  }

  int _imageIndexOfPath(String path) {
    final key = _pathKey(path);
    return _images.indexWhere((image) => _pathKey(image.path) == key);
  }

  void _deleteImage(int index) {
    if (index < 0 || index >= _images.length) {
      return;
    }

    setState(() {
      _images.removeAt(index);
      _selectedImageIndex = _images.isEmpty
          ? 0
          : _selectedImageIndex.clamp(0, _images.length - 1);
      _selectedAnnotationId = null;
      _undoStack.clear();
      _redoStack.clear();
    });
  }

  Future<void> _showImageContextMenu(TapDownDetails details, int? index) async {
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
  }

  void _redoAnnotationChange() {
    if (_redoStack.isEmpty) {
      return;
    }
    final snapshot = _redoStack.removeLast();
    _undoStack.add(List<_AnnotationRegion>.of(_currentAnnotations));
    setState(() => _restoreCurrentImageAnnotations(snapshot));
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
    return id;
  }

  Future<void> _editLabelClass(_LabelClass labelClass) async {
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
    final currentColor = labelClass.color;
    final selected = await showColorPickerDialog(
      context,
      currentColor,
      title: Text(t('label.classColor')),
      heading: Text(t('label.classColor')),
      subheading: Text(t('label.classColor')),
      wheelSubheading: Text(t('label.classColor')),
      pickersEnabled: const {
        ColorPickerType.primary: true,
        ColorPickerType.accent: true,
        ColorPickerType.wheel: true,
      },
      enableShadesSelection: true,
      showColorCode: true,
      showColorName: true,
      width: 34,
      height: 34,
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
      barrierDismissible: true,
      barrierColor: Colors.black26,
      selectedPickerTypeColor: Theme.of(context).colorScheme.primary,
    );
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
  }

  void _deleteLabelClass(_LabelClass labelClass) {
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
  }

  void _reorderLabelClass(int oldIndex, int newIndex) {
    setState(() {
      final item = _labelClasses.removeAt(oldIndex);
      _labelClasses.insert(newIndex, item);
    });
  }

  void _selectLabelClass(int id) {
    setState(() => _activeClassId = id);
  }

  void _createAnnotation(Rect rect, int classId) {
    final imageKey = _selectedImageKey;
    if (imageKey == null || rect.width.abs() < 4 || rect.height.abs() < 4) {
      return;
    }
    _pushAnnotationSnapshot();
    final annotation = _AnnotationRegion.fromRect(
      id: 'ann_${_annotationSerial++}',
      mode: _activeAnnotationMode,
      rect: rect,
      classId: classId,
    );
    setState(() {
      _annotationsByImage.putIfAbsent(imageKey, () => []).add(annotation);
      _selectedAnnotationId = annotation.id;
      _activeTool = 'draw';
    });
  }

  void _createSegAnnotation(List<Offset> points, int classId) {
    final imageKey = _selectedImageKey;
    if (imageKey == null || points.length < 3) {
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
    );
    setState(() {
      _annotationsByImage.putIfAbsent(imageKey, () => []).add(annotation);
      _selectedAnnotationId = annotation.id;
      _activeTool = 'draw';
    });
  }

  void _selectAnnotation(String? id) {
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

  void _updateAnnotation(_AnnotationRegion annotation) {
    final imageKey = _selectedImageKey;
    if (imageKey == null) {
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
  }

  void _changeAnnotationClass(String annotationId, int classId) {
    final imageKey = _selectedImageKey;
    if (imageKey == null) {
      return;
    }
    _pushAnnotationSnapshot();
    setState(() {
      final annotations = _annotationsByImage[imageKey];
      if (annotations == null) {
        return;
      }
      final index = annotations.indexWhere((item) => item.id == annotationId);
      if (index >= 0) {
        annotations[index] = annotations[index].copyWith(classId: classId);
        _activeClassId = classId;
      }
    });
  }

  void _deleteAnnotation(String id) {
    final imageKey = _selectedImageKey;
    if (imageKey == null) {
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

  void _pasteAnnotation() {
    final imageKey = _selectedImageKey;
    final copied = _copiedAnnotation;
    if (imageKey == null || copied == null) {
      return;
    }
    _pushAnnotationSnapshot();
    final pasted = copied.duplicate('ann_${_annotationSerial++}');
    setState(() {
      _annotationsByImage.putIfAbsent(imageKey, () => []).add(pasted);
      _selectedAnnotationId = pasted.id;
    });
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
    _pushAnnotationSnapshot();
    _updateAnnotation(selected.rotated(deltaDegrees));
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
      _selectPreviousImage(step: imageStep);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.nextImage, key)) {
      _selectNextImage(step: imageStep);
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
    return KeyEventResult.ignored;
  }

  void _toggleThemeMode() {
    setState(() => _darkMode = !_darkMode);
    _themeModeNotifier.value = _darkMode ? ThemeMode.dark : ThemeMode.light;
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

  Future<int> _clearCacheData() async {
    setState(() {
      _recentFolders.clear();
      _recentFiles.clear();
      _labelClasses.clear();
      _annotationsByImage.clear();
      _undoStack.clear();
      _redoStack.clear();
      _activeClassId = null;
      _selectedAnnotationId = null;
    });
    _saveHistory();
    return _ConfigStore.cacheSizeInBytes();
  }

  @override
  Widget build(BuildContext context) {
    final labelPage = _activeSection == 'label';

    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Column(
        children: [
          _TopMenuBar(
            visible: _topMenuVisible,
            recentFolders: _recentFolders,
            recentFiles: _recentFiles,
            languageOptions: _languageOptions,
            activeLanguageCode: _activeLanguageCode,
            onOpenFile: () => _openImageFile(),
            onOpenFolder: () => _openImageFolder(),
            onOpenRecentFolder: _openImageFolder,
            onOpenRecentFile: _openRecentFile,
            onClearRecent: _clearRecentItems,
            onExit: () => SystemNavigator.pop(),
            onUndo: _undoAnnotationChange,
            onRedo: _redoAnnotationChange,
            onCopy: _copySelectedAnnotation,
            onPaste: _pasteAnnotation,
            onShowSettings: _showSettings,
            onShowHelp: _showKeySettings,
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
                    setState(() => _activeSection = section);
                  },
                ),
                if (labelPage)
                  _LabelPage(
                    status: widget.status,
                    images: _images,
                    selectedImage: _selectedImage,
                    selectedImageIndex: _selectedImageIndex,
                    zoom: _zoom,
                    activeTool: _activeTool,
                    activeMode: _activeAnnotationMode,
                    activeClassId: _activeClassId,
                    labelClasses: _labelClasses,
                    annotations: _currentAnnotations,
                    selectedAnnotationId: _selectedAnnotationId,
                    showClassLabels: _showClassLabels,
                    onImageSelected: _selectImage,
                    onImageContextMenu: _showImageContextMenu,
                    onPointerSignal: _handlePointerSignal,
                    onToolSelected: _selectTool,
                    onSelectMode: () => _selectTool('select'),
                    onModeSelected: _activateAnnotationMode,
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
                    onToggleClassLabels: () =>
                        setState(() => _showClassLabels = !_showClassLabels),
                    onAnnotationClassChanged: _changeAnnotationClass,
                  )
                else if (_activeSection == 'train')
                  _TrainPage(settings: _appSettings)
                else
                  _DetectVideoPage(settings: _appSettings),
              ],
            ),
          ),
          if (labelPage)
            _BottomControls(
              zoom: _zoom,
              zoomLocked: _zoomLocked,
              darkMode: _darkMode,
              onZoomChanged: _setZoom,
              onToggleZoomLock: _toggleZoomLock,
              onToggleThemeMode: _toggleThemeMode,
              onOpenKeySettings: _showKeySettings,
            ),
        ],
      ),
    );
  }
}

class _TopMenuBar extends StatelessWidget {
  const _TopMenuBar({
    required this.visible,
    required this.recentFolders,
    required this.recentFiles,
    required this.languageOptions,
    required this.activeLanguageCode,
    required this.onOpenFile,
    required this.onOpenFolder,
    required this.onOpenRecentFolder,
    required this.onOpenRecentFile,
    required this.onClearRecent,
    required this.onExit,
    required this.onUndo,
    required this.onRedo,
    required this.onCopy,
    required this.onPaste,
    required this.onShowSettings,
    required this.onShowHelp,
    required this.onLanguageSelected,
    required this.onPointerEnter,
    required this.onPointerExit,
  });

  final bool visible;
  final List<String> recentFolders;
  final List<String> recentFiles;
  final List<_LanguageOption> languageOptions;
  final String activeLanguageCode;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenFolder;
  final ValueChanged<String> onOpenRecentFolder;
  final ValueChanged<String> onOpenRecentFile;
  final VoidCallback onClearRecent;
  final VoidCallback onExit;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onShowSettings;
  final VoidCallback onShowHelp;
  final Future<void> Function(String code) onLanguageSelected;
  final VoidCallback onPointerEnter;
  final VoidCallback onPointerExit;

  @override
  Widget build(BuildContext context) {
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
                            onPressed: onOpenFile,
                            leadingIcon: const Icon(Icons.image_outlined),
                            child: Text(t('menu.openFile')),
                          ),
                          MenuItemButton(
                            onPressed: onOpenFolder,
                            leadingIcon: const Icon(Icons.folder_open),
                            child: Text(t('menu.openFolder')),
                          ),
                          _RecentFilesMenu(
                            recentFolders: recentFolders,
                            recentFiles: recentFiles,
                            onOpenRecentFolder: onOpenRecentFolder,
                            onOpenRecentFile: onOpenRecentFile,
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
                            onPressed: () {
                              showAboutDialog(
                                context: context,
                                applicationName: t('app.title'),
                                applicationVersion: '0.1.0',
                              );
                            },
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
}

class _RecentFilesMenu extends StatelessWidget {
  const _RecentFilesMenu({
    required this.recentFolders,
    required this.recentFiles,
    required this.onOpenRecentFolder,
    required this.onOpenRecentFile,
    required this.onClearRecent,
  });

  final List<String> recentFolders;
  final List<String> recentFiles;
  final ValueChanged<String> onOpenRecentFolder;
  final ValueChanged<String> onOpenRecentFile;
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
    return MenuItemButton(
      onPressed: () => onOpenRecentFolder(folder),
      leadingIcon: const Icon(Icons.folder_outlined),
      child: SizedBox(
        width: 260,
        child: Text(folder, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  MenuItemButton _fileMenuItem(String file) {
    return MenuItemButton(
      onPressed: () => onOpenRecentFile(file),
      leadingIcon: const Icon(Icons.image_outlined),
      child: SizedBox(
        width: 260,
        child: Text(file, maxLines: 1, overflow: TextOverflow.ellipsis),
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

    return AlertDialog(
      title: Text(t('shortcut.title')),
      content: Focus(
        focusNode: _captureFocusNode,
        autofocus: true,
        onKeyEvent: _captureKey,
        child: SizedBox(
          width: 420,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final action in _ShortcutAction.values)
                    _ShortcutEditRow(
                      action: action,
                      label: t(action.labelKey),
                      shortcut: config.binding(action).displayLabel,
                      waiting: _waitingAction == action,
                      onPressed: _startCapture,
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

bool _addRecent(List<String> items, String value) {
  final key = _pathKey(value);
  if (items.any((item) => _pathKey(item) == key)) {
    return false;
  }
  items.insert(0, value);
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

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNullValue {
    final iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }
}

String _keyboardLabel(LogicalKeyboardKey key) {
  if (key.keyLabel.isNotEmpty) {
    return key.keyLabel.toUpperCase();
  }
  return key.debugName ?? key.keyId.toString();
}
