// =============================================================================
// collaboration_controller.dart - Collaboration State Controller / 协作状态控制器
// =============================================================================
// Manages host/client collaboration lifecycle, peer discovery, permission
// delegation, transport polling, and annotation snapshot broadcasting.
//
// 管理主机/客户端协作生命周期：节点发现、权限委托、传输轮询和标注快照广播。
// =============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/collaboration.dart';
import '../services/app_runtime.dart';
import '../services/collaboration_codec.dart';
import '../services/collaboration_identity.dart';
import '../services/logger.dart';
import '../services/rust_backend.dart';

typedef CollaborationCommandRunner =
    Future<Map<String, dynamic>> Function(Map<String, Object?> request);
typedef CollaborationEventPoller =
    Future<List<Map<String, dynamic>>> Function({required int maxEvents});
typedef CollaborationEventHandler = void Function(Map<String, dynamic> event);
typedef CollaborationTransportErrorHandler =
    void Function(Map<String, Object?> request, Object error);
typedef CollaborationProjectSnapshotBuilder =
    Map<String, Object?> Function(int assignmentStart, int assignmentEnd);

class CollaborationJoinRequest {
  const CollaborationJoinRequest({
    required this.userId,
    required this.userName,
    required this.address,
    required this.colorValue,
  });

  final String userId;
  final String userName;
  final String address;
  final int colorValue;
}

enum CollaborationTcpMessageKind {
  ignored,
  joinAccepted,
  joinRejected,
  permissionsUpdated,
  assignmentUpdated,
  peerJoined,
  annotationSnapshot,
  classSnapshot,
  projectSnapshot,
}

class CollaborationTcpMessageResult {
  const CollaborationTcpMessageResult({
    required this.kind,
    this.message = const {},
    this.fromUserId = '',
  });

  static const ignored = CollaborationTcpMessageResult(
    kind: CollaborationTcpMessageKind.ignored,
  );

  final CollaborationTcpMessageKind kind;
  final Map<String, dynamic> message;
  final String fromUserId;
}

enum CollaborationTransportEventKind {
  ignored,
  joinRequest,
  tcpMessage,
  hostDisconnected,
  hostTransportFailed,
}

class CollaborationTransportEventResult {
  const CollaborationTransportEventResult({
    required this.kind,
    this.event = const {},
    this.tcpMessage = CollaborationTcpMessageResult.ignored,
    this.joinRequest,
  });

  static const ignored = CollaborationTransportEventResult(
    kind: CollaborationTransportEventKind.ignored,
  );

  final CollaborationTransportEventKind kind;
  final Map<String, dynamic> event;
  final CollaborationTcpMessageResult tcpMessage;
  final CollaborationJoinRequest? joinRequest;
}

/// Owns collaboration runtime state independently from the workspace widget.
///
/// The controller owns transport polling and connection lifecycle. Project
/// payload application is delegated to the collaboration sync/workspace
/// controllers.
class CollaborationController extends ChangeNotifier {
  CollaborationController({
    String defaultUserName = 'User',
    CollaborationCommandRunner? commandRunner,
    CollaborationEventPoller? eventPoller,
    this.onTransportError,
    this.reconnectDelay = const Duration(seconds: 3),
    this.maxReconnectAttempts = 5,
  }) : _userName = _normalizedUserName(defaultUserName),
       _commandRunner = commandRunner ?? _runCommand,
       _eventPoller = eventPoller ?? RustBackend.collaborationPollEvents;

  final CollaborationCommandRunner _commandRunner;
  final CollaborationEventPoller _eventPoller;
  final Duration reconnectDelay;
  final int maxReconnectAttempts;
  CollaborationTransportErrorHandler? onTransportError;
  Timer? _pollTimer;
  Timer? _reconnectTimer;
  CollaborationEventHandler? _eventHandler;
  VoidCallback? _onReconnectExhausted;

  CollaborationMode mode = CollaborationMode.off;
  String hostId = newCollaborationId('host');
  String userId = newCollaborationId('user');
  String _userName;
  int port = 8765;
  int assignmentStart = 1;
  int assignmentEnd = 1;
  CollaborationPermissions selfPermissions = const CollaborationPermissions();
  final List<CollaborationPeer> peers = [];
  final List<CollaborationDiscoveredHost> discoveredHosts = [];
  final Set<String> pendingJoinRequests = {};
  String? selectedHostId;
  bool pollInFlight = false;
  bool applyingAnnotationSnapshot = false;
  bool joining = false;
  bool reconnecting = false;
  int reconnectAttempts = 0;
  CollaborationDiscoveredHost? connectedHost;

  CollaborationDiscoveredHost? get selectedHost {
    final id = selectedHostId;
    if (id == null) {
      return null;
    }
    for (final host in discoveredHosts) {
      if (host.hostId == id) {
        return host;
      }
    }
    return null;
  }

  String get userName => _userName;

  set userName(String value) {
    _userName = _normalizedUserName(value);
    notifyListeners();
  }

  bool get clientMode => mode == CollaborationMode.client;

  bool get projectLocked => clientMode;

  String get authorId => collaborationPeerIdFor(hostId, userId);

  String get annotatorName => _normalizedUserName(_userName);

  int get annotatorColorValue => collaborationColorForId(authorId).toARGB32();

  String get annotatorLabel =>
      '$annotatorName#${shortCollaborationId(authorId)}';

  void restoreIdentity({required String hostId, required String userId}) {
    final normalizedHostId = hostId.trim();
    final normalizedUserId = userId.trim();
    if (normalizedHostId.isNotEmpty) {
      this.hostId = normalizedHostId;
    }
    if (normalizedUserId.isNotEmpty) {
      this.userId = normalizedUserId;
    }
  }

  void selectHost(String? hostId) {
    selectedHostId = hostId;
    notifyListeners();
  }

  void updatePort(int value) {
    port = value;
    notifyListeners();
  }

  void startPolling(CollaborationEventHandler onEvent) {
    _eventHandler = onEvent;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 350),
      (_) => unawaited(pollEventsOnce()),
    );
  }

  Future<void> pollEventsOnce() async {
    if (pollInFlight) {
      return;
    }
    pollInFlight = true;
    try {
      final events = await _eventPoller(maxEvents: 50);
      final handler = _eventHandler;
      if (handler == null) {
        return;
      }
      for (final event in events) {
        handler(event);
      }
    } on Object catch (error) {
      logApp('COLLAB', 'Event poll failed: $error', level: AppLogLevel.debug);
    } finally {
      pollInFlight = false;
    }
  }

  CollaborationTransportEventResult handleTransportEvent(
    Map<String, dynamic> event, {
    required int imageCount,
  }) {
    switch (collaborationString(event, 'type')) {
      case 'host_found':
        upsertDiscoveredHost(event);
        return CollaborationTransportEventResult.ignored;
      case 'join_request':
        final requestedUserId = collaborationString(event, 'userId');
        if (!beginJoinRequest(requestedUserId)) {
          return CollaborationTransportEventResult.ignored;
        }
        final rawUserName = collaborationString(event, 'userName').trim();
        return CollaborationTransportEventResult(
          kind: CollaborationTransportEventKind.joinRequest,
          event: event,
          joinRequest: CollaborationJoinRequest(
            userId: requestedUserId,
            userName: rawUserName.isEmpty ? 'User' : rawUserName,
            address: collaborationString(event, 'address'),
            colorValue: collaborationInt(
              event,
              'colorValue',
              fallback: collaborationColorForId(requestedUserId).toARGB32(),
            ),
          ),
        );
      case 'tcp_message':
        final tcpMessage = handleTcpMessage(event, imageCount: imageCount);
        if (tcpMessage.kind == CollaborationTcpMessageKind.ignored) {
          return CollaborationTransportEventResult.ignored;
        }
        return CollaborationTransportEventResult(
          kind: CollaborationTransportEventKind.tcpMessage,
          event: event,
          tcpMessage: tcpMessage,
        );
      case 'client_disconnected':
        markPeerOffline(collaborationString(event, 'userId'));
        return CollaborationTransportEventResult.ignored;
      case 'host_disconnected':
        return mode == CollaborationMode.client
            ? CollaborationTransportEventResult(
                kind: CollaborationTransportEventKind.hostDisconnected,
                event: event,
              )
            : CollaborationTransportEventResult.ignored;
      case 'network_error':
        final scope = collaborationString(event, 'scope');
        logApp(
          'COLLAB',
          'Network error: ${event['scope'] ?? '-'} ${event['error'] ?? ''}',
          level: AppLogLevel.warning,
        );
        if (mode != CollaborationMode.host || scope != 'host_tcp') {
          return CollaborationTransportEventResult.ignored;
        }
        unawaited(endSession());
        return CollaborationTransportEventResult(
          kind: CollaborationTransportEventKind.hostTransportFailed,
          event: event,
        );
      default:
        return CollaborationTransportEventResult.ignored;
    }
  }

  CollaborationTcpMessageResult handleTcpMessage(
    Map<String, dynamic> event, {
    required int imageCount,
  }) {
    final message = collaborationMap(event['message']);
    final fromUserId = collaborationString(event, 'fromUserId');
    switch (collaborationString(message, 'type')) {
      case 'join_accepted':
        final permissions = collaborationMap(message['permissions']);
        completeJoin(
          assignmentStart: collaborationInt(
            message,
            'assignmentStart',
            fallback: 1,
          ),
          assignmentEnd: collaborationInt(
            message,
            'assignmentEnd',
            fallback: imageCount < 1 ? 1 : imageCount,
          ),
          permissions: CollaborationPermissions(
            canEditOthers: collaborationBool(permissions, 'canEditOthers'),
            canDeleteOthers: collaborationBool(permissions, 'canDeleteOthers'),
            canChangeClass: collaborationBool(permissions, 'canChangeClass'),
          ),
        );
        final host = connectedHost;
        if (host != null) {
          upsertPeer(
            CollaborationPeer(
              userId: host.hostId,
              userName: host.hostName,
              address: '${host.address}:${host.port}',
              colorValue: collaborationColorForId(host.hostId).toARGB32(),
              online: true,
            ),
          );
        }
        return CollaborationTcpMessageResult(
          kind: CollaborationTcpMessageKind.joinAccepted,
          message: message,
          fromUserId: fromUserId,
        );
      case 'join_rejected':
        rejectJoin();
        return CollaborationTcpMessageResult(
          kind: CollaborationTcpMessageKind.joinRejected,
          message: message,
          fromUserId: fromUserId,
        );
      case 'permission_update':
        final permissions = collaborationMap(message['permissions']);
        selfPermissions = CollaborationPermissions(
          canEditOthers: collaborationBool(permissions, 'canEditOthers'),
          canDeleteOthers: collaborationBool(permissions, 'canDeleteOthers'),
          canChangeClass: collaborationBool(permissions, 'canChangeClass'),
        );
        assignmentStart = collaborationInt(
          message,
          'assignmentStart',
          fallback: assignmentStart,
        );
        assignmentEnd = collaborationInt(
          message,
          'assignmentEnd',
          fallback: assignmentEnd,
        );
        notifyListeners();
        return CollaborationTcpMessageResult(
          kind: CollaborationTcpMessageKind.permissionsUpdated,
          message: message,
          fromUserId: fromUserId,
        );
      case 'assignment_update':
        assignmentStart = collaborationInt(
          message,
          'assignmentStart',
          fallback: assignmentStart,
        );
        assignmentEnd = collaborationInt(
          message,
          'assignmentEnd',
          fallback: assignmentEnd,
        );
        notifyListeners();
        return CollaborationTcpMessageResult(
          kind: CollaborationTcpMessageKind.assignmentUpdated,
          message: message,
          fromUserId: fromUserId,
        );
      case 'peer_joined':
        final peerUserId = collaborationString(message, 'userId');
        if (peerUserId.isEmpty || peerUserId == authorId) {
          return CollaborationTcpMessageResult.ignored;
        }
        upsertPeer(
          CollaborationPeer(
            userId: peerUserId,
            userName: collaborationString(message, 'userName'),
            colorValue: collaborationInt(
              message,
              'colorValue',
              fallback: collaborationColorForId(peerUserId).toARGB32(),
            ),
            address: collaborationString(message, 'address'),
            online: true,
          ),
        );
        return CollaborationTcpMessageResult(
          kind: CollaborationTcpMessageKind.peerJoined,
          message: message,
          fromUserId: fromUserId,
        );
      case 'annotation_snapshot':
        return CollaborationTcpMessageResult(
          kind: CollaborationTcpMessageKind.annotationSnapshot,
          message: message,
          fromUserId: fromUserId,
        );
      case 'class_snapshot':
        return CollaborationTcpMessageResult(
          kind: CollaborationTcpMessageKind.classSnapshot,
          message: message,
          fromUserId: fromUserId,
        );
      case 'project_snapshot':
        return CollaborationTcpMessageResult(
          kind: CollaborationTcpMessageKind.projectSnapshot,
          message: message,
          fromUserId: fromUserId,
        );
      default:
        return CollaborationTcpMessageResult.ignored;
    }
  }

  Future<Map<String, dynamic>> sendCommand(Map<String, Object?> request) {
    return _commandRunner(request);
  }

  Future<bool> sendTransportCommand(Map<String, Object?> request) async {
    try {
      await sendCommand(request);
      return true;
    } on Object catch (error) {
      logApp(
        'COLLAB',
        'Command failed: ${request['action'] ?? '-'} $error',
        level: AppLogLevel.warning,
      );
      onTransportError?.call(request, error);
      return false;
    }
  }

  Future<bool> sendPeerMessage(
    String peerUserId,
    Map<String, Object?> message,
  ) {
    return sendTransportCommand({
      'action': 'send_peer',
      'userId': peerUserId,
      'message': jsonEncode(message),
    });
  }

  Future<bool> sendHostMessage(Map<String, Object?> message) {
    return sendTransportCommand({
      'action': 'send_host',
      'message': jsonEncode(message),
    });
  }

  Future<bool> broadcastMessage(Map<String, Object?> message) {
    if (mode != CollaborationMode.host) {
      return Future<bool>.value(false);
    }
    return sendTransportCommand({
      'action': 'broadcast',
      'message': jsonEncode(message),
    });
  }

  int sendMessageToAuthorizedPeers(
    Map<String, Object?> message,
    int zeroBasedImageIndex, {
    String? excludeUserId,
  }) {
    if (mode != CollaborationMode.host) {
      return 0;
    }
    var count = 0;
    for (final peer in peers) {
      if (!peer.online || peer.userId == excludeUserId) {
        continue;
      }
      if (!peerCanAccessImage(peer, zeroBasedImageIndex)) {
        continue;
      }
      unawaited(sendPeerMessage(peer.userId, message));
      count += 1;
    }
    return count;
  }

  int sendMessageToOnlinePeers(
    Map<String, Object?> Function(CollaborationPeer peer) messageForPeer,
  ) {
    if (mode != CollaborationMode.host) {
      return 0;
    }
    var count = 0;
    for (final peer in peers) {
      if (!peer.online) {
        continue;
      }
      unawaited(sendPeerMessage(peer.userId, messageForPeer(peer)));
      count += 1;
    }
    return count;
  }

  Future<void> restartDiscovery() async {
    if (mode != CollaborationMode.off) {
      return;
    }
    try {
      await sendCommand({'action': 'start_discovery', 'port': port});
    } on Object catch (error) {
      logApp(
        'COLLAB',
        'Discovery start failed: $error',
        level: AppLogLevel.warning,
      );
    }
  }

  Future<void> resetTransportForStartup() async {
    try {
      await sendCommand(const {'action': 'stop'});
    } on Object catch (error) {
      logApp(
        'COLLAB',
        'Startup collaboration reset failed: $error',
        level: AppLogLevel.debug,
      );
    }
    await restartDiscovery();
  }

  void prepareHost(int imageCount) {
    cancelReconnect();
    mode = CollaborationMode.host;
    joining = false;
    peers.clear();
    pendingJoinRequests.clear();
    assignmentStart = 1;
    assignmentEnd = imageCount < 1 ? 1 : imageCount;
    notifyListeners();
  }

  Future<void> startHostTransport({
    required String projectId,
    required int imageCount,
  }) async {
    await sendCommand({
      'action': 'start_host',
      'hostId': hostId,
      'hostName': annotatorName,
      'userId': authorId,
      'userName': annotatorName,
      'port': port,
      'projectId': projectId,
      'imageCount': imageCount,
    });
  }

  Future<void> startHostSession({
    required String projectId,
    required int imageCount,
  }) async {
    prepareHost(imageCount);
    try {
      await startHostTransport(projectId: projectId, imageCount: imageCount);
    } on Object {
      resetSession();
      await restartDiscovery();
      rethrow;
    }
  }

  Future<void> joinHost(CollaborationDiscoveredHost host) async {
    connectedHost = host;
    joining = true;
    notifyListeners();
    try {
      await _sendJoinCommand(host);
      joining = false;
      notifyListeners();
    } on Object {
      connectedHost = null;
      joining = false;
      notifyListeners();
      await restartDiscovery();
      rethrow;
    }
  }

  Future<void> _sendJoinCommand(CollaborationDiscoveredHost host) {
    return sendCommand({
      'action': 'join_host',
      'hostId': host.hostId,
      'address': host.address,
      'port': host.port,
      'userId': authorId,
      'userName': annotatorName,
      'colorValue': annotatorColorValue,
    }).then<void>((_) {});
  }

  void completeJoin({
    required int assignmentStart,
    required int assignmentEnd,
    required CollaborationPermissions permissions,
  }) {
    cancelReconnect();
    mode = CollaborationMode.client;
    joining = false;
    reconnecting = false;
    reconnectAttempts = 0;
    this.assignmentStart = assignmentStart;
    this.assignmentEnd = assignmentEnd;
    selfPermissions = permissions;
    notifyListeners();
  }

  void rejectJoin() {
    joining = false;
    notifyListeners();
  }

  bool beginReconnect({required VoidCallback onExhausted}) {
    if (reconnecting || connectedHost == null) {
      return false;
    }
    _onReconnectExhausted = onExhausted;
    reconnecting = true;
    reconnectAttempts = 0;
    notifyListeners();
    _scheduleReconnect(immediate: true);
    return true;
  }

  void _scheduleReconnect({bool immediate = false}) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      immediate ? Duration.zero : reconnectDelay,
      () => unawaited(_attemptReconnect()),
    );
  }

  Future<void> _attemptReconnect() async {
    if (!reconnecting) {
      return;
    }
    final host = connectedHost;
    if (host == null || reconnectAttempts >= maxReconnectAttempts) {
      cancelReconnect();
      _onReconnectExhausted?.call();
      return;
    }
    reconnectAttempts += 1;
    notifyListeners();
    try {
      await _sendJoinCommand(host);
      logApp(
        'COLLAB',
        'Reconnect attempt sent: $reconnectAttempts/$maxReconnectAttempts',
        level: AppLogLevel.warning,
      );
    } on Object catch (error) {
      logApp(
        'COLLAB',
        'Reconnect attempt failed: $reconnectAttempts/$maxReconnectAttempts, error=$error',
        level: AppLogLevel.warning,
      );
    }
    if (reconnecting) {
      _scheduleReconnect();
    }
  }

  void cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    reconnecting = false;
    reconnectAttempts = 0;
  }

  void resetSession() {
    cancelReconnect();
    mode = CollaborationMode.off;
    joining = false;
    peers.clear();
    pendingJoinRequests.clear();
    selectedHostId = null;
    connectedHost = null;
    selfPermissions = const CollaborationPermissions();
    notifyListeners();
  }

  Future<void> stopTransport({bool restartDiscovery = true}) async {
    try {
      await sendCommand(const {'action': 'stop'});
    } on Object catch (error) {
      logApp('COLLAB', 'Stop failed: $error', level: AppLogLevel.warning);
    }
    if (restartDiscovery) {
      await this.restartDiscovery();
    }
  }

  Future<void> endSession({bool restartDiscovery = true}) {
    resetSession();
    return stopTransport(restartDiscovery: restartDiscovery);
  }

  bool isImageIndexAuthorized(int zeroBasedIndex, int imageCount) {
    if (!clientMode) {
      return true;
    }
    if (imageCount <= 0) {
      return false;
    }
    final start = assignmentStart.clamp(1, imageCount);
    final end = assignmentEnd.clamp(start, imageCount);
    final index = zeroBasedIndex + 1;
    return index >= start && index <= end;
  }

  void normalizeAssignment(int imageCount) {
    if (imageCount <= 0) {
      assignmentStart = 1;
      assignmentEnd = 1;
      return;
    }
    assignmentStart = assignmentStart.clamp(1, imageCount).toInt();
    assignmentEnd = assignmentEnd.clamp(assignmentStart, imageCount).toInt();
  }

  bool peerCanAccessImage(CollaborationPeer peer, int zeroBasedIndex) {
    final index = zeroBasedIndex + 1;
    return index >= peer.assignmentStart && index <= peer.assignmentEnd;
  }

  bool upsertDiscoveredHost(Map<String, dynamic> event) {
    if (mode == CollaborationMode.host) {
      return false;
    }
    final discoveredHostId = collaborationString(event, 'hostId');
    if (discoveredHostId.isEmpty || discoveredHostId == hostId) {
      return false;
    }
    final host = CollaborationDiscoveredHost(
      hostId: discoveredHostId,
      hostName: collaborationString(event, 'hostName').trim().isEmpty
          ? 'Host'
          : collaborationString(event, 'hostName'),
      address: collaborationString(event, 'address'),
      port: collaborationInt(event, 'port', fallback: port),
      online: true,
    );
    final index = discoveredHosts.indexWhere(
      (item) => item.hostId == host.hostId,
    );
    if (index >= 0) {
      discoveredHosts[index] = host;
    } else {
      discoveredHosts.add(host);
    }
    if (selectedHostId == null ||
        !discoveredHosts.any((item) => item.hostId == selectedHostId)) {
      selectedHostId = host.hostId;
    }
    discoveredHosts.sort(
      (a, b) => a.hostName.toLowerCase().compareTo(b.hostName.toLowerCase()),
    );
    notifyListeners();
    return true;
  }

  bool beginJoinRequest(String requestedUserId) {
    final normalized = requestedUserId.trim();
    if (mode != CollaborationMode.host ||
        normalized.isEmpty ||
        pendingJoinRequests.contains(normalized)) {
      return false;
    }
    pendingJoinRequests.add(normalized);
    return true;
  }

  void finishJoinRequest(String requestedUserId) {
    pendingJoinRequests.remove(requestedUserId.trim());
  }

  Future<CollaborationPeer> acceptJoinRequest(
    CollaborationJoinRequest request, {
    required int imageCount,
    required CollaborationProjectSnapshotBuilder projectSnapshotBuilder,
  }) async {
    finishJoinRequest(request.userId);
    final max = imageCount < 1 ? 1 : imageCount;
    final start = assignmentStart.clamp(1, max).toInt();
    final end = assignmentEnd.clamp(start, max).toInt();
    const permissions = CollaborationPermissions();
    final peer = CollaborationPeer(
      userId: request.userId,
      userName: request.userName,
      colorValue: request.colorValue,
      address: request.address,
      online: true,
      assignmentStart: start,
      assignmentEnd: end,
      permissions: permissions,
    );
    upsertPeer(peer);
    await sendTransportCommand({
      'action': 'host_accept',
      'userId': request.userId,
      'hostId': hostId,
      'assignmentStart': start,
      'assignmentEnd': end,
      'canEditOthers': permissions.canEditOthers,
      'canDeleteOthers': permissions.canDeleteOthers,
      'canChangeClass': permissions.canChangeClass,
    });
    unawaited(
      sendPeerMessage(request.userId, projectSnapshotBuilder(start, end)),
    );
    unawaited(
      broadcastMessage({
        'type': 'peer_joined',
        'userId': request.userId,
        'userName': request.userName,
        'colorValue': request.colorValue,
        'address': request.address,
      }),
    );
    return peer;
  }

  Future<void> rejectJoinRequest(CollaborationJoinRequest request) async {
    finishJoinRequest(request.userId);
    await sendTransportCommand({
      'action': 'host_reject',
      'userId': request.userId,
      'reason': 'rejected',
    });
  }

  void upsertPeer(CollaborationPeer peer) {
    final index = peers.indexWhere((item) => item.userId == peer.userId);
    if (index >= 0) {
      peers[index] = peers[index].copyWith(
        userName: peer.userName,
        colorValue: peer.colorValue,
        address: peer.address,
        online: peer.online,
        assignmentStart: peer.assignmentStart,
        assignmentEnd: peer.assignmentEnd,
        permissions: peer.permissions,
      );
    } else {
      peers.add(peer);
    }
    notifyListeners();
  }

  bool markPeerOffline(String peerUserId) {
    final normalized = peerUserId.trim();
    if (normalized.isEmpty) {
      return false;
    }
    final index = peers.indexWhere((peer) => peer.userId == normalized);
    if (index < 0 || !peers[index].online) {
      return false;
    }
    peers[index] = peers[index].copyWith(online: false);
    notifyListeners();
    return true;
  }

  CollaborationPeer? updatePeerPermissions(
    CollaborationPeerPermissionResult result, {
    required int imageCount,
  }) {
    final max = imageCount < 1 ? 1 : imageCount;
    final start = result.assignmentStart.clamp(1, max).toInt();
    final end = result.assignmentEnd.clamp(start, max).toInt();
    final index = peers.indexWhere((peer) => peer.userId == result.userId);
    if (index < 0) {
      return null;
    }
    final updated = peers[index].copyWith(
      assignmentStart: start,
      assignmentEnd: end,
      permissions: result.permissions,
    );
    peers[index] = updated;
    notifyListeners();
    return updated;
  }

  CollaborationPeer? applyPeerPermissions(
    CollaborationPeerPermissionResult result, {
    required int imageCount,
    required CollaborationProjectSnapshotBuilder projectSnapshotBuilder,
  }) {
    final updated = updatePeerPermissions(result, imageCount: imageCount);
    if (updated == null) {
      return null;
    }
    final permissions = updated.permissions;
    unawaited(
      sendPeerMessage(updated.userId, {
        'type': 'permission_update',
        'assignmentStart': updated.assignmentStart,
        'assignmentEnd': updated.assignmentEnd,
        'permissions': {
          'canEditOthers': permissions.canEditOthers,
          'canDeleteOthers': permissions.canDeleteOthers,
          'canChangeClass': permissions.canChangeClass,
        },
      }),
    );
    unawaited(
      sendPeerMessage(
        updated.userId,
        projectSnapshotBuilder(updated.assignmentStart, updated.assignmentEnd),
      ),
    );
    return updated;
  }

  static Future<Map<String, dynamic>> _runCommand(
    Map<String, Object?> request,
  ) {
    return RustBackend.collaborationCommand(request: request);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    cancelReconnect();
    _eventHandler = null;
    _onReconnectExhausted = null;
    onTransportError = null;
    super.dispose();
  }

  static String _normalizedUserName(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? 'User' : normalized;
  }
}
