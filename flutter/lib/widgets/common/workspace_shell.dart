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

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/annotation_database_controller.dart';
import '../../controllers/ai_annotation_controller.dart';
import '../../controllers/ai_workspace_controller.dart';
import '../../controllers/annotation_editing_controller.dart';
import '../../controllers/collaboration_controller.dart';
import '../../controllers/collaboration_sync_controller.dart';
import '../../controllers/collaboration_workspace_controller.dart';
import '../../controllers/dataset_import_controller.dart';
import '../../controllers/export_controller.dart';
import '../../controllers/project_controller.dart';
import '../../controllers/workspace_navigation_controller.dart';
import '../../controllers/workspace_settings_controller.dart';
import '../../controllers/workspace_viewport_controller.dart';
import '../../dialogs/training_history_dialog.dart';
import '../../models/app_status.dart';
import '../../models/config.dart';
import '../../models/shortcut.dart';
import '../../pages/detect_video_page.dart';
import '../../pages/train_page.dart';
import '../../services/app_runtime.dart';
import '../../services/config_store.dart';
import '../../services/i18n.dart';
import '../../services/input_utils.dart';
import '../../services/logger.dart';
import '../../theme/dimensions.dart';
import 'floating_message.dart';
import 'workspace_annotation_actions.dart';
import 'workspace_ai_actions.dart';
import 'workspace_collaboration_actions.dart';
import 'workspace_controller_scope.dart';
import 'workspace_export_actions.dart';
import 'workspace_project_actions.dart';
import 'workspace_settings_actions.dart';
import 'workspace_shell_content.dart';

const _topMenuAutoHideDelay = topMenuAutoHideDelay;

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
  DateTime? _lastPreviousBoundaryNoticeAt;
  DateTime? _lastNextBoundaryNoticeAt;
  DateTime? _lastAnnotationModeNoticeAt;

  static const _imageBoundaryNoticeInterval = appNoticeRepeatInterval;

  final ProjectController _project = ProjectController();
  late final AnnotationDatabaseController _annotationDatabase;
  late final DatasetImportController _datasetImportController;
  late final ExportController _exportController;
  final WorkspaceNavigationController _navigation =
      WorkspaceNavigationController();
  static const WorkspaceShortcutResolver _shortcutResolver =
      WorkspaceShortcutResolver();
  late final WorkspaceShortcutDispatcher _shortcutDispatcher;
  late final WorkspaceSettingsController _settingsController;
  final WorkspaceViewportController _viewport = WorkspaceViewportController();
  final AiAnnotationController _ai = AiAnnotationController();
  late final AiWorkspaceController _aiWorkspace;
  bool _topMenuVisible = true;
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
  late final WorkspaceAnnotationActions _annotationActions;
  late final WorkspaceSettingsActions _settingsActions;
  late final WorkspaceCollaborationActions _collaborationActions;
  late final WorkspaceExportActions _exportActions;
  late final WorkspaceAiActions _aiActions;
  late final WorkspaceProjectActions _projectActions;
  late final Listenable _workspaceListenable;

  bool get _collaborationReconnecting => _collaboration.reconnecting;
  double get _zoom => _viewport.zoom;
  bool get _zoomLocked => _viewport.zoomLocked;
  ShortcutConfig get _shortcutConfig => _settingsController.shortcuts;
  bool get _showClassLabels => _navigation.showClassLabels;
  set _showClassLabels(bool value) => _navigation.showClassLabels = value;
  List<RecentEntry> get _recentFolders => _project.recentFolders;
  List<RecentEntry> get _recentFiles => _project.recentFiles;

  @override
  void initState() {
    super.initState();
    _settingsController = WorkspaceSettingsController(
      collaboration: _collaboration,
    );
    _datasetImportController = DatasetImportController(project: _project);
    _exportController = ExportController(
      project: _project,
      trainingLauncher: _launchExportedDatasetTraining,
    );
    _exportActions = WorkspaceExportActions(
      export: _exportController,
      project: _project,
      settings: _settingsController,
      context: () => context,
      mounted: () => mounted,
      showMessage: _showFloatingMessage,
    );
    _collaborationSync = CollaborationSyncController(
      collaboration: _collaboration,
      project: _project,
    );
    _annotationDatabase = AnnotationDatabaseController(
      project: _project,
      collaboration: _collaboration,
      collaborationSync: _collaborationSync,
    );
    _projectActions = WorkspaceProjectActions(
      project: _project,
      database: _annotationDatabase,
      datasetImport: _datasetImportController,
      ai: _ai,
      collaboration: _collaboration,
      collaborationSync: _collaborationSync,
      navigation: _navigation,
      viewport: _viewport,
      context: () => context,
      mounted: () => mounted,
      showMessage: _showFloatingMessage,
    );
    _aiWorkspace = AiWorkspaceController(
      runtime: _ai,
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
    _annotationActions = WorkspaceAnnotationActions(
      project: _project,
      editing: _annotationEditing,
      database: _annotationDatabase,
      navigation: _navigation,
      context: () => context,
      projectChangeBlocked: _projectActions.guardProjectChangeBlocked,
      showMessage: _showFloatingMessage,
      showModeIncompatibleMessage: _showAnnotationModeIncompatibleMessage,
      showExport: () => unawaited(_exportActions.showExportDialog()),
      showClearItems: () => unawaited(_projectActions.showClearProjectItems()),
    );
    _settingsActions = WorkspaceSettingsActions(
      settings: _settingsController,
      project: _project,
      annotationDatabase: _annotationDatabase,
      context: () => context,
      mounted: () => mounted,
      keyboardFocusNode: _keyboardFocusNode,
      showMessage: _showFloatingMessage,
    );
    _collaborationActions = WorkspaceCollaborationActions(
      collaboration: _collaboration,
      sync: _collaborationSync,
      workspace: _collaborationWorkspace,
      project: _project,
      database: _annotationDatabase,
      navigation: _navigation,
      context: () => context,
      mounted: () => mounted,
      clearProject: _projectActions.clearCurrentProject,
      showMessage: _showFloatingMessage,
    );
    _aiActions = WorkspaceAiActions(
      ai: _ai,
      workspace: _aiWorkspace,
      project: _project,
      collaboration: _collaboration,
      settings: _settingsController,
      annotationActions: _annotationActions,
      context: () => context,
      mounted: () => mounted,
      panelVisible: () => _aiPanelVisible,
      showPanel: () => setState(() => _aiPanelVisible = true),
      showMessage: _showFloatingMessage,
    );
    _shortcutDispatcher = WorkspaceShortcutDispatcher(
      actions: WorkspaceShortcutActions(
        delegateBrowse: (event) =>
            _detectVideoSession.handleShortcutKey(event, _shortcutConfig),
        undo: _annotationActions.undo,
        redo: _annotationActions.redo,
        copy: _annotationActions.copySelected,
        paste: _annotationActions.paste,
        cancelSelection: () {
          if (_aiPanelVisible) {
            setState(() => _aiPanelVisible = false);
          }
          _navigation.cancelSelection();
          _project.selectAnnotation(null);
        },
        previousImage: (step) {
          final changed = _projectActions.selectPreviousImage(step: step);
          if (changed) _lastPreviousBoundaryNoticeAt = null;
          return changed;
        },
        nextImage: (step) {
          final changed = _projectActions.selectNextImage(step: step);
          if (changed) _lastNextBoundaryNoticeAt = null;
          return changed;
        },
        onNoPreviousImage: () => _showImageBoundaryNotice(previous: true),
        onNoNextImage: () => _showImageBoundaryNotice(previous: false),
        adjustZoom: _viewport.adjustZoom,
        toggleZoomLock: _viewport.toggleZoomLock,
        resetLabelView: _viewport.reset,
        importDataset: () => unawaited(_projectActions.importYoloDataset()),
        exportDataset: () => unawaited(_exportActions.showExportDialog()),
        activateMode: _annotationActions.activateMode,
        deleteSelected: _annotationActions.deleteSelected,
        toggleClassLabels: () {
          setState(() => _showClassLabels = !_showClassLabels);
        },
        rotateObb: _annotationActions.rotateSelected,
        aiAnnotateCurrent: () => unawaited(_aiActions.annotateCurrent()),
        aiAnnotateAll: () => unawaited(_aiActions.annotateAll()),
        trainStart: () => _trainPageKey.currentState?.startFromShortcut(),
        trainStop: () => _trainPageKey.currentState?.stopFromShortcut(),
        trainChooseModel: () =>
            _trainPageKey.currentState?.chooseModelFromShortcut(),
        trainChooseDataset: () =>
            _trainPageKey.currentState?.chooseDatasetFromShortcut(),
        trainExport: () => _trainPageKey.currentState?.exportFromShortcut(),
      ),
    );
    _workspaceListenable = Listenable.merge([
      _detectVideoSession,
      _collaboration,
      _settingsController,
      _viewport,
      _project,
      _ai,
      _projectActions,
    ]);
    _project.addListener(_syncAnnotationModeWithProject);
    _collaboration.onTransportError = _handleCollaborationTransportError;
    _loadPersistedConfig();
    _loadAvailableLanguages();
    _collaboration.startPolling(_collaborationActions.handleEvent);
    _resetCollaborationRuntimeForStartup();
    _scheduleTopMenuHide();
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
    _projectActions.saveResumePositionNow();
    appLogger.dispose();
    _settingsController.dispose();
    _viewport.dispose();
    _collaboration.dispose();
    _project.removeListener(_syncAnnotationModeWithProject);
    _project.dispose();
    _ai.dispose();
    _projectActions.dispose();
    _detectVideoSession.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _handleCollaborationTransportError(
    Map<String, Object?> request,
    Object error,
  ) {
    if (mounted) {
      _showFloatingMessage(t('collab.networkError'));
    }
  }

  void _loadPersistedConfig() {
    _project.loadHistory();
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
    _showTopMenu();
  }

  void _setZoom(double value) {
    _viewport.setZoom(value);
  }

  void _showTrainingHistoryDialog() {
    showTrainingHistoryRecordsDialog(
      context: context,
      history: ConfigStore.loadTrainingHistory().entries,
      onEmpty: () => _showFloatingMessage(t('train.noHistory')),
    );
  }

  void _showFloatingMessage(
    String message, {
    Duration duration = const Duration(milliseconds: 1800),
  }) {
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => FloatingMessage(message: message, duration: duration),
    );
    overlay.insert(entry);
    Future<void>.delayed(duration + const Duration(milliseconds: 80), () {
      if (entry.mounted) entry.remove();
    });
  }

  void _syncAnnotationModeWithProject() {
    final projectMode = _project.projectAnnotationMode;
    if (projectMode != null && _navigation.annotationMode != projectMode) {
      _navigation.activateAnnotationMode(projectMode);
    }
  }

  void _showAnnotationModeIncompatibleMessage(String message) {
    final now = DateTime.now();
    final last = _lastAnnotationModeNoticeAt;
    if (last != null && now.difference(last) < appNoticeRepeatInterval) {
      return;
    }
    _lastAnnotationModeNoticeAt = now;
    _showFloatingMessage(message, duration: appNoticeDisplayDuration);
  }

  void _showImageBoundaryNotice({required bool previous}) {
    final now = DateTime.now();
    final last = previous
        ? _lastPreviousBoundaryNoticeAt
        : _lastNextBoundaryNoticeAt;
    if (last != null && now.difference(last) < _imageBoundaryNoticeInterval) {
      return;
    }
    if (previous) {
      _lastPreviousBoundaryNoticeAt = now;
    } else {
      _lastNextBoundaryNoticeAt = now;
    }
    _showFloatingMessage(
      t(previous ? 'detect.hudNoPrevious' : 'detect.hudNoNext'),
      duration: appNoticeDisplayDuration,
    );
  }

  void _showTopMenu() {
    _topMenuHideTimer?.cancel();
    if (!_topMenuVisible) setState(() => _topMenuVisible = true);
  }

  void _scheduleTopMenuHide() {
    _topMenuHideTimer?.cancel();
    _topMenuHideTimer = Timer(_topMenuAutoHideDelay, () {
      if (mounted && _topMenuVisible) {
        setState(() => _topMenuVisible = false);
      }
    });
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (_navigation.activeSection != 'label' || _zoomLocked) {
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
      activeSection: _navigation.activeSection,
      shortcutDialogOpen: _settingsActions.shortcutDialogOpen,
      inputBlocked:
          _collaborationReconnecting || _projectActions.importingDataset,
      editableTextFocused: isEditableTextFocused(),
      controlPressed: HardwareKeyboard.instance.isControlPressed,
    );
    return _shortcutDispatcher.dispatch(decision: decision, event: event);
  }

  Future<bool> _launchExportedDatasetTraining(String dataYamlPath) async {
    _navigation.activeSection = 'train';
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return false;
    final trainPage = _trainPageKey.currentState;
    if (trainPage == null) return false;
    await trainPage.loadExportedDatasetAndStartTraining(dataYamlPath);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _workspaceListenable,
      builder: (context, _) => WorkspaceControllerScope(
        project: _project,
        annotationDatabase: _annotationDatabase,
        annotationEditing: _annotationEditing,
        collaboration: _collaboration,
        collaborationSync: _collaborationSync,
        collaborationWorkspace: _collaborationWorkspace,
        ai: _ai,
        aiWorkspace: _aiWorkspace,
        export: _exportController,
        navigation: _navigation,
        settings: _settingsController,
        viewport: _viewport,
        aiActions: _aiActions,
        annotationActions: _annotationActions,
        collaborationActions: _collaborationActions,
        exportActions: _exportActions,
        projectActions: _projectActions,
        settingsActions: _settingsActions,
        child: WorkspaceShellContent(
          status: widget.status,
          keyboardFocusNode: _keyboardFocusNode,
          onKeyEvent: _handleKeyEvent,
          trainPageKey: _trainPageKey,
          detectVideoSession: _detectVideoSession,
          topMenuVisible: _topMenuVisible,
          aiPanelVisible: _aiPanelVisible,
          aiAssistPanelSize: _aiAssistPanelSize,
          aiAssistPanelOffset: _aiAssistPanelOffset,
          onLanguageSelected: _changeLanguage,
          onShowTrainingHistory: _showTrainingHistoryDialog,
          onPointerEnter: _showTopMenu,
          onPointerExit: _scheduleTopMenuHide,
          onPointerSignal: _handlePointerSignal,
          onAiPanelVisibilityChanged: (visible) {
            setState(() => _aiPanelVisible = visible);
          },
          onAiPanelGeometryChanged: (size, offset) {
            setState(() {
              _aiAssistPanelSize = size;
              _aiAssistPanelOffset = offset;
            });
          },
        ),
      ),
    );
  }
}
