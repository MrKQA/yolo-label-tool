import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/config.dart';
import '../services/app_runtime.dart';
import '../services/config_store.dart';
import '../services/logger.dart';
import '../services/path_utils.dart';
import 'project_controller.dart';

typedef HistoryLoader = HistoryConfig Function();
typedef HistorySaver = void Function(HistoryConfig history);
typedef ResumePositionLoader = LabelResumePosition? Function(String projectKey);
typedef ResumePositionSaver = void Function(LabelResumePosition position);

/// Owns recent-project history and the current project's resume position.
class ProjectSessionController extends ChangeNotifier {
  ProjectSessionController({
    required this.project,
    HistoryLoader? historyLoader,
    HistorySaver? historySaver,
    ResumePositionLoader? resumePositionLoader,
    ResumePositionSaver? resumePositionSaver,
    this.resumeSaveDelay = const Duration(milliseconds: 350),
  }) : _historyLoader = historyLoader ?? ConfigStore.loadHistory,
       _historySaver = historySaver ?? ConfigStore.saveHistory,
       _resumePositionLoader =
           resumePositionLoader ?? ConfigStore.loadLabelResumePosition,
       _resumePositionSaver =
           resumePositionSaver ?? ConfigStore.saveLabelResumePosition;

  final ProjectController project;
  final HistoryLoader _historyLoader;
  final HistorySaver _historySaver;
  final ResumePositionLoader _resumePositionLoader;
  final ResumePositionSaver _resumePositionSaver;
  final Duration resumeSaveDelay;

  final List<RecentEntry> recentFolders = [];
  final List<RecentEntry> recentFiles = [];
  Timer? _resumeSaveTimer;

  void loadHistory() {
    final history = _historyLoader();
    recentFolders
      ..clear()
      ..addAll(history.folders);
    recentFiles
      ..clear()
      ..addAll(history.files);
    notifyListeners();
  }

  bool touchRecentFolder(String path) => _touchRecent(recentFolders, path);

  bool touchRecentFile(String path) => _touchRecent(recentFiles, path);

  bool removeRecentFolder(String path) => _removeRecent(recentFolders, path);

  bool removeRecentFile(String path) => _removeRecent(recentFiles, path);

  void openSingleImage(String path) {
    touchRecentFile(path);
    project.openSingleImage(path);
  }

  List<String> openImageFolder(String path) {
    final images = imageFilesInDirectory(path);
    touchRecentFolder(path);
    project.openImages(images);
    return images;
  }

  void clearHistory() {
    if (recentFolders.isEmpty && recentFiles.isEmpty) {
      return;
    }
    recentFolders.clear();
    recentFiles.clear();
    _saveHistory();
    notifyListeners();
  }

  void scheduleResumeSave({required String projectKey, bool enabled = true}) {
    if (!enabled || project.images.isEmpty) {
      return;
    }
    _resumeSaveTimer?.cancel();
    _resumeSaveTimer = Timer(resumeSaveDelay, () {
      saveResumePosition(projectKey: projectKey, enabled: enabled);
    });
  }

  void saveResumePosition({required String projectKey, bool enabled = true}) {
    if (!enabled || project.images.isEmpty) {
      return;
    }
    final image = project.selectedImage;
    if (image == null) {
      return;
    }
    try {
      _resumePositionSaver(
        LabelResumePosition(
          projectKey: projectKey,
          imagePath: image.path,
          imageIndex: project.selectedImageIndex,
          updatedAt: DateTime.now(),
        ),
      );
    } on Object catch (error) {
      logApp(
        'LABEL',
        'Save resume position failed: $error',
        level: AppLogLevel.debug,
      );
    }
  }

  int? restoreResumePosition({
    required String projectKey,
    bool enabled = true,
  }) {
    if (!enabled || project.images.isEmpty) {
      return null;
    }
    try {
      final position = _resumePositionLoader(projectKey);
      if (position == null) {
        return null;
      }
      final pathIndex = project.imageIndexOfPath(position.imagePath);
      final nextIndex = pathIndex >= 0
          ? pathIndex
          : position.imageIndex.clamp(0, project.images.length - 1).toInt();
      if (nextIndex == project.selectedImageIndex) {
        return null;
      }
      return project.selectImage(nextIndex) ? nextIndex : null;
    } on Object catch (error) {
      logApp(
        'LABEL',
        'Restore resume position failed: $error',
        level: AppLogLevel.debug,
      );
      return null;
    }
  }

  void cancelResumeSave() {
    _resumeSaveTimer?.cancel();
    _resumeSaveTimer = null;
  }

  bool _touchRecent(List<RecentEntry> items, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    final key = pathKey(trimmed);
    items.removeWhere((item) => pathKey(item.path) == key);
    items.insert(0, RecentEntry(path: trimmed, timestamp: DateTime.now()));
    if (items.length > configRecentHistoryLimit) {
      items.removeRange(configRecentHistoryLimit, items.length);
    }
    _saveHistory();
    notifyListeners();
    return true;
  }

  bool _removeRecent(List<RecentEntry> items, String path) {
    final previousLength = items.length;
    final key = pathKey(path);
    items.removeWhere((item) => pathKey(item.path) == key);
    if (items.length == previousLength) {
      return false;
    }
    _saveHistory();
    notifyListeners();
    return true;
  }

  void _saveHistory() {
    _historySaver(
      HistoryConfig(
        folders: List<RecentEntry>.unmodifiable(recentFolders),
        files: List<RecentEntry>.unmodifiable(recentFiles),
      ),
    );
  }

  @override
  void dispose() {
    cancelResumeSave();
    super.dispose();
  }
}
