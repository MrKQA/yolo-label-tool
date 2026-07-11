enum CollaborationMode { off, host, client }

class CollaborationPermissions {
  const CollaborationPermissions({
    this.canEditOthers = false,
    this.canDeleteOthers = false,
    this.canChangeClass = false,
  });

  final bool canEditOthers;
  final bool canDeleteOthers;
  final bool canChangeClass;

  CollaborationPermissions copyWith({
    bool? canEditOthers,
    bool? canDeleteOthers,
    bool? canChangeClass,
  }) {
    return CollaborationPermissions(
      canEditOthers: canEditOthers ?? this.canEditOthers,
      canDeleteOthers: canDeleteOthers ?? this.canDeleteOthers,
      canChangeClass: canChangeClass ?? this.canChangeClass,
    );
  }
}

class CollaborationPeer {
  const CollaborationPeer({
    required this.userId,
    required this.userName,
    required this.address,
    required this.colorValue,
    required this.online,
    this.assignmentStart = 1,
    this.assignmentEnd = 1,
    this.permissions = const CollaborationPermissions(),
  });

  final String userId;
  final String userName;
  final String address;
  final int colorValue;
  final bool online;
  final int assignmentStart;
  final int assignmentEnd;
  final CollaborationPermissions permissions;

  CollaborationPeer copyWith({
    String? userId,
    String? userName,
    String? address,
    int? colorValue,
    bool? online,
    int? assignmentStart,
    int? assignmentEnd,
    CollaborationPermissions? permissions,
  }) {
    return CollaborationPeer(
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      address: address ?? this.address,
      colorValue: colorValue ?? this.colorValue,
      online: online ?? this.online,
      assignmentStart: assignmentStart ?? this.assignmentStart,
      assignmentEnd: assignmentEnd ?? this.assignmentEnd,
      permissions: permissions ?? this.permissions,
    );
  }
}

class CollaborationPeerPermissionResult {
  const CollaborationPeerPermissionResult({
    required this.userId,
    required this.permissions,
    required this.assignmentStart,
    required this.assignmentEnd,
  });

  final String userId;
  final CollaborationPermissions permissions;
  final int assignmentStart;
  final int assignmentEnd;
}

class CollaborationDiscoveredHost {
  const CollaborationDiscoveredHost({
    required this.hostId,
    required this.hostName,
    required this.address,
    required this.port,
    required this.online,
  });

  final String hostId;
  final String hostName;
  final String address;
  final int port;
  final bool online;
}
