import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../models/annotation.dart';
import '../models/shortcut.dart';

class WorkspaceNavigationController extends ChangeNotifier {
  String _activeSection = 'label';
  String _activeTool = 'select';
  bool _sidebarCollapsed = false;
  bool _showClassLabels = true;
  AnnotationMode _annotationMode = AnnotationMode.hbb;

  String get activeSection => _activeSection;
  set activeSection(String value) {
    if (_activeSection == value) return;
    _activeSection = value;
    notifyListeners();
  }

  String get activeTool => _activeTool;
  set activeTool(String value) {
    if (_activeTool == value) return;
    _activeTool = value;
    notifyListeners();
  }

  bool get sidebarCollapsed => _sidebarCollapsed;
  set sidebarCollapsed(bool value) {
    if (_sidebarCollapsed == value) return;
    _sidebarCollapsed = value;
    notifyListeners();
  }

  bool get showClassLabels => _showClassLabels;
  set showClassLabels(bool value) {
    if (_showClassLabels == value) return;
    _showClassLabels = value;
    notifyListeners();
  }

  AnnotationMode get annotationMode => _annotationMode;

  int get pageIndex => switch (activeSection) {
    'label' => 0,
    'train' => 1,
    'crop' => 2,
    'collaboration' => 3,
    'database' => 5,
    _ => 4,
  };

  void activateAnnotationMode(AnnotationMode mode) {
    final changed = _annotationMode != mode || _activeTool != 'draw';
    _annotationMode = mode;
    _activeTool = 'draw';
    if (changed) notifyListeners();
  }

  void cancelSelection() {
    activeTool = 'select';
  }
}

enum WorkspaceShortcutCommand {
  ignored,
  consume,
  delegateBrowse,
  undo,
  redo,
  copy,
  paste,
  cancelSelection,
  previousImage,
  nextImage,
  zoomIn,
  zoomOut,
  toggleZoomLock,
  resetLabelView,
  importDataset,
  exportDataset,
  hbbMode,
  obbMode,
  segMode,
  deleteSelected,
  toggleClassLabels,
  rotateObb,
  aiAnnotateCurrent,
  aiAnnotateAll,
  trainStart,
  trainStop,
  trainChooseModel,
  trainChooseDataset,
  trainExport,
}

class WorkspaceShortcutDecision {
  const WorkspaceShortcutDecision(
    this.command, {
    this.imageStep = 1,
    this.rotationDegrees = 0,
  });

  static const ignored = WorkspaceShortcutDecision(
    WorkspaceShortcutCommand.ignored,
  );

  final WorkspaceShortcutCommand command;
  final int imageStep;
  final double rotationDegrees;
}

class WorkspaceShortcutResolver {
  const WorkspaceShortcutResolver();

  WorkspaceShortcutDecision resolve({
    required KeyEvent event,
    required ShortcutConfig config,
    required String activeSection,
    required bool shortcutDialogOpen,
    required bool inputBlocked,
    required bool editableTextFocused,
    required bool controlPressed,
  }) {
    final keyDown = event is KeyDownEvent || event is KeyRepeatEvent;
    if (inputBlocked) {
      return keyDown
          ? const WorkspaceShortcutDecision(WorkspaceShortcutCommand.consume)
          : WorkspaceShortcutDecision.ignored;
    }
    if (editableTextFocused || shortcutDialogOpen) {
      return WorkspaceShortcutDecision.ignored;
    }
    if (!keyDown) {
      return WorkspaceShortcutDecision.ignored;
    }

    final key = event.logicalKey;
    if (event is KeyDownEvent &&
        config.matches(ShortcutAction.dialogCancel, key)) {
      return const WorkspaceShortcutDecision(
        WorkspaceShortcutCommand.cancelSelection,
      );
    }
    if (activeSection == 'browse') {
      return const WorkspaceShortcutDecision(
        WorkspaceShortcutCommand.delegateBrowse,
      );
    }
    if (activeSection == 'train') {
      if (event is! KeyDownEvent) {
        return WorkspaceShortcutDecision.ignored;
      }
      if (config.matches(ShortcutAction.trainStart, key)) {
        return const WorkspaceShortcutDecision(
          WorkspaceShortcutCommand.trainStart,
        );
      }
      if (config.matches(ShortcutAction.trainStop, key)) {
        return const WorkspaceShortcutDecision(
          WorkspaceShortcutCommand.trainStop,
        );
      }
      if (config.matches(ShortcutAction.trainChooseModel, key)) {
        return const WorkspaceShortcutDecision(
          WorkspaceShortcutCommand.trainChooseModel,
        );
      }
      if (config.matches(ShortcutAction.trainChooseDataset, key)) {
        return const WorkspaceShortcutDecision(
          WorkspaceShortcutCommand.trainChooseDataset,
        );
      }
      if (config.matches(ShortcutAction.trainExport, key)) {
        return const WorkspaceShortcutDecision(
          WorkspaceShortcutCommand.trainExport,
        );
      }
      return WorkspaceShortcutDecision.ignored;
    }
    if (activeSection != 'label') {
      return WorkspaceShortcutDecision.ignored;
    }
    if (controlPressed) {
      if (key == LogicalKeyboardKey.keyZ) {
        return const WorkspaceShortcutDecision(WorkspaceShortcutCommand.undo);
      }
      if (key == LogicalKeyboardKey.keyY) {
        return const WorkspaceShortcutDecision(WorkspaceShortcutCommand.redo);
      }
      if (key == LogicalKeyboardKey.keyC) {
        return const WorkspaceShortcutDecision(WorkspaceShortcutCommand.copy);
      }
      if (key == LogicalKeyboardKey.keyV) {
        return const WorkspaceShortcutDecision(WorkspaceShortcutCommand.paste);
      }
    }
    final imageStep = event is KeyRepeatEvent ? 3 : 1;
    if (config.matches(ShortcutAction.previousImage, key)) {
      return WorkspaceShortcutDecision(
        WorkspaceShortcutCommand.previousImage,
        imageStep: imageStep,
      );
    }
    if (config.matches(ShortcutAction.nextImage, key)) {
      return WorkspaceShortcutDecision(
        WorkspaceShortcutCommand.nextImage,
        imageStep: imageStep,
      );
    }
    if (config.matches(ShortcutAction.zoomIn, key)) {
      return const WorkspaceShortcutDecision(WorkspaceShortcutCommand.zoomIn);
    }
    if (config.matches(ShortcutAction.zoomOut, key)) {
      return const WorkspaceShortcutDecision(WorkspaceShortcutCommand.zoomOut);
    }
    if (event is KeyDownEvent &&
        config.matches(ShortcutAction.toggleZoomLock, key)) {
      return const WorkspaceShortcutDecision(
        WorkspaceShortcutCommand.toggleZoomLock,
      );
    }
    if (event is KeyDownEvent &&
        config.matches(ShortcutAction.resetLabelView, key)) {
      return const WorkspaceShortcutDecision(
        WorkspaceShortcutCommand.resetLabelView,
      );
    }
    if (event is KeyDownEvent &&
        config.matches(ShortcutAction.importDataset, key)) {
      return const WorkspaceShortcutDecision(
        WorkspaceShortcutCommand.importDataset,
      );
    }
    if (event is KeyDownEvent &&
        config.matches(ShortcutAction.exportDataset, key)) {
      return const WorkspaceShortcutDecision(
        WorkspaceShortcutCommand.exportDataset,
      );
    }
    if (config.matches(ShortcutAction.hbbMode, key)) {
      return const WorkspaceShortcutDecision(WorkspaceShortcutCommand.hbbMode);
    }
    if (config.matches(ShortcutAction.obbMode, key)) {
      return const WorkspaceShortcutDecision(WorkspaceShortcutCommand.obbMode);
    }
    if (config.matches(ShortcutAction.segMode, key)) {
      return const WorkspaceShortcutDecision(WorkspaceShortcutCommand.segMode);
    }
    if (config.matches(ShortcutAction.deleteSelected, key)) {
      return const WorkspaceShortcutDecision(
        WorkspaceShortcutCommand.deleteSelected,
      );
    }
    if (config.matches(ShortcutAction.hideClassLabels, key)) {
      return const WorkspaceShortcutDecision(
        WorkspaceShortcutCommand.toggleClassLabels,
      );
    }
    if (config.matches(ShortcutAction.rotateObbLeft5, key)) {
      return const WorkspaceShortcutDecision(
        WorkspaceShortcutCommand.rotateObb,
        rotationDegrees: -5,
      );
    }
    if (config.matches(ShortcutAction.rotateObbLeft1, key)) {
      return const WorkspaceShortcutDecision(
        WorkspaceShortcutCommand.rotateObb,
        rotationDegrees: -1,
      );
    }
    if (config.matches(ShortcutAction.rotateObbRight1, key)) {
      return const WorkspaceShortcutDecision(
        WorkspaceShortcutCommand.rotateObb,
        rotationDegrees: 1,
      );
    }
    if (config.matches(ShortcutAction.rotateObbRight5, key)) {
      return const WorkspaceShortcutDecision(
        WorkspaceShortcutCommand.rotateObb,
        rotationDegrees: 5,
      );
    }
    if (config.matches(ShortcutAction.aiAnnotateCurrent, key)) {
      return const WorkspaceShortcutDecision(
        WorkspaceShortcutCommand.aiAnnotateCurrent,
      );
    }
    if (config.matches(ShortcutAction.aiAnnotateAll, key)) {
      return const WorkspaceShortcutDecision(
        WorkspaceShortcutCommand.aiAnnotateAll,
      );
    }
    return WorkspaceShortcutDecision.ignored;
  }
}

class WorkspaceShortcutActions {
  const WorkspaceShortcutActions({
    required this.delegateBrowse,
    required this.undo,
    required this.redo,
    required this.copy,
    required this.paste,
    required this.cancelSelection,
    required this.previousImage,
    required this.nextImage,
    required this.onNoPreviousImage,
    required this.onNoNextImage,
    required this.adjustZoom,
    required this.toggleZoomLock,
    required this.resetLabelView,
    required this.importDataset,
    required this.exportDataset,
    required this.activateMode,
    required this.deleteSelected,
    required this.toggleClassLabels,
    required this.rotateObb,
    required this.aiAnnotateCurrent,
    required this.aiAnnotateAll,
    required this.trainStart,
    required this.trainStop,
    required this.trainChooseModel,
    required this.trainChooseDataset,
    required this.trainExport,
  });

  final KeyEventResult Function(KeyEvent event) delegateBrowse;
  final VoidCallback undo;
  final VoidCallback redo;
  final VoidCallback copy;
  final VoidCallback paste;
  final VoidCallback cancelSelection;
  final bool Function(int step) previousImage;
  final bool Function(int step) nextImage;
  final VoidCallback onNoPreviousImage;
  final VoidCallback onNoNextImage;
  final ValueChanged<double> adjustZoom;
  final VoidCallback toggleZoomLock;
  final VoidCallback resetLabelView;
  final VoidCallback importDataset;
  final VoidCallback exportDataset;
  final ValueChanged<AnnotationMode> activateMode;
  final VoidCallback deleteSelected;
  final VoidCallback toggleClassLabels;
  final ValueChanged<double> rotateObb;
  final VoidCallback aiAnnotateCurrent;
  final VoidCallback aiAnnotateAll;
  final VoidCallback trainStart;
  final VoidCallback trainStop;
  final VoidCallback trainChooseModel;
  final VoidCallback trainChooseDataset;
  final VoidCallback trainExport;
}

/// Executes a resolved shortcut without coupling key parsing to workspace UI.
class WorkspaceShortcutDispatcher {
  const WorkspaceShortcutDispatcher({required this.actions});

  final WorkspaceShortcutActions actions;

  KeyEventResult dispatch({
    required WorkspaceShortcutDecision decision,
    required KeyEvent event,
  }) {
    switch (decision.command) {
      case WorkspaceShortcutCommand.ignored:
        return KeyEventResult.ignored;
      case WorkspaceShortcutCommand.consume:
        return KeyEventResult.handled;
      case WorkspaceShortcutCommand.delegateBrowse:
        return actions.delegateBrowse(event);
      case WorkspaceShortcutCommand.undo:
        actions.undo();
        return KeyEventResult.handled;
      case WorkspaceShortcutCommand.redo:
        actions.redo();
        return KeyEventResult.handled;
      case WorkspaceShortcutCommand.copy:
        actions.copy();
        return KeyEventResult.handled;
      case WorkspaceShortcutCommand.paste:
        actions.paste();
        return KeyEventResult.handled;
      case WorkspaceShortcutCommand.cancelSelection:
        actions.cancelSelection();
        return KeyEventResult.handled;
      case WorkspaceShortcutCommand.previousImage:
        if (!actions.previousImage(decision.imageStep)) {
          actions.onNoPreviousImage();
        }
        return KeyEventResult.handled;
      case WorkspaceShortcutCommand.nextImage:
        if (!actions.nextImage(decision.imageStep)) {
          actions.onNoNextImage();
        }
        return KeyEventResult.handled;
      case WorkspaceShortcutCommand.zoomIn:
        actions.adjustZoom(10);
        return KeyEventResult.handled;
      case WorkspaceShortcutCommand.zoomOut:
        actions.adjustZoom(-10);
        return KeyEventResult.handled;
      case WorkspaceShortcutCommand.toggleZoomLock:
        actions.toggleZoomLock();
        return KeyEventResult.handled;
      case WorkspaceShortcutCommand.resetLabelView:
        actions.resetLabelView();
        return KeyEventResult.handled;
      case WorkspaceShortcutCommand.importDataset:
        actions.importDataset();
        return KeyEventResult.handled;
      case WorkspaceShortcutCommand.exportDataset:
        actions.exportDataset();
        return KeyEventResult.handled;
      case WorkspaceShortcutCommand.hbbMode:
        actions.activateMode(AnnotationMode.hbb);
        return KeyEventResult.handled;
      case WorkspaceShortcutCommand.obbMode:
        actions.activateMode(AnnotationMode.obb);
        return KeyEventResult.handled;
      case WorkspaceShortcutCommand.segMode:
        actions.activateMode(AnnotationMode.seg);
        return KeyEventResult.handled;
      case WorkspaceShortcutCommand.deleteSelected:
        actions.deleteSelected();
        return KeyEventResult.handled;
      case WorkspaceShortcutCommand.toggleClassLabels:
        actions.toggleClassLabels();
        return KeyEventResult.handled;
      case WorkspaceShortcutCommand.rotateObb:
        actions.rotateObb(decision.rotationDegrees);
        return KeyEventResult.handled;
      case WorkspaceShortcutCommand.aiAnnotateCurrent:
        actions.aiAnnotateCurrent();
        return KeyEventResult.handled;
      case WorkspaceShortcutCommand.aiAnnotateAll:
        actions.aiAnnotateAll();
        return KeyEventResult.handled;
      case WorkspaceShortcutCommand.trainStart:
        actions.trainStart();
        return KeyEventResult.handled;
      case WorkspaceShortcutCommand.trainStop:
        actions.trainStop();
        return KeyEventResult.handled;
      case WorkspaceShortcutCommand.trainChooseModel:
        actions.trainChooseModel();
        return KeyEventResult.handled;
      case WorkspaceShortcutCommand.trainChooseDataset:
        actions.trainChooseDataset();
        return KeyEventResult.handled;
      case WorkspaceShortcutCommand.trainExport:
        actions.trainExport();
        return KeyEventResult.handled;
    }
  }
}
