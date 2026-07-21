// =============================================================================
// training_history_dialog.dart - Training History Dialog / 训练历史对话框
// =============================================================================
// Displays recent training actions (start, resume, stop) with timestamps,
// model paths, dataset paths, and epoch ranges.
//
// 显示最近的训练操作记录（启动、继续、停止），含时间戳、模型路径、数据集路径和 epoch。
// =============================================================================

import 'package:flutter/material.dart';

import '../models/training.dart';
import '../services/i18n.dart';
import '../services/path_utils.dart';
import '../widgets/train/train_runtime_support.dart';
import 'dialog_shortcuts.dart';

void showTrainingHistoryRecordsDialog({
  required BuildContext context,
  required List<TrainingHistoryEntry> history,
  required VoidCallback onEmpty,
}) {
  if (history.isEmpty) {
    onEmpty();
    return;
  }
  showDialog<void>(
    context: context,
    builder: (context) => DialogCancelAction(
      child: AlertDialog(
        title: Text(t('menu.trainingHistory')),
        content: SizedBox(
          width: 560,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: history.length,
            itemBuilder: (context, index) {
              final entry = history[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    entry.action == TrainingHistoryAction.stop
                        ? Icons.stop_circle_outlined
                        : Icons.play_circle_outline,
                  ),
                  title: Text(
                    '${trainingActionLabel(entry.action)}  '
                    '${entry.epoch}/${entry.targetEpochs}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${t('train.historyTimePoint')}: '
                    '${formatTrainingHistoryTime(entry.timestamp)}\n'
                    '${t('path.model')}: ${fileName(entry.modelPath)}\n'
                    '${t('train.datasetPath')}: ${entry.datasetPath}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('action.close')),
          ),
        ],
      ),
    ),
  );
}
