import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/annotation_database_controller.dart';
import '../../controllers/collaboration_controller.dart';
import '../../controllers/collaboration_sync_controller.dart';
import '../../controllers/collaboration_workspace_controller.dart';
import '../../controllers/project_controller.dart';
import '../../controllers/workspace_navigation_controller.dart';
import '../../dialogs/dialog_shortcuts.dart';
import '../../models/collaboration.dart';
import '../../services/app_runtime.dart';
import '../../services/collaboration_identity.dart';
import '../../services/i18n.dart';
import '../../services/logger.dart';

/// Coordinates collaboration sessions and their user-facing feedback.
class WorkspaceCollaborationActions {
  const WorkspaceCollaborationActions({
    required this.collaboration,
    required this.sync,
    required this.workspace,
    required this.project,
    required this.database,
    required this.navigation,
    required this.context,
    required this.mounted,
    required this.clearProject,
    required this.showMessage,
  });

  final CollaborationController collaboration;
  final CollaborationSyncController sync;
  final CollaborationWorkspaceController workspace;
  final ProjectController project;
  final AnnotationDatabaseController database;
  final WorkspaceNavigationController navigation;
  final BuildContext Function() context;
  final bool Function() mounted;
  final VoidCallback clearProject;
  final ValueChanged<String> showMessage;

  void handleEvent(Map<String, dynamic> event) {
    final result = workspace.handleTransportEvent(event);
    if (result.saveReason case final reason?) {
      unawaited(database.saveCollaborationNow(reason));
    }
    if (result.activateLabelPage) navigation.activeSection = 'label';
    switch (result.kind) {
      case CollaborationWorkspaceEventKind.joinRequest:
        if (result.joinRequest case final request?) {
          unawaited(_confirmJoin(request));
        }
      case CollaborationWorkspaceEventKind.joined:
        showMessage(t('collab.joined'));
        logApp('COLLAB', 'Join accepted by host');
      case CollaborationWorkspaceEventKind.joinRejected:
        showMessage(t('collab.joinRejected'));
        disconnectClient(clearProjectState: true);
      case CollaborationWorkspaceEventKind.permissionsUpdated:
        showMessage(t('collab.permissionsUpdated'));
      case CollaborationWorkspaceEventKind.reconnectRequired:
        startReconnect();
      case CollaborationWorkspaceEventKind.networkError:
        showMessage(t('collab.networkError'));
      case CollaborationWorkspaceEventKind.assignmentUpdated:
      case CollaborationWorkspaceEventKind.peerJoined:
      case CollaborationWorkspaceEventKind.snapshotApplied:
      case CollaborationWorkspaceEventKind.ignored:
        break;
    }
  }

  void broadcastProjectSnapshot(String reason) {
    sync.broadcastProjectSnapshot(reason);
  }

  void updateUserName(String value) => collaboration.userName = value;

  void updatePort(int value) {
    collaboration.updatePort(value);
    unawaited(collaboration.restartDiscovery());
  }

  void startHost() => unawaited(_startHost());

  void joinSelectedHost() => unawaited(_joinSelectedHost());

  void startReconnect() {
    final result = workspace.beginReconnect(
      onExhausted: () {
        if (!mounted()) return;
        showMessage(t('collab.reconnectFailed'));
        disconnectClient(clearProjectState: true);
      },
    );
    switch (result.status) {
      case CollaborationReconnectStartStatus.started:
        project.selectAnnotation(null);
        logApp(
          'COLLAB',
          'Host disconnected, reconnecting: host=${result.host!.hostId}',
          level: AppLogLevel.warning,
        );
      case CollaborationReconnectStartStatus.noConnectedHost:
        disconnectClient(clearProjectState: true);
      case CollaborationReconnectStartStatus.alreadyReconnecting:
      case CollaborationReconnectStartStatus.notStarted:
        break;
    }
  }

  void cancelReconnect() {
    workspace.cancelReconnect();
    showMessage(t('collab.reconnectCancelled'));
    disconnectClient(clearProjectState: true);
  }

  void disconnectClient({required bool clearProjectState}) {
    unawaited(workspace.endSession());
    if (clearProjectState) clearProject();
    project.selectAnnotation(null);
  }

  void stop() {
    final wasClient = collaboration.mode == CollaborationMode.client;
    if (!wasClient) {
      database.cancelScheduledSave();
      unawaited(database.saveNow());
    }
    unawaited(workspace.endSession());
    if (wasClient) clearProject();
    project.selectAnnotation(null);
    logApp('COLLAB', 'Collaboration stopped');
  }

  void updatePeerPermissions(CollaborationPeerPermissionResult result) {
    final updated = workspace.applyPeerPermissions(result);
    if (updated == null) return;
    logApp(
      'COLLAB',
      'Peer permissions updated: user=${result.userId}, assignment=${updated.assignmentStart}-${updated.assignmentEnd}, edit=${result.permissions.canEditOthers}, delete=${result.permissions.canDeleteOthers}, class=${result.permissions.canChangeClass}',
      level: AppLogLevel.debug,
    );
    database.scheduleSave();
  }

  Future<void> _confirmJoin(CollaborationJoinRequest request) async {
    final allow = await showDialog<bool>(
      context: context(),
      builder: (context) => DialogPrimaryAction(
        onInvoke: () => Navigator.of(context).pop(true),
        child: AlertDialog(
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
      ),
    );
    if (!mounted()) {
      collaboration.finishJoinRequest(request.userId);
      return;
    }
    if (allow == true) {
      final peer = await collaboration.acceptJoinRequest(
        request,
        imageCount: project.images.length,
        projectSnapshotBuilder: (start, end) => sync.projectSnapshotMessage(
          assignmentStart: start,
          assignmentEnd: end,
        ),
      );
      database.scheduleSave();
      showMessage(t('collab.joinAccepted'));
      logApp(
        'COLLAB',
        'Join accepted: user=${peer.userId}, address=${peer.address}',
      );
      return;
    }
    await collaboration.rejectJoinRequest(request);
    logApp(
      'COLLAB',
      'Join rejected: user=${request.userId}, address=${request.address}',
    );
  }

  Future<void> _startHost() async {
    final result = await workspace.startHostSession(
      projectId: database.projectKey,
    );
    if (!mounted()) return;
    switch (result.status) {
      case CollaborationHostStartStatus.started:
        logApp(
          'COLLAB',
          'Host mode enabled: hostId=${collaboration.hostId}, port=${collaboration.port}',
        );
      case CollaborationHostStartStatus.noProject:
        showMessage(t('collab.openProjectFirst'));
      case CollaborationHostStartStatus.failed:
        showMessage(t('collab.networkError'));
        logApp(
          'COLLAB',
          'Host start failed: ${result.error}',
          level: AppLogLevel.error,
        );
    }
  }

  Future<void> _joinSelectedHost() async {
    final result = await workspace.joinSelectedHost();
    if (!mounted()) return;
    switch (result.status) {
      case CollaborationJoinStartStatus.sent:
        final host = result.host!;
        logApp(
          'COLLAB',
          'Join request sent: user=${collaboration.annotatorLabel}, host=${host.hostId}, address=${host.address}:${host.port}',
        );
      case CollaborationJoinStartStatus.noHostSelected:
        showMessage(t('collab.selectHostFirst'));
      case CollaborationJoinStartStatus.failed:
        showMessage(t('collab.networkError'));
        logApp(
          'COLLAB',
          'Join failed: ${result.error}',
          level: AppLogLevel.error,
        );
      case CollaborationJoinStartStatus.alreadyJoining:
        break;
    }
  }
}
