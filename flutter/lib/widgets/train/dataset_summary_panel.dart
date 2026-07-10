import 'package:flutter/material.dart';

import '../../models/training.dart';
import '../../services/i18n.dart';
import '../../theme/theme_helpers.dart';

class DatasetSummaryPanel extends StatelessWidget {
  const DatasetSummaryPanel({required this.summary});

  final DatasetSummary? summary;

  @override
  Widget build(BuildContext context) {
    final summary = this.summary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: appPanelColor(
          Theme.of(context).brightness == Brightness.dark,
        ),
        border: Border.all(
          color: appBorderColor(
            Theme.of(context).brightness == Brightness.dark,
          ),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: summary == null
              ? Text(t('train.datasetSummaryEmpty'))
              : Wrap(
                  spacing: 18,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('${t('train.classes')}: ${summary.classes.length}'),
                    Text('${t('train.trainCount')}: ${summary.trainCount}'),
                    Text('${t('train.valCount')}: ${summary.valCount}'),
                    Text('${t('train.testCount')}: ${summary.testCount}'),
                    Text(
                      '${t('train.imbalanceRatio')}: ${summary.imbalanceRatio.toStringAsFixed(2)}',
                    ),
                    Text(
                      '${t('train.clsPwAuto')}: ${summary.recommendedClsPw.toStringAsFixed(2)}',
                    ),
                    if (summary.classes.isNotEmpty)
                      SizedBox(
                        width: 420,
                        child: Text(
                          summary.classes.join(', '),
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
