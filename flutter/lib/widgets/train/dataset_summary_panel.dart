// =============================================================================
// dataset_summary_panel.dart - Dataset Summary Panel / 数据集摘要面板
// =============================================================================
// Displays class count, train/val/test image counts, class imbalance ratio,
// recommended cls_pw, and the class name list for the loaded YOLO dataset.
//
// 显示当前 YOLO 数据集的类别数、各 split 图片数、不均衡比、cls_pw 和类别名。
// =============================================================================

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
