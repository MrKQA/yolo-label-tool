import 'dart:async';

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

/// Owns collaboration runtime state independently from the workspace widget.
///
/// The controller owns transport polling and connection lifecycle. Applying
/// remote project and annotation payloads remains a workspace responsibility
/// because those operations mutate the currently opened project.
class CollaborationController extends ChangeNotifier {
  CollaborationController({
    String defaultUserName = 'User',
    CollaborationCommandRunner? commandRunner,
    CollaborationEventPoller? eventPoller,
    this.reconnectDelay = const Duration(seconds: 3),
    this.maxReconnectAttempts = 5,
  }) : _userName = _normalizedUserName(defaultUserName),
       _commandRunner = commandRunner ?? _runCommand,
       _eventPoller = eventPoller ?? RustBackend.collaborationPollEvents;

  final CollaborationCommandRunner _commandRunner;
  final CollaborationEventPoller _eventPoller;
  final Duration reconnectDelay;
  final int maxReconnectAttempts;
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

  Future<Map<String, dynamic>> sendCommand(Map<String, Object?> request) {
    return _commandRunner(request);
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
    return true;
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
    super.dispose();
  }

  static String _normalizedUserName(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? 'User' : normalized;
  }
}
