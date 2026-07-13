// =============================================================================
// i18n.dart - Internationalization / 国际化
// =============================================================================
// Loads language strings from JSON assets, provides the t() lookup function,
// fallback English/Chinese dictionary, and available language enumeration.
//
// 从 JSON 资源加载语言字符串，提供 t() 查找函数、中英文回退字典和可用语言枚举。
// =============================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const appDefaultLanguageCode = 'zh_cn';
const appLanguageAssetDirectory = 'lib/language';

class AppLanguageStrings {
  const AppLanguageStrings(this._values);

  factory AppLanguageStrings.fallback() => const AppLanguageStrings(_fallback);

  final Map<String, String> _values;

  String text(String key) => _values[key] ?? _fallback[key] ?? key;

  static Future<AppLanguageStrings> load(String code) async {
    try {
      final source = await rootBundle.loadString(
        '$appLanguageAssetDirectory/$code.json',
      );
      final decoded = jsonDecode(source);
      if (decoded is! Map) {
        return AppLanguageStrings.fallback();
      }
      return AppLanguageStrings(
        decoded.map((key, value) => MapEntry(key.toString(), value.toString())),
      );
    } on Object {
      return AppLanguageStrings.fallback();
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
    'ai.sam3ClickHint': '点击模式：左键添加目标点，右键添加排除点。',
    'ai.sam3ClickLocalOnly':
        '全部标注会使用 SAM3-Video 将当前图片的正负点传播到目标范围；图片序列构图连续或高度相似时效果最好，不会训练模型。',
    'ai.sam3ClickPreview': '刷新预览',
    'ai.sam3PromptRequired': '请先输入 SAM3 文本提示词',
    'ai.sam3ClickRequired': '请先在图片上左键添加 SAM3 正点',
    'ai.sam3ClickCurrentOnly': '当前点击提示图片必须在标注范围内',
    'ai.sam3RuntimeConfig': 'SAM3 配置',
    'ai.sam3Precision': '精度',
    'ai.sam3Encoder': '编码器',
    'ai.sam3BatchImage': '图片 batch',
    'ai.sam3BatchVideo': '视频 batch',
    'ai.sam3BatchInteractive': '交互 batch',
    'ai.sam3MaxWidth': '预缩放宽度',
    'ai.sam3MaxHeight': '预缩放高度',
    'ai.sam3ResizeMethod': '缩放方式',
    'ai.sam3ResizeShorterSide': 'shorter_side',
    'ai.sam3Compile': 'torch.compile',
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
    'train.exportSettings': '导出设置',
    'train.exportFormat': '导出类型',
    'train.exportNow': '手动导出',
    'train.autoExportAfterTraining': '训练完成后自动导出',
    'train.exportDone': '导出完成',
    'train.exportFailed': '导出失败',
    'train.exportNoModel': '请先选择可导出的模型',
    'train.exportDataOnlyInt8': '仅 INT8 量化需要 data.yaml',
    'train.exportDataMissing': 'INT8 量化需要选择 data.yaml；自动导出会使用本次训练的数据集',
    'train.exportParam.format':
        '导出格式。目前支持 OpenVINO 和 ONNX；OpenVINO 适合 Intel 推理，ONNX 适合通用部署。',
    'train.exportParam.imgsz': '导出模型的输入图像尺寸，通常与训练尺寸一致。',
    'train.exportParam.batch': '导出模型的 batch 大小。需要可变 batch 时可配合 dynamic 使用。',
    'train.exportParam.quantize': '量化精度。默认 FP32；FP16 可降低体积和显存；INT8 需要校准数据。',
    'train.exportParam.fraction': 'INT8 校准时使用的数据集比例，范围 0-1，默认使用全部数据。',
    'train.exportParam.dynamic': '启用动态输入尺寸或 batch，适合可变输入，但可能影响部分推理后端优化。',
    'train.exportParam.nms': '将 NMS 后处理合入导出模型，方便端侧直接输出过滤后的预测结果。',
    'train.exportParam.simplify': 'ONNX 导出后简化计算图，通常可减少冗余节点。',
    'train.exportParam.opset': 'ONNX opset 版本；留空时由 Ultralytics 自动选择。',
    'train.exportParam.data': 'INT8 量化校准使用的 data.yaml。手动导出需选择；自动导出使用本次训练的数据集。',
    'train.exportParam.device': 'ONNX 导出或量化使用的设备，例如 cpu 或 GPU 编号 0。',
    'train.exportParam.autoExport':
        '训练完成后按当前设置自动导出模型；INT8 自动导出会使用本次训练的 data.yaml。',
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
    'logs.top': '顶端',
    'logs.bottom': '底部',
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
    'detect.deviceIntelUnavailable': '未检测到 Intel OpenVINO 设备',
    'detect.deviceCpu': 'CPU',
    'detect.deviceHelp':
        '自动优先使用 NVIDIA CUDA，其次使用 OpenVINO 导出的 Intel GPU、NPU、CPU 推理模型，最后回退 CPU；OpenVINO 需要选择 *_openvino_model 或 .xml 模型。',
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
    'action.select': '选择',
    'action.close': '关闭',
    'action.save': '保存',
    'action.cancel': '取消',
    'action.delete': '删除',
    'action.clear': '清空',
    'ai.sam3SaveClassTitle': '保存 SAM3 标注',
    'ai.sam3SaveClassName': '类别名称',
    'ai.sam3SaveClassHint': '选择已有类别或输入新类别',
  };
}

AppLanguageStrings _currentLanguageStrings = AppLanguageStrings.fallback();

final ValueNotifier<AppLanguageStrings> languageStringsNotifier =
    ValueNotifier(_currentLanguageStrings);

String t(String key) => _currentLanguageStrings.text(key);

void setCurrentLanguageStrings(AppLanguageStrings strings) {
  _currentLanguageStrings = strings;
  languageStringsNotifier.value = strings;
}

typedef LanguageCodeComparator = int Function(String left, String right);

class LanguageOption {
  const LanguageOption({required this.code, required this.label});

  final String code;
  final String label;

  static Future<List<LanguageOption>> loadAvailable({
    LanguageCodeComparator? compare,
  }) async {
    final codes = await _loadLanguageCodes(compare: compare);
    final options = <LanguageOption>[];
    for (final code in codes) {
      final strings = await AppLanguageStrings.load(code);
      final label = strings.text('language.name');
      options.add(LanguageOption(code: code, label: label));
    }
    options.sort((a, b) => (compare ?? _compareLanguageText)(a.label, b.label));
    return options;
  }

  static Future<List<String>> _loadLanguageCodes({
    LanguageCodeComparator? compare,
  }) async {
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
      codes.add(appDefaultLanguageCode);
    }
    return codes.toList()..sort(compare ?? _compareLanguageText);
  }

  static void _addLanguageCodesFromPaths(
    Set<String> codes,
    Iterable<String> paths,
  ) {
    const prefix = '$appLanguageAssetDirectory/';
    for (final path in paths) {
      if (!path.startsWith(prefix) || !path.endsWith('.json')) {
        continue;
      }
      final filename = path.substring(prefix.length);
      codes.add(filename.substring(0, filename.length - '.json'.length));
    }
  }
}

int _compareLanguageText(String left, String right) => left.compareTo(right);
