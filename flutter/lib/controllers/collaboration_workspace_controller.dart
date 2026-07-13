import '../models/collaboration.dart';
import 'collaboration_controller.dart';
import 'collaboration_sync_controller.dart';
import 'project_controller.dart';

enum CollaborationWorkspaceEventKind {
  ignored,
  joinRequest,
  joined,
  joinRejected,
  permissionsUpdated,
  assignmentUpdated,
  peerJoined,
  snapshotApplied,
  reconnectRequired,
  networkError,
}

class CollaborationWorkspaceEvent {
  const CollaborationWorkspaceEvent({
    required this.kind,
    this.joinRequest,
    this.saveReason,
    this.activateLabelPage = false,
  });

  static const ignored = CollaborationWorkspaceEvent(
    kind: CollaborationWorkspaceEventKind.ignored,
  );

  final CollaborationWorkspaceEventKind kind;
  final CollaborationJoinRequest? joinRequest;
  final String? saveReason;
  final bool activateLabelPage;
}

enum CollaborationHostStartStatus { started, noProject, failed }

class CollaborationHostStartResult {
  const CollaborationHostStartResult(this.status, {this.error});

  final CollaborationHostStartStatus status;
  final Object? error;
}

enum CollaborationJoinStartStatus {
  sent,
  alreadyJoining,
  noHostSelected,
  failed,
}

class CollaborationJoinStartResult {
  const CollaborationJoinStartResult(this.status, {this.host, this.error});

  final CollaborationJoinStartStatus status;
  final CollaborationDiscoveredHost? host;
  final Object? error;
}

enum CollaborationReconnectStartStatus {
  started,
  alreadyReconnecting,
  noConnectedHost,
  notStarted,
}

class CollaborationReconnectStartResult {
  const CollaborationReconnectStartResult(this.status, {this.host});

  final CollaborationReconnectStartStatus status;
  final CollaborationDiscoveredHost? host;
}

/// Applies collaboration transport events to project state and returns the
/// remaining UI effects for the workspace to display.
class CollaborationWorkspaceController {
  const CollaborationWorkspaceController({
    required this.collaboration,
    required this.sync,
    required this.project,
  });

  final CollaborationController collaboration;
  final CollaborationSyncController sync;
  final ProjectController project;

  Future<CollaborationHostStartResult> startHostSession({
    required String projectId,
  }) async {
    if (project.images.isEmpty) {
      return const CollaborationHostStartResult(
        CollaborationHostStartStatus.noProject,
      );
    }
    try {
      await collaboration.startHostSession(
        projectId: projectId,
        imageCount: project.images.length,
      );
      return const CollaborationHostStartResult(
        CollaborationHostStartStatus.started,
      );
    } on Object catch (error) {
      return CollaborationHostStartResult(
        CollaborationHostStartStatus.failed,
        error: error,
      );
    }
  }

  Future<CollaborationJoinStartResult> joinSelectedHost() async {
    if (collaboration.joining) {
      return const CollaborationJoinStartResult(
        CollaborationJoinStartStatus.alreadyJoining,
      );
    }
    final host = collaboration.selectedHost;
    if (host == null) {
      return const CollaborationJoinStartResult(
        CollaborationJoinStartStatus.noHostSelected,
      );
    }
    try {
      await collaboration.joinHost(host);
      return CollaborationJoinStartResult(
        CollaborationJoinStartStatus.sent,
        host: host,
      );
    } on Object catch (error) {
      return CollaborationJoinStartResult(
        CollaborationJoinStartStatus.failed,
        host: host,
        error: error,
      );
    }
  }

  CollaborationReconnectStartResult beginReconnect({
    required void Function() onExhausted,
  }) {
    if (collaboration.reconnecting) {
      return const CollaborationReconnectStartResult(
        CollaborationReconnectStartStatus.alreadyReconnecting,
      );
    }
    final host = collaboration.connectedHost;
    if (host == null) {
      return const CollaborationReconnectStartResult(
        CollaborationReconnectStartStatus.noConnectedHost,
      );
    }
    final started = collaboration.beginReconnect(onExhausted: onExhausted);
    return CollaborationReconnectStartResult(
      started
          ? CollaborationReconnectStartStatus.started
          : CollaborationReconnectStartStatus.notStarted,
      host: host,
    );
  }

  void cancelReconnect() {
    collaboration.cancelReconnect();
  }

  Future<void> endSession() {
    return collaboration.endSession();
  }

  CollaborationPeer? applyPeerPermissions(
    CollaborationPeerPermissionResult result,
  ) {
    return collaboration.applyPeerPermissions(
      result,
      imageCount: project.images.length,
      projectSnapshotBuilder: (start, end) => sync.projectSnapshotMessage(
        assignmentStart: start,
        assignmentEnd: end,
      ),
    );
  }

  CollaborationWorkspaceEvent handleTransportEvent(Map<String, dynamic> event) {
    final result = collaboration.handleTransportEvent(
      event,
      imageCount: project.images.length,
    );
    return switch (result.kind) {
      CollaborationTransportEventKind.joinRequest =>
        CollaborationWorkspaceEvent(
          kind: CollaborationWorkspaceEventKind.joinRequest,
          joinRequest: result.joinRequest,
        ),
      CollaborationTransportEventKind.tcpMessage => handleTcpMessage(
        result.tcpMessage,
      ),
      CollaborationTransportEventKind.hostDisconnected =>
        const CollaborationWorkspaceEvent(
          kind: CollaborationWorkspaceEventKind.reconnectRequired,
        ),
      CollaborationTransportEventKind.hostTransportFailed =>
        const CollaborationWorkspaceEvent(
          kind: CollaborationWorkspaceEventKind.networkError,
        ),
      CollaborationTransportEventKind.ignored =>
        CollaborationWorkspaceEvent.ignored,
    };
  }

  CollaborationWorkspaceEvent handleTcpMessage(
    CollaborationTcpMessageResult result,
  ) {
    switch (result.kind) {
      case CollaborationTcpMessageKind.joinAccepted:
        return const CollaborationWorkspaceEvent(
          kind: CollaborationWorkspaceEventKind.joined,
          saveReason: 'join accepted',
        );
      case CollaborationTcpMessageKind.joinRejected:
        return const CollaborationWorkspaceEvent(
          kind: CollaborationWorkspaceEventKind.joinRejected,
        );
      case CollaborationTcpMessageKind.permissionsUpdated:
        _moveToFirstAuthorizedImage();
        return const CollaborationWorkspaceEvent(
          kind: CollaborationWorkspaceEventKind.permissionsUpdated,
          saveReason: 'permissions updated',
        );
      case CollaborationTcpMessageKind.assignmentUpdated:
        _moveToFirstAuthorizedImage();
        return const CollaborationWorkspaceEvent(
          kind: CollaborationWorkspaceEventKind.assignmentUpdated,
          saveReason: 'assignment updated',
        );
      case CollaborationTcpMessageKind.peerJoined:
        return const CollaborationWorkspaceEvent(
          kind: CollaborationWorkspaceEventKind.peerJoined,
          saveReason: 'peer joined',
        );
      case CollaborationTcpMessageKind.annotationSnapshot:
        if (!sync.applyAnnotationSnapshot(
          result.message,
          fromUserId: result.fromUserId,
        )) {
          return CollaborationWorkspaceEvent.ignored;
        }
        return const CollaborationWorkspaceEvent(
          kind: CollaborationWorkspaceEventKind.snapshotApplied,
          saveReason: 'annotation snapshot',
        );
      case CollaborationTcpMessageKind.classSnapshot:
        if (collaboration.mode != CollaborationMode.client ||
            !sync.applyClassSnapshot(result.message)) {
          return CollaborationWorkspaceEvent.ignored;
        }
        return const CollaborationWorkspaceEvent(
          kind: CollaborationWorkspaceEventKind.snapshotApplied,
          saveReason: 'class snapshot',
        );
      case CollaborationTcpMessageKind.projectSnapshot:
        if (collaboration.mode != CollaborationMode.client ||
            !sync.applyProjectSnapshot(result.message)) {
          return CollaborationWorkspaceEvent.ignored;
        }
        _moveToFirstAuthorizedImage();
        return const CollaborationWorkspaceEvent(
          kind: CollaborationWorkspaceEventKind.snapshotApplied,
          saveReason: 'project snapshot',
          activateLabelPage: true,
        );
      case CollaborationTcpMessageKind.ignored:
        return CollaborationWorkspaceEvent.ignored;
    }
  }

  void _moveToFirstAuthorizedImage() {
    if (!collaboration.clientMode || project.images.isEmpty) {
      return;
    }
    collaboration.normalizeAssignment(project.images.length);
    if (!collaboration.isImageIndexAuthorized(
      project.selectedImageIndex,
      project.images.length,
    )) {
      project.selectImage(collaboration.assignmentStart - 1);
    }
  }
}
