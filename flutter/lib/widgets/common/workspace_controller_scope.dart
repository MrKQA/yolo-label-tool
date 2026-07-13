import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../controllers/ai_annotation_controller.dart';
import '../../controllers/ai_workspace_controller.dart';
import '../../controllers/annotation_database_controller.dart';
import '../../controllers/annotation_editing_controller.dart';
import '../../controllers/collaboration_controller.dart';
import '../../controllers/collaboration_sync_controller.dart';
import '../../controllers/collaboration_workspace_controller.dart';
import '../../controllers/export_controller.dart';
import '../../controllers/project_controller.dart';
import '../../controllers/workspace_navigation_controller.dart';
import '../../controllers/workspace_settings_controller.dart';
import '../../controllers/workspace_viewport_controller.dart';
import 'workspace_ai_actions.dart';
import 'workspace_annotation_actions.dart';
import 'workspace_collaboration_actions.dart';
import 'workspace_export_actions.dart';
import 'workspace_project_actions.dart';
import 'workspace_settings_actions.dart';

/// Makes the long-lived workspace controllers available without transferring
/// ownership. WorkspaceShell remains responsible for their lifecycle.
class WorkspaceControllerScope extends StatelessWidget {
  const WorkspaceControllerScope({
    super.key,
    required this.project,
    required this.annotationDatabase,
    required this.annotationEditing,
    required this.collaboration,
    required this.collaborationSync,
    required this.collaborationWorkspace,
    required this.ai,
    required this.aiWorkspace,
    required this.export,
    required this.navigation,
    required this.settings,
    required this.viewport,
    required this.aiActions,
    required this.annotationActions,
    required this.collaborationActions,
    required this.exportActions,
    required this.projectActions,
    required this.settingsActions,
    required this.child,
  });

  final ProjectController project;
  final AnnotationDatabaseController annotationDatabase;
  final AnnotationEditingController annotationEditing;
  final CollaborationController collaboration;
  final CollaborationSyncController collaborationSync;
  final CollaborationWorkspaceController collaborationWorkspace;
  final AiAnnotationController ai;
  final AiWorkspaceController aiWorkspace;
  final ExportController export;
  final WorkspaceNavigationController navigation;
  final WorkspaceSettingsController settings;
  final WorkspaceViewportController viewport;
  final WorkspaceAiActions aiActions;
  final WorkspaceAnnotationActions annotationActions;
  final WorkspaceCollaborationActions collaborationActions;
  final WorkspaceExportActions exportActions;
  final WorkspaceProjectActions projectActions;
  final WorkspaceSettingsActions settingsActions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: project),
        Provider.value(value: annotationDatabase),
        Provider.value(value: annotationEditing),
        ChangeNotifierProvider.value(value: collaboration),
        Provider.value(value: collaborationSync),
        Provider.value(value: collaborationWorkspace),
        ChangeNotifierProvider.value(value: ai),
        Provider.value(value: aiWorkspace),
        Provider.value(value: export),
        ChangeNotifierProvider.value(value: navigation),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: viewport),
        Provider.value(value: aiActions),
        Provider.value(value: annotationActions),
        Provider.value(value: collaborationActions),
        Provider.value(value: exportActions),
        ChangeNotifierProvider.value(value: projectActions),
        Provider.value(value: settingsActions),
      ],
      child: child,
    );
  }
}
