// =============================================================================
// workspace_shell.dart - Workspace Shell / 工作区外壳
// =============================================================================
// Main workspace layout: top menu bar, collapsible sidebar, IndexedStack page
// switcher, bottom controls, floating AI assist panel, and fullscreen overlays.
// Owns all top-level state (theme, zoom, tool, section, collaboration).
//
// 主工作区布局：顶栏、侧边栏、页面切换器、底栏、浮动 AI 面板和全屏覆盖层。
// 持有顶层状态：主题、缩放、工具、当前功能区、协作。
// =============================================================================

// ignore_for_file: invalid_use_of_protected_member

import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/annotation_database_controller.dart';
import '../../controllers/ai_annotation_controller.dart';
import '../../controllers/ai_annotation_workflow_controller.dart';
import '../../controllers/ai_workspace_controller.dart';
import '../../controllers/annotation_editing_controller.dart';
import '../../controllers/collaboration_controller.dart';
import '../../controllers/collaboration_sync_controller.dart';
import '../../controllers/collaboration_workspace_controller.dart';
import '../../controllers/dataset_workflow_controller.dart';
import '../../controllers/export_controller.dart';
import '../../controllers/project_controller.dart';
import '../../controllers/project_session_controller.dart';
import '../../controllers/sam3_click_workflow_controller.dart';
import '../../controllers/workspace_navigation_controller.dart';
import '../../controllers/workspace_settings_controller.dart';
import '../../controllers/workspace_viewport_controller.dart';
import '../../dialogs/about_dialog.dart';
import '../../dialogs/color_picker_dialog.dart';
import '../../dialogs/export_dialog.dart';
import '../../dialogs/label_class_dialog.dart';
import '../../dialogs/log_viewer_dialog.dart';
import '../../dialogs/settings_dialog.dart';
import '../../dialogs/shortcut_dialog.dart';
import '../../dialogs/training_history_dialog.dart';
import '../../models/ai_assist.dart';
import '../../models/app_status.dart';
import '../../models/annotation.dart';
import '../../models/collaboration.dart';
import '../../models/config.dart';
import '../../models/export.dart';
import '../../models/imported_dataset.dart';
import '../../models/shortcut.dart';
import '../../pages/detect_video_page.dart';
import '../../pages/label/bottom_controls.dart';
import '../../pages/train_page.dart';
import '../../services/ai_error_utils.dart';
import '../../services/app_runtime.dart';
import '../../services/collaboration_identity.dart';
import '../../services/config_store.dart';
import '../../services/i18n.dart';
import '../../services/image_size.dart';
import '../../services/input_utils.dart';
import '../../services/logger.dart';
import '../../services/path_utils.dart';
import '../../theme/colors.dart';
import '../../theme/dimensions.dart';
import '../label/label_workspace_page.dart';
import 'floating_message.dart';
import 'navigation.dart';
import 'workspace_composition.dart';
import 'workspace_layers.dart';

const _topMenuAutoHideDelay = topMenuAutoHideDelay;
const _labelColorPalette = labelColorPalette;

const _imageTypeGroup = XTypeGroup(
  label: 'Images',
  extensions: ['jpg', 'jpeg', 'png', 'bmp', 'webp'],
);
const _yamlTypeGroup = XTypeGroup(label: 'YAML', extensions: ['yaml', 'yml']);

class WorkspaceShell extends StatefulWidget {
  const WorkspaceShell({super.key, required this.status});

  final BridgeStatus status;

  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell> {
  final FocusNode _keyboardFocusNode = FocusNode(debugLabel: 'workspace');
  final DetectVideoSession _detectVideoSession = DetectVideoSession();
  final GlobalKey<TrainPageState> _trainPageKey = GlobalKey<TrainPageState>();
  Timer? _topMenuHideTimer;

  final ProjectController _project = ProjectController();
  late final ProjectSessionController _projectSession;
  late final AnnotationDatabaseController _annotationDatabase;
  late final DatasetWorkflowController _datasetWorkflow;
  late final ExportController _exportController;
  final WorkspaceNavigationController _navigation =
      WorkspaceNavigationController();
  static const WorkspaceShortcutResolver _shortcutResolver =
      WorkspaceShortcutResolver();
  late final WorkspaceShortcutDispatcher _shortcutDispatcher;
  late final WorkspaceSettingsController _settingsController;
  final WorkspaceViewportController _viewport = WorkspaceViewportController();
  final AiAnnotationController _ai = AiAnnotationController();
  late final AiAnnotationWorkflowController _aiWorkflow;
  late final AiWorkspaceController _aiWorkspace;
  late final Sam3ClickWorkflowController _sam3ClickWorkflow;
  bool _shortcutDialogOpen = false;
  bool _importingDataset = false;
  bool _topMenuVisible = true;
  bool _videoFullscreenVisible = false;
  bool _aiPanelVisible = false;
  Offset? _aiAssistPanelOffset;
  Size _aiAssistPanelSize = const Size(320, 360);
  late final CollaborationController _collaboration = CollaborationController(
    defaultUserName: Platform.environment['USERNAME']?.trim().isNotEmpty == true
        ? Platform.environment['USERNAME']!.trim()
        : 'User',
  );
  late final CollaborationSyncController _collaborationSync;
  late final CollaborationWorkspaceController _collaborationWorkspace;
  late final AnnotationEditingController _annotationEditing;

  CollaborationMode get _collaborationMode => _collaboration.mode;
  String get _collaborationHostId => _collaboration.hostId;
  String get _collaborationUserId => _collaboration.userId;
  String get _collaborationUserName => _collaboration.userName;
  int get _collaborationPort => _collaboration.port;
  int get _collaborationStartIndex => _collaboration.assignmentStart;
  int get _collaborationEndIndex => _collaboration.assignmentEnd;
  List<CollaborationPeer> get _collaborationPeers => _collaboration.peers;
  List<CollaborationDiscoveredHost> get _collaborationDiscoveredHosts =>
      _collaboration.discoveredHosts;
  String? get _selectedCollaborationHostId => _collaboration.selectedHostId;
  bool get _collaborationJoining => _collaboration.joining;
  bool get _collaborationReconnecting => _collaboration.reconnecting;
  int get _collaborationReconnectAttempts => _collaboration.reconnectAttempts;
  List<ImageItem> get _images => _project.images;
  double get _zoom => _viewport.zoom;
  bool get _zoomLocked => _viewport.zoomLocked;
  Offset get _labelViewportOffset => _viewport.offset;
  List<LanguageOption> get _languageOptions =>
      _settingsController.languageOptions;
  bool get _darkMode => _settingsController.darkMode;
  String get _activeLanguageCode => _settingsController.activeLanguageCode;
  ShortcutConfig get _shortcutConfig => _settingsController.shortcuts;
  AppSettings get _appSettings => _settingsController.settings;
  String get _activeSection => _navigation.activeSection;
  set _activeSection(String value) => _navigation.activeSection = value;
  String get _activeTool => _navigation.activeTool;
  set _activeTool(String value) => _navigation.activeTool = value;
  bool get _sidebarCollapsed => _navigation.sidebarCollapsed;
  set _sidebarCollapsed(bool value) => _navigation.sidebarCollapsed = value;
  bool get _showClassLabels => _navigation.showClassLabels;
  set _showClassLabels(bool value) => _navigation.showClassLabels = value;
  AnnotationMode get _activeAnnotationMode => _navigation.annotationMode;
  List<RecentEntry> get _recentFolders => _projectSession.recentFolders;
  List<RecentEntry> get _recentFiles => _projectSession.recentFiles;
  List<LabelClass> get _labelClasses => _project.labelClasses;
  Map<String, List<AnnotationRegion>> get _annotationsByImage =>
      _project.annotationsByImage;
  int get _selectedImageIndex => _project.selectedImageIndex;
  String? get _selectedAnnotationId => _project.selectedAnnotationId;
  set _selectedAnnotationId(String? value) =>
      _project.selectedAnnotationId = value;
  int? get _activeClassId => _project.activeClassId;
  set _activeClassId(int? value) => _project.activeClassId = value;
  Size? get _imageDisplaySize => _project.imageDisplaySize;
  set _imageDisplaySize(Size? value) => _project.imageDisplaySize = value;
  Map<String, Size> get _imageDisplaySizes => _project.imageDisplaySizes;
  ImportedDataset? get _importedDataset => _project.importedDataset;
  set _importedDataset(ImportedDataset? value) =>
      _project.importedDataset = value;
  AiAssistConfig? get _aiAssistConfig => _ai.config;
  bool get _aiAnnotating => _ai.annotating;

  ImageItem? get _selectedImage => _project.selectedImage;

  bool get _collaborationClientMode => _collaboration.clientMode;

  int get _currentAnnotatorColorValue => _collaboration.annotatorColorValue;

  String get _currentAnnotatorLabel => _collaboration.annotatorLabel;

  bool get _selectedImageAuthorized =>
      _isImageIndexAuthorized(_selectedImageIndex);

  bool get _projectLockedByCollaboration => _collaboration.projectLocked;

  ImageItem? get _selectedImageForLabel {
    if (!_selectedImageAuthorized) {
      return null;
    }
    return _selectedImage;
  }

  List<AnnotationRegion> get _currentAnnotationsForLabel {
    if (!_selectedImageAuthorized) {
      return const [];
    }
    return _currentAnnotations;
  }

  bool get _sam3ClickModeActive {
    final config = _aiAssistConfig;
    return _aiPanelVisible &&
        config != null &&
        config.backend == AiAssistBackend.sam3 &&
        config.sam3PromptMode == AiSam3PromptMode.click;
  }

  List<Sam3ClickPromptPoint> get _currentSam3ClickPromptsForLabel {
    if (!_sam3ClickModeActive || !_selectedImageAuthorized) {
      return const [];
    }
    final image = _selectedImage;
    if (image == null) {
      return const [];
    }
    return _ai.promptsFor(image.path);
  }

  List<AnnotationRegion> get _currentSam3ClickPreviewForLabel {
    if (!_sam3ClickModeActive || !_selectedImageAuthorized) {
      return const [];
    }
    final image = _selectedImage;
    if (image == null) {
      return const [];
    }
    return _ai.previewFor(image.path)?.annotations ?? const [];
  }

  bool _isImageIndexAuthorized(int zeroBasedIndex) {
    return _collaboration.isImageIndexAuthorized(
      zeroBasedIndex,
      _images.length,
    );
  }

  bool _guardProjectChangeBlocked() {
    if (!_projectLockedByCollaboration) {
      return false;
    }
    _showFloatingMessage(t('collab.disconnectFirst'));
    return true;
  }

  void _clearCurrentProjectState() {
    _projectSession.cancelResumeSave();
    _project.clear();
    _ai.clearProject();
    _viewport.forceReset();
    setState(() {
      _activeSection = 'label';
    });
  }

  String? get _selectedImageKey {
    return _project.selectedImageKey;
  }

  List<AnnotationRegion> get _currentAnnotations => _project.currentAnnotations;

  String get _selectedImageSplit => _project.selectedImageSplit;

  Size? _displaySizeForImagePath(String path) {
    return _project.displaySizeForPath(path);
  }

  @override
  void initState() {
    super.initState();
    _settingsController = WorkspaceSettingsController(
      collaboration: _collaboration,
    );
    _projectSession = ProjectSessionController(project: _project);
    _datasetWorkflow = DatasetWorkflowController(project: _project);
    _exportController = ExportController(
      project: _project,
      trainingLauncher: _launchExportedDatasetTraining,
    );
    _aiWorkflow = AiAnnotationWorkflowController(
      runtime: _ai,
      project: _project,
    );
    _sam3ClickWorkflow = Sam3ClickWorkflowController(runtime: _ai);
    _collaborationSync = CollaborationSyncController(
      collaboration: _collaboration,
      project: _project,
    );
    _annotationDatabase = AnnotationDatabaseController(
      project: _project,
      collaboration: _collaboration,
      collaborationSync: _collaborationSync,
    );
    _aiWorkspace = AiWorkspaceController(
      runtime: _ai,
      workflow: _aiWorkflow,
      project: _project,
      collaboration: _collaboration,
      collaborationSync: _collaborationSync,
      annotationDatabase: _annotationDatabase,
    );
    _collaborationWorkspace = CollaborationWorkspaceController(
      collaboration: _collaboration,
      sync: _collaborationSync,
      project: _project,
    );
    _annotationEditing = AnnotationEditingController(
      project: _project,
      collaboration: _collaboration,
      collaborationSync: _collaborationSync,
      onChanged: _annotationDatabase.scheduleSave,
    );
    _shortcutDispatcher = WorkspaceShortcutDispatcher(
      actions: WorkspaceShortcutActions(
        delegateBrowse: (event) =>
            _detectVideoSession.handleShortcutKey(event, _shortcutConfig),
        undo: _undoAnnotationChange,
        redo: _redoAnnotationChange,
        copy: _copySelectedAnnotation,
        paste: _pasteAnnotation,
        cancelSelection: () {
          setState(() {
            _navigation.cancelSelection();
            _selectedAnnotationId = null;
          });
        },
        previousImage: (step) => _selectPreviousImage(step: step),
        nextImage: (step) => _selectNextImage(step: step),
        onNoPreviousImage: () =>
            _showFloatingMessage(t('detect.hudNoPrevious')),
        onNoNextImage: () => _showFloatingMessage(t('detect.hudNoNext')),
        adjustZoom: _viewport.adjustZoom,
        activateMode: _activateAnnotationMode,
        deleteSelected: _deleteSelectedAnnotation,
        toggleClassLabels: () {
          setState(() => _showClassLabels = !_showClassLabels);
        },
        rotateObb: _rotateSelectedAnnotation,
        aiAnnotateCurrent: () => unawaited(_runAiAnnotateCurrent()),
        aiAnnotateAll: () => unawaited(_runAiAnnotateAll()),
      ),
    );
    _detectVideoSession.addListener(_handleDetectVideoSessionChanged);
    _collaboration.onTransportError = _handleCollaborationTransportError;
    _collaboration.addListener(_handleCollaborationControllerChanged);
    _settingsController.addListener(_handleSettingsChanged);
    _viewport.addListener(_handleViewportChanged);
    _project.addListener(_handleProjectControllerChanged);
    _projectSession.addListener(_handleProjectSessionChanged);
    _ai.addListener(_handleAiControllerChanged);
    _loadPersistedConfig();
    _loadAvailableLanguages();
    _collaboration.startPolling(_handleCollaborationEvent);
    _resetCollaborationRuntimeForStartup();
    this._scheduleTopMenuHide();
  }

  void _resetCollaborationRuntimeForStartup() {
    unawaited(_collaboration.resetTransportForStartup());
  }

  @override
  void dispose() {
    logApp('APP', 'Shutdown requested');
    _topMenuHideTimer?.cancel();
    _annotationDatabase.cancelScheduledSave();
    unawaited(_collaboration.stopTransport(restartDiscovery: false));
    unawaited(_annotationDatabase.saveNow());
    _annotationDatabase.dispose();
    _saveLabelResumePositionNow();
    appLogger.dispose();
    _settingsController.removeListener(_handleSettingsChanged);
    _settingsController.dispose();
    _viewport.removeListener(_handleViewportChanged);
    _viewport.dispose();
    _collaboration.removeListener(_handleCollaborationControllerChanged);
    _collaboration.dispose();
    _project.removeListener(_handleProjectControllerChanged);
    _project.dispose();
    _projectSession.removeListener(_handleProjectSessionChanged);
    _projectSession.dispose();
    _ai.removeListener(_handleAiControllerChanged);
    _ai.dispose();
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

  void _handleCollaborationControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleSettingsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleViewportChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleCollaborationTransportError(
    Map<String, Object?> request,
    Object error,
  ) {
    if (mounted) {
      _showFloatingMessage(t('collab.networkError'));
    }
  }

  void _handleProjectControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleProjectSessionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleAiControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _loadPersistedConfig() {
    _projectSession.loadHistory();
    _settingsController.loadPersisted();
    logApp(
      'APP',
      'Config loaded: recentFolders=${_recentFolders.length}, recentFiles=${_recentFiles.length}, logLevel=${appLogger.minLevel.name}',
      level: AppLogLevel.debug,
    );
  }

  Future<void> _loadAvailableLanguages() async {
    await _settingsController.loadAvailableLanguages();
  }

  Future<void> _changeLanguage(String code) async {
    final changed = await _settingsController.changeLanguage(code);
    if (!changed || !mounted) {
      return;
    }
    logApp('SETTINGS', 'Language changed: $code');
    this._showTopMenu();
  }

  void _saveAppSettings(AppSettings settings) {
    _settingsController.saveSettings(settings);
  }

  void _setZoom(double value) {
    _viewport.setZoom(value);
  }

  void _setLabelViewportOffset(Offset offset) {
    _viewport.setOffset(offset);
  }

  void _resetZoomAndViewport() {
    _viewport.reset();
  }

  void _toggleZoomLock() {
    _viewport.toggleZoomLock();
  }

  void _scheduleLabelResumePositionSave() {
    _projectSession.scheduleResumeSave(
      projectKey: _annotationDatabase.projectKey,
      enabled: !_collaborationClientMode,
    );
  }

  void _saveLabelResumePositionNow() {
    _projectSession.saveResumePosition(
      projectKey: _annotationDatabase.projectKey,
      enabled: !_collaborationClientMode,
    );
  }

  void _restoreLabelResumePosition() {
    final nextIndex = _projectSession.restoreResumePosition(
      projectKey: _annotationDatabase.projectKey,
      enabled: !_collaborationClientMode,
    );
    if (nextIndex != null) {
      logApp(
        'LABEL',
        'Restored image position: ${nextIndex + 1}/${_images.length}',
        level: AppLogLevel.debug,
      );
    }
  }

  void _selectImage(int index) {
    if (!_project.selectImage(index)) {
      return;
    }
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
    logApp('LABEL', 'Open image file: ${file.path}');

    if (insertAfterIndex != null) {
      final existingIndex = _imageIndexOfPath(file.path);
      if (existingIndex >= 0) {
        _projectSession.touchRecentFile(file.path);
        _selectImage(existingIndex);
        return;
      }

      _projectSession.touchRecentFile(file.path);
      _importedDataset = null;
      _insertImages([file.path], insertAfterIndex: insertAfterIndex);
      await _annotationDatabase.loadForCurrentImages();
      return;
    }

    await _openSingleImageProject(file.path);
  }

  Future<void> _openSingleImageProject(String path) async {
    _clearCurrentProjectState();
    _projectSession.openSingleImage(path);
    logApp('LABEL', 'Single image project opened: $path');
    await _annotationDatabase.loadForCurrentImages();
    _scheduleLabelResumePositionSave();
  }

  Future<void> _openImageFolder([String? path]) async {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    final folderPath = path ?? await getDirectoryPath();
    if (folderPath == null) {
      return;
    }

    final files = _projectSession.openImageFolder(folderPath);
    logApp(
      'LABEL',
      'Open image folder: $folderPath, images=${files.length}',
      level: files.isEmpty ? AppLogLevel.warning : AppLogLevel.info,
    );
    setState(() => _activeSection = 'label');
    await _annotationDatabase.loadForCurrentImages();
    _restoreLabelResumePosition();
  }

  Future<void> _openRecentFolder(String path) async {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    if (!Directory(path).existsSync()) {
      _projectSession.removeRecentFolder(path);
      logApp(
        'HISTORY',
        'Removed missing recent folder: $path',
        level: AppLogLevel.warning,
      );
      _showFloatingMessage(t('recent.missingFolder'));
      return;
    }
    await _openImageFolder(path);
  }

  Future<void> _openRecentFile(String path) async {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    logApp('LABEL', 'Open recent file: $path');
    if (!File(path).existsSync()) {
      _projectSession.removeRecentFile(path);
      logApp(
        'HISTORY',
        'Removed missing recent file: $path',
        level: AppLogLevel.warning,
      );
      _showFloatingMessage(t('recent.missingFile'));
      return;
    }
    await _openSingleImageProject(path);
  }

  void _insertImages(List<String> paths, {int? insertAfterIndex}) {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    final inserted = _project.insertImages(
      paths,
      insertAfterIndex: insertAfterIndex,
    );
    if (inserted == 0) {
      return;
    }
    setState(() => _activeSection = 'label');
    logApp(
      'LABEL',
      'Images inserted: count=$inserted, total=${_images.length}',
    );
    this._broadcastCollaborationProjectSnapshot('images inserted');
    _scheduleLabelResumePositionSave();
    _annotationDatabase.scheduleSave();
  }

  int _imageIndexOfPath(String path) {
    return _project.imageIndexOfPath(path);
  }

  void _deleteImage(int index) {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    if (index < 0 || index >= _images.length) {
      return;
    }

    final removedPath = _images[index].path;
    final removed = _project.deleteImage(index);
    if (removed == null) {
      return;
    }
    _ai.clearImage(removed.path);
    logApp('LABEL', 'Image removed: $removedPath, total=${_images.length}');
    this._broadcastCollaborationProjectSnapshot('image deleted');
    _scheduleLabelResumePositionSave();
    _annotationDatabase.scheduleSave();
  }

  void _setSelectedImageSplit(String split) {
    if (_project.setSelectedImageSplit(split, datasetSplits.toSet())) {
      _annotationDatabase.scheduleSave();
    }
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
    showTrainingHistoryRecordsDialog(
      context: context,
      history: ConfigStore.loadTrainingHistory().entries,
      onEmpty: () => _showFloatingMessage(t('train.noHistory')),
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
      final result = await _datasetWorkflow.importDataset(
        yamlPath: file.path,
        ensureImageDisplaySize: this._computeImageDisplaySize,
      );
      if (!mounted) {
        return;
      }
      switch (result.status) {
        case DatasetImportStatus.imported:
          setState(() => _activeSection = 'label');
          _restoreLabelResumePosition();
          unawaited(_annotationDatabase.saveNow());
          _showFloatingMessage('${t('import.done')} (${result.imageCount})');
          break;
        case DatasetImportStatus.noImages:
          _showFloatingMessage(t('import.noImages'));
          break;
        case DatasetImportStatus.failed:
          _showFloatingMessage(t('import.failed'));
          break;
      }
    } finally {
      if (mounted) {
        setState(() => _importingDataset = false);
      }
    }
  }

  void _showFloatingMessage(String message) {
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;
    entry = OverlayEntry(builder: (_) => FloatingMessage(message: message));
    overlay.insert(entry);
    Future<void>.delayed(const Duration(milliseconds: 950), () {
      entry.remove();
    });
  }

  void _saveAiAssistConfig(AiAssistConfig config) {
    _aiWorkspace.saveConfig(config);
  }

  Future<AiAssistConfig?> _ensureAiAssistConfig() async {
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

  Future<void> _runAiAnnotateCurrentWithConfig(AiAssistConfig config) async {
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

  Future<void> _runAiAnnotateAllWithConfig(AiAssistConfig config) async {
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

  bool _sam3ClickHasPositivePoint(String imagePath) {
    return _ai.hasPositivePoint(imagePath);
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
        config.backend != AiAssistBackend.sam3 ||
        config.sam3PromptMode != AiSam3PromptMode.click ||
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
    final addition = _sam3ClickWorkflow.addPrompt(
      imagePath: image.path,
      imagePoint: imagePoint,
      displaySize: imageDisplaySize,
      positive: positive,
    );
    if (addition == null) {
      return false;
    }
    final point = addition.point;
    logApp(
      'AI',
      'SAM3 click prompt added: image=${image.name}, point=${point.x.toStringAsFixed(4)},${point.y.toStringAsFixed(4)}, positive=$positive, total=${addition.count}',
      level: AppLogLevel.debug,
    );
    if (_sam3ClickHasPositivePoint(image.path)) {
      await _runSam3ClickPreview(config);
    } else {
      _showFloatingMessage(t('ai.sam3ClickRequired'));
    }
    return true;
  }

  Future<void> _runSam3ClickPreview(AiAssistConfig config) async {
    final image = _selectedImage;
    final imageKey = _selectedImageKey;
    if (_aiAnnotating ||
        image == null ||
        imageKey == null ||
        config.backend != AiAssistBackend.sam3 ||
        config.sam3PromptMode != AiSam3PromptMode.click) {
      return;
    }
    try {
      await _sam3ClickWorkflow.runPreview(
        config: config,
        pythonPath: _appSettings.pythonPath,
        imagePath: image.path,
        classId: _activeClassId ?? -1,
        displaySizeResolver: this._computeImageDisplaySize,
        beforeRun: () => WidgetsBinding.instance.endOfFrame,
      );
    } on Sam3ClickWorkflowException catch (error) {
      switch (error.failure) {
        case Sam3ClickWorkflowFailure.busy:
          _showFloatingMessage(t('ai.annotating'));
          return;
        case Sam3ClickWorkflowFailure.pythonNotConfigured:
          logApp(
            'AI',
            'SAM3 click preview blocked: Python path is empty',
            level: AppLogLevel.warning,
          );
          _showFloatingMessage(t('detect.pythonNotConfigured'));
          return;
        case Sam3ClickWorkflowFailure.positivePointRequired:
          logApp(
            'AI',
            'SAM3 click preview blocked: no positive click prompt points',
            level: AppLogLevel.warning,
          );
          _showFloatingMessage(t('ai.sam3ClickRequired'));
          return;
        case Sam3ClickWorkflowFailure.invalidConfig:
          return;
      }
    } on Object catch (error) {
      final failure = classifyAiFailure(error);
      logApp(
        'AI',
        'SAM3 click preview failed: failure=$failure',
        level: AppLogLevel.error,
      );
      logAppMultiline(
        'AI',
        error.toString(),
        level: AppLogLevel.error,
        prefix: 'detail: ',
      );
      _showFloatingMessage('${t('ai.failed')}: ${shortAiError(error)}');
    }
  }

  Future<void> _commitSam3ClickPreview(AiAssistConfig config) async {
    final image = _selectedImage;
    final imageKey = _selectedImageKey;
    if (image == null ||
        imageKey == null ||
        config.backend != AiAssistBackend.sam3 ||
        config.sam3PromptMode != AiSam3PromptMode.click) {
      return;
    }
    if (!_sam3ClickHasPositivePoint(image.path)) {
      _showFloatingMessage(t('ai.sam3ClickRequired'));
      return;
    }
    var preview = _ai.previewFor(image.path);
    if (preview == null) {
      await _runSam3ClickPreview(config);
      preview = _ai.previewFor(image.path);
    }
    if (preview == null) {
      return;
    }
    if (preview.result.masks.isEmpty) {
      _showFloatingMessage('${t('ai.done')} (0)');
      return;
    }
    final selectedClassName = await _promptSam3ClickSaveClassName(config);
    if (selectedClassName == null || selectedClassName.trim().isEmpty) {
      return;
    }
    final added = _aiWorkspace.commitClickPreview(
      config: config,
      imagePath: image.path,
      className: selectedClassName,
      nextClassColorValue: () => _nextClassColor().toARGB32(),
    );
    _showFloatingMessage('${t('ai.done')} ($added)');
  }

  Future<void> _handleAiAssistSave(AiAssistConfig config) async {
    if (config.backend == AiAssistBackend.sam3 &&
        config.sam3PromptMode == AiSam3PromptMode.click) {
      await _commitSam3ClickPreview(config);
    }
  }

  Future<String?> _promptSam3ClickSaveClassName(AiAssistConfig config) async {
    final activeClass = _activeClassId == null
        ? null
        : this._classById(_activeClassId!);
    final firstPrompt = config.sam3PromptText
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .firstOrNull;
    final initialName =
        activeClass?.name ??
        (_labelClasses.isNotEmpty ? _labelClasses.first.name : null) ??
        firstPrompt ??
        'sam3_click';
    return showSam3SaveClassDialog(
      context: context,
      initialName: initialName,
      labelClasses: _labelClasses,
    );
  }

  Future<void> _runAiAnnotateForIndices(
    List<int> indices,
    AiAssistConfig config,
  ) async {
    if (_aiAnnotating || indices.isEmpty) {
      return;
    }
    final planResult = _aiWorkflow.createPlan(
      indices: indices,
      config: config,
      pythonPath: _appSettings.pythonPath,
      promptImageIndex: _selectedImageIndex,
    );
    final plan = planResult.plan;
    if (plan == null) {
      _handleAiAnnotationPlanFailure(planResult.failure!);
      return;
    }
    if (plan.previewOnly) {
      await _runSam3ClickPreview(config);
      return;
    }
    String? samClickClassNameOverride;
    if (plan.sam3ClickMode) {
      samClickClassNameOverride = await _promptSam3ClickSaveClassName(config);
      if (samClickClassNameOverride == null ||
          samClickClassNameOverride.trim().isEmpty) {
        return;
      }
    }
    final execution = await _aiWorkspace.runPlan(
      plan: plan,
      displaySizeResolver: this._computeImageDisplaySize,
      nextClassColorValue: () => _nextClassColor().toARGB32(),
      classNameOverride: samClickClassNameOverride,
      beforeRun: () => WidgetsBinding.instance.endOfFrame,
    );
    final workflowResult = execution.workflowResult;
    if (workflowResult != null) {
      _showFloatingMessage('${t('ai.done')} (${workflowResult.addedCount})');
    } else if (execution.error != null) {
      _showFloatingMessage(
        '${t('ai.failed')}: ${shortAiError(execution.error!)}',
      );
    }
  }

  void _handleAiAnnotationPlanFailure(AiAnnotationPlanFailure failure) {
    switch (failure) {
      case AiAnnotationPlanFailure.pythonNotConfigured:
        logApp(
          'AI',
          'AI annotation blocked: Python path is empty',
          level: AppLogLevel.warning,
        );
        _showFloatingMessage(t('detect.pythonNotConfigured'));
        return;
      case AiAnnotationPlanFailure.noSelectedClasses:
        logApp(
          'AI',
          'AI annotation blocked: no classes selected',
          level: AppLogLevel.warning,
        );
        _showFloatingMessage(t('ai.noSelectedClasses'));
        return;
      case AiAnnotationPlanFailure.sam3TextPromptRequired:
        logApp(
          'AI',
          'SAM3 annotation blocked: text prompt is empty',
          level: AppLogLevel.warning,
        );
        _showFloatingMessage(t('ai.sam3PromptRequired'));
        return;
      case AiAnnotationPlanFailure.noValidTargets:
        logApp(
          'AI',
          'AI annotation blocked: no valid target indices',
          level: AppLogLevel.warning,
        );
        return;
      case AiAnnotationPlanFailure.sam3PromptOutsideTargets:
        logApp(
          'AI',
          'SAM3 click annotation blocked: prompt image is outside the target range',
          level: AppLogLevel.warning,
        );
        _showFloatingMessage(t('ai.sam3ClickCurrentOnly'));
        return;
      case AiAnnotationPlanFailure.sam3PositivePointRequired:
        logApp(
          'AI',
          'SAM3 click annotation blocked: no positive click prompt points',
          level: AppLogLevel.warning,
        );
        _showFloatingMessage(t('ai.sam3ClickRequired'));
        return;
    }
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
    final decision = _shortcutResolver.resolve(
      event: event,
      config: _shortcutConfig,
      activeSection: _activeSection,
      shortcutDialogOpen: _shortcutDialogOpen,
      inputBlocked: _collaborationReconnecting || _importingDataset,
      editableTextFocused: isEditableTextFocused(),
      controlPressed: HardwareKeyboard.instance.isControlPressed,
    );
    return _shortcutDispatcher.dispatch(decision: decision, event: event);
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
            WorkspaceMainLayout(
              topMenu: WorkspaceTopMenu(
                data: WorkspaceTopMenuData(
                  visible: _topMenuVisible,
                  recentFolders: _recentFolders
                      .map((entry) => entry.path)
                      .toList(),
                  recentFiles: _recentFiles.map((entry) => entry.path).toList(),
                  languageOptions: _languageOptions,
                  activeLanguageCode: _activeLanguageCode,
                  projectActionsLocked: _projectLockedByCollaboration,
                ),
                actions: WorkspaceTopMenuActions(
                  onOpenFile: () => _openImageFile(),
                  onOpenFolder: () => _openImageFolder(),
                  onOpenRecentFolder: (path) =>
                      unawaited(_openRecentFolder(path)),
                  onOpenRecentFile: (path) => unawaited(_openRecentFile(path)),
                  onClearRecent: this._clearRecentItems,
                  onExit: () => SystemNavigator.pop(),
                  onImportDataset: _importYoloDataset,
                  onExportDataset: this._showExportDialog,
                  onShowTrainingHistory: _showTrainingHistoryDialog,
                  onUndo: this._undoAnnotationChange,
                  onRedo: this._redoAnnotationChange,
                  onCopy: this._copySelectedAnnotation,
                  onPaste: this._pasteAnnotation,
                  onShowSettings: this._showSettings,
                  onShowLogs: this._showLogViewerDialog,
                  onShowHelp: this._showKeySettings,
                  onShowAbout: this._showAboutDialog,
                  onProjectActionBlocked: () =>
                      _showFloatingMessage(t('collab.disconnectFirst')),
                  onLanguageSelected: _changeLanguage,
                  onPointerEnter: this._showTopMenu,
                  onPointerExit: this._scheduleTopMenuHide,
                ),
              ),
              sidebar: PrimarySidebar(
                activeSection: _activeSection,
                collapsed: _sidebarCollapsed,
                onCollapseChanged: (value) {
                  setState(() => _sidebarCollapsed = value);
                },
                onSectionSelected: (section) {
                  logApp(
                    'NAV',
                    'Switched to: $section',
                    level: AppLogLevel.debug,
                  );
                  setState(() => _activeSection = section);
                },
              ),
              pages: WorkspacePageStack(
                index: _navigation.pageIndex,
                labelPage: LabelWorkspacePage(
                  data: LabelWorkspaceData(
                    status: widget.status,
                    images: _images,
                    selectedImage: _selectedImageForLabel,
                    selectedImageIndex: _selectedImageIndex,
                    unauthorized:
                        _collaborationClientMode && !_selectedImageAuthorized,
                    zoom: _zoom,
                    viewportOffset: _labelViewportOffset,
                    activeTool: _activeTool,
                    activeMode: _activeAnnotationMode,
                    imageSplit: _selectedImageSplit,
                    activeClassId: _activeClassId,
                    labelClasses: _labelClasses,
                    annotationsByImage: _annotationsByImage,
                    annotations: _currentAnnotationsForLabel,
                    sam3ClickPrompts: _currentSam3ClickPromptsForLabel,
                    sam3PreviewAnnotations: _currentSam3ClickPreviewForLabel,
                    selectedAnnotationId: _selectedAnnotationId,
                    showClassLabels: _showClassLabels,
                    aiPanelVisible: _aiPanelVisible,
                    classesEditable: !_collaborationClientMode,
                  ),
                  actions: LabelWorkspaceActions(
                    onImageSelected: _selectImage,
                    onImageContextMenu: _showImageContextMenu,
                    onPointerSignal: _handlePointerSignal,
                    onViewportOffsetChanged: _setLabelViewportOffset,
                    onToolSelected: this._selectTool,
                    onSelectMode: () => this._selectTool('select'),
                    onModeSelected: this._activateAnnotationMode,
                    onImageSplitChanged: _setSelectedImageSplit,
                    onEnsureClass: this._ensureActiveClass,
                    onAnnotationCreated: this._createAnnotation,
                    onSegAnnotationCreated: this._createSegAnnotation,
                    onAnnotationSelected: this._selectAnnotation,
                    onAnnotationUpdated: this._updateAnnotation,
                    onAnnotationDeleted: this._deleteAnnotation,
                    onAnnotationDragStarted: this._pushAnnotationSnapshot,
                    onClassSelected: this._selectLabelClass,
                    onClassAdded: () => this._addLabelClass(),
                    onClassEdited: this._editLabelClass,
                    onClassColorChanged: this._chooseLabelClassColor,
                    onClassDeleted: this._deleteLabelClass,
                    onClassReordered: this._reorderLabelClass,
                    onToggleClassLabels: () =>
                        setState(() => _showClassLabels = !_showClassLabels),
                    onAnnotationClassChanged: this._changeAnnotationClass,
                    onSam3ClickPrompt: _handleSam3ClickPrompt,
                    onAiConfigPressed: () {
                      setState(() => _aiPanelVisible = !_aiPanelVisible);
                    },
                    onImageDisplaySizeChanged: (size) {
                      _imageDisplaySize = size;
                      final key = _selectedImageKey;
                      if (key != null && size != Size.zero) {
                        _imageDisplaySizes[key] = size;
                        _annotationDatabase.scheduleSave();
                      }
                    },
                  ),
                ),
                trainPageKey: _trainPageKey,
                settings: _appSettings,
                shortcutConfig: _shortcutConfig,
                detectVideoSession: _detectVideoSession,
                collaboration: CollaborationPageBinding(
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
                  onUserNameChanged: this._setCollaborationUserName,
                  onPortChanged: this._setCollaborationPort,
                  onHostSelected: _collaboration.selectHost,
                  onStartHost: this._startCollaborationHost,
                  onJoinClient: this._joinCollaborationHost,
                  onStop: this._stopCollaboration,
                  onPeerPermissionsChanged:
                      this._setCollaborationPeerPermissions,
                ),
              ),
              bottomControls: labelPage
                  ? BottomControls(
                      zoom: _zoom,
                      zoomLocked: _zoomLocked,
                      darkMode: _darkMode,
                      onZoomChanged: _setZoom,
                      onResetView: _resetZoomAndViewport,
                      onToggleZoomLock: _toggleZoomLock,
                      onToggleThemeMode: this._toggleThemeMode,
                      onOpenKeySettings: this._showKeySettings,
                    )
                  : null,
            ),
            if (labelPage && _aiPanelVisible)
              Positioned.fill(
                child: AiAssistPanelLayer(
                  requestedSize: _aiAssistPanelSize,
                  requestedOffset: _aiAssistPanelOffset,
                  initialConfig: _aiAssistConfig,
                  imageCount: _images.length,
                  pythonPath: _appSettings.pythonPath,
                  onClose: () => setState(() => _aiPanelVisible = false),
                  onGeometryChanged: (size, offset) {
                    setState(() {
                      _aiAssistPanelSize = size;
                      _aiAssistPanelOffset = offset;
                    });
                  },
                  onConfigSaved: _saveAiAssistConfig,
                  onSave: _handleAiAssistSave,
                  onAnnotateCurrent: _runAiAnnotateCurrentWithConfig,
                  onAnnotateAll: _runAiAnnotateAllWithConfig,
                ),
              ),
            Positioned.fill(
              child: WorkspaceStatusLayers(
                importingDataset: _importingDataset,
                aiAnnotating: _aiAnnotating,
                collaborationReconnecting: _collaborationReconnecting,
                reconnectAttempts: _collaborationReconnectAttempts,
                onCancelReconnect: this._cancelCollaborationReconnect,
                videoFullscreenVisible: _videoFullscreenVisible,
                videoSession: _detectVideoSession,
                shortcutConfig: _shortcutConfig,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension _WorkspaceShellAnnotationActions on _WorkspaceShellState {
  void _pushAnnotationSnapshot() {
    _project.pushAnnotationSnapshot();
  }

  void _undoAnnotationChange() {
    if (_project.undoAnnotations()) {
      _annotationDatabase.scheduleSave();
    }
  }

  void _redoAnnotationChange() {
    if (_project.redoAnnotations()) {
      _annotationDatabase.scheduleSave();
    }
  }

  void _activateAnnotationMode(AnnotationMode mode) {
    setState(() {
      _navigation.activateAnnotationMode(mode);
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
      this._showExportDialog();
      return;
    }
    setState(() => _activeTool = tool);
  }

  LabelClass? _classById(int id) {
    return _project.classById(id);
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
    final name = await showLabelClassNameDialog(
      context: context,
      initialName: 'class_${_labelClasses.length}',
      title: t('label.createClassPrompt'),
    );
    if (name == null || name.trim().isEmpty) {
      return null;
    }
    return _annotationEditing.addLabelClass(
      name: name.trim(),
      colorValue: _nextClassColor().toARGB32(),
    );
  }

  Future<void> _editLabelClass(LabelClass labelClass) async {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    final name = await showLabelClassNameDialog(
      context: context,
      initialName: labelClass.name,
      title: t('label.editClass'),
    );
    if (name == null || name.trim().isEmpty) {
      return;
    }
    _annotationEditing.updateLabelClass(
      labelClass.copyWith(name: name.trim()),
      reason: 'class renamed',
    );
  }

  Future<void> _chooseLabelClassColor(LabelClass labelClass) async {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    final currentColor = labelClass.color;
    final selected = await showWheelColorDialog(
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
    _annotationEditing.updateLabelClass(
      labelClass.copyWith(colorValue: selected.toARGB32()),
      reason: 'class color changed',
    );
  }

  void _deleteLabelClass(LabelClass labelClass) {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    _annotationEditing.deleteLabelClass(labelClass.id);
  }

  void _reorderLabelClass(int oldIndex, int newIndex) {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    _annotationEditing.reorderLabelClass(oldIndex, newIndex);
  }

  void _selectLabelClass(int id) {
    _project.selectLabelClass(id);
  }

  void _createAnnotation(Rect rect, int classId) {
    final annotation = _annotationEditing.createRect(
      rect: rect,
      classId: classId,
      mode: _activeAnnotationMode,
    );
    if (annotation == null) {
      return;
    }
    setState(() => _activeTool = 'draw');
    logApp(
      'ANNOTATION',
      'Created ${annotation.mode.name}: image=${_selectedImage?.name ?? '-'}, classId=$classId',
      level: AppLogLevel.debug,
    );
  }

  void _createSegAnnotation(List<Offset> points, int classId) {
    final annotation = _annotationEditing.createSeg(
      points: points,
      classId: classId,
    );
    if (annotation == null) {
      return;
    }
    setState(() => _activeTool = 'draw');
    logApp(
      'ANNOTATION',
      'Created seg: image=${_selectedImage?.name ?? '-'}, classId=$classId, points=${points.length}',
      level: AppLogLevel.debug,
    );
  }

  void _selectAnnotation(String? id) {
    _annotationEditing.selectAnnotation(id);
  }

  void _updateAnnotation(AnnotationRegion annotation) {
    _annotationEditing.updateAnnotation(annotation);
  }

  void _changeAnnotationClass(String annotationId, int classId) {
    final result = _annotationEditing.changeAnnotationClass(
      annotationId,
      classId,
    );
    if (result == AnnotationEditResult.permissionDenied) {
      _showFloatingMessage(t('collab.permissionDenied'));
    }
  }

  void _deleteAnnotation(String id) {
    final result = _annotationEditing.deleteAnnotation(id);
    if (result == AnnotationEditResult.permissionDenied) {
      _showFloatingMessage(t('collab.permissionDenied'));
    }
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
    final selected = _annotationEditing.copySelectedAnnotation();
    if (selected != null) {
      _showFloatingMessage(t('feedback.copiedAnnotation'));
    }
  }

  void _pasteAnnotation() {
    _annotationEditing.pasteAnnotation();
  }

  void _rotateSelectedAnnotation(double deltaDegrees) {
    final result = _annotationEditing.rotateSelectedAnnotation(
      deltaDegrees,
      imageSize: _imageDisplaySize,
    );
    if (result == AnnotationEditResult.permissionDenied) {
      _showFloatingMessage(t('collab.permissionDenied'));
    }
  }
}

extension _WorkspaceShellCollaborationActions on _WorkspaceShellState {
  void _handleCollaborationEvent(Map<String, dynamic> event) {
    final result = _collaborationWorkspace.handleTransportEvent(event);
    final saveReason = result.saveReason;
    if (saveReason != null) {
      unawaited(_annotationDatabase.saveCollaborationNow(saveReason));
    }
    if (result.activateLabelPage) {
      setState(() => _activeSection = 'label');
    }
    switch (result.kind) {
      case CollaborationWorkspaceEventKind.joinRequest:
        final request = result.joinRequest;
        if (request != null) {
          unawaited(_confirmCollaborationJoin(request));
        }
        break;
      case CollaborationWorkspaceEventKind.joined:
        _showFloatingMessage(t('collab.joined'));
        logApp('COLLAB', 'Join accepted by host');
        break;
      case CollaborationWorkspaceEventKind.joinRejected:
        _showFloatingMessage(t('collab.joinRejected'));
        _disconnectCollaborationClient(clearProject: true);
        break;
      case CollaborationWorkspaceEventKind.permissionsUpdated:
        _showFloatingMessage(t('collab.permissionsUpdated'));
        break;
      case CollaborationWorkspaceEventKind.reconnectRequired:
        _startCollaborationReconnect();
        break;
      case CollaborationWorkspaceEventKind.networkError:
        _showFloatingMessage(t('collab.networkError'));
        break;
      case CollaborationWorkspaceEventKind.assignmentUpdated:
      case CollaborationWorkspaceEventKind.peerJoined:
      case CollaborationWorkspaceEventKind.snapshotApplied:
      case CollaborationWorkspaceEventKind.ignored:
        break;
    }
  }

  Future<void> _confirmCollaborationJoin(
    CollaborationJoinRequest request,
  ) async {
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('collab.joinRequestTitle')),
        content: Text(
          '${t('collab.joinRequestBody')}\n${request.userName}#${shortCollaborationId(request.userId)}\n${request.address}',
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
    if (!mounted) {
      _collaboration.finishJoinRequest(request.userId);
      return;
    }
    if (allow == true) {
      final peer = await _collaboration.acceptJoinRequest(
        request,
        imageCount: _images.length,
        projectSnapshotBuilder: (start, end) =>
            _collaborationProjectSnapshotMessage(
              assignmentStart: start,
              assignmentEnd: end,
            ),
      );
      _annotationDatabase.scheduleSave();
      _showFloatingMessage(t('collab.joinAccepted'));
      logApp(
        'COLLAB',
        'Join accepted: user=${peer.userId}, address=${peer.address}',
      );
    } else {
      await _collaboration.rejectJoinRequest(request);
      logApp(
        'COLLAB',
        'Join rejected: user=${request.userId}, address=${request.address}',
      );
    }
  }

  Map<String, Object?> _collaborationProjectSnapshotMessage({
    int? assignmentStart,
    int? assignmentEnd,
  }) {
    return _collaborationSync.projectSnapshotMessage(
      assignmentStart: assignmentStart,
      assignmentEnd: assignmentEnd,
    );
  }

  void _broadcastCollaborationProjectSnapshot(String reason) {
    _collaborationSync.broadcastProjectSnapshot(reason);
  }

  void _setCollaborationUserName(String value) {
    _collaboration.userName = value;
  }

  void _setCollaborationPort(int value) {
    _collaboration.updatePort(value);
    unawaited(_collaboration.restartDiscovery());
  }

  void _startCollaborationHost() {
    unawaited(_startCollaborationHostNetwork());
  }

  Future<void> _startCollaborationHostNetwork() async {
    final result = await _collaborationWorkspace.startHostSession(
      projectId: _annotationDatabase.projectKey,
    );
    if (!mounted) {
      return;
    }
    switch (result.status) {
      case CollaborationHostStartStatus.started:
        logApp(
          'COLLAB',
          'Host mode enabled: hostId=$_collaborationHostId, port=$_collaborationPort',
        );
        return;
      case CollaborationHostStartStatus.noProject:
        _showFloatingMessage(t('collab.openProjectFirst'));
        return;
      case CollaborationHostStartStatus.failed:
        _showFloatingMessage(t('collab.networkError'));
        logApp(
          'COLLAB',
          'Host start failed: ${result.error}',
          level: AppLogLevel.error,
        );
        return;
    }
  }

  void _joinCollaborationHost() {
    unawaited(_joinCollaborationHostNetwork());
  }

  Future<void> _joinCollaborationHostNetwork() async {
    final result = await _collaborationWorkspace.joinSelectedHost();
    if (!mounted) {
      return;
    }
    switch (result.status) {
      case CollaborationJoinStartStatus.sent:
        final host = result.host!;
        logApp(
          'COLLAB',
          'Join request sent: user=$_currentAnnotatorLabel, host=${host.hostId}, address=${host.address}:${host.port}',
        );
        return;
      case CollaborationJoinStartStatus.noHostSelected:
        _showFloatingMessage(t('collab.selectHostFirst'));
        return;
      case CollaborationJoinStartStatus.failed:
        _showFloatingMessage(t('collab.networkError'));
        logApp(
          'COLLAB',
          'Join failed: ${result.error}',
          level: AppLogLevel.error,
        );
        return;
      case CollaborationJoinStartStatus.alreadyJoining:
        return;
    }
  }

  void _startCollaborationReconnect() {
    final result = _collaborationWorkspace.beginReconnect(
      onExhausted: () {
        if (!mounted) {
          return;
        }
        _showFloatingMessage(t('collab.reconnectFailed'));
        _disconnectCollaborationClient(clearProject: true);
      },
    );
    switch (result.status) {
      case CollaborationReconnectStartStatus.started:
        setState(() => _selectedAnnotationId = null);
        logApp(
          'COLLAB',
          'Host disconnected, reconnecting: host=${result.host!.hostId}',
          level: AppLogLevel.warning,
        );
        return;
      case CollaborationReconnectStartStatus.noConnectedHost:
        _disconnectCollaborationClient(clearProject: true);
        return;
      case CollaborationReconnectStartStatus.alreadyReconnecting:
      case CollaborationReconnectStartStatus.notStarted:
        return;
    }
  }

  void _cancelCollaborationReconnect() {
    _collaborationWorkspace.cancelReconnect();
    _showFloatingMessage(t('collab.reconnectCancelled'));
    _disconnectCollaborationClient(clearProject: true);
  }

  void _disconnectCollaborationClient({required bool clearProject}) {
    unawaited(_collaborationWorkspace.endSession());
    if (clearProject) {
      _clearCurrentProjectState();
    }
    setState(() {
      _selectedAnnotationId = null;
    });
  }

  void _stopCollaboration() {
    final wasClient = _collaborationMode == CollaborationMode.client;
    if (!wasClient) {
      _annotationDatabase.cancelScheduledSave();
      unawaited(_annotationDatabase.saveNow());
    }
    unawaited(_collaborationWorkspace.endSession());
    if (wasClient) {
      _clearCurrentProjectState();
    }
    setState(() {
      _selectedAnnotationId = null;
    });
    logApp('COLLAB', 'Collaboration stopped');
  }

  void _setCollaborationPeerPermissions(
    CollaborationPeerPermissionResult result,
  ) {
    final updated = _collaborationWorkspace.applyPeerPermissions(result);
    if (updated == null) {
      return;
    }
    final assignmentStart = updated.assignmentStart;
    final assignmentEnd = updated.assignmentEnd;
    logApp(
      'COLLAB',
      'Peer permissions updated: user=${result.userId}, assignment=$assignmentStart-$assignmentEnd, edit=${result.permissions.canEditOthers}, delete=${result.permissions.canDeleteOthers}, class=${result.permissions.canChangeClass}',
      level: AppLogLevel.debug,
    );
    _annotationDatabase.scheduleSave();
  }
}

extension _WorkspaceShellExportActions on _WorkspaceShellState {
  Future<void> _showExportDialog() async {
    final config = await showDialog<DatasetExportConfig>(
      context: context,
      builder: (context) => ExportDialog(exportPath: _appSettings.exportPath),
    );
    if (config == null || !mounted) return;
    final importedDataset = _importedDataset;
    var overwriteImported = false;
    if (importedDataset != null) {
      final overwrite = await _confirmOverwriteImportedDataset();
      if (overwrite == null || !mounted) {
        return;
      }
      overwriteImported = overwrite;
    }
    final workflowResult = await _exportController.exportDataset(
      config: config,
      exportRoot: _appSettings.exportPath,
      overwriteImported: overwriteImported,
      displaySizeForImagePath: _displaySizeForImagePath,
      ensureDisplaySizeForImagePath: _computeImageDisplaySize,
    );
    if (!mounted) {
      return;
    }
    final exportResult = workflowResult.result;
    if (exportResult == null) {
      _showFloatingMessage(t('export.noData'));
      return;
    }
    if (workflowResult.mode == DatasetExportMode.overwriteImported) {
      _showFloatingMessage(t('export.done'));
    } else {
      _showFloatingMessage(
        '${t('export.done')} (${t('export.folderName')}: ${config.folderName})',
      );
    }
    if (config.trainAfterExport) {
      await _exportController.startTrainingAfterExport(
        exportResult.dataYamlPath,
      );
    }
  }

  Future<bool> _launchExportedDatasetTraining(String dataYamlPath) async {
    setState(() => _activeSection = 'train');
    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return false;
    }
    final trainPage = _trainPageKey.currentState;
    if (trainPage == null) {
      return false;
    }
    await trainPage.loadExportedDatasetAndStartTraining(dataYamlPath);
    return true;
  }

  Future<bool?> _confirmOverwriteImportedDataset() async {
    return showOverwriteImportedDatasetDialog(context);
  }

  Future<Size> _computeImageDisplaySize(String imagePath) async {
    final displaySize = await computeImageDisplaySizeForPath(
      imagePath,
      onDecodeError: (path, error) {
        logApp(
          'LABEL',
          'Image size decode failed: $path, error=$error',
          level: AppLogLevel.warning,
        );
      },
    );
    _imageDisplaySizes[pathKey(imagePath)] = displaySize;
    return displaySize;
  }
}

extension _WorkspaceShellSettingsActions on _WorkspaceShellState {
  void _toggleThemeMode() {
    _settingsController.toggleTheme();
  }

  void _updateShortcut(ShortcutAction action, LogicalKeyboardKey key) {
    _settingsController.updateShortcut(action, key);
  }

  void _resetShortcuts() {
    _settingsController.resetShortcuts();
  }

  void _clearRecentItems() {
    _projectSession.clearHistory();
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
      builder: (context) => ShortcutSettingsDialog(
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
      builder: (context) => SettingsDialog(
        initialSettings: _appSettings,
        cacheSizeBytes: ConfigStore.cacheSizeInBytes(),
        onSave: _saveAppSettings,
        onClearCache: _clearCacheData,
        logger: appLogger,
        onLogLevelChanged: (index) =>
            setAppLogLevel(appLogLevelFromIndex(index), writeLog: true),
      ),
    );
    if (mounted) {
      _keyboardFocusNode.requestFocus();
    }
  }

  Future<void> _showAboutDialog() async {
    await showAboutDialogForContext(context);
    if (mounted) {
      _keyboardFocusNode.requestFocus();
    }
  }

  Future<void> _showLogViewerDialog() async {
    if (!mounted) return;
    await showLogViewerDialogForContext(
      context: context,
      onMessage: _showFloatingMessage,
      flushLogs: flushAppLogs,
    );
    if (mounted) {
      _keyboardFocusNode.requestFocus();
    }
  }

  Future<int> _clearCacheData() async {
    _project.clearAnnotationData();
    _projectSession.clearHistory();
    unawaited(_annotationDatabase.saveNow());
    return ConfigStore.cacheSizeInBytes();
  }
}
