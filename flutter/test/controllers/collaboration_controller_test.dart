import 'package:flutter_test/flutter_test.dart';
import 'package:yolo_label_tool/controllers/collaboration_controller.dart';
import 'package:yolo_label_tool/models/collaboration.dart';

void main() {
  group('CollaborationController', () {
    test('normalizes identity and assignment authorization', () {
      final controller = CollaborationController(defaultUserName: '  ')
        ..restoreIdentity(hostId: 'HOST-A', userId: 'USER-A')
        ..mode = CollaborationMode.client
        ..assignmentStart = 2
        ..assignmentEnd = 4;
      addTearDown(controller.dispose);

      expect(controller.annotatorName, 'User');
      expect(controller.authorId, 'USER-A@HOST-A');
      expect(controller.isImageIndexAuthorized(0, 5), isFalse);
      expect(controller.isImageIndexAuthorized(1, 5), isTrue);
      expect(controller.isImageIndexAuthorized(3, 5), isTrue);
      expect(controller.isImageIndexAuthorized(4, 5), isFalse);
    });

    test('upserts discovered hosts and peers without duplicates', () {
      final controller = CollaborationController()
        ..restoreIdentity(hostId: 'LOCAL-HOST', userId: 'LOCAL-USER');
      addTearDown(controller.dispose);

      expect(
        controller.upsertDiscoveredHost({
          'hostId': 'REMOTE-HOST',
          'hostName': 'Remote',
          'address': '192.168.1.2',
          'port': 9000,
        }),
        isTrue,
      );
      controller.upsertDiscoveredHost({
        'hostId': 'REMOTE-HOST',
        'hostName': 'Remote Updated',
        'address': '192.168.1.3',
        'port': 9001,
      });
      expect(controller.discoveredHosts, hasLength(1));
      expect(controller.discoveredHosts.single.port, 9001);

      controller.upsertPeer(
        const CollaborationPeer(
          userId: 'PEER-A',
          userName: 'Peer',
          address: '192.168.1.4',
          colorValue: 1,
          online: true,
        ),
      );
      controller.upsertPeer(
        const CollaborationPeer(
          userId: 'PEER-A',
          userName: 'Peer Updated',
          address: '192.168.1.5',
          colorValue: 2,
          online: true,
        ),
      );
      expect(controller.peers, hasLength(1));
      expect(controller.peers.single.userName, 'Peer Updated');
      expect(controller.markPeerOffline('PEER-A'), isTrue);
      expect(controller.peers.single.online, isFalse);
    });

    test('builds host and join transport commands', () async {
      final requests = <Map<String, Object?>>[];
      final controller = CollaborationController(
        defaultUserName: 'Admin',
        commandRunner: (request) async {
          requests.add(Map<String, Object?>.from(request));
          return <String, dynamic>{};
        },
      )..restoreIdentity(hostId: 'HOST-A', userId: 'USER-A');
      addTearDown(controller.dispose);

      controller.prepareHost(12);
      await controller.startHostTransport(
        projectId: 'PROJECT-A',
        imageCount: 12,
      );
      expect(requests.single, {
        'action': 'start_host',
        'hostId': 'HOST-A',
        'hostName': 'Admin',
        'userId': 'USER-A@HOST-A',
        'userName': 'Admin',
        'port': 8765,
        'projectId': 'PROJECT-A',
        'imageCount': 12,
      });

      controller.mode = CollaborationMode.off;
      const host = CollaborationDiscoveredHost(
        hostId: 'HOST-B',
        hostName: 'Remote',
        address: '192.168.1.8',
        port: 9000,
        online: true,
      );
      await controller.joinHost(host);
      expect(controller.connectedHost, host);
      expect(controller.joining, isFalse);
      expect(requests.last, {
        'action': 'join_host',
        'hostId': 'HOST-B',
        'address': '192.168.1.8',
        'port': 9000,
        'userId': 'USER-A@HOST-A',
        'userName': 'Admin',
        'colorValue': controller.annotatorColorValue,
      });
    });

    test('polls transport events through the registered handler', () async {
      final received = <Map<String, dynamic>>[];
      final controller = CollaborationController(
        eventPoller: ({required maxEvents}) async {
          expect(maxEvents, 50);
          return [
            {'type': 'host_found', 'hostId': 'HOST-B'},
          ];
        },
      );
      addTearDown(controller.dispose);

      controller.startPolling(received.add);
      await controller.pollEventsOnce();

      expect(received, [
        {'type': 'host_found', 'hostId': 'HOST-B'},
      ]);
      expect(controller.pollInFlight, isFalse);
    });
  });
}
