part of '../main.dart';

void _showTrainingHistoryRecordsDialog({
  required BuildContext context,
  required VoidCallback onEmpty,
}) {
  final history = _ConfigStore.loadTrainingHistory().entries;
  if (history.isEmpty) {
    onEmpty();
    return;
  }
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
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
                  entry.action == _TrainingHistoryAction.stop
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline,
                ),
                title: Text(
                  '${_trainingActionLabel(entry.action)}  '
                  '${entry.epoch}/${entry.targetEpochs}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${t('train.historyTimePoint')}: '
                  '${_formatTrainingHistoryTime(entry.timestamp)}\n'
                  '${t('path.model')}: ${_fileName(entry.modelPath)}\n'
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
  );
}
