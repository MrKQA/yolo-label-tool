import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/collaboration_controller.dart';
import '../../controllers/project_controller.dart';
import '../../controllers/workspace_navigation_controller.dart';
import '../../controllers/workspace_settings_controller.dart';
import '../../models/collaboration.dart';
import '../../pages/collaboration_page.dart';
import '../../pages/crop_page.dart';
import '../../pages/database_page.dart';
import '../../pages/detect_video_page.dart';
import '../../pages/train_page.dart';
import '../../services/i18n.dart';
import 'navigation.dart';

class WorkspaceTopMenuData {
  const WorkspaceTopMenuData({
    required this.visible,
    required this.recentFolders,
    required this.recentFiles,
    required this.languageOptions,
    required this.activeLanguageCode,
    required this.projectActionsLocked,
  });

  final bool visible;
  final List<String> recentFolders;
  final List<String> recentFiles;
  final List<LanguageOption> languageOptions;
  final String activeLanguageCode;
  final bool projectActionsLocked;
}

class WorkspaceTopMenuActions {
  const WorkspaceTopMenuActions({
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
}

class WorkspaceTopMenu extends StatelessWidget {
  const WorkspaceTopMenu({
    super.key,
    required this.data,
    required this.actions,
  });

  final WorkspaceTopMenuData data;
  final WorkspaceTopMenuActions actions;

  @override
  Widget build(BuildContext context) {
    return TopMenuBar(
      visible: data.visible,
      recentFolders: data.recentFolders,
      recentFiles: data.recentFiles,
      languageOptions: data.languageOptions,
      activeLanguageCode: data.activeLanguageCode,
      projectActionsLocked: data.projectActionsLocked,
      onOpenFile: actions.onOpenFile,
      onOpenFolder: actions.onOpenFolder,
      onOpenRecentFolder: actions.onOpenRecentFolder,
      onOpenRecentFile: actions.onOpenRecentFile,
      onClearRecent: actions.onClearRecent,
      onExit: actions.onExit,
      onImportDataset: actions.onImportDataset,
      onExportDataset: actions.onExportDataset,
      onShowTrainingHistory: actions.onShowTrainingHistory,
      onUndo: actions.onUndo,
      onRedo: actions.onRedo,
      onCopy: actions.onCopy,
      onPaste: actions.onPaste,
      onShowSettings: actions.onShowSettings,
      onShowLogs: actions.onShowLogs,
      onShowHelp: actions.onShowHelp,
      onShowAbout: actions.onShowAbout,
      onProjectActionBlocked: actions.onProjectActionBlocked,
      onLanguageSelected: actions.onLanguageSelected,
      onPointerEnter: actions.onPointerEnter,
      onPointerExit: actions.onPointerExit,
    );
  }
}

class CollaborationPageActions {
  const CollaborationPageActions({
    required this.onUserNameChanged,
    required this.onPortChanged,
    required this.onHostSelected,
    required this.onStartHost,
    required this.onJoinClient,
    required this.onStop,
    required this.onPeerPermissionsChanged,
  });

  final ValueChanged<String> onUserNameChanged;
  final ValueChanged<int> onPortChanged;
  final ValueChanged<String?> onHostSelected;
  final VoidCallback onStartHost;
  final VoidCallback onJoinClient;
  final VoidCallback onStop;
  final ValueChanged<CollaborationPeerPermissionResult>
  onPeerPermissionsChanged;
}

class WorkspacePageStack extends StatelessWidget {
  const WorkspacePageStack({
    super.key,
    required this.labelPage,
    required this.trainPageKey,
    required this.detectVideoSession,
    required this.collaborationActions,
  });

  static const pageCount = 6;

  final Widget labelPage;
  final GlobalKey<TrainPageState> trainPageKey;
  final DetectVideoSession detectVideoSession;
  final CollaborationPageActions collaborationActions;

  @override
  Widget build(BuildContext context) {
    final settingsController = context.watch<WorkspaceSettingsController>();
    final collaboration = context.watch<CollaborationController>();
    final project = context.watch<ProjectController>();
    final navigation = context.watch<WorkspaceNavigationController>();
    final settings = settingsController.settings;
    final shortcuts = settingsController.shortcuts;
    final actions = collaborationActions;
    return IndexedStack(
      index: navigation.pageIndex,
      children: [
        labelPage,
        TrainPage(key: trainPageKey, settings: settings),
        CropPage(exportPath: settings.exportPath),
        CollaborationPage(
          mode: collaboration.mode,
          hostId: collaboration.hostId,
          userId: collaboration.userId,
          userName: collaboration.userName,
          userColor: Color(collaboration.annotatorColorValue),
          port: collaboration.port,
          imageCount: project.images.length,
          assignmentStart: collaboration.assignmentStart,
          assignmentEnd: collaboration.assignmentEnd,
          discoveredHosts: collaboration.discoveredHosts,
          selectedHostId: collaboration.selectedHostId,
          joining: collaboration.joining,
          peers: collaboration.peers,
          onUserNameChanged: actions.onUserNameChanged,
          onPortChanged: actions.onPortChanged,
          onHostSelected: actions.onHostSelected,
          onStartHost: actions.onStartHost,
          onJoinClient: actions.onJoinClient,
          onStop: actions.onStop,
          onPeerPermissionsChanged: actions.onPeerPermissionsChanged,
        ),
        DetectVideoPage(
          settings: settings,
          shortcutConfig: shortcuts,
          session: detectVideoSession,
        ),
        const DatabasePage(),
      ],
    );
  }
}
