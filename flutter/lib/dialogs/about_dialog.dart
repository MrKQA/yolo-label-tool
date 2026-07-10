import 'package:flutter/material.dart';

import '../services/i18n.dart';

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

      return AlertDialog(
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
      );
    },
  );
}
