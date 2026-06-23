// =============================================================================
// CollaborationPage.dart - Team Annotation Collaboration / 团队协作标注
// =============================================================================
// Host/client collaboration control surface. The first implementation keeps
// local state and permission boundaries ready for the UDP/TCP transport.
//
// 主机/客户端协作控制界面。第一版先建立本地状态和权限边界，后续可直接接入
// UDP discovery and Rust TCP message transport.
// =============================================================================

// ignore_for_file: file_names

part of 'main.dart';

enum _CollaborationMode { off, host, client }

class _CollaborationPermissions {
  const _CollaborationPermissions({
    this.canEditOthers = false,
    this.canDeleteOthers = false,
    this.canChangeClass = false,
  });

  final bool canEditOthers;
  final bool canDeleteOthers;
  final bool canChangeClass;

  _CollaborationPermissions copyWith({
    bool? canEditOthers,
    bool? canDeleteOthers,
    bool? canChangeClass,
  }) {
    return _CollaborationPermissions(
      canEditOthers: canEditOthers ?? this.canEditOthers,
      canDeleteOthers: canDeleteOthers ?? this.canDeleteOthers,
      canChangeClass: canChangeClass ?? this.canChangeClass,
    );
  }
}

class _CollaborationPeer {
  const _CollaborationPeer({
    required this.userId,
    required this.userName,
    required this.address,
    required this.colorValue,
    required this.online,
    this.assignmentStart = 1,
    this.assignmentEnd = 1,
    this.permissions = const _CollaborationPermissions(),
  });

  final String userId;
  final String userName;
  final String address;
  final int colorValue;
  final bool online;
  final int assignmentStart;
  final int assignmentEnd;
  final _CollaborationPermissions permissions;

  _CollaborationPeer copyWith({
    String? userId,
    String? userName,
    String? address,
    int? colorValue,
    bool? online,
    int? assignmentStart,
    int? assignmentEnd,
    _CollaborationPermissions? permissions,
  }) {
    return _CollaborationPeer(
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

class _CollaborationPeerPermissionResult {
  const _CollaborationPeerPermissionResult({
    required this.userId,
    required this.permissions,
    required this.assignmentStart,
    required this.assignmentEnd,
  });

  final String userId;
  final _CollaborationPermissions permissions;
  final int assignmentStart;
  final int assignmentEnd;
}

class _CollaborationDiscoveredHost {
  const _CollaborationDiscoveredHost({
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

class _CollaborationPage extends StatelessWidget {
  const _CollaborationPage({
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

  final _CollaborationMode mode;
  final String hostId;
  final String userId;
  final String userName;
  final Color userColor;
  final int port;
  final int imageCount;
  final int assignmentStart;
  final int assignmentEnd;
  final List<_CollaborationDiscoveredHost> discoveredHosts;
  final String? selectedHostId;
  final bool joining;
  final List<_CollaborationPeer> peers;
  final ValueChanged<String> onUserNameChanged;
  final ValueChanged<int> onPortChanged;
  final ValueChanged<String?> onHostSelected;
  final VoidCallback onStartHost;
  final VoidCallback onJoinClient;
  final VoidCallback onStop;
  final ValueChanged<_CollaborationPeerPermissionResult>
  onPeerPermissionsChanged;

  bool get _active => mode != _CollaborationMode.off;

  bool get _canJoinSelectedHost =>
      mode == _CollaborationMode.off &&
      !joining &&
      selectedHostId != null &&
      discoveredHosts.any((host) => host.hostId == selectedHostId && host.online);

  @override
  Widget build(BuildContext context) {
    final canEditPeers = mode == _CollaborationMode.host;
    return SizedBox.expand(
      child: Container(
        color: _workspaceColor(context),
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: ListView(
                children: [
                  Text(
                    t('collab.title'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t('collab.subtitle'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _CollaborationCard(
                    title: t('collab.identity'),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 280,
                          child: TextFormField(
                            initialValue: userName,
                            decoration: InputDecoration(
                              labelText: t('collab.userName'),
                              isDense: true,
                            ),
                            onChanged: onUserNameChanged,
                          ),
                        ),
                        _CollaborationIdentityChip(
                          label: t('collab.hostId'),
                          value: hostId,
                          color: _collaborationColorForId(hostId),
                        ),
                        _CollaborationIdentityChip(
                          label: t('collab.userId'),
                          value: userId,
                          color: userColor,
                        ),
                        SizedBox(
                          width: 160,
                          child: TextFormField(
                            initialValue: '$port',
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: InputDecoration(
                              labelText: t('collab.port'),
                              isDense: true,
                            ),
                            onChanged: (value) {
                              final next = int.tryParse(value);
                              if (next != null && next > 0) {
                                onPortChanged(next);
                              }
                            },
                          ),
                        ),
                        _StatusPill(label: _modeLabel()),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _CollaborationCard(
                    title: t('collab.discovery'),
                    child: _DiscoveredHostsList(
                      hosts: discoveredHosts,
                      selectedHostId: selectedHostId,
                      onSelected: onHostSelected,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _CollaborationCard(
                    title: t('collab.hostControls'),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: mode == _CollaborationMode.host
                              ? null
                              : onStartHost,
                          icon: const Icon(Icons.cast_connected_outlined),
                          label: Text(t('collab.startHost')),
                        ),
                        OutlinedButton.icon(
                          onPressed: _canJoinSelectedHost
                              ? onJoinClient
                              : null,
                          icon: joining
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.login_outlined),
                          label: Text(
                            joining
                                ? t('collab.joiningHost')
                                : t('collab.joinHost'),
                          ),
                        ),
                        if (_active)
                          OutlinedButton.icon(
                            onPressed: onStop,
                            icon: const Icon(Icons.stop_circle_outlined),
                            label: Text(t('collab.stop')),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _CollaborationCard(
                    title: t('collab.assignment'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mode == _CollaborationMode.host
                              ? t('collab.assignmentPeerHint')
                              : t('collab.assignmentHint'),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        if (mode == _CollaborationMode.client)
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _StatusPill(
                                label: '${t('collab.startIndex')}: $assignmentStart',
                              ),
                              _StatusPill(
                                label: '${t('collab.endIndex')}: $assignmentEnd',
                              ),
                              _StatusPill(
                                label:
                                    '${t('collab.totalImages')}: $imageCount',
                              ),
                            ],
                          )
                        else
                          _StatusPill(
                            label: '${t('collab.totalImages')}: $imageCount',
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            SizedBox(
              width: 360,
              child: ListView(
                children: [
                  _CollaborationCard(
                    title: t('collab.connectedUsers'),
                    child: peers.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Center(child: Text(t('collab.noPeers'))),
                          )
                        : Column(
                            children: [
                              if (canEditPeers) ...[
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    t('collab.tapUserPermissions'),
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                              for (final peer in peers)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    Icons.circle,
                                    color: Color(peer.colorValue),
                                    size: 14,
                                  ),
                                  title: Text(
                                    '${peer.userName}#${_shortCollaborationId(peer.userId)}',
                                  ),
                                  subtitle: Text(
                                    '${peer.address}  ${peer.online ? t('collab.online') : t('collab.offline')}  ${t('collab.assignment')}: ${peer.assignmentStart}-${peer.assignmentEnd}',
                                  ),
                                  trailing: canEditPeers
                                      ? IconButton(
                                          tooltip: t('collab.permissions'),
                                          icon: const Icon(Icons.tune_outlined),
                                          onPressed: () =>
                                              _editPeerPermissions(
                                                context,
                                                peer,
                                              ),
                                        )
                                      : null,
                                  onTap: canEditPeers
                                      ? () => _editPeerPermissions(
                                          context,
                                          peer,
                                        )
                                      : null,
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _modeLabel() {
    return switch (mode) {
      _CollaborationMode.host => t('collab.modeHost'),
      _CollaborationMode.client => t('collab.modeClient'),
      _CollaborationMode.off => t('collab.modeOff'),
    };
  }

  Future<void> _editPeerPermissions(
    BuildContext context,
    _CollaborationPeer peer,
  ) async {
    if (mode != _CollaborationMode.host) {
      return;
    }
    final result = await showDialog<_CollaborationPeerPermissionResult>(
      context: context,
      builder: (context) => _CollaborationPeerPermissionDialog(
        peer: peer,
        imageCount: imageCount,
      ),
    );
    if (result == null) {
      return;
    }
    onPeerPermissionsChanged(
      _CollaborationPeerPermissionResult(
        userId: peer.userId,
        permissions: result.permissions,
        assignmentStart: result.assignmentStart,
        assignmentEnd: result.assignmentEnd,
      ),
    );
  }
}

class _CollaborationCard extends StatelessWidget {
  const _CollaborationCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _panelColor(context),
        border: Border.all(color: _borderColor(context)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _CollaborationIdentityChip extends StatelessWidget {
  const _CollaborationIdentityChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _controlColor(context),
          border: Border.all(color: _borderColor(context)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '$label: $value',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollaborationPeerPermissionDialog extends StatefulWidget {
  const _CollaborationPeerPermissionDialog({
    required this.peer,
    required this.imageCount,
  });

  final _CollaborationPeer peer;
  final int imageCount;

  @override
  State<_CollaborationPeerPermissionDialog> createState() =>
      _CollaborationPeerPermissionDialogState();
}

class _CollaborationPeerPermissionDialogState
    extends State<_CollaborationPeerPermissionDialog> {
  late _CollaborationPermissions _permissions = widget.peer.permissions;
  late int _assignmentStart = widget.peer.assignmentStart;
  late int _assignmentEnd = widget.peer.assignmentEnd;

  @override
  Widget build(BuildContext context) {
    final peer = widget.peer;
    final maxImageCount = math.max(1, widget.imageCount);
    return AlertDialog(
      title: Text(t('collab.peerPermissions')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Color(peer.colorValue),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${peer.userName}#${_shortCollaborationId(peer.userId)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              t('collab.permissionsHint'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text(
              t('collab.assignment'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _CollaborationIndexField(
                    label: t('collab.startIndex'),
                    value: _assignmentStart.clamp(1, maxImageCount).toInt(),
                    maxValue: maxImageCount,
                    onChanged: (value) => setState(() {
                      _assignmentStart = value.clamp(1, maxImageCount).toInt();
                      if (_assignmentEnd < _assignmentStart) {
                        _assignmentEnd = _assignmentStart;
                      }
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CollaborationIndexField(
                    label: t('collab.endIndex'),
                    value: _assignmentEnd.clamp(1, maxImageCount).toInt(),
                    maxValue: maxImageCount,
                    onChanged: (value) => setState(() {
                      _assignmentEnd = value
                          .clamp(_assignmentStart, maxImageCount)
                          .toInt();
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              t('collab.permissions'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _CollaborationSwitch(
              title: t('collab.canEditOthers'),
              value: _permissions.canEditOthers,
              onChanged: (value) => setState(
                () => _permissions = _permissions.copyWith(
                  canEditOthers: value,
                ),
              ),
            ),
            _CollaborationSwitch(
              title: t('collab.canDeleteOthers'),
              value: _permissions.canDeleteOthers,
              onChanged: (value) => setState(
                () => _permissions = _permissions.copyWith(
                  canDeleteOthers: value,
                ),
              ),
            ),
            _CollaborationSwitch(
              title: t('collab.canChangeClass'),
              value: _permissions.canChangeClass,
              onChanged: (value) => setState(
                () => _permissions = _permissions.copyWith(
                  canChangeClass: value,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t('action.cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _CollaborationPeerPermissionResult(
              userId: peer.userId,
              permissions: _permissions,
              assignmentStart: _assignmentStart
                  .clamp(1, maxImageCount)
                  .toInt(),
              assignmentEnd: _assignmentEnd
                  .clamp(_assignmentStart, maxImageCount)
                  .toInt(),
            ),
          ),
          child: Text(t('action.save')),
        ),
      ],
    );
  }
}

class _DiscoveredHostsList extends StatelessWidget {
  const _DiscoveredHostsList({
    required this.hosts,
    required this.selectedHostId,
    required this.onSelected,
  });

  final List<_CollaborationDiscoveredHost> hosts;
  final String? selectedHostId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    if (hosts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('collab.noHosts')),
            const SizedBox(height: 8),
            Text(
              t('collab.discoveryHint'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            t('collab.selectHostHint'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 8),
        for (final host in hosts)
          RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            value: host.hostId,
            groupValue: selectedHostId,
            onChanged: host.online ? onSelected : null,
            title: Text(
              '${host.hostName}#${_shortCollaborationId(host.hostId)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text('${host.address}:${host.port}'),
            secondary: Icon(
              Icons.circle,
              size: 12,
              color: host.online
                  ? _collaborationColorForId(host.hostId)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _CollaborationIndexField extends StatelessWidget {
  const _CollaborationIndexField({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int maxValue;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: '$value',
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, isDense: true),
      onChanged: (raw) {
        final parsed = int.tryParse(raw);
        if (parsed == null) {
          return;
        }
        final max = math.max(1, maxValue);
        onChanged(parsed.clamp(1, max).toInt());
      },
    );
  }
}

class _CollaborationSwitch extends StatelessWidget {
  const _CollaborationSwitch({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      value: value,
      onChanged: onChanged,
    );
  }
}
