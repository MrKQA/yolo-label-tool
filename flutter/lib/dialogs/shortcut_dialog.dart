import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/shortcut.dart';
import '../services/i18n.dart';

class ShortcutSettingsDialog extends StatefulWidget {
  const ShortcutSettingsDialog({
    required this.config,
    required this.onShortcutChanged,
    required this.onReset,
  });

  final ShortcutConfig config;
  final void Function(ShortcutAction action, LogicalKeyboardKey key)
  onShortcutChanged;
  final VoidCallback onReset;

  @override
  State<ShortcutSettingsDialog> createState() =>
      _ShortcutSettingsDialogState();
}

class _ShortcutSettingsDialogState extends State<ShortcutSettingsDialog> {
  final FocusNode _captureFocusNode = FocusNode(debugLabel: 'shortcut-capture');
  late ShortcutConfig _currentConfig;
  ShortcutAction? _waitingAction;

  @override
  void initState() {
    super.initState();
    _currentConfig = widget.config;
  }

  @override
  void dispose() {
    _captureFocusNode.dispose();
    super.dispose();
  }

  KeyEventResult _captureKey(FocusNode node, KeyEvent event) {
    final action = _waitingAction;
    if (event is! KeyDownEvent || action == null) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _waitingAction = null);
      return KeyEventResult.handled;
    }

    widget.onShortcutChanged(action, event.logicalKey);
    setState(() {
      _currentConfig = _currentConfig.copyWith(
        action: action,
        key: event.logicalKey,
      );
      _waitingAction = null;
    });
    return KeyEventResult.handled;
  }

  void _startCapture(ShortcutAction action) {
    setState(() => _waitingAction = action);
    _captureFocusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _captureFocusNode.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = _currentConfig;
    const scopes = ShortcutScope.values;

    return AlertDialog(
      title: Text(t('shortcut.title')),
      content: Focus(
        focusNode: _captureFocusNode,
        autofocus: true,
        onKeyEvent: _captureKey,
        child: SizedBox(
          width: 480,
          height: 520,
          child: DefaultTabController(
            length: scopes.length,
            child: Column(
              children: [
                TabBar(
                  isScrollable: true,
                  tabs: [
                    for (final scope in scopes) Tab(text: t(scope.labelKey)),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TabBarView(
                    children: [
                      for (final scope in scopes)
                        _ShortcutScopePane(
                          scope: scope,
                          config: config,
                          waitingAction: _waitingAction,
                          onPressed: _startCapture,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(t('shortcut.note')),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onReset();
            setState(() {
              _currentConfig = ShortcutConfig.defaults();
              _waitingAction = null;
            });
          },
          child: Text(t('action.reset')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t('action.close')),
        ),
      ],
    );
  }
}

class _ShortcutScopePane extends StatelessWidget {
  const _ShortcutScopePane({
    required this.scope,
    required this.config,
    required this.waitingAction,
    required this.onPressed,
  });

  final ShortcutScope scope;
  final ShortcutConfig config;
  final ShortcutAction? waitingAction;
  final ValueChanged<ShortcutAction> onPressed;

  @override
  Widget build(BuildContext context) {
    final actions = [
      for (final action in ShortcutAction.values)
        if (action.scope == scope) action,
    ];
    if (actions.isEmpty) {
      return Center(child: Text(t('shortcut.noItems')));
    }
    final normalActions = actions.where((action) => !action.isAiAction);
    final aiActions = actions.where((action) => action.isAiAction);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (normalActions.isNotEmpty) ...[
            _ShortcutSectionTitle(title: t('shortcut.normalGroup')),
            for (final action in normalActions)
              _ShortcutEditRow(
                action: action,
                label: t(action.labelKey),
                shortcut: config.binding(action).displayLabel,
                waiting: waitingAction == action,
                onPressed: onPressed,
              ),
          ],
          if (aiActions.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ShortcutSectionTitle(title: t('shortcut.aiGroup')),
            for (final action in aiActions)
              _ShortcutEditRow(
                action: action,
                label: t(action.labelKey),
                shortcut: config.binding(action).displayLabel,
                waiting: waitingAction == action,
                onPressed: onPressed,
              ),
          ],
        ],
      ),
    );
  }
}

class _ShortcutSectionTitle extends StatelessWidget {
  const _ShortcutSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      ),
    );
  }
}

class _ShortcutEditRow extends StatelessWidget {
  const _ShortcutEditRow({
    required this.action,
    required this.label,
    required this.shortcut,
    required this.waiting,
    required this.onPressed,
  });

  final ShortcutAction action;
  final String label;
  final String shortcut;
  final bool waiting;
  final ValueChanged<ShortcutAction> onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          SizedBox(
            width: 136,
            child: OutlinedButton(
              onPressed: () => onPressed(action),
              child: Text(
                waiting ? t('shortcut.waiting') : shortcut,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
