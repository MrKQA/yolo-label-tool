import 'package:flutter/material.dart';

import '../../models/collaboration.dart';
import '../../models/config.dart';
import '../../models/shortcut.dart';
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

class CollaborationPageBinding {
  const CollaborationPageBinding({
    required this.mode,
    required this.hostId,
    required this.userId,
    required this.userName,
    required this.userColor,
    required this.port,
    required this.imageCount,
    required this.assignmentStart,
    required this.assignmentEnd,
    required this.discoveredHosts,
    required this.selectedHostId,
    required this.joining,
    required this.peers,
    required this.onUserNameChanged,
    required this.onPortChanged,
    required this.onHostSelected,
    required this.onStartHost,
    required this.onJoinClient,
    required this.onStop,
    required this.onPeerPermissionsChanged,
  });

  final CollaborationMode mode;
  final String hostId;
  final String userId;
  final String userName;
  final Color userColor;
  final int port;
  final int imageCount;
  final int assignmentStart;
  final int assignmentEnd;
  final List<CollaborationDiscoveredHost> discoveredHosts;
  final String? selectedHostId;
  final bool joining;
  final List<CollaborationPeer> peers;
  final ValueChanged<String> onUserNameChanged;
  final ValueChanged<int> onPortChanged;
  final ValueChanged<String?> onHostSelected;
  final VoidCallback onStartHost;
  final VoidCallback onJoinClient;
  final VoidCallback onStop;
  final ValueChanged<CollaborationPeerPermissionResult>
  onPeerPermissionsChanged;

  Widget build() {
    return CollaborationPage(
      mode: mode,
      hostId: hostId,
      userId: userId,
      userName: userName,
      userColor: userColor,
      port: port,
      imageCount: imageCount,
      assignmentStart: assignmentStart,
      assignmentEnd: assignmentEnd,
      discoveredHosts: discoveredHosts,
      selectedHostId: selectedHostId,
      joining: joining,
      peers: peers,
      onUserNameChanged: onUserNameChanged,
      onPortChanged: onPortChanged,
      onHostSelected: onHostSelected,
      onStartHost: onStartHost,
      onJoinClient: onJoinClient,
      onStop: onStop,
      onPeerPermissionsChanged: onPeerPermissionsChanged,
    );
  }
}

class WorkspacePageStack extends StatelessWidget {
  const WorkspacePageStack({
    super.key,
    required this.index,
    required this.labelPage,
    required this.trainPageKey,
    required this.settings,
    required this.shortcutConfig,
    required this.detectVideoSession,
    required this.collaboration,
  });

  static const pageCount = 6;

  final int index;
  final Widget labelPage;
  final GlobalKey<TrainPageState> trainPageKey;
  final AppSettings settings;
  final ShortcutConfig shortcutConfig;
  final DetectVideoSession detectVideoSession;
  final CollaborationPageBinding collaboration;

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: index,
      children: [
        labelPage,
        TrainPage(key: trainPageKey, settings: settings),
        CropPage(exportPath: settings.exportPath),
        collaboration.build(),
        DetectVideoPage(
          settings: settings,
          shortcutConfig: shortcutConfig,
          session: detectVideoSession,
        ),
        const DatabasePage(),
      ],
    );
  }
}
