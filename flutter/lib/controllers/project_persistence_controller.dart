import 'dart:async';

import '../services/rust_backend.dart';

typedef ProjectDatabaseRunner =
    Future<Map<String, dynamic>> Function(String payload);

/// Coordinates debounced project persistence and database load exclusivity.
class ProjectPersistenceController {
  ProjectPersistenceController({
    ProjectDatabaseRunner? saveRunner,
    ProjectDatabaseRunner? loadRunner,
    this.saveDelay = const Duration(milliseconds: 700),
  }) : _saveRunner = saveRunner ?? _save,
       _loadRunner = loadRunner ?? _load;

  final ProjectDatabaseRunner _saveRunner;
  final ProjectDatabaseRunner _loadRunner;
  final Duration saveDelay;
  Timer? _saveTimer;

  bool applying = false;

  void scheduleSave(Future<void> Function() action) {
    if (applying) {
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, () => unawaited(action()));
  }

  void cancelScheduledSave() {
    _saveTimer?.cancel();
    _saveTimer = null;
  }

  Future<Map<String, dynamic>> save(String payload) {
    return _saveRunner(payload);
  }

  Future<Map<String, dynamic>> load(String payload) {
    return _loadRunner(payload);
  }

  Future<T> runApplying<T>(Future<T> Function() action) async {
    cancelScheduledSave();
    applying = true;
    try {
      return await action();
    } finally {
      applying = false;
    }
  }

  void dispose() {
    cancelScheduledSave();
  }

  static Future<Map<String, dynamic>> _save(String payload) {
    return RustBackend.saveLabelDatabase(payload: payload);
  }

  static Future<Map<String, dynamic>> _load(String payload) {
    return RustBackend.loadLabelDatabase(payload: payload);
  }
}
