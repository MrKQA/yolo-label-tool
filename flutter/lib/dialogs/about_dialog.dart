// =============================================================================
// about_dialog.dart - About Dialog / 关于对话框
// =============================================================================
// Displays version info, license (GPLv3), open-source purpose, and compliance
// warning for the YOLO Label Tool.
//
// 显示 YOLO Label Tool 的版本、LICENSE、开源初衷和侵权合规警告。
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/i18n.dart';
import 'dialog_shortcuts.dart';

const _projectRepositoryUrl = 'https://github.com/MrKQA/yolo-label-tool';

Future<void> _openProjectRepository(BuildContext context) async {
  try {
    if (Platform.isWindows) {
      await Process.start('explorer.exe', [
        _projectRepositoryUrl,
      ], mode: ProcessStartMode.detached);
      return;
    }
    if (Platform.isMacOS) {
      await Process.start('open', [
        _projectRepositoryUrl,
      ], mode: ProcessStartMode.detached);
      return;
    }
    if (Platform.isLinux) {
      await Process.start('xdg-open', [
        _projectRepositoryUrl,
      ], mode: ProcessStartMode.detached);
      return;
    }
    throw UnsupportedError('Unsupported platform');
  } on Object {
    await Clipboard.setData(const ClipboardData(text: _projectRepositoryUrl));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(t('about.repositoryCopied'))));
  }
}

Future<void> showAboutDialogForContext(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      Widget section(String titleKey, String bodyKey) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titleKey, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Text(t(bodyKey), style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        );
      }

      return DialogCancelAction(
        child: AlertDialog(
          title: Text(t('about.title')),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t('about.version'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  section(t('about.licenseTitle'), 'about.licenseBody'),
                  section(t('about.opensourceTitle'), 'about.opensourceBody'),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('about.repositoryTitle'),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          t('about.repositoryBody'),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 6),
                        TextButton.icon(
                          onPressed: () => _openProjectRepository(context),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('MrKQA/yolo-label-tool'),
                        ),
                      ],
                    ),
                  ),
                  section(t('about.warningTitle'), 'about.warningBody'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t('action.close')),
            ),
          ],
        ),
      );
    },
  );
}
