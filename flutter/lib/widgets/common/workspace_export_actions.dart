import 'package:flutter/material.dart';

import '../../controllers/export_controller.dart';
import '../../controllers/project_controller.dart';
import '../../controllers/workspace_settings_controller.dart';
import '../../dialogs/export_dialog.dart';
import '../../models/export.dart';
import '../../services/i18n.dart';

/// Owns the export dialog flow; ExportController performs the actual work.
class WorkspaceExportActions {
  const WorkspaceExportActions({
    required this.export,
    required this.project,
    required this.settings,
    required this.context,
    required this.mounted,
    required this.showMessage,
  });

  final ExportController export;
  final ProjectController project;
  final WorkspaceSettingsController settings;
  final BuildContext Function() context;
  final bool Function() mounted;
  final ValueChanged<String> showMessage;

  Future<void> showExportDialog() async {
    final config = await showDialog<DatasetExportConfig>(
      context: context(),
      builder: (context) =>
          ExportDialog(exportPath: settings.settings.exportPath),
    );
    if (config == null || !mounted()) return;

    var overwriteImported = false;
    if (project.importedDataset != null) {
      final overwrite = await showOverwriteImportedDatasetDialog(context());
      if (overwrite == null || !mounted()) return;
      overwriteImported = overwrite;
    }

    DatasetExportWorkflowResult workflow;
    try {
      workflow = await export.exportDataset(
        config: config,
        exportRoot: settings.settings.exportPath,
        overwriteImported: overwriteImported,
        displaySizeForImagePath: project.displaySizeForPath,
        ensureDisplaySizeForImagePath: project.ensureDisplaySizeForPath,
      );
    } on Object catch (error) {
      if (mounted()) {
        showMessage('${t('export.failed')}: $error');
      }
      return;
    }
    if (!mounted()) return;
    final result = workflow.result;
    if (result == null) {
      showMessage(t('export.noData'));
      return;
    }
    showMessage(
      workflow.mode == DatasetExportMode.overwriteImported
          ? t('export.done')
          : '${t('export.done')} (${t('export.folderName')}: ${config.folderName})',
    );
    if (config.trainAfterExport) {
      await export.startTrainingAfterExport(result.dataYamlPath);
    }
  }
}
