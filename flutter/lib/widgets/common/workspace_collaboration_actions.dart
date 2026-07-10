part of '../../main.dart';

extension _WorkspaceShellCollaborationActions on _WorkspaceShellState {
  void _startCollaborationPolling() {
    _collaborationPollTimer?.cancel();
    _collaborationPollTimer = Timer.periodic(
      const Duration(milliseconds: 350),
      (_) => _pollCollaborationEvents(),
    );
  }

  void _restartCollaborationDiscovery() {
    if (_collaborationMode != _CollaborationMode.off) {
      return;
    }
    unawaited(
      RustBackend.collaborationCommand(
        request: {'action': 'start_discovery', 'port': _collaborationPort},
      ).catchError((Object error) {
        _log(
          'COLLAB',
          'Discovery start failed: $error',
          level: _LogLevel.warning,
        );
        return <String, dynamic>{};
      }),
    );
  }

  Future<void> _pollCollaborationEvents() async {
    if (_collaborationPollInFlight) {
      return;
    }
    _collaborationPollInFlight = true;
    try {
      final events = await RustBackend.collaborationPollEvents(
        maxEvents: 50,
      );
      if (!mounted || events.isEmpty) {
        return;
      }
      for (final event in events) {
        _handleCollaborationEvent(event);
      }
    } on Object catch (error) {
      _log('COLLAB', 'Event poll failed: $error', level: _LogLevel.debug);
    } finally {
      _collaborationPollInFlight = false;
    }
  }

  void _handleCollaborationEvent(Map<String, dynamic> event) {
    switch (collaborationString(event, 'type')) {
      case 'host_found':
        _upsertDiscoveredHost(event);
        break;
      case 'join_request':
        _handleCollaborationJoinRequest(event);
        break;
      case 'tcp_message':
        _handleCollaborationTcpMessage(event);
        break;
      case 'client_disconnected':
        _markCollaborationPeerOffline(collaborationString(event, 'userId'));
        break;
      case 'host_disconnected':
        if (_collaborationMode == _CollaborationMode.client) {
          _startCollaborationReconnect();
        }
        break;
      case 'network_error':
        _log(
          'COLLAB',
          'Network error: ${event['scope'] ?? '-'} ${event['error'] ?? ''}',
          level: _LogLevel.warning,
        );
        if (_collaborationMode == _CollaborationMode.host &&
            collaborationString(event, 'scope') == 'host_tcp') {
          setState(() {
            _collaborationMode = _CollaborationMode.off;
            _collaborationPeers.clear();
            _pendingCollaborationJoinRequests.clear();
          });
          _showFloatingMessage(t('collab.networkError'));
          unawaited(
            RustBackend.collaborationCommand(
                  request: const {'action': 'stop'},
                )
                .catchError((Object error) {
                  _log(
                    'COLLAB',
                    'Stop after host TCP error failed: $error',
                    level: _LogLevel.debug,
                  );
                  return <String, dynamic>{};
                })
                .whenComplete(_restartCollaborationDiscovery),
          );
        }
        break;
      default:
        break;
    }
  }

  void _upsertDiscoveredHost(Map<String, dynamic> event) {
    if (_collaborationMode == _CollaborationMode.host) {
      return;
    }
    final hostId = collaborationString(event, 'hostId');
    if (hostId.isEmpty || hostId == _collaborationHostId) {
      return;
    }
    final host = _CollaborationDiscoveredHost(
      hostId: hostId,
      hostName: collaborationString(event, 'hostName').trim().isEmpty
          ? 'Host'
          : collaborationString(event, 'hostName'),
      address: collaborationString(event, 'address'),
      port: collaborationInt(event, 'port', fallback: _collaborationPort),
      online: true,
    );
    setState(() {
      final index = _collaborationDiscoveredHosts.indexWhere(
        (item) => item.hostId == host.hostId,
      );
      if (index >= 0) {
        _collaborationDiscoveredHosts[index] = host;
      } else {
        _collaborationDiscoveredHosts.add(host);
      }
      if (_selectedCollaborationHostId == null ||
          !_collaborationDiscoveredHosts.any(
            (item) => item.hostId == _selectedCollaborationHostId,
          )) {
        _selectedCollaborationHostId = host.hostId;
      }
      _collaborationDiscoveredHosts.sort(
        (a, b) => a.hostName.toLowerCase().compareTo(b.hostName.toLowerCase()),
      );
    });
  }

  void _handleCollaborationJoinRequest(Map<String, dynamic> event) {
    if (_collaborationMode != _CollaborationMode.host) {
      return;
    }
    final userId = collaborationString(event, 'userId');
    if (userId.isEmpty || _pendingCollaborationJoinRequests.contains(userId)) {
      return;
    }
    _pendingCollaborationJoinRequests.add(userId);
    unawaited(_confirmCollaborationJoin(event));
  }

  Future<void> _confirmCollaborationJoin(Map<String, dynamic> event) async {
    final userId = collaborationString(event, 'userId');
    final userName = collaborationString(event, 'userName').trim().isEmpty
        ? 'User'
        : collaborationString(event, 'userName');
    final address = collaborationString(event, 'address');
    final colorValue = collaborationInt(
      event,
      'colorValue',
      fallback: _collaborationColorForId(userId).toARGB32(),
    );
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('collab.joinRequestTitle')),
        content: Text(
          '${t('collab.joinRequestBody')}\n$userName#${_shortCollaborationId(userId)}\n$address',
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
    _pendingCollaborationJoinRequests.remove(userId);
    if (!mounted) {
      return;
    }
    if (allow == true) {
      final permissions = const _CollaborationPermissions();
      final assignmentStart = _collaborationStartIndex
          .clamp(1, math.max(1, _images.length))
          .toInt();
      final assignmentEnd = _collaborationEndIndex
          .clamp(assignmentStart, math.max(1, _images.length))
          .toInt();
      setState(() {
        _upsertCollaborationPeer(
          _CollaborationPeer(
            userId: userId,
            userName: userName,
            colorValue: colorValue,
            address: address,
            online: true,
            assignmentStart: assignmentStart,
            assignmentEnd: assignmentEnd,
            permissions: permissions,
          ),
        );
      });
      await _sendCollaborationCommand({
        'action': 'host_accept',
        'userId': userId,
        'hostId': _collaborationHostId,
        'assignmentStart': assignmentStart,
        'assignmentEnd': assignmentEnd,
        'canEditOthers': permissions.canEditOthers,
        'canDeleteOthers': permissions.canDeleteOthers,
        'canChangeClass': permissions.canChangeClass,
      });
      _sendCollaborationMessageToPeer(
        userId,
        _collaborationProjectSnapshotMessage(
          assignmentStart: assignmentStart,
          assignmentEnd: assignmentEnd,
        ),
      );
      _broadcastCollaborationMessage({
        'type': 'peer_joined',
        'userId': userId,
        'userName': userName,
        'colorValue': colorValue,
        'address': address,
      });
      _scheduleAnnotationDatabaseSave();
      _showFloatingMessage(t('collab.joinAccepted'));
      _log('COLLAB', 'Join accepted: user=$userId, address=$address');
    } else {
      await _sendCollaborationCommand({
        'action': 'host_reject',
        'userId': userId,
        'reason': 'rejected',
      });
      _log('COLLAB', 'Join rejected: user=$userId, address=$address');
    }
  }

  void _handleCollaborationTcpMessage(Map<String, dynamic> event) {
    final message = collaborationMap(event['message']);
    switch (collaborationString(message, 'type')) {
      case 'join_accepted':
        setState(() {
          _collaborationMode = _CollaborationMode.client;
          _collaborationJoining = false;
          _collaborationReconnecting = false;
          _collaborationReconnectAttempts = 0;
          _collaborationReconnectTimer?.cancel();
          _collaborationStartIndex = collaborationInt(
            message,
            'assignmentStart',
            fallback: 1,
          );
          _collaborationEndIndex = collaborationInt(
            message,
            'assignmentEnd',
            fallback: math.max(1, _images.length),
          );
          final permissions = collaborationMap(message['permissions']);
          _collaborationSelfPermissions = _CollaborationPermissions(
            canEditOthers: collaborationBool(permissions, 'canEditOthers'),
            canDeleteOthers: collaborationBool(permissions, 'canDeleteOthers'),
            canChangeClass: collaborationBool(permissions, 'canChangeClass'),
          );
          final host = _connectedCollaborationHost;
          if (host != null) {
            _upsertCollaborationPeer(
              _CollaborationPeer(
                userId: host.hostId,
                userName: host.hostName,
                address: '${host.address}:${host.port}',
                colorValue: _collaborationColorForId(host.hostId).toARGB32(),
                online: true,
              ),
            );
          }
        });
        unawaited(_saveCollaborationAnnotationDatabaseNow('join accepted'));
        _showFloatingMessage(t('collab.joined'));
        _log('COLLAB', 'Join accepted by host');
        break;
      case 'join_rejected':
        setState(() => _collaborationJoining = false);
        _showFloatingMessage(t('collab.joinRejected'));
        _disconnectCollaborationClient(clearProject: true);
        break;
      case 'permission_update':
        final permissions = collaborationMap(message['permissions']);
        setState(() {
          _collaborationSelfPermissions = _CollaborationPermissions(
            canEditOthers: collaborationBool(permissions, 'canEditOthers'),
            canDeleteOthers: collaborationBool(permissions, 'canDeleteOthers'),
            canChangeClass: collaborationBool(permissions, 'canChangeClass'),
          );
          _collaborationStartIndex = collaborationInt(
            message,
            'assignmentStart',
            fallback: _collaborationStartIndex,
          );
          _collaborationEndIndex = collaborationInt(
            message,
            'assignmentEnd',
            fallback: _collaborationEndIndex,
          );
          _moveToFirstAuthorizedCollaborationImage();
        });
        unawaited(
          _saveCollaborationAnnotationDatabaseNow('permissions updated'),
        );
        _showFloatingMessage(t('collab.permissionsUpdated'));
        break;
      case 'assignment_update':
        setState(() {
          _collaborationStartIndex = collaborationInt(
            message,
            'assignmentStart',
            fallback: _collaborationStartIndex,
          );
          _collaborationEndIndex = collaborationInt(
            message,
            'assignmentEnd',
            fallback: _collaborationEndIndex,
          );
          _moveToFirstAuthorizedCollaborationImage();
        });
        unawaited(
          _saveCollaborationAnnotationDatabaseNow('assignment updated'),
        );
        break;
      case 'peer_joined':
        final userId = collaborationString(message, 'userId');
        if (userId.isNotEmpty && userId != _collaborationAuthorId) {
          setState(() {
            _upsertCollaborationPeer(
              _CollaborationPeer(
                userId: userId,
                userName: collaborationString(message, 'userName'),
                colorValue: collaborationInt(
                  message,
                  'colorValue',
                  fallback: _collaborationColorForId(userId).toARGB32(),
                ),
                address: collaborationString(message, 'address'),
                online: true,
              ),
            );
          });
          unawaited(_saveCollaborationAnnotationDatabaseNow('peer joined'));
        }
        break;
      case 'annotation_snapshot':
        _applyCollaborationAnnotationSnapshot(
          message,
          fromUserId: collaborationString(event, 'fromUserId'),
        );
        break;
      case 'class_snapshot':
        if (_collaborationMode == _CollaborationMode.client) {
          _applyCollaborationClassSnapshot(message);
        }
        break;
      case 'project_snapshot':
        if (_collaborationMode == _CollaborationMode.client) {
          _applyCollaborationProjectSnapshot(message);
        }
        break;
      default:
        break;
    }
  }

  void _publishCurrentCollaborationAnnotations() {
    if (_collaborationMode == _CollaborationMode.off ||
        !_selectedImageAuthorized) {
      return;
    }
    final image = _selectedImage;
    if (image == null) {
      return;
    }
    final limitedToOwnAnnotations =
        _collaborationMode == _CollaborationMode.client &&
        !_collaborationSelfPermissions.canEditOthers &&
        !_collaborationSelfPermissions.canDeleteOthers &&
        !_collaborationSelfPermissions.canChangeClass;
    final annotations = limitedToOwnAnnotations
        ? _currentAnnotations
              .where(
                (annotation) =>
                    annotation.authorId.isEmpty ||
                    annotation.authorId == _collaborationAuthorId,
              )
              .toList(growable: false)
        : _currentAnnotations;
    final message = <String, Object?>{
      'type': 'annotation_snapshot',
      'imagePath': image.path,
      'imageIndex': _selectedImageIndex + 1,
      'sourceUserId': _collaborationAuthorId,
      'authoritative': !limitedToOwnAnnotations,
      if (limitedToOwnAnnotations) 'authorScope': _collaborationAuthorId,
      if (_collaborationMode == _CollaborationMode.host)
        'classes': _collaborationClassesPayload(),
      'annotations': [
        for (final annotation in annotations)
          _collaborationAnnotationToJson(annotation),
      ],
    };
    if (_collaborationMode == _CollaborationMode.host) {
      _sendCollaborationMessageToAuthorizedPeers(message, _selectedImageIndex);
    } else {
      unawaited(
        _sendCollaborationCommand({
          'action': 'send_host',
          'message': jsonEncode(message),
        }),
      );
    }
  }

  Map<String, Object?> _collaborationProjectSnapshotMessage({
    int? assignmentStart,
    int? assignmentEnd,
  }) {
    final start = assignmentStart ?? _collaborationStartIndex;
    final end = assignmentEnd ?? _collaborationEndIndex;
    return {
      'type': 'project_snapshot',
      'projectKey': _databaseProjectKey(),
      'assignmentStart': start,
      'assignmentEnd': end,
      'images': [
        for (var index = 0; index < _images.length; index++)
          {
            'path': _images[index].path,
            'name': _images[index].name,
            'split': _imageSplits[pathKey(_images[index].path)] ?? 'train',
            'width':
                (_displaySizeForImagePath(_images[index].path) ?? Size.zero)
                    .width,
            'height':
                (_displaySizeForImagePath(_images[index].path) ?? Size.zero)
                    .height,
            'index': index + 1,
            if (index + 1 >= start && index + 1 <= end)
              'bytesBase64': _collaborationImageBytesBase64(
                _images[index].path,
              ),
          },
      ],
      'classes': _collaborationClassesPayload(),
      'annotationsByImage': [
        for (var index = 0; index < _images.length; index++)
          if (index + 1 >= start && index + 1 <= end)
            {
              'imageIndex': index + 1,
              'imagePath': _images[index].path,
              'annotations': [
                for (final annotation in _annotationsForImagePath(
                  _images[index].path,
                ))
                  _collaborationAnnotationToJson(annotation),
              ],
            },
      ],
    };
  }

  List<Map<String, Object?>> _collaborationClassesPayload() {
    return [
      for (final labelClass in _labelClasses)
        {
          'id': labelClass.id,
          'name': labelClass.name,
          'color': labelClass.colorValue,
        },
    ];
  }

  Map<String, Object?> _collaborationClassSnapshotMessage() {
    return {
      'type': 'class_snapshot',
      'classes': _collaborationClassesPayload(),
    };
  }

  void _replaceLabelClassesFromCollaboration(List<LabelClass> classes) {
    _labelClasses
      ..clear()
      ..addAll(classes);
    if (_activeClassId == null ||
        !_labelClasses.any((item) => item.id == _activeClassId)) {
      _activeClassId = _labelClasses.isEmpty ? null : _labelClasses.first.id;
    }
    _classSerial = math.max(_classSerial, nextClassSerialFor(classes));
  }

  String _collaborationImageBytesBase64(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        return '';
      }
      return base64Encode(file.readAsBytesSync());
    } on Object catch (error) {
      _log(
        'COLLAB',
        'Image payload read failed: path=$path, error=$error',
        level: _LogLevel.warning,
      );
      return '';
    }
  }

  String _collaborationLocalImagePath({
    required String remotePath,
    required String name,
    required String bytesBase64,
  }) {
    if (File(remotePath).existsSync() || bytesBase64.trim().isEmpty) {
      return remotePath;
    }
    try {
      final bytes = base64Decode(bytesBase64);
      final cacheDir = Directory(
        '${ConfigStore.projectDirectory.path}\\collaboration_cache',
      );
      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }
      final fileName = collaborationCacheFileName(remotePath, name);
      final file = File('${cacheDir.path}\\$fileName');
      file.writeAsBytesSync(bytes);
      return file.path;
    } on Object catch (error) {
      _log(
        'COLLAB',
        'Image payload write failed: path=$remotePath, error=$error',
        level: _LogLevel.warning,
      );
      return remotePath;
    }
  }

  void _applyCollaborationProjectSnapshot(Map<String, dynamic> message) {
    final rawImages = message['images'];
    if (rawImages is! List) {
      return;
    }

    final nextImages = <ImageItem>[];
    final nextSplits = <String, String>{};
    final nextSizes = <String, Size>{};
    final remoteToLocalImagePath = <String, String>{};
    for (final rawImage in rawImages) {
      final image = collaborationMap(rawImage);
      final path = collaborationString(image, 'path');
      if (path.isEmpty) {
        continue;
      }
      final name = collaborationString(image, 'name').trim().isEmpty
          ? fileName(path)
          : collaborationString(image, 'name');
      final localPath = _collaborationLocalImagePath(
        remotePath: path,
        name: name,
        bytesBase64: collaborationString(image, 'bytesBase64'),
      );
      final imageKey = pathKey(localPath);
      remoteToLocalImagePath[pathKey(path)] = localPath;
      nextImages.add(ImageItem(path: localPath, name: name));
      nextSplits[imageKey] = collaborationString(image, 'split').trim().isEmpty
          ? 'train'
          : collaborationString(image, 'split');
      nextSizes[imageKey] = Size(
        collaborationDouble(image, 'width'),
        collaborationDouble(image, 'height'),
      );
    }
    if (nextImages.isEmpty) {
      return;
    }

    final nextClasses = collaborationClassesFromJson(message['classes']);
    final nextClassSerial = nextClassSerialFor(nextClasses);

    final nextAnnotations = <String, List<AnnotationRegion>>{};
    var maxAnnotationSerial = _annotationSerial;
    final rawAnnotationsByImage = message['annotationsByImage'];
    if (rawAnnotationsByImage is List) {
      for (final rawEntry in rawAnnotationsByImage) {
        final entry = collaborationMap(rawEntry);
        final imagePath = collaborationString(entry, 'imagePath');
        final imageIndex =
            collaborationInt(entry, 'imageIndex', fallback: 0) - 1;
        final localImagePath = imageIndex >= 0 && imageIndex < nextImages.length
            ? nextImages[imageIndex].path
            : remoteToLocalImagePath[pathKey(imagePath)] ?? imagePath;
        if (localImagePath.isEmpty) {
          continue;
        }
        final rawAnnotations = entry['annotations'];
        if (rawAnnotations is! List) {
          continue;
        }
        final annotations = rawAnnotations
            .map(collaborationAnnotationFromJson)
            .whereType<AnnotationRegion>()
            .toList();
        for (final annotation in annotations) {
          final match = RegExp(r'^ann_(\d+)$').firstMatch(annotation.id);
          if (match != null) {
            final serial = int.tryParse(match.group(1) ?? '');
            if (serial != null && serial >= maxAnnotationSerial) {
              maxAnnotationSerial = serial + 1;
            }
          }
        }
        nextAnnotations[pathKey(localImagePath)] = annotations;
      }
    }

    final snapshotStart = collaborationInt(
      message,
      'assignmentStart',
      fallback: _collaborationStartIndex,
    );
    final snapshotEnd = collaborationInt(
      message,
      'assignmentEnd',
      fallback: _collaborationEndIndex,
    );
    final firstAuthorizedIndex = (snapshotStart - 1)
        .clamp(0, nextImages.length - 1)
        .toInt();
    setState(() {
      _collaborationStartIndex = snapshotStart;
      _collaborationEndIndex = snapshotEnd;
      _images
        ..clear()
        ..addAll(nextImages);
      _imageSplits
        ..clear()
        ..addAll(nextSplits);
      _imageDisplaySizes
        ..clear()
        ..addAll(nextSizes);
      _replaceLabelClassesFromCollaboration(nextClasses);
      _annotationsByImage
        ..clear()
        ..addAll(nextAnnotations);
      _importedDataset = null;
      _selectedImageIndex = firstAuthorizedIndex;
      _selectedAnnotationId = null;
      _activeClassId = nextClasses.isEmpty ? null : nextClasses.first.id;
      _classSerial = math.max(_classSerial, nextClassSerial);
      _annotationSerial = math.max(_annotationSerial, maxAnnotationSerial);
      _undoStack.clear();
      _redoStack.clear();
      _moveToFirstAuthorizedCollaborationImage();
      _activeSection = 'label';
    });
    unawaited(_saveCollaborationAnnotationDatabaseNow('project snapshot'));
  }

  void _applyCollaborationClassSnapshot(Map<String, dynamic> message) {
    if (message['classes'] is! List) {
      return;
    }
    final nextClasses = collaborationClassesFromJson(message['classes']);
    setState(() {
      _replaceLabelClassesFromCollaboration(nextClasses);
    });
    unawaited(_saveCollaborationAnnotationDatabaseNow('class snapshot'));
  }

  Map<String, Object?> _collaborationAnnotationToJson(
    AnnotationRegion annotation,
  ) {
    final rect = annotation.rect;
    final authorId = annotation.authorId.trim().isEmpty
        ? _collaborationAuthorId
        : annotation.authorId;
    final authorName = annotation.authorName.trim().isEmpty
        ? _currentAnnotatorName
        : annotation.authorName;
    final authorColor = annotation.authorColorValue == 0
        ? _currentAnnotatorColorValue
        : annotation.authorColorValue;
    return {
      'id': annotation.id,
      'mode': annotation.mode.name,
      'classId': annotation.classId,
      'left': rect.left,
      'top': rect.top,
      'right': rect.right,
      'bottom': rect.bottom,
      'rotation': annotation.rotationDegrees,
      'points': [
        for (final point in annotation.points) {'x': point.dx, 'y': point.dy},
      ],
      'authorId': authorId,
      'authorName': authorName,
      'authorColor': authorColor,
    };
  }

  AnnotationRegion _withCollaborationAuthorFallback(
    AnnotationRegion annotation,
    String fallbackUserId,
  ) {
    final userId = annotation.authorId.trim().isEmpty
        ? fallbackUserId.trim()
        : annotation.authorId;
    if (userId.isEmpty) {
      return annotation;
    }
    final peer = _collaborationPeers
        .where((item) => item.userId == userId)
        .firstOrNullValue;
    final peerName = peer?.userName.trim() ?? '';
    final peerColor = peer?.colorValue;
    final authorName = annotation.authorName.trim().isEmpty
        ? userId == _collaborationAuthorId
              ? _currentAnnotatorName
              : (peerName.isNotEmpty ? peerName : 'User')
        : annotation.authorName;
    final authorColor = annotation.authorColorValue == 0
        ? userId == _collaborationAuthorId
              ? _currentAnnotatorColorValue
              : (peerColor ?? _collaborationColorForId(userId).toARGB32())
        : annotation.authorColorValue;
    return annotation.copyWith(
      authorId: userId,
      authorName: authorName,
      authorColorValue: authorColor,
    );
  }

  void _applyCollaborationAnnotationSnapshot(
    Map<String, dynamic> message, {
    required String fromUserId,
  }) {
    if (_collaborationMode == _CollaborationMode.off) {
      return;
    }
    final imageIndex =
        collaborationInt(message, 'imageIndex', fallback: 0) - 1;
    if (imageIndex < 0 || imageIndex >= _images.length) {
      return;
    }
    if (_collaborationMode == _CollaborationMode.host &&
        fromUserId.isNotEmpty) {
      final peer = _collaborationPeers
          .where((item) => item.userId == fromUserId)
          .firstOrNullValue;
      if (peer == null || !_collaborationPeerCanAccessImage(peer, imageIndex)) {
        return;
      }
    }
    if (_collaborationMode == _CollaborationMode.client &&
        !_isImageIndexAuthorized(imageIndex)) {
      return;
    }
    final rawAnnotations = message['annotations'];
    if (rawAnnotations is! List) {
      return;
    }
    final hasClassPayload = message['classes'] is List;
    final nextClasses = hasClassPayload
        ? collaborationClassesFromJson(message['classes'])
        : const <LabelClass>[];
    final sourceUserId = fromUserId.trim().isNotEmpty
        ? fromUserId.trim()
        : collaborationString(message, 'sourceUserId').trim();
    final authorScope = collaborationString(message, 'authorScope').trim();
    final authoritative = collaborationBool(message, 'authoritative');
    final incoming = rawAnnotations
        .map(collaborationAnnotationFromJson)
        .whereType<AnnotationRegion>()
        .map(
          (annotation) =>
              _withCollaborationAuthorFallback(annotation, sourceUserId),
        )
        .toList(growable: false);
    final imageKey = pathKey(_images[imageIndex].path);
    final incomingIds = {for (final item in incoming) item.id};
    final incomingAuthors = {
      for (final item in incoming)
        if (item.authorId.isNotEmpty) item.authorId,
    };
    setState(() {
      if (hasClassPayload) {
        _replaceLabelClassesFromCollaboration(nextClasses);
      }
      final annotations = _annotationsByImage.putIfAbsent(imageKey, () => []);
      if (authoritative) {
        annotations.removeWhere((item) => !incomingIds.contains(item.id));
      } else {
        final scopedAuthors = {
          ...incomingAuthors,
          if (authorScope.isNotEmpty) authorScope,
          if (authorScope.isEmpty && sourceUserId.isNotEmpty) sourceUserId,
        };
        annotations.removeWhere(
          (item) =>
              scopedAuthors.contains(item.authorId) &&
              !incomingIds.contains(item.id),
        );
      }
      for (final annotation in incoming) {
        final index = annotations.indexWhere(
          (item) => item.id == annotation.id,
        );
        if (index >= 0) {
          annotations[index] = annotation;
        } else {
          annotations.add(annotation);
        }
      }
    });
    unawaited(_saveCollaborationAnnotationDatabaseNow('annotation snapshot'));
    if (_collaborationMode == _CollaborationMode.host) {
      _sendCollaborationMessageToAuthorizedPeers(
        {
          ...message,
          'sourceUserId': fromUserId,
          'classes': _collaborationClassesPayload(),
        },
        imageIndex,
        excludeUserId: fromUserId,
      );
    }
  }

  void _upsertCollaborationPeer(_CollaborationPeer peer) {
    final index = _collaborationPeers.indexWhere(
      (item) => item.userId == peer.userId,
    );
    if (index >= 0) {
      _collaborationPeers[index] = _collaborationPeers[index].copyWith(
        userName: peer.userName,
        colorValue: peer.colorValue,
        address: peer.address,
        online: peer.online,
        assignmentStart: peer.assignmentStart,
        assignmentEnd: peer.assignmentEnd,
        permissions: peer.permissions,
      );
    } else {
      _collaborationPeers.add(peer);
    }
  }

  void _markCollaborationPeerOffline(String userId) {
    if (userId.isEmpty) {
      return;
    }
    setState(() {
      final index = _collaborationPeers.indexWhere(
        (peer) => peer.userId == userId,
      );
      if (index >= 0) {
        _collaborationPeers[index] = _collaborationPeers[index].copyWith(
          online: false,
        );
      }
    });
  }

  Future<void> _sendCollaborationCommand(Map<String, Object?> request) async {
    try {
      await RustBackend.collaborationCommand(request: request);
    } on Object catch (error) {
      _log(
        'COLLAB',
        'Command failed: ${request['action'] ?? '-'} $error',
        level: _LogLevel.warning,
      );
      if (mounted) {
        _showFloatingMessage(t('collab.networkError'));
      }
    }
  }

  void _sendCollaborationMessageToPeer(
    String userId,
    Map<String, Object?> message,
  ) {
    unawaited(
      _sendCollaborationCommand({
        'action': 'send_peer',
        'userId': userId,
        'message': jsonEncode(message),
      }),
    );
  }

  void _broadcastCollaborationMessage(Map<String, Object?> message) {
    if (_collaborationMode != _CollaborationMode.host) {
      return;
    }
    unawaited(
      _sendCollaborationCommand({
        'action': 'broadcast',
        'message': jsonEncode(message),
      }),
    );
  }

  void _broadcastCollaborationClassSnapshot(String reason) {
    if (_collaborationMode != _CollaborationMode.host) {
      return;
    }
    _broadcastCollaborationMessage(_collaborationClassSnapshotMessage());
    _log(
      'COLLAB',
      'Class snapshot broadcast: reason=$reason, classes=${_labelClasses.length}',
      level: _LogLevel.debug,
    );
  }

  void _broadcastCollaborationProjectSnapshot(String reason) {
    if (_collaborationMode != _CollaborationMode.host) {
      return;
    }
    var count = 0;
    for (final peer in _collaborationPeers) {
      if (!peer.online) {
        continue;
      }
      _sendCollaborationMessageToPeer(
        peer.userId,
        _collaborationProjectSnapshotMessage(
          assignmentStart: peer.assignmentStart,
          assignmentEnd: peer.assignmentEnd,
        ),
      );
      count += 1;
    }
    _log(
      'COLLAB',
      'Project snapshot broadcast: reason=$reason, peers=$count, images=${_images.length}',
      level: _LogLevel.debug,
    );
  }

  void _broadcastCollaborationAllAnnotations(String reason) {
    if (_collaborationMode != _CollaborationMode.host || _images.isEmpty) {
      return;
    }
    for (var index = 0; index < _images.length; index++) {
      final image = _images[index];
      _sendCollaborationMessageToAuthorizedPeers({
        'type': 'annotation_snapshot',
        'imagePath': image.path,
        'imageIndex': index + 1,
        'sourceUserId': _collaborationAuthorId,
        'authoritative': true,
        'classes': _collaborationClassesPayload(),
        'annotations': [
          for (final annotation in _annotationsForImagePath(image.path))
            _collaborationAnnotationToJson(annotation),
        ],
      }, index);
    }
    _log(
      'COLLAB',
      'Annotation snapshots broadcast: reason=$reason, images=${_images.length}',
      level: _LogLevel.debug,
    );
  }

  bool _collaborationPeerCanAccessImage(
    _CollaborationPeer peer,
    int zeroBasedIndex,
  ) {
    if (!peer.online || _images.isEmpty) {
      return false;
    }
    final start = peer.assignmentStart.clamp(1, _images.length).toInt();
    final end = peer.assignmentEnd.clamp(start, _images.length).toInt();
    final imageIndex = zeroBasedIndex + 1;
    return imageIndex >= start && imageIndex <= end;
  }

  void _sendCollaborationMessageToAuthorizedPeers(
    Map<String, Object?> message,
    int zeroBasedImageIndex, {
    String? excludeUserId,
  }) {
    if (_collaborationMode != _CollaborationMode.host) {
      return;
    }
    for (final peer in _collaborationPeers) {
      if (peer.userId == excludeUserId) {
        continue;
      }
      if (!_collaborationPeerCanAccessImage(peer, zeroBasedImageIndex)) {
        continue;
      }
      _sendCollaborationMessageToPeer(peer.userId, message);
    }
  }

  void _setCollaborationUserName(String value) {
    setState(() => _collaborationUserName = value.trim());
  }

  void _setCollaborationPort(int value) {
    setState(() => _collaborationPort = value);
    _restartCollaborationDiscovery();
  }

  void _startCollaborationHost() {
    if (_images.isEmpty) {
      _showFloatingMessage(t('collab.openProjectFirst'));
      return;
    }
    final imageCount = _images.length;
    setState(() {
      _collaborationMode = _CollaborationMode.host;
      _collaborationJoining = false;
      _collaborationPeers.clear();
      _collaborationStartIndex = 1;
      _collaborationEndIndex = math.max(1, imageCount);
    });
    unawaited(_startCollaborationHostNetwork(imageCount));
  }

  Future<void> _startCollaborationHostNetwork(int imageCount) async {
    try {
      await RustBackend.collaborationCommand(
        request: {
          'action': 'start_host',
          'hostId': _collaborationHostId,
          'hostName': _currentAnnotatorName,
          'userId': _collaborationAuthorId,
          'userName': _currentAnnotatorName,
          'port': _collaborationPort,
          'projectId': _databaseProjectKey(),
          'imageCount': imageCount,
        },
      );
      _log(
        'COLLAB',
        'Host mode enabled: hostId=$_collaborationHostId, port=$_collaborationPort',
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _collaborationMode = _CollaborationMode.off);
      _showFloatingMessage(t('collab.networkError'));
      _log('COLLAB', 'Host start failed: $error', level: _LogLevel.error);
      _restartCollaborationDiscovery();
    }
  }

  void _joinCollaborationHost() {
    if (_collaborationJoining) {
      return;
    }
    final selectedHost = _collaborationDiscoveredHosts
        .where((host) => host.hostId == _selectedCollaborationHostId)
        .firstOrNullValue;
    if (selectedHost == null) {
      _showFloatingMessage(t('collab.selectHostFirst'));
      return;
    }
    unawaited(_joinCollaborationHostNetwork(selectedHost));
  }

  Future<void> _joinCollaborationHostNetwork(
    _CollaborationDiscoveredHost selectedHost,
  ) async {
    setState(() => _collaborationJoining = true);
    try {
      _connectedCollaborationHost = selectedHost;
      await RustBackend.collaborationCommand(
        request: {
          'action': 'join_host',
          'hostId': selectedHost.hostId,
          'address': selectedHost.address,
          'port': selectedHost.port,
          'userId': _collaborationAuthorId,
          'userName': _currentAnnotatorName,
          'colorValue': _currentAnnotatorColorValue,
        },
      );
      if (!mounted) {
        return;
      }
      setState(() => _collaborationJoining = false);
      _log(
        'COLLAB',
        'Join request sent: user=$_currentAnnotatorLabel, host=${selectedHost.hostId}, address=${selectedHost.address}:${selectedHost.port}',
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      _connectedCollaborationHost = null;
      setState(() => _collaborationJoining = false);
      _showFloatingMessage(t('collab.networkError'));
      _log('COLLAB', 'Join failed: $error', level: _LogLevel.error);
      _restartCollaborationDiscovery();
    }
  }

  void _startCollaborationReconnect() {
    if (_collaborationReconnecting) {
      return;
    }
    final host = _connectedCollaborationHost;
    if (host == null) {
      _disconnectCollaborationClient(clearProject: true);
      return;
    }
    setState(() {
      _collaborationReconnecting = true;
      _collaborationReconnectAttempts = 0;
      _selectedAnnotationId = null;
    });
    _log(
      'COLLAB',
      'Host disconnected, reconnecting: host=${host.hostId}',
      level: _LogLevel.warning,
    );
    _scheduleCollaborationReconnectAttempt(immediate: true);
  }

  void _scheduleCollaborationReconnectAttempt({bool immediate = false}) {
    _collaborationReconnectTimer?.cancel();
    _collaborationReconnectTimer = Timer(
      immediate ? Duration.zero : const Duration(seconds: 3),
      _attemptCollaborationReconnect,
    );
  }

  Future<void> _attemptCollaborationReconnect() async {
    if (!_collaborationReconnecting) {
      return;
    }
    final host = _connectedCollaborationHost;
    if (host == null) {
      _disconnectCollaborationClient(clearProject: true);
      return;
    }
    if (_collaborationReconnectAttempts >= 5) {
      _showFloatingMessage(t('collab.reconnectFailed'));
      _disconnectCollaborationClient(clearProject: true);
      return;
    }
    setState(() => _collaborationReconnectAttempts += 1);
    try {
      await RustBackend.collaborationCommand(
        request: {
          'action': 'join_host',
          'hostId': host.hostId,
          'address': host.address,
          'port': host.port,
          'userId': _collaborationAuthorId,
          'userName': _currentAnnotatorName,
          'colorValue': _currentAnnotatorColorValue,
        },
      );
      _log(
        'COLLAB',
        'Reconnect attempt sent: $_collaborationReconnectAttempts/5',
        level: _LogLevel.warning,
      );
    } on Object catch (error) {
      _log(
        'COLLAB',
        'Reconnect attempt failed: $_collaborationReconnectAttempts/5, error=$error',
        level: _LogLevel.warning,
      );
    }
    if (_collaborationReconnecting) {
      _scheduleCollaborationReconnectAttempt();
    }
  }

  void _cancelCollaborationReconnect() {
    _showFloatingMessage(t('collab.reconnectCancelled'));
    _disconnectCollaborationClient(clearProject: true);
  }

  void _disconnectCollaborationClient({required bool clearProject}) {
    _collaborationReconnectTimer?.cancel();
    setState(() {
      _collaborationMode = _CollaborationMode.off;
      _collaborationJoining = false;
      _collaborationReconnecting = false;
      _collaborationReconnectAttempts = 0;
      _collaborationPeers.clear();
      _pendingCollaborationJoinRequests.clear();
      _selectedCollaborationHostId = null;
      _connectedCollaborationHost = null;
      _collaborationSelfPermissions = const _CollaborationPermissions();
      _selectedAnnotationId = null;
      if (clearProject) {
        _clearCurrentProjectState();
      }
    });
    unawaited(
      RustBackend.collaborationCommand(request: const {'action': 'stop'})
          .catchError((Object error) {
            _log(
              'COLLAB',
              'Client disconnect stop failed: $error',
              level: _LogLevel.debug,
            );
            return <String, dynamic>{};
          })
          .whenComplete(_restartCollaborationDiscovery),
    );
  }

  void _stopCollaboration() {
    final wasClient = _collaborationMode == _CollaborationMode.client;
    if (!wasClient) {
      _databaseSaveTimer?.cancel();
      unawaited(_saveAnnotationDatabaseNow());
    }
    setState(() {
      _collaborationMode = _CollaborationMode.off;
      _collaborationJoining = false;
      _collaborationReconnecting = false;
      _collaborationReconnectAttempts = 0;
      _collaborationPeers.clear();
      _selectedCollaborationHostId = null;
      _connectedCollaborationHost = null;
      _pendingCollaborationJoinRequests.clear();
      _selectedAnnotationId = null;
      if (wasClient) {
        _clearCurrentProjectState();
      }
    });
    _collaborationReconnectTimer?.cancel();
    unawaited(
      RustBackend.collaborationCommand(request: const {'action': 'stop'})
          .catchError((Object error) {
            _log('COLLAB', 'Stop failed: $error', level: _LogLevel.warning);
            return <String, dynamic>{};
          })
          .whenComplete(_restartCollaborationDiscovery),
    );
    _log('COLLAB', 'Collaboration stopped');
  }

  void _setCollaborationPeerPermissions(
    _CollaborationPeerPermissionResult result,
  ) {
    final max = math.max(1, _images.length);
    final assignmentStart = result.assignmentStart.clamp(1, max).toInt();
    final assignmentEnd = result.assignmentEnd
        .clamp(assignmentStart, max)
        .toInt();
    setState(() {
      final index = _collaborationPeers.indexWhere(
        (peer) => peer.userId == result.userId,
      );
      if (index >= 0) {
        _collaborationPeers[index] = _collaborationPeers[index].copyWith(
          assignmentStart: assignmentStart,
          assignmentEnd: assignmentEnd,
          permissions: result.permissions,
        );
      }
    });
    _log(
      'COLLAB',
      'Peer permissions updated: user=${result.userId}, assignment=$assignmentStart-$assignmentEnd, edit=${result.permissions.canEditOthers}, delete=${result.permissions.canDeleteOthers}, class=${result.permissions.canChangeClass}',
      level: _LogLevel.debug,
    );
    _sendCollaborationMessageToPeer(result.userId, {
      'type': 'permission_update',
      'assignmentStart': assignmentStart,
      'assignmentEnd': assignmentEnd,
      'permissions': {
        'canEditOthers': result.permissions.canEditOthers,
        'canDeleteOthers': result.permissions.canDeleteOthers,
        'canChangeClass': result.permissions.canChangeClass,
      },
    });
    _sendCollaborationMessageToPeer(
      result.userId,
      _collaborationProjectSnapshotMessage(
        assignmentStart: assignmentStart,
        assignmentEnd: assignmentEnd,
      ),
    );
    _scheduleAnnotationDatabaseSave();
  }
}
