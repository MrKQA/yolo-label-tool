part of '../../main.dart';

class _WorkspaceShell extends StatefulWidget {
  const _WorkspaceShell({required this.status});

  final _BridgeStatus status;

  @override
  State<_WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<_WorkspaceShell> {
  final FocusNode _keyboardFocusNode = FocusNode(debugLabel: 'workspace');
  final _DetectVideoSession _detectVideoSession = _DetectVideoSession();
  final GlobalKey<_TrainPageState> _trainPageKey = GlobalKey<_TrainPageState>();
  Timer? _topMenuHideTimer;
  Timer? _databaseSaveTimer;
  Timer? _labelResumeSaveTimer;
  Timer? _collaborationPollTimer;

  final List<_ImageItem> _images = [];
  final List<_RecentEntry> _recentFolders = [];
  final List<_RecentEntry> _recentFiles = [];
  final List<_LabelClass> _labelClasses = [];
  final Map<String, List<_AnnotationRegion>> _annotationsByImage = {};
  final Map<String, String> _imageSplits = {};
  final List<List<_AnnotationRegion>> _undoStack = [];
  final List<List<_AnnotationRegion>> _redoStack = [];
  List<LanguageOption> _languageOptions = const [
    LanguageOption(code: _languageCode, label: 'Simplified Chinese'),
  ];

  bool _sidebarCollapsed = false;
  bool _darkMode = false;
  bool _shortcutDialogOpen = false;
  bool _importingDataset = false;
  bool _databaseApplying = false;
  bool _topMenuVisible = true;
  bool _videoFullscreenVisible = false;
  bool _zoomLocked = false;
  double _zoom = 100;
  Offset _labelViewportOffset = Offset.zero;
  int _selectedImageIndex = 0;
  String _activeSection = 'label';
  String _activeTool = 'select';
  String _activeLanguageCode = _languageCode;
  String? _selectedAnnotationId;
  bool _showClassLabels = true;
  bool _aiPanelVisible = false;
  int? _activeClassId;
  int _classSerial = 1;
  int _annotationSerial = 1;
  _AnnotationMode _activeAnnotationMode = _AnnotationMode.hbb;
  _AnnotationRegion? _copiedAnnotation;
  Size? _imageDisplaySize;
  final Map<String, Size> _imageDisplaySizes = {};
  _ShortcutConfig _shortcutConfig = _ShortcutConfig.defaults();
  _AppSettings _appSettings = _AppSettings.empty();
  _ImportedDataset? _importedDataset;
  _AiAssistConfig? _aiAssistConfig;
  bool _aiAnnotating = false;
  final Map<String, List<_Sam3ClickPromptPoint>> _sam3ClickPromptsByImage = {};
  final Map<String, _Sam3ClickPreviewState> _sam3ClickPreviewsByImage = {};
  final Map<String, Set<String>> _sam3ClickAnnotationIdsByImage = {};
  Offset? _aiAssistPanelOffset;
  Size _aiAssistPanelSize = const Size(320, 360);
  _CollaborationMode _collaborationMode = _CollaborationMode.off;
  String _collaborationHostId = _newCollaborationId('host');
  String _collaborationUserId = _newCollaborationId('user');
  String _collaborationUserName =
      Platform.environment['USERNAME']?.trim().isNotEmpty == true
      ? Platform.environment['USERNAME']!.trim()
      : 'User';
  int _collaborationPort = 8765;
  int _collaborationStartIndex = 1;
  int _collaborationEndIndex = 1;
  _CollaborationPermissions _collaborationSelfPermissions =
      const _CollaborationPermissions();
  final List<_CollaborationPeer> _collaborationPeers = [];
  final List<_CollaborationDiscoveredHost> _collaborationDiscoveredHosts = [];
  final Set<String> _pendingCollaborationJoinRequests = {};
  String? _selectedCollaborationHostId;
  bool _collaborationPollInFlight = false;
  bool _applyingCollaborationAnnotationSnapshot = false;
  bool _collaborationJoining = false;
  bool _collaborationReconnecting = false;
  int _collaborationReconnectAttempts = 0;
  Timer? _collaborationReconnectTimer;
  _CollaborationDiscoveredHost? _connectedCollaborationHost;

  _ImageItem? get _selectedImage {
    if (_images.isEmpty) {
      return null;
    }
    return _images[_selectedImageIndex.clamp(0, _images.length - 1)];
  }

  bool get _collaborationClientMode =>
      _collaborationMode == _CollaborationMode.client;

  String get _currentAnnotatorName {
    final name = _collaborationUserName.trim();
    return name.isEmpty ? 'User' : name;
  }

  int get _currentAnnotatorColorValue =>
      _collaborationColorForId(_collaborationAuthorId).toARGB32();

  String get _currentAnnotatorLabel =>
      '$_currentAnnotatorName#${_shortCollaborationId(_collaborationAuthorId)}';

  String get _collaborationAuthorId =>
      _collaborationPeerIdFor(_collaborationHostId, _collaborationUserId);

  bool get _selectedImageAuthorized =>
      _isImageIndexAuthorized(_selectedImageIndex);

  bool get _projectLockedByCollaboration =>
      _collaborationMode == _CollaborationMode.client;

  _ImageItem? get _selectedImageForLabel {
    if (!_selectedImageAuthorized) {
      return null;
    }
    return _selectedImage;
  }

  List<_AnnotationRegion> get _currentAnnotationsForLabel {
    if (!_selectedImageAuthorized) {
      return const [];
    }
    return _currentAnnotations;
  }

  bool get _sam3ClickModeActive {
    final config = _aiAssistConfig;
    return _aiPanelVisible &&
        config != null &&
        config.backend == _AiAssistBackend.sam3 &&
        config.sam3PromptMode == _AiSam3PromptMode.click;
  }

  List<_Sam3ClickPromptPoint> get _currentSam3ClickPromptsForLabel {
    if (!_sam3ClickModeActive || !_selectedImageAuthorized) {
      return const [];
    }
    final imageKey = _selectedImageKey;
    if (imageKey == null) {
      return const [];
    }
    return _sam3ClickPromptsByImage[imageKey] ?? const [];
  }

  List<_AnnotationRegion> get _currentSam3ClickPreviewForLabel {
    if (!_sam3ClickModeActive || !_selectedImageAuthorized) {
      return const [];
    }
    final imageKey = _selectedImageKey;
    if (imageKey == null) {
      return const [];
    }
    return _sam3ClickPreviewsByImage[imageKey]?.annotations ?? const [];
  }

  bool _isImageIndexAuthorized(int zeroBasedIndex) {
    if (!_collaborationClientMode) {
      return true;
    }
    if (_images.isEmpty) {
      return false;
    }
    final start = _collaborationStartIndex.clamp(1, _images.length);
    final end = _collaborationEndIndex.clamp(start, _images.length);
    final index = zeroBasedIndex + 1;
    return index >= start && index <= end;
  }

  void _moveToFirstAuthorizedCollaborationImage() {
    if (!_collaborationClientMode || _images.isEmpty) {
      return;
    }
    final start = _collaborationStartIndex.clamp(1, _images.length).toInt();
    final end = _collaborationEndIndex.clamp(start, _images.length).toInt();
    _collaborationStartIndex = start;
    _collaborationEndIndex = end;
    if (!_isImageIndexAuthorized(_selectedImageIndex)) {
      _selectedImageIndex = start - 1;
      _selectedAnnotationId = null;
    }
  }

  bool _guardProjectChangeBlocked() {
    if (!_projectLockedByCollaboration) {
      return false;
    }
    _showFloatingMessage(t('collab.disconnectFirst'));
    return true;
  }

  void _clearCurrentProjectState() {
    _labelResumeSaveTimer?.cancel();
    _images.clear();
    _labelClasses.clear();
    _annotationsByImage.clear();
    _imageSplits.clear();
    _imageDisplaySizes.clear();
    _sam3ClickPromptsByImage.clear();
    _sam3ClickPreviewsByImage.clear();
    _sam3ClickAnnotationIdsByImage.clear();
    _undoStack.clear();
    _redoStack.clear();
    _importedDataset = null;
    _copiedAnnotation = null;
    _selectedImageIndex = 0;
    _selectedAnnotationId = null;
    _activeClassId = null;
    _classSerial = 1;
    _annotationSerial = 1;
    _imageDisplaySize = null;
    _labelViewportOffset = Offset.zero;
    _zoom = 100;
    _activeSection = 'label';
  }

  String? get _selectedImageKey {
    final image = _selectedImage;
    return image == null ? null : _pathKey(image.path);
  }

  List<_AnnotationRegion> get _currentAnnotations {
    final imageKey = _selectedImageKey;
    if (imageKey == null) {
      return const [];
    }
    return _annotationsByImage[imageKey] ?? const [];
  }

  String get _selectedImageSplit {
    final image = _selectedImage;
    if (image == null) {
      return 'train';
    }
    return _imageSplits[_pathKey(image.path)] ?? 'train';
  }

  List<_AnnotationRegion> _annotationsForImagePath(String path) {
    return _annotationsByImage[_pathKey(path)] ?? const [];
  }

  Size? _displaySizeForImagePath(String path) {
    final key = _pathKey(path);
    return _imageDisplaySizes[key] ?? _imageDisplaySizes[path];
  }

  String _databasePayload({
    bool includeClasses = true,
    bool includeAnnotations = true,
  }) {
    return _buildAnnotationDatabasePayload(
      images: _images,
      labelClasses: _labelClasses,
      annotationsByImage: _annotationsByImage,
      imageSplits: _imageSplits,
      imageDisplaySizes: _imageDisplaySizes,
      importedDataset: _importedDataset,
      collaborationMode: _collaborationMode,
      collaborationSelfPermissions: _collaborationSelfPermissions,
      collaborationAuthorId: _collaborationAuthorId,
      currentAnnotatorName: _currentAnnotatorName,
      currentAnnotatorColorValue: _currentAnnotatorColorValue,
      collaborationStartIndex: _collaborationStartIndex,
      collaborationEndIndex: _collaborationEndIndex,
      collaborationPeers: _collaborationPeers,
      includeClasses: includeClasses,
      includeAnnotations: includeAnnotations,
    );
  }

  String _databaseProjectKey() {
    return _annotationDatabaseProjectKey(
      importedDataset: _importedDataset,
      images: _images,
    );
  }

  void _scheduleAnnotationDatabaseSave() {
    if (_databaseApplying || _images.isEmpty) {
      return;
    }
    _databaseSaveTimer?.cancel();
    _databaseSaveTimer = Timer(const Duration(milliseconds: 700), () {
      unawaited(_saveAnnotationDatabaseNow());
    });
  }

  Future<void> _saveAnnotationDatabaseNow() async {
    if (_databaseApplying || _images.isEmpty) {
      return;
    }
    if (_collaborationMode == _CollaborationMode.client) {
      if (!_applyingCollaborationAnnotationSnapshot) {
        _publishCurrentCollaborationAnnotations();
      }
      return;
    }
    try {
      final result = await _RustVideoBackend.saveLabelDatabase(
        payload: _databasePayload(),
      );
      _log(
        'DB',
        'Label database saved: images=${result['images'] ?? '-'}, classes=${result['classes'] ?? '-'}, annotations=${result['annotations'] ?? '-'}',
        level: _LogLevel.debug,
      );
      if (!_applyingCollaborationAnnotationSnapshot) {
        _publishCurrentCollaborationAnnotations();
      }
    } on Object catch (error) {
      _log('DB', 'Label database save failed: $error', level: _LogLevel.error);
    }
  }

  Future<void> _saveCollaborationAnnotationDatabaseNow(String reason) async {
    if (_images.isEmpty || _collaborationMode == _CollaborationMode.client) {
      return;
    }
    final previousApplying = _applyingCollaborationAnnotationSnapshot;
    _applyingCollaborationAnnotationSnapshot = true;
    try {
      final result = await _RustVideoBackend.saveLabelDatabase(
        payload: _databasePayload(),
      );
      _log(
        'COLLAB',
        'Collaboration data saved: reason=$reason, images=${result['images'] ?? '-'}, classes=${result['classes'] ?? '-'}, annotations=${result['annotations'] ?? '-'}',
        level: _LogLevel.debug,
      );
    } on Object catch (error) {
      _log(
        'COLLAB',
        'Collaboration data save failed: reason=$reason, error=$error',
        level: _LogLevel.error,
      );
    } finally {
      _applyingCollaborationAnnotationSnapshot = previousApplying;
    }
  }

  Future<void> _loadAnnotationDatabaseForCurrentImages() async {
    if (_images.isEmpty) {
      return;
    }
    _databaseSaveTimer?.cancel();
    _databaseApplying = true;
    try {
      final result = await _RustVideoBackend.loadLabelDatabase(
        payload: _databasePayload(
          includeClasses: false,
          includeAnnotations: false,
        ),
      );
      final loadedClasses = _labelClassesFromDatabase(result['classes']);
      final loadedAnnotations = _annotationsFromDatabase(
        result['annotations'],
        {for (final image in _images) _pathKey(image.path)},
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _labelClasses
          ..clear()
          ..addAll(loadedClasses);
        if (loadedClasses.isNotEmpty) {
          var maxClassId = -1;
          for (final labelClass in loadedClasses) {
            if (labelClass.id > maxClassId) {
              maxClassId = labelClass.id;
            }
          }
          _classSerial = maxClassId + 1;
          if (_activeClassId == null ||
              !_labelClasses.any((item) => item.id == _activeClassId)) {
            _activeClassId = _labelClasses.first.id;
          }
        } else {
          _classSerial = 1;
          _activeClassId = null;
        }

        for (final image in _images) {
          final imageKey = _pathKey(image.path);
          final annotations = loadedAnnotations[imageKey];
          if (annotations == null || annotations.isEmpty) {
            _annotationsByImage.remove(imageKey);
          } else {
            _annotationsByImage[imageKey] = annotations;
          }
        }
        _annotationSerial = _nextAnnotationSerial();
        _selectedAnnotationId = null;
        _undoStack.clear();
        _redoStack.clear();
      });
      final count = loadedAnnotations.values.fold<int>(
        0,
        (sum, annotations) => sum + annotations.length,
      );
      _log(
        'DB',
        'Label database loaded: classes=${loadedClasses.length}, annotations=$count',
        level: _LogLevel.debug,
      );
    } on Object catch (error) {
      _log('DB', 'Label database load failed: $error', level: _LogLevel.error);
    } finally {
      _databaseApplying = false;
    }
  }

  int _nextAnnotationSerial() {
    return _nextAnnotationSerialFor(_annotationsByImage);
  }

  @override
  void initState() {
    super.initState();
    _detectVideoSession.addListener(_handleDetectVideoSessionChanged);
    _loadPersistedConfig();
    _loadAvailableLanguages();
    _startCollaborationPolling();
    _resetCollaborationRuntimeForStartup();
    _scheduleTopMenuHide();
  }

  void _resetCollaborationRuntimeForStartup() {
    unawaited(
      _RustVideoBackend.collaborationCommand(request: const {'action': 'stop'})
          .catchError((Object error) {
            _log(
              'COLLAB',
              'Startup collaboration reset failed: $error',
              level: _LogLevel.debug,
            );
            return <String, dynamic>{};
          })
          .whenComplete(_restartCollaborationDiscovery),
    );
  }

  @override
  void dispose() {
    _log('APP', 'Shutdown requested');
    _topMenuHideTimer?.cancel();
    _databaseSaveTimer?.cancel();
    _labelResumeSaveTimer?.cancel();
    _collaborationPollTimer?.cancel();
    _collaborationReconnectTimer?.cancel();
    unawaited(
      _RustVideoBackend.collaborationCommand(
        request: const {'action': 'stop'},
      ).catchError((Object error) {
        _log(
          'COLLAB',
          'Stop on dispose failed: $error',
          level: _LogLevel.debug,
        );
        return <String, dynamic>{};
      }),
    );
    unawaited(_saveAnnotationDatabaseNow());
    _saveLabelResumePositionNow();
    _appLogger.dispose();
    _detectVideoSession.removeListener(_handleDetectVideoSessionChanged);
    _detectVideoSession.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _handleDetectVideoSessionChanged() {
    final visible =
        _detectVideoSession.fullscreen &&
        _detectVideoSession.hasInitializedVideo;
    if (visible == _videoFullscreenVisible || !mounted) {
      return;
    }
    setState(() => _videoFullscreenVisible = visible);
  }

  void _loadPersistedConfig() {
    final history = _ConfigStore.loadHistory();
    final keybindings = _ConfigStore.loadKeybindings();
    final settings = _ConfigStore.loadSettings();
    setState(() {
      _recentFolders
        ..clear()
        ..addAll(history.folders);
      _recentFiles
        ..clear()
        ..addAll(history.files);
      _shortcutConfig = keybindings;
      _appSettings = settings;
      _darkMode = settings.darkMode;
      _collaborationHostId = settings.collaborationHostId;
      _collaborationUserId = settings.collaborationUserId;
    });
    _ConfigStore.saveSettings(settings);
    _themeModeNotifier.value = settings.darkMode
        ? ThemeMode.dark
        : ThemeMode.light;
    _setLogLevel(_logLevelFromIndex(settings.logLevelIndex));
    _log(
      'APP',
      'Config loaded: recentFolders=${_recentFolders.length}, recentFiles=${_recentFiles.length}, logLevel=${_logLevel.name}',
      level: _LogLevel.debug,
    );
  }

  Future<void> _loadAvailableLanguages() async {
    final options = await LanguageOption.loadAvailable(
      compare: _naturalCompare,
    );
    if (!mounted) {
      return;
    }
    setState(() => _languageOptions = options);
  }

  Future<void> _changeLanguage(String code) async {
    if (code == _activeLanguageCode) {
      return;
    }
    final strings = await AppLanguageStrings.load(code);
    if (!mounted) {
      return;
    }
    _appText = strings;
    _languageStringsNotifier.value = strings;
    setState(() => _activeLanguageCode = code);
    _log('SETTINGS', 'Language changed: $code');
    _showTopMenu();
  }

  void _saveHistory() {
    _ConfigStore.saveHistory(
      _HistoryConfig(folders: _recentFolders, files: _recentFiles),
    );
  }

  void _saveKeybindings() {
    _ConfigStore.saveKeybindings(_shortcutConfig);
  }

  void _saveAppSettings(_AppSettings settings) {
    final nextSettings = settings.copyWith(
      collaborationHostId: _collaborationHostId,
      collaborationUserId: _collaborationUserId,
    );
    setState(() {
      _appSettings = nextSettings;
      _darkMode = nextSettings.darkMode;
    });
    _themeModeNotifier.value = nextSettings.darkMode
        ? ThemeMode.dark
        : ThemeMode.light;
    _ConfigStore.saveSettings(nextSettings);
  }

  void _setZoom(double value) {
    if (_zoomLocked) {
      return;
    }
    setState(() => _zoom = value.clamp(25, 400).toDouble());
  }

  void _setLabelViewportOffset(Offset offset) {
    if (_labelViewportOffset == offset) {
      return;
    }
    setState(() => _labelViewportOffset = offset);
  }

  void _resetZoomAndViewport() {
    if (_zoomLocked) {
      return;
    }
    setState(() {
      _zoom = 100;
      _labelViewportOffset = Offset.zero;
    });
  }

  void _toggleZoomLock() {
    setState(() => _zoomLocked = !_zoomLocked);
  }

  void _scheduleLabelResumePositionSave() {
    if (_images.isEmpty || _collaborationClientMode) {
      return;
    }
    _labelResumeSaveTimer?.cancel();
    _labelResumeSaveTimer = Timer(const Duration(milliseconds: 350), () {
      _saveLabelResumePositionNow();
    });
  }

  void _saveLabelResumePositionNow() {
    if (_images.isEmpty || _collaborationClientMode) {
      return;
    }
    final image = _selectedImage;
    if (image == null) {
      return;
    }
    try {
      _ConfigStore.saveLabelResumePosition(
        _LabelResumePosition(
          projectKey: _databaseProjectKey(),
          imagePath: image.path,
          imageIndex: _selectedImageIndex,
          updatedAt: DateTime.now(),
        ),
      );
    } on Object catch (error) {
      _log(
        'LABEL',
        'Save resume position failed: $error',
        level: _LogLevel.debug,
      );
    }
  }

  void _restoreLabelResumePosition() {
    if (_images.isEmpty || _collaborationClientMode) {
      return;
    }
    try {
      final position = _ConfigStore.loadLabelResumePosition(
        _databaseProjectKey(),
      );
      if (position == null) {
        return;
      }
      final pathIndex = _imageIndexOfPath(position.imagePath);
      final nextIndex = pathIndex >= 0
          ? pathIndex
          : position.imageIndex.clamp(0, _images.length - 1).toInt();
      if (nextIndex == _selectedImageIndex) {
        return;
      }
      setState(() {
        _selectedImageIndex = nextIndex;
        _selectedAnnotationId = null;
        _undoStack.clear();
        _redoStack.clear();
      });
      _log(
        'LABEL',
        'Restored image position: ${nextIndex + 1}/${_images.length}',
        level: _LogLevel.debug,
      );
    } on Object catch (error) {
      _log(
        'LABEL',
        'Restore resume position failed: $error',
        level: _LogLevel.debug,
      );
    }
  }

  void _selectImage(int index) {
    if (index < 0 || index >= _images.length) {
      return;
    }
    setState(() {
      _selectedImageIndex = index;
      _selectedAnnotationId = null;
      _undoStack.clear();
      _redoStack.clear();
    });
    _scheduleLabelResumePositionSave();
  }

  bool _selectPreviousImage({int step = 1}) {
    if (_images.isEmpty) {
      return false;
    }
    final nextIndex = (_selectedImageIndex - step).clamp(0, _images.length - 1);
    if (nextIndex == _selectedImageIndex) {
      return false;
    }
    _selectImage(nextIndex);
    return true;
  }

  bool _selectNextImage({int step = 1}) {
    if (_images.isEmpty) {
      return false;
    }
    final nextIndex = (_selectedImageIndex + step).clamp(0, _images.length - 1);
    if (nextIndex == _selectedImageIndex) {
      return false;
    }
    _selectImage(nextIndex);
    return true;
  }

  Future<void> _openImageFile({int? insertAfterIndex}) async {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    final file = await openFile(acceptedTypeGroups: [_imageTypeGroup]);
    if (file == null) {
      return;
    }
    _log('LABEL', 'Open image file: ${file.path}');

    if (insertAfterIndex != null) {
      final existingIndex = _imageIndexOfPath(file.path);
      if (existingIndex >= 0) {
        if (_touchRecent(_recentFiles, file.path)) {
          _saveHistory();
        }
        _selectImage(existingIndex);
        return;
      }

      if (_touchRecent(_recentFiles, file.path)) {
        _saveHistory();
      }
      _importedDataset = null;
      _insertImages([file.path], insertAfterIndex: insertAfterIndex);
      await _loadAnnotationDatabaseForCurrentImages();
      return;
    }

    if (_touchRecent(_recentFiles, file.path)) {
      _saveHistory();
    }
    await _openSingleImageProject(file.path);
  }

  Future<void> _openSingleImageProject(String path) async {
    setState(() {
      _clearCurrentProjectState();
      _images.add(_ImageItem.fromPath(path));
      _imageSplits[_pathKey(path)] = 'train';
      _activeSection = 'label';
    });
    _log('LABEL', 'Single image project opened: $path');
    await _loadAnnotationDatabaseForCurrentImages();
    _scheduleLabelResumePositionSave();
  }

  Future<void> _openImageFolder([String? path]) async {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    final folderPath = path ?? await getDirectoryPath();
    if (folderPath == null) {
      return;
    }

    final files = _imageFilesInDirectory(folderPath);
    _log(
      'LABEL',
      'Open image folder: $folderPath, images=${files.length}',
      level: files.isEmpty ? _LogLevel.warning : _LogLevel.info,
    );
    if (_touchRecent(_recentFolders, folderPath)) {
      _saveHistory();
    }
    setState(() {
      _images
        ..clear()
        ..addAll(files.map(_ImageItem.fromPath));
      _imageSplits.clear();
      _labelClasses.clear();
      _annotationsByImage.clear();
      _importedDataset = null;
      _selectedImageIndex = 0;
      _selectedAnnotationId = null;
      _activeClassId = null;
      _classSerial = 1;
      _annotationSerial = 1;
      _undoStack.clear();
      _redoStack.clear();
      _activeSection = 'label';
    });
    await _loadAnnotationDatabaseForCurrentImages();
    _restoreLabelResumePosition();
  }

  Future<void> _openRecentFolder(String path) async {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    if (!Directory(path).existsSync()) {
      setState(() {
        _recentFolders.removeWhere(
          (entry) => _pathKey(entry.path) == _pathKey(path),
        );
      });
      _saveHistory();
      _log(
        'HISTORY',
        'Removed missing recent folder: $path',
        level: _LogLevel.warning,
      );
      _showFloatingMessage(t('recent.missingFolder'));
      return;
    }
    await _openImageFolder(path);
  }

  Future<void> _openRecentFile(String path) async {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    _log('LABEL', 'Open recent file: $path');
    if (!File(path).existsSync()) {
      setState(() {
        _recentFiles.removeWhere(
          (entry) => _pathKey(entry.path) == _pathKey(path),
        );
      });
      _saveHistory();
      _log(
        'HISTORY',
        'Removed missing recent file: $path',
        level: _LogLevel.warning,
      );
      _showFloatingMessage(t('recent.missingFile'));
      return;
    }
    if (_touchRecent(_recentFiles, path)) {
      _saveHistory();
    }
    await _openSingleImageProject(path);
  }

  void _insertImages(List<String> paths, {int? insertAfterIndex}) {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    final newPaths = paths
        .where((path) => _imageIndexOfPath(path) < 0)
        .toList(growable: false);
    if (newPaths.isEmpty) {
      return;
    }
    final insertIndex = insertAfterIndex == null
        ? _images.length
        : (insertAfterIndex + 1).clamp(0, _images.length);

    setState(() {
      _images.insertAll(insertIndex, newPaths.map(_ImageItem.fromPath));
      for (final path in newPaths) {
        _imageSplits.putIfAbsent(_pathKey(path), () => 'train');
      }
      _selectedImageIndex = insertIndex;
      _selectedAnnotationId = null;
      _undoStack.clear();
      _redoStack.clear();
      _activeSection = 'label';
    });
    _log(
      'LABEL',
      'Images inserted: count=${newPaths.length}, total=${_images.length}',
    );
    _broadcastCollaborationProjectSnapshot('images inserted');
    _scheduleLabelResumePositionSave();
    _scheduleAnnotationDatabaseSave();
  }

  int _imageIndexOfPath(String path) {
    final key = _pathKey(path);
    return _images.indexWhere((image) => _pathKey(image.path) == key);
  }

  void _deleteImage(int index) {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    if (index < 0 || index >= _images.length) {
      return;
    }

    final removedPath = _images[index].path;
    setState(() {
      final removed = _images.removeAt(index);
      _imageSplits.remove(_pathKey(removed.path));
      _annotationsByImage.remove(_pathKey(removed.path));
      _sam3ClickPromptsByImage.remove(_pathKey(removed.path));
      _sam3ClickPreviewsByImage.remove(_pathKey(removed.path));
      _sam3ClickAnnotationIdsByImage.remove(_pathKey(removed.path));
      _selectedImageIndex = _images.isEmpty
          ? 0
          : _selectedImageIndex.clamp(0, _images.length - 1);
      _selectedAnnotationId = null;
      _undoStack.clear();
      _redoStack.clear();
    });
    _log('LABEL', 'Image removed: $removedPath, total=${_images.length}');
    _broadcastCollaborationProjectSnapshot('image deleted');
    _scheduleLabelResumePositionSave();
    _scheduleAnnotationDatabaseSave();
  }

  void _setSelectedImageSplit(String split) {
    final imageKey = _selectedImageKey;
    if (imageKey == null || !_datasetSplits.contains(split)) {
      return;
    }
    setState(() => _imageSplits[imageKey] = split);
    _scheduleAnnotationDatabaseSave();
  }

  Future<void> _showImageContextMenu(TapDownDetails details, int? index) async {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(details.globalPosition, details.globalPosition),
      Offset.zero & overlay.size,
    );
    final action = await showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(value: 'add', child: Text(t('context.addImage'))),
        PopupMenuItem(value: 'delete', child: Text(t('context.deleteImage'))),
      ],
    );

    if (action == 'add') {
      await _openImageFile(insertAfterIndex: index);
    } else if (action == 'delete' && index != null) {
      _deleteImage(index);
    }
  }

  void _showTrainingHistoryDialog() {
    _showTrainingHistoryRecordsDialog(
      context: context,
      onEmpty: () => _showFloatingMessage(t('train.noHistory')),
    );
  }

  Future<void> _importYoloDataset() async {
    if (_importingDataset) {
      return;
    }
    if (_guardProjectChangeBlocked()) {
      return;
    }
    final file = await openFile(acceptedTypeGroups: [_yamlTypeGroup]);
    if (file == null) {
      return;
    }
    if (!mounted) {
      return;
    }

    setState(() => _importingDataset = true);
    await WidgetsBinding.instance.endOfFrame;
    try {
      _log('IMPORT', 'Dataset import started: ${file.path}');
      final project = await _loadImportedYoloProject(
        yamlPath: file.path,
        ensureImageDisplaySize: _computeImageDisplaySize,
      );
      if (project == null) {
        _log(
          'IMPORT',
          'Dataset import found no images: ${file.path}',
          level: _LogLevel.warning,
        );
        _showFloatingMessage(t('import.noImages'));
        return;
      }

      setState(() {
        _images
          ..clear()
          ..addAll(project.images);
        _annotationsByImage
          ..clear()
          ..addAll(project.annotationsByImage);
        _imageSplits
          ..clear()
          ..addAll(project.imageSplits);
        _labelClasses
          ..clear()
          ..addAll(project.labelClasses);
        _importedDataset = project.dataset;
        _classSerial = project.classSerial;
        _annotationSerial = project.annotationSerial;
        _activeClassId = project.labelClasses.isEmpty
            ? null
            : project.labelClasses.first.id;
        _selectedImageIndex = 0;
        _selectedAnnotationId = null;
        _undoStack.clear();
        _redoStack.clear();
        _activeSection = 'label';
      });
      _log(
        'IMPORT',
        'Dataset import completed: images=${project.images.length}, classes=${project.labelClasses.length}, annotations=${project.annotationCount}, yaml=${file.path}',
      );
      _restoreLabelResumePosition();
      unawaited(_saveAnnotationDatabaseNow());
      _showFloatingMessage('${t('import.done')} (${project.images.length})');
    } on Object catch (error) {
      _log(
        'IMPORT',
        'Dataset import failed: ${file.path}, error=$error',
        level: _LogLevel.error,
      );
      _showFloatingMessage(t('import.failed'));
    } finally {
      if (mounted) {
        setState(() => _importingDataset = false);
      }
    }
  }

  void _pushAnnotationSnapshot() {
    _undoStack.add(List<_AnnotationRegion>.of(_currentAnnotations));
    if (_undoStack.length > 50) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void _restoreCurrentImageAnnotations(List<_AnnotationRegion> snapshot) {
    final imageKey = _selectedImageKey;
    if (imageKey == null) {
      return;
    }
    _annotationsByImage[imageKey] = List<_AnnotationRegion>.of(snapshot);
    if (_selectedAnnotationId != null &&
        !_currentAnnotations.any(
          (annotation) => annotation.id == _selectedAnnotationId,
        )) {
      _selectedAnnotationId = null;
    }
  }

  void _undoAnnotationChange() {
    if (_undoStack.isEmpty) {
      return;
    }
    final snapshot = _undoStack.removeLast();
    _redoStack.add(List<_AnnotationRegion>.of(_currentAnnotations));
    setState(() => _restoreCurrentImageAnnotations(snapshot));
    _scheduleAnnotationDatabaseSave();
  }

  void _redoAnnotationChange() {
    if (_redoStack.isEmpty) {
      return;
    }
    final snapshot = _redoStack.removeLast();
    _undoStack.add(List<_AnnotationRegion>.of(_currentAnnotations));
    setState(() => _restoreCurrentImageAnnotations(snapshot));
    _scheduleAnnotationDatabaseSave();
  }

  void _activateAnnotationMode(_AnnotationMode mode) {
    setState(() {
      _activeAnnotationMode = mode;
      _activeTool = 'draw';
      _selectedAnnotationId = null;
    });
  }

  void _selectTool(String tool) {
    if (tool == 'undo') {
      _undoAnnotationChange();
      return;
    }
    if (tool == 'redo') {
      _redoAnnotationChange();
      return;
    }
    if (tool == 'copy') {
      _copySelectedAnnotation();
      return;
    }
    if (tool == 'paste') {
      _pasteAnnotation();
      return;
    }
    if (tool == 'delete') {
      _deleteSelectedAnnotation();
      return;
    }
    if (tool == 'export') {
      _showExportDialog();
      return;
    }
    setState(() => _activeTool = tool);
  }

  _LabelClass? _classById(int id) {
    for (final labelClass in _labelClasses) {
      if (labelClass.id == id) {
        return labelClass;
      }
    }
    return null;
  }

  Color _nextClassColor() {
    return _labelColorPalette[_labelClasses.length % _labelColorPalette.length];
  }

  Future<int?> _ensureActiveClass() async {
    if (_activeClassId != null && _classById(_activeClassId!) != null) {
      return _activeClassId;
    }
    if (_labelClasses.isNotEmpty) {
      setState(() => _activeClassId = _labelClasses.first.id);
      return _activeClassId;
    }
    return _addLabelClass();
  }

  Future<int?> _addLabelClass() async {
    if (_guardProjectChangeBlocked()) {
      return null;
    }
    final name = await _requestClassName(
      initialName: 'class_${_labelClasses.length}',
      title: t('label.createClassPrompt'),
    );
    if (name == null || name.trim().isEmpty) {
      return null;
    }
    final id = _classSerial++;
    final labelClass = _LabelClass(
      id: id,
      name: name.trim(),
      colorValue: _nextClassColor().toARGB32(),
    );
    setState(() {
      _labelClasses.add(labelClass);
      _activeClassId = id;
    });
    _broadcastCollaborationClassSnapshot('class added');
    _scheduleAnnotationDatabaseSave();
    return id;
  }

  Future<void> _editLabelClass(_LabelClass labelClass) async {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    final name = await _requestClassName(
      initialName: labelClass.name,
      title: t('label.editClass'),
    );
    if (name == null || name.trim().isEmpty) {
      return;
    }
    setState(() {
      final index = _labelClasses.indexWhere(
        (item) => item.id == labelClass.id,
      );
      if (index >= 0) {
        _labelClasses[index] = labelClass.copyWith(name: name.trim());
      }
    });
    _broadcastCollaborationClassSnapshot('class renamed');
    _scheduleAnnotationDatabaseSave();
  }

  Future<String?> _requestClassName({
    required String initialName,
    required String title,
  }) async {
    final controller = TextEditingController(text: initialName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: t('label.className')),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('label.cancelAnnotation')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(t('label.saveAnnotation')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _chooseLabelClassColor(_LabelClass labelClass) async {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    final currentColor = labelClass.color;
    final selected = await _showWheelColorDialog(
      context: context,
      initialColor: currentColor,
      title: t('label.classColor'),
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
    );
    if (selected == null) {
      return;
    }
    if (selected.toARGB32() == currentColor.toARGB32()) {
      return;
    }
    setState(() {
      final index = _labelClasses.indexWhere(
        (item) => item.id == labelClass.id,
      );
      if (index >= 0) {
        _labelClasses[index] = labelClass.copyWith(
          colorValue: selected.toARGB32(),
        );
      }
    });
    _broadcastCollaborationClassSnapshot('class color changed');
    _scheduleAnnotationDatabaseSave();
  }

  void _deleteLabelClass(_LabelClass labelClass) {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    _pushAnnotationSnapshot();
    setState(() {
      _labelClasses.removeWhere((item) => item.id == labelClass.id);
      for (final entry in _annotationsByImage.entries) {
        entry.value.removeWhere(
          (annotation) => annotation.classId == labelClass.id,
        );
      }
      if (_activeClassId == labelClass.id) {
        _activeClassId = _labelClasses.isEmpty ? null : _labelClasses.first.id;
      }
      _selectedAnnotationId = null;
    });
    _broadcastCollaborationClassSnapshot('class deleted');
    _broadcastCollaborationAllAnnotations('class deleted');
    _scheduleAnnotationDatabaseSave();
  }

  void _reorderLabelClass(int oldIndex, int newIndex) {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    setState(() {
      final item = _labelClasses.removeAt(oldIndex);
      _labelClasses.insert(newIndex, item);
    });
    _broadcastCollaborationClassSnapshot('class reordered');
    _scheduleAnnotationDatabaseSave();
  }

  void _selectLabelClass(int id) {
    setState(() => _activeClassId = id);
  }

  void _createAnnotation(Rect rect, int classId) {
    final imageKey = _selectedImageKey;
    if (imageKey == null ||
        !_selectedImageAuthorized ||
        rect.width.abs() < 4 ||
        rect.height.abs() < 4) {
      return;
    }
    _pushAnnotationSnapshot();
    final annotation = _AnnotationRegion.fromRect(
      id: 'ann_${_annotationSerial++}',
      mode: _activeAnnotationMode,
      rect: rect,
      classId: classId,
      authorId: _collaborationAuthorId,
      authorName: _currentAnnotatorName,
      authorColorValue: _currentAnnotatorColorValue,
    );
    setState(() {
      _annotationsByImage.putIfAbsent(imageKey, () => []).add(annotation);
      _selectedAnnotationId = null;
      _activeTool = 'draw';
    });
    _log(
      'ANNOTATION',
      'Created ${annotation.mode.name}: image=${_selectedImage?.name ?? '-'}, classId=$classId',
      level: _LogLevel.debug,
    );
    _scheduleAnnotationDatabaseSave();
  }

  void _createSegAnnotation(List<Offset> points, int classId) {
    final imageKey = _selectedImageKey;
    if (imageKey == null || !_selectedImageAuthorized || points.length < 3) {
      return;
    }
    _pushAnnotationSnapshot();
    final left = points.map((point) => point.dx).reduce(math.min);
    final top = points.map((point) => point.dy).reduce(math.min);
    final right = points.map((point) => point.dx).reduce(math.max);
    final bottom = points.map((point) => point.dy).reduce(math.max);
    final annotation = _AnnotationRegion(
      id: 'ann_${_annotationSerial++}',
      mode: _AnnotationMode.seg,
      rect: Rect.fromLTRB(left, top, right, bottom),
      classId: classId,
      points: List<Offset>.of(points),
      authorId: _collaborationAuthorId,
      authorName: _currentAnnotatorName,
      authorColorValue: _currentAnnotatorColorValue,
    );
    setState(() {
      _annotationsByImage.putIfAbsent(imageKey, () => []).add(annotation);
      _selectedAnnotationId = null;
      _activeTool = 'draw';
    });
    _log(
      'ANNOTATION',
      'Created seg: image=${_selectedImage?.name ?? '-'}, classId=$classId, points=${points.length}',
      level: _LogLevel.debug,
    );
    _scheduleAnnotationDatabaseSave();
  }

  void _selectAnnotation(String? id) {
    if (!_selectedImageAuthorized) {
      setState(() => _selectedAnnotationId = null);
      return;
    }
    final annotation = id == null
        ? null
        : _currentAnnotations
              .where((annotation) => annotation.id == id)
              .firstOrNullValue;
    setState(() {
      _selectedAnnotationId = id;
      if (annotation != null) {
        _activeClassId = annotation.classId;
      }
    });
  }

  bool _canModifyAnnotation(
    _AnnotationRegion annotation, {
    required String action,
  }) {
    if (_collaborationMode != _CollaborationMode.client) {
      return true;
    }
    if (annotation.authorId == _collaborationAuthorId) {
      return true;
    }
    return switch (action) {
      'edit' => _collaborationSelfPermissions.canEditOthers,
      'delete' => _collaborationSelfPermissions.canDeleteOthers,
      'class' => _collaborationSelfPermissions.canChangeClass,
      _ => false,
    };
  }

  void _updateAnnotation(_AnnotationRegion annotation) {
    final imageKey = _selectedImageKey;
    if (imageKey == null || !_selectedImageAuthorized) {
      return;
    }
    final existing = _currentAnnotations
        .where((item) => item.id == annotation.id)
        .firstOrNullValue;
    if (existing != null && !_canModifyAnnotation(existing, action: 'edit')) {
      return;
    }
    setState(() {
      final annotations = _annotationsByImage[imageKey];
      if (annotations == null) {
        return;
      }
      final index = annotations.indexWhere((item) => item.id == annotation.id);
      if (index >= 0) {
        annotations[index] = annotation;
      }
    });
    _scheduleAnnotationDatabaseSave();
  }

  void _changeAnnotationClass(String annotationId, int classId) {
    final imageKey = _selectedImageKey;
    if (imageKey == null || !_selectedImageAuthorized) {
      return;
    }
    final existing = _currentAnnotations
        .where((item) => item.id == annotationId)
        .firstOrNullValue;
    if (existing != null && !_canModifyAnnotation(existing, action: 'class')) {
      _showFloatingMessage(t('collab.permissionDenied'));
      return;
    }
    _pushAnnotationSnapshot();
    var changed = false;
    setState(() {
      final annotations = _annotationsByImage[imageKey];
      if (annotations == null) {
        return;
      }
      final index = annotations.indexWhere((item) => item.id == annotationId);
      if (index >= 0) {
        annotations[index] = annotations[index].copyWith(classId: classId);
        _activeClassId = classId;
        changed = true;
      }
    });
    if (changed) {
      _log(
        'ANNOTATION',
        'Class changed: annotation=$annotationId, classId=$classId',
        level: _LogLevel.debug,
      );
      _scheduleAnnotationDatabaseSave();
    }
  }

  void _deleteAnnotation(String id) {
    final imageKey = _selectedImageKey;
    if (imageKey == null || !_selectedImageAuthorized) {
      return;
    }
    final existing = _currentAnnotations
        .where((item) => item.id == id)
        .firstOrNullValue;
    if (existing != null && !_canModifyAnnotation(existing, action: 'delete')) {
      _showFloatingMessage(t('collab.permissionDenied'));
      return;
    }
    _pushAnnotationSnapshot();
    setState(() {
      _annotationsByImage[imageKey]?.removeWhere(
        (annotation) => annotation.id == id,
      );
      if (_selectedAnnotationId == id) {
        _selectedAnnotationId = null;
      }
    });
    _log('ANNOTATION', 'Deleted annotation: $id', level: _LogLevel.debug);
    _scheduleAnnotationDatabaseSave();
  }

  void _deleteSelectedAnnotation() {
    final selectedId = _selectedAnnotationId;
    if (selectedId == null) {
      return;
    }
    _deleteAnnotation(selectedId);
  }

  void _copySelectedAnnotation() {
    final selectedId = _selectedAnnotationId;
    if (selectedId == null) {
      return;
    }
    final selected = _currentAnnotations
        .where((annotation) => annotation.id == selectedId)
        .firstOrNullValue;
    if (selected != null) {
      setState(() => _copiedAnnotation = selected);
      _showFloatingMessage(t('feedback.copiedAnnotation'));
    }
  }

  void _showFloatingMessage(String message) {
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;
    entry = OverlayEntry(builder: (_) => _FloatingMessage(message: message));
    overlay.insert(entry);
    Future<void>.delayed(const Duration(milliseconds: 950), () {
      entry.remove();
    });
  }

  Size _clampAiAssistPanelSize(Size size, Size viewport) {
    final maxWidth = math.min(
      _aiAssistPanelMaxWidth,
      math.max(
        _aiAssistPanelMinWidth,
        viewport.width - _aiAssistPanelMargin * 2,
      ),
    );
    final maxHeight = math.min(
      _aiAssistPanelMaxHeight,
      math.max(
        _aiAssistPanelMinHeight,
        viewport.height - _aiAssistPanelMargin * 2,
      ),
    );
    return Size(
      size.width.clamp(_aiAssistPanelMinWidth, maxWidth).toDouble(),
      size.height.clamp(_aiAssistPanelMinHeight, maxHeight).toDouble(),
    );
  }

  Offset _clampAiAssistPanelOffset(
    Offset offset,
    Size viewport,
    Size panelSize,
  ) {
    final maxX = math.max(
      _aiAssistPanelMargin,
      viewport.width - panelSize.width - _aiAssistPanelMargin,
    );
    final maxY = math.max(
      _aiAssistPanelMargin,
      viewport.height - panelSize.height - _aiAssistPanelMargin,
    );
    return Offset(
      offset.dx.clamp(_aiAssistPanelMargin, maxX).toDouble(),
      offset.dy.clamp(_aiAssistPanelMargin, maxY).toDouble(),
    );
  }

  void _moveAiAssistPanel(
    Offset delta,
    Size viewport,
    Size panelSize,
    Offset fallbackOffset,
  ) {
    setState(() {
      final current = _aiAssistPanelOffset ?? fallbackOffset;
      _aiAssistPanelOffset = _clampAiAssistPanelOffset(
        current + delta,
        viewport,
        panelSize,
      );
    });
  }

  void _resizeAiAssistPanel(
    Offset delta,
    Size viewport,
    Size panelSize,
    Offset fallbackOffset,
  ) {
    setState(() {
      final currentOffset = _aiAssistPanelOffset ?? fallbackOffset;
      final nextSize = _clampAiAssistPanelSize(
        Size(panelSize.width + delta.dx, panelSize.height + delta.dy),
        viewport,
      );
      _aiAssistPanelSize = nextSize;
      _aiAssistPanelOffset = _clampAiAssistPanelOffset(
        currentOffset,
        viewport,
        nextSize,
      );
    });
  }

  void _saveAiAssistConfig(_AiAssistConfig config) {
    setState(() => _aiAssistConfig = config);
    if (config.backend == _AiAssistBackend.sam3) {
      _ConfigStore.saveLastSam3ModelPath(config.modelPath);
    }
    final sam3Detail = config.backend == _AiAssistBackend.sam3
        ? ', sam3Mode=${config.sam3OutputMode.wireName}, prompt=${config.sam3PromptMode.wireName}, ${config.sam3Runtime.logSummary}'
        : '';
    _log(
      'AI',
      'AI assist config saved: backend=${config.backend.wireName}, model=${_fileName(config.modelPath)}, classes=${config.selectedClassIds.length}, conf=${config.confThreshold.toStringAsFixed(2)}, imgsz=${config.imageSize}, range=${config.startIndex}-${config.endIndex}$sam3Detail',
    );
  }

  Future<_AiAssistConfig?> _ensureAiAssistConfig() async {
    final config = _aiAssistConfig;
    if (config != null) {
      return config;
    }
    setState(() => _aiPanelVisible = true);
    _showFloatingMessage(t('ai.chooseModelFirst'));
    return null;
  }

  Future<void> _runAiAnnotateCurrent() async {
    final config = await _ensureAiAssistConfig();
    if (config == null) {
      return;
    }
    await _runAiAnnotateCurrentWithConfig(config);
  }

  Future<void> _runAiAnnotateCurrentWithConfig(_AiAssistConfig config) async {
    if (_selectedImage == null) {
      return;
    }
    await _runAiAnnotateForIndices([_selectedImageIndex], config);
  }

  Future<void> _runAiAnnotateAll() async {
    final config = await _ensureAiAssistConfig();
    if (config == null) {
      return;
    }
    await _runAiAnnotateAllWithConfig(config);
  }

  Future<void> _runAiAnnotateAllWithConfig(_AiAssistConfig config) async {
    if (_images.isEmpty) {
      return;
    }
    final start = (config.startIndex - 1).clamp(0, _images.length - 1);
    final end = (config.endIndex - 1).clamp(0, _images.length - 1);
    if (start > end) {
      return;
    }
    await _runAiAnnotateForIndices([
      for (var index = start; index <= end; index++) index,
    ], config);
  }

  String _sam3ClickPointsTextForImage(String imagePath) {
    final points = _sam3ClickPromptsByImage[_pathKey(imagePath)] ?? const [];
    return points.map((point) => point.wireLine).join('\n');
  }

  bool _sam3ClickHasPositivePoint(String imagePath) {
    final points = _sam3ClickPromptsByImage[_pathKey(imagePath)] ?? const [];
    return points.any((point) => point.positive);
  }

  Future<bool> _handleSam3ClickPrompt(
    Offset imagePoint,
    Size imageDisplaySize,
    bool positive,
  ) async {
    final config = _aiAssistConfig;
    final image = _selectedImage;
    final imageKey = _selectedImageKey;
    if (!_aiPanelVisible ||
        config == null ||
        config.backend != _AiAssistBackend.sam3 ||
        config.sam3PromptMode != _AiSam3PromptMode.click ||
        image == null ||
        imageKey == null ||
        !_selectedImageAuthorized ||
        imageDisplaySize.width <= 0 ||
        imageDisplaySize.height <= 0) {
      return false;
    }
    if (_aiAnnotating) {
      _showFloatingMessage(t('ai.annotating'));
      return true;
    }
    final point = _Sam3ClickPromptPoint(
      x: (imagePoint.dx / imageDisplaySize.width).clamp(0.0, 1.0).toDouble(),
      y: (imagePoint.dy / imageDisplaySize.height).clamp(0.0, 1.0).toDouble(),
      positive: positive,
    );
    final points = _sam3ClickPromptsByImage.putIfAbsent(imageKey, () => []);
    points.add(point);
    setState(() {});
    _log(
      'AI',
      'SAM3 click prompt added: image=${image.name}, point=${point.x.toStringAsFixed(4)},${point.y.toStringAsFixed(4)}, positive=$positive, total=${points.length}',
      level: _LogLevel.debug,
    );
    if (_sam3ClickHasPositivePoint(image.path)) {
      await _runSam3ClickPreview(config);
    } else {
      _showFloatingMessage(t('ai.sam3ClickRequired'));
    }
    return true;
  }

  Future<void> _runSam3ClickPreview(_AiAssistConfig config) async {
    final image = _selectedImage;
    final imageKey = _selectedImageKey;
    if (_aiAnnotating ||
        image == null ||
        imageKey == null ||
        config.backend != _AiAssistBackend.sam3 ||
        config.sam3PromptMode != _AiSam3PromptMode.click) {
      return;
    }
    if (_appSettings.pythonPath.trim().isEmpty) {
      _log(
        'AI',
        'SAM3 click preview blocked: Python path is empty',
        level: _LogLevel.warning,
      );
      _showFloatingMessage(t('detect.pythonNotConfigured'));
      return;
    }
    final samClickPointsText = _sam3ClickPointsTextForImage(image.path);
    if (samClickPointsText.trim().isEmpty ||
        !_sam3ClickHasPositivePoint(image.path)) {
      _log(
        'AI',
        'SAM3 click preview blocked: no positive click prompt points',
        level: _LogLevel.warning,
      );
      _showFloatingMessage(t('ai.sam3ClickRequired'));
      return;
    }
    _log(
      'AI',
      'SAM3 click preview started: image=${image.name}, mode=${config.sam3OutputMode.wireName}, clickPoints=${samClickPointsText.trim().split('\n').length}, ${config.sam3Runtime.logSummary}',
    );
    setState(() => _aiAnnotating = true);
    await WidgetsBinding.instance.endOfFrame;
    try {
      final result = await _RustVideoBackend.aiAnnotateImage(
        backend: config.backend.wireName,
        pythonPath: _appSettings.pythonPath.trim(),
        modelPath: config.modelPath,
        inputPath: image.path,
        classIds: config.selectedClassIds.toList()..sort(),
        confThreshold: config.confThreshold,
        iouThreshold: 0.45,
        imgsz: config.imageSize,
        device: 'auto',
        samMode: _AiSam3OutputMode.seg.wireName,
        samPromptMode: config.sam3PromptMode.wireName,
        promptsText: config.sam3PromptText,
        samClickPointsText: samClickPointsText,
        samPrecision: config.sam3Runtime.precision,
        samEncoder: config.sam3Runtime.encoder,
        samImageBatchSize: config.sam3Runtime.imageBatchSize,
        samVideoBatchSize: config.sam3Runtime.videoBatchSize,
        samInteractiveBatchSize: config.sam3Runtime.interactiveBatchSize,
        samMaxImageWidth: config.sam3Runtime.maxImageWidth,
        samMaxImageHeight: config.sam3Runtime.maxImageHeight,
        samResizeMethod: config.sam3Runtime.resizeMethod,
        samCompile: config.sam3Runtime.compile,
      );
      final displaySize = await _computeImageDisplaySize(image.path);
      final annotations = _sam3PreviewAnnotationsFromResult(
        result: result,
        displaySize: displaySize,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _sam3ClickPreviewsByImage[imageKey] = _Sam3ClickPreviewState(
          result: result,
          displaySize: displaySize,
          annotations: annotations,
        );
      });
      _log(
        'AI',
        'SAM3 click preview updated: image=${image.name}, masks=${result.masks.length}, preview=${annotations.length}',
      );
    } on Object catch (error) {
      final failure = _classifyAiFailure(error);
      _log(
        'AI',
        'SAM3 click preview failed: failure=$failure',
        level: _LogLevel.error,
      );
      _logMultiline(
        'AI',
        error.toString(),
        level: _LogLevel.error,
        prefix: 'detail: ',
      );
      _showFloatingMessage('${t('ai.failed')}: ${_shortAiError(error)}');
    } finally {
      if (mounted) {
        setState(() => _aiAnnotating = false);
      }
    }
  }

  List<_AnnotationRegion> _sam3PreviewAnnotationsFromResult({
    required _AiAnnotationResult result,
    required Size displaySize,
  }) {
    if (result.width <= 0 || result.height <= 0) {
      return const [];
    }
    final annotations = <_AnnotationRegion>[];
    for (var index = 0; index < result.masks.length; index += 1) {
      final mask = result.masks[index];
      final points = _scaleAiPoints(
        mask.points,
        sourceSize: Size(result.width, result.height),
        displaySize: displaySize,
      );
      if (points.length < 3) {
        continue;
      }
      final bounds = _pointsBounds(points).intersect(Offset.zero & displaySize);
      if (bounds.width < 2 || bounds.height < 2) {
        continue;
      }
      annotations.add(
        _AnnotationRegion(
          id: 'sam3_preview_$index',
          mode: _AnnotationMode.seg,
          rect: bounds,
          classId: _activeClassId ?? -1,
          points: points,
        ),
      );
    }
    return annotations;
  }

  Future<void> _commitSam3ClickPreview(_AiAssistConfig config) async {
    final image = _selectedImage;
    final imageKey = _selectedImageKey;
    if (image == null ||
        imageKey == null ||
        config.backend != _AiAssistBackend.sam3 ||
        config.sam3PromptMode != _AiSam3PromptMode.click) {
      return;
    }
    if (!_sam3ClickHasPositivePoint(image.path)) {
      _showFloatingMessage(t('ai.sam3ClickRequired'));
      return;
    }
    var preview = _sam3ClickPreviewsByImage[imageKey];
    if (preview == null) {
      await _runSam3ClickPreview(config);
      preview = _sam3ClickPreviewsByImage[imageKey];
    }
    if (preview == null) {
      return;
    }
    if (preview.result.masks.isEmpty) {
      _showFloatingMessage('${t('ai.done')} (0)');
      return;
    }
    final selectedClassName = await _promptSam3ClickSaveClassName(config);
    if (selectedClassName == null || selectedClassName.trim().isEmpty) {
      return;
    }
    final classCountBefore = _labelClasses.length;
    _pushAnnotationSnapshot();
    final added = _applyAiAnnotationResult(
      imagePath: image.path,
      displaySize: preview.displaySize,
      result: preview.result,
      config: config,
      classNameOverride: selectedClassName.trim(),
    );
    setState(() {
      _sam3ClickPreviewsByImage.remove(imageKey);
    });
    final classesChanged = _labelClasses.length != classCountBefore;
    if (classesChanged) {
      _broadcastCollaborationClassSnapshot('sam3 click preview saved');
    }
    if (added > 0 || classesChanged) {
      _scheduleAnnotationDatabaseSave();
    }
    _log('AI', 'SAM3 click preview saved: image=${image.name}, added=$added');
    _showFloatingMessage('${t('ai.done')} ($added)');
  }

  Future<void> _handleAiAssistSave(_AiAssistConfig config) async {
    if (config.backend == _AiAssistBackend.sam3 &&
        config.sam3PromptMode == _AiSam3PromptMode.click) {
      await _commitSam3ClickPreview(config);
    }
  }

  Future<String?> _promptSam3ClickSaveClassName(_AiAssistConfig config) async {
    final activeClass = _activeClassId == null
        ? null
        : _classById(_activeClassId!);
    final firstPrompt = config.sam3PromptText
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .firstOrNull;
    final initialName =
        activeClass?.name ??
        (_labelClasses.isNotEmpty ? _labelClasses.first.name : null) ??
        firstPrompt ??
        'sam3_click';
    final controller = TextEditingController(text: initialName);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(t('ai.sam3SaveClassTitle')),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: DropdownMenu<String>(
              controller: controller,
              requestFocusOnTap: true,
              enableFilter: true,
              width: 360,
              label: Text(t('ai.sam3SaveClassName')),
              hintText: t('ai.sam3SaveClassHint'),
              dropdownMenuEntries: [
                for (final labelClass in _labelClasses)
                  DropdownMenuEntry<String>(
                    value: labelClass.name,
                    label: labelClass.name,
                    leadingIcon: Icon(
                      Icons.square_rounded,
                      color: labelClass.color,
                      size: 16,
                    ),
                  ),
              ],
              onSelected: (value) {
                if (value != null) {
                  controller.text = value;
                }
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(t('action.cancel')),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) {
                  return;
                }
                Navigator.of(dialogContext).pop(value);
              },
              child: Text(t('action.save')),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<void> _runAiAnnotateForIndices(
    List<int> indices,
    _AiAssistConfig config,
  ) async {
    if (_aiAnnotating || indices.isEmpty) {
      return;
    }
    if (_appSettings.pythonPath.trim().isEmpty) {
      _log(
        'AI',
        'AI annotation blocked: Python path is empty',
        level: _LogLevel.warning,
      );
      _showFloatingMessage(t('detect.pythonNotConfigured'));
      return;
    }
    if (config.backend == _AiAssistBackend.yolo &&
        config.selectedClassIds.isEmpty) {
      _log(
        'AI',
        'AI annotation blocked: no classes selected',
        level: _LogLevel.warning,
      );
      _showFloatingMessage(t('ai.noSelectedClasses'));
      return;
    }
    if (config.backend == _AiAssistBackend.sam3 &&
        config.sam3PromptMode == _AiSam3PromptMode.text &&
        config.sam3PromptText.trim().isEmpty) {
      _log(
        'AI',
        'SAM3 annotation blocked: text prompt is empty',
        level: _LogLevel.warning,
      );
      _showFloatingMessage(t('ai.sam3PromptRequired'));
      return;
    }
    final targetIndices = [
      for (final index in indices)
        if (index >= 0 && index < _images.length) index,
    ];
    if (targetIndices.isEmpty) {
      _log(
        'AI',
        'AI annotation blocked: no valid target indices',
        level: _LogLevel.warning,
      );
      return;
    }
    var samClickPointsText = '';
    var samPromptFrameIndex = 0;
    String? samClickClassNameOverride;
    final isSam3ClickMode =
        config.backend == _AiAssistBackend.sam3 &&
        config.sam3PromptMode == _AiSam3PromptMode.click;
    if (isSam3ClickMode) {
      final promptImageIndex = _selectedImageIndex;
      if (!targetIndices.contains(promptImageIndex)) {
        _log(
          'AI',
          'SAM3 click annotation blocked: prompt image is outside the target range',
          level: _LogLevel.warning,
        );
        _showFloatingMessage(t('ai.sam3ClickCurrentOnly'));
        return;
      }
      final promptImage = _images[promptImageIndex];
      samPromptFrameIndex = targetIndices.indexOf(promptImageIndex);
      samClickPointsText = _sam3ClickPointsTextForImage(promptImage.path);
      if (samClickPointsText.trim().isEmpty ||
          !_sam3ClickHasPositivePoint(promptImage.path)) {
        _log(
          'AI',
          'SAM3 click annotation blocked: no positive click prompt points',
          level: _LogLevel.warning,
        );
        _showFloatingMessage(t('ai.sam3ClickRequired'));
        return;
      }
      if (targetIndices.length == 1 &&
          targetIndices.first == promptImageIndex) {
        await _runSam3ClickPreview(config);
        return;
      }
      samClickClassNameOverride = await _promptSam3ClickSaveClassName(config);
      if (samClickClassNameOverride == null ||
          samClickClassNameOverride.trim().isEmpty) {
        return;
      }
    }
    _log(
      'AI',
      'AI annotation started: backend=${config.backend.wireName}, targets=${targetIndices.length}, model=${_fileName(config.modelPath)}, classes=${config.selectedClassIds.length}, conf=${config.confThreshold.toStringAsFixed(2)}, imgsz=${config.imageSize}, sam3Mode=${config.sam3OutputMode.wireName}, prompt=${config.sam3PromptMode.wireName}, clickPoints=${samClickPointsText.trim().isEmpty ? 0 : samClickPointsText.trim().split('\n').length}, samPromptFrame=$samPromptFrameIndex, ${config.sam3Runtime.logSummary}',
    );

    setState(() => _aiAnnotating = true);
    await WidgetsBinding.instance.endOfFrame;
    var added = 0;
    final classCountBefore = _labelClasses.length;
    try {
      if (targetIndices.length == 1 &&
          targetIndices.first == _selectedImageIndex) {
        _pushAnnotationSnapshot();
      }
      if (targetIndices.length == 1) {
        final image = _images[targetIndices.first];
        final result = await _RustVideoBackend.aiAnnotateImage(
          backend: config.backend.wireName,
          pythonPath: _appSettings.pythonPath.trim(),
          modelPath: config.modelPath,
          inputPath: image.path,
          classIds: config.selectedClassIds.toList()..sort(),
          confThreshold: config.confThreshold,
          iouThreshold: 0.45,
          imgsz: config.imageSize,
          device: 'auto',
          samMode: config.sam3OutputMode.wireName,
          samPromptMode: config.sam3PromptMode.wireName,
          promptsText: config.sam3PromptText,
          samClickPointsText: samClickPointsText,
          samPrecision: config.sam3Runtime.precision,
          samEncoder: config.sam3Runtime.encoder,
          samImageBatchSize: config.sam3Runtime.imageBatchSize,
          samVideoBatchSize: config.sam3Runtime.videoBatchSize,
          samInteractiveBatchSize: config.sam3Runtime.interactiveBatchSize,
          samMaxImageWidth: config.sam3Runtime.maxImageWidth,
          samMaxImageHeight: config.sam3Runtime.maxImageHeight,
          samResizeMethod: config.sam3Runtime.resizeMethod,
          samCompile: config.sam3Runtime.compile,
        );
        final displaySize = await _computeImageDisplaySize(image.path);
        added += _applyAiAnnotationResult(
          imagePath: image.path,
          displaySize: displaySize,
          result: result,
          config: config,
          classNameOverride: samClickClassNameOverride,
        );
      } else if (targetIndices.isNotEmpty) {
        final targetImages = [
          for (final index in targetIndices) _images[index],
        ];
        final results = await _RustVideoBackend.aiAnnotateImages(
          backend: config.backend.wireName,
          pythonPath: _appSettings.pythonPath.trim(),
          modelPath: config.modelPath,
          inputPaths: [for (final image in targetImages) image.path],
          classIds: config.selectedClassIds.toList()..sort(),
          confThreshold: config.confThreshold,
          iouThreshold: 0.45,
          imgsz: config.imageSize,
          device: 'auto',
          samMode: config.sam3OutputMode.wireName,
          samPromptMode: config.sam3PromptMode.wireName,
          promptsText: config.sam3PromptText,
          samClickPointsText: samClickPointsText,
          samPromptFrameIndex: samPromptFrameIndex,
          samPrecision: config.sam3Runtime.precision,
          samEncoder: config.sam3Runtime.encoder,
          samImageBatchSize: config.sam3Runtime.imageBatchSize,
          samVideoBatchSize: config.sam3Runtime.videoBatchSize,
          samInteractiveBatchSize: config.sam3Runtime.interactiveBatchSize,
          samMaxImageWidth: config.sam3Runtime.maxImageWidth,
          samMaxImageHeight: config.sam3Runtime.maxImageHeight,
          samResizeMethod: config.sam3Runtime.resizeMethod,
          samCompile: config.sam3Runtime.compile,
        );
        for (final result in results) {
          final imagePath = result.inputPath.isEmpty ? null : result.inputPath;
          if (imagePath == null || !File(imagePath).existsSync()) {
            continue;
          }
          final displaySize = await _computeImageDisplaySize(imagePath);
          added += _applyAiAnnotationResult(
            imagePath: imagePath,
            displaySize: displaySize,
            result: result,
            config: config,
            classNameOverride: samClickClassNameOverride,
          );
        }
      }
      if (mounted) {
        setState(() {});
      }
      _log(
        'AI',
        'AI annotation completed: targets=${targetIndices.length}, added=$added',
      );
      final classesChanged = _labelClasses.length != classCountBefore;
      if (classesChanged) {
        _broadcastCollaborationClassSnapshot('ai classes changed');
      }
      if (added > 0 || classesChanged || isSam3ClickMode) {
        _scheduleAnnotationDatabaseSave();
      }
      _showFloatingMessage('${t('ai.done')} ($added)');
    } on Object catch (error) {
      final failure = _classifyAiFailure(error);
      _log(
        'AI',
        'AI annotation failed: backend=${config.backend.wireName}, failure=$failure',
        level: _LogLevel.error,
      );
      _logMultiline(
        'AI',
        error.toString(),
        level: _LogLevel.error,
        prefix: 'detail: ',
      );
      _showFloatingMessage('${t('ai.failed')}: ${_shortAiError(error)}');
    } finally {
      if (mounted) {
        setState(() => _aiAnnotating = false);
      }
    }
  }

  int _applyAiAnnotationResult({
    required String imagePath,
    required Size displaySize,
    required _AiAnnotationResult result,
    required _AiAssistConfig config,
    String? classNameOverride,
  }) {
    if (result.width <= 0 || result.height <= 0) {
      return 0;
    }
    final imageKey = _pathKey(imagePath);
    final annotations = _annotationsByImage.putIfAbsent(imageKey, () => []);
    var count = 0;
    if (config.backend == _AiAssistBackend.sam3) {
      final replaceSam3ClickAnnotations =
          config.sam3PromptMode == _AiSam3PromptMode.click;
      final generatedClickIds = <String>{};
      if (replaceSam3ClickAnnotations) {
        final previousIds = _sam3ClickAnnotationIdsByImage.remove(imageKey);
        if (previousIds != null && previousIds.isNotEmpty) {
          annotations.removeWhere(
            (annotation) => previousIds.contains(annotation.id),
          );
        }
      }
      for (final mask in result.masks) {
        final points = _scaleAiPoints(
          mask.points,
          sourceSize: Size(result.width, result.height),
          displaySize: displaySize,
        );
        if (points.length < 3) {
          continue;
        }
        final classId = _ensureLabelClassByName(
          classNameOverride?.trim().isNotEmpty == true
              ? classNameOverride!.trim()
              : mask.className,
        );
        final bounds = _pointsBounds(
          points,
        ).intersect(Offset.zero & displaySize);
        if (bounds.width < 2 || bounds.height < 2) {
          continue;
        }
        final mode = config.sam3OutputMode.annotationMode;
        final id = 'ann_${_annotationSerial++}';
        if (mode == _AnnotationMode.seg) {
          annotations.add(
            _AnnotationRegion(
              id: id,
              mode: _AnnotationMode.seg,
              rect: bounds,
              classId: classId,
              points: points,
              authorId: _collaborationAuthorId,
              authorName: _currentAnnotatorName,
              authorColorValue: _currentAnnotatorColorValue,
            ),
          );
        } else if (mode == _AnnotationMode.obb) {
          final oriented = _minimumAreaRect(points);
          annotations.add(
            _AnnotationRegion.fromRect(
              id: id,
              mode: _AnnotationMode.obb,
              rect: oriented.rect.intersect(Offset.zero & displaySize),
              classId: classId,
              authorId: _collaborationAuthorId,
              authorName: _currentAnnotatorName,
              authorColorValue: _currentAnnotatorColorValue,
            ).copyWith(rotationDegrees: oriented.rotationDegrees),
          );
        } else {
          annotations.add(
            _AnnotationRegion.fromRect(
              id: id,
              mode: _AnnotationMode.hbb,
              rect: bounds,
              classId: classId,
              authorId: _collaborationAuthorId,
              authorName: _currentAnnotatorName,
              authorColorValue: _currentAnnotatorColorValue,
            ),
          );
        }
        if (replaceSam3ClickAnnotations) {
          generatedClickIds.add(id);
        }
        count += 1;
      }
      if (replaceSam3ClickAnnotations) {
        _sam3ClickAnnotationIdsByImage[imageKey] = generatedClickIds;
      }
      _log(
        'AI',
        'SAM3 annotations applied: image=${_fileName(imagePath)}, mode=${config.sam3OutputMode.wireName}, prompt=${config.sam3PromptMode.wireName}, masks=${result.masks.length}, added=$count',
        level: _LogLevel.debug,
      );
      return count;
    }
    for (final box in result.boxes) {
      final annotation = _annotationFromAiBox(
        box: box,
        sourceSize: Size(result.width, result.height),
        displaySize: displaySize,
      );
      if (annotation == null) {
        continue;
      }
      annotations.add(annotation);
      count += 1;
    }
    return count;
  }

  _AnnotationRegion? _annotationFromAiBox({
    required _AiPredictionBox box,
    required Size sourceSize,
    required Size displaySize,
  }) {
    final classId = _ensureLabelClassByName(box.className);
    final rect = Rect.fromLTRB(
      box.rect.left / sourceSize.width * displaySize.width,
      box.rect.top / sourceSize.height * displaySize.height,
      box.rect.right / sourceSize.width * displaySize.width,
      box.rect.bottom / sourceSize.height * displaySize.height,
    ).intersect(Offset.zero & displaySize);
    if (rect.width < 2 || rect.height < 2) {
      return null;
    }
    return _AnnotationRegion.fromRect(
      id: 'ann_${_annotationSerial++}',
      mode: _AnnotationMode.hbb,
      rect: rect,
      classId: classId,
      authorId: _collaborationAuthorId,
      authorName: _currentAnnotatorName,
      authorColorValue: _currentAnnotatorColorValue,
    );
  }

  int _ensureLabelClassByName(String rawName) {
    final name = rawName.trim().isEmpty
        ? 'class_${_labelClasses.length}'
        : rawName.trim();
    for (final labelClass in _labelClasses) {
      if (labelClass.name.toLowerCase() == name.toLowerCase()) {
        return labelClass.id;
      }
    }
    final id = _classSerial++;
    _labelClasses.add(
      _LabelClass(id: id, name: name, colorValue: _nextClassColor().toARGB32()),
    );
    _activeClassId ??= id;
    return id;
  }

  Future<void> _showExportDialog() async {
    final config = await showDialog<_ExportConfig>(
      context: context,
      builder: (context) => _ExportDialog(exportPath: _appSettings.exportPath),
    );
    if (config == null || !mounted) return;
    final importedDataset = _importedDataset;
    String? dataYamlPath;
    if (importedDataset != null) {
      final overwrite = await _confirmOverwriteImportedDataset();
      if (overwrite == null || !mounted) {
        return;
      }
      if (overwrite) {
        dataYamlPath = await _exportImportedDataset(config, importedDataset);
      } else {
        dataYamlPath = await _exportAnnotations(config);
      }
    } else {
      dataYamlPath = await _exportAnnotations(config);
    }
    if (config.trainAfterExport && dataYamlPath != null && mounted) {
      await _trainFromExportedDataset(dataYamlPath);
    }
  }

  Future<void> _trainFromExportedDataset(String dataYamlPath) async {
    _log('EXPORT', 'Export auto training requested: data_yaml=$dataYamlPath');
    setState(() => _activeSection = 'train');
    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return;
    }
    final trainPage = _trainPageKey.currentState;
    if (trainPage == null) {
      _log(
        'EXPORT',
        'Export auto training skipped: training page is not ready',
        level: _LogLevel.warning,
      );
      return;
    }
    await trainPage._loadExportedDatasetAndStartTraining(dataYamlPath);
  }

  Future<bool?> _confirmOverwriteImportedDataset() async {
    return _showOverwriteImportedDatasetDialog(context);
  }

  Future<Size> _computeImageDisplaySize(String imagePath) async {
    final displaySize = await _computeImageDisplaySizeForPath(imagePath);
    _imageDisplaySizes[_pathKey(imagePath)] = displaySize;
    return displaySize;
  }

  Future<String?> _exportAnnotations(_ExportConfig config) async {
    _log(
      'EXPORT',
      'Export started: ${config.folderName} (train=${config.trainRatio.toStringAsFixed(0)}% val=${config.valRatio.toStringAsFixed(0)}% test=${config.testRatio.toStringAsFixed(0)}%)',
    );
    final result = await _exportAnnotationsToNewDataset(
      config: config,
      exportRoot: _appSettings.exportPath,
      images: _images,
      labelClasses: _labelClasses,
      annotationsByImage: _annotationsByImage,
      displaySizeForImagePath: _displaySizeForImagePath,
      ensureDisplaySizeForImagePath: _computeImageDisplaySize,
    );
    if (result == null) {
      _log(
        'EXPORT',
        'Export skipped: no images or annotations to export',
        level: _LogLevel.warning,
      );
      _showFloatingMessage(t('export.noData'));
      return null;
    }
    _log(
      'EXPORT',
      'Export completed: path=${result.outputPath}, images=${result.imageCount}, annotations=${result.annotationCount}, train=${result.trainCount}, val=${result.valCount}, test=${result.testCount}, exportImages=${result.exportImages}, skipEmpty=${result.skipEmpty}',
    );
    _showFloatingMessage(
      '${t('export.done')} (${t('export.folderName')}: ${config.folderName})',
    );
    return result.dataYamlPath;
  }

  Future<String?> _exportImportedDataset(
    _ExportConfig config,
    _ImportedDataset dataset,
  ) async {
    _log(
      'EXPORT',
      'Overwrite imported dataset started: yaml=${dataset.dataYamlPath}',
    );
    final result = await _overwriteImportedDatasetExport(
      config: config,
      dataset: dataset,
      images: _images,
      labelClasses: _labelClasses,
      annotationsByImage: _annotationsByImage,
      imageSplits: _imageSplits,
      displaySizeForImagePath: _displaySizeForImagePath,
      ensureDisplaySizeForImagePath: _computeImageDisplaySize,
    );
    if (result == null) {
      _log(
        'EXPORT',
        'Overwrite imported dataset skipped: no data',
        level: _LogLevel.warning,
      );
      _showFloatingMessage(t('export.noData'));
      return null;
    }
    _log(
      'EXPORT',
      'Overwrite imported dataset completed: yaml=${result.dataYamlPath}, images=${result.imageCount}, annotations=${result.annotationCount}, train=${result.trainCount}, val=${result.valCount}, test=${result.testCount}, exportImages=${result.exportImages}, skipEmpty=${result.skipEmpty}',
    );
    _showFloatingMessage(t('export.done'));
    return result.dataYamlPath;
  }

  void _pasteAnnotation() {
    final imageKey = _selectedImageKey;
    final copied = _copiedAnnotation;
    if (imageKey == null || copied == null || !_selectedImageAuthorized) {
      return;
    }
    _pushAnnotationSnapshot();
    final pasted = copied
        .duplicate('ann_${_annotationSerial++}')
        .copyWith(
          authorId: _collaborationAuthorId,
          authorName: _currentAnnotatorName,
          authorColorValue: _currentAnnotatorColorValue,
        );
    setState(() {
      _annotationsByImage.putIfAbsent(imageKey, () => []).add(pasted);
      _selectedAnnotationId = pasted.id;
    });
    _log(
      'ANNOTATION',
      'Pasted annotation: source=${copied.id}, pasted=${pasted.id}',
      level: _LogLevel.debug,
    );
    _scheduleAnnotationDatabaseSave();
  }

  void _rotateSelectedAnnotation(double deltaDegrees) {
    final selectedId = _selectedAnnotationId;
    if (selectedId == null) {
      return;
    }
    final selected = _currentAnnotations
        .where((annotation) => annotation.id == selectedId)
        .firstOrNullValue;
    if (selected == null || selected.mode != _AnnotationMode.obb) {
      return;
    }
    if (!_canModifyAnnotation(selected, action: 'edit')) {
      _showFloatingMessage(t('collab.permissionDenied'));
      return;
    }
    _pushAnnotationSnapshot();
    final rotated = selected.rotated(deltaDegrees);
    final imageSize = _imageDisplaySize;
    _updateAnnotation(
      imageSize != null && imageSize != Size.zero
          ? rotated.clampObbToImage(imageSize)
          : rotated,
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (_activeSection != 'label' || _zoomLocked) {
      return;
    }
    if (event is PointerScrollEvent) {
      _setZoom(_zoom + (event.scrollDelta.dy < 0 ? 10 : -10));
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (_collaborationReconnecting) {
      return event is KeyDownEvent || event is KeyRepeatEvent
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }

    if (_importingDataset) {
      return event is KeyDownEvent || event is KeyRepeatEvent
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }

    if (_isEditableTextFocused()) {
      return KeyEventResult.ignored;
    }

    if (_activeSection == 'browse' && !_shortcutDialogOpen) {
      final result = _detectVideoSession.handleShortcutKey(
        event,
        _shortcutConfig,
      );
      if (result == KeyEventResult.handled) {
        return result;
      }
    }

    if ((event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        _activeSection != 'label' ||
        _shortcutDialogOpen) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final repeated = event is KeyRepeatEvent;
    final imageStep = repeated ? 3 : 1;
    if (HardwareKeyboard.instance.isControlPressed) {
      if (key == LogicalKeyboardKey.keyZ) {
        _undoAnnotationChange();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyY) {
        _redoAnnotationChange();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyC) {
        _copySelectedAnnotation();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyV) {
        _pasteAnnotation();
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.escape) {
      setState(() {
        _activeTool = 'select';
        _selectedAnnotationId = null;
      });
      return KeyEventResult.handled;
    }

    if (_shortcutConfig.matches(_ShortcutAction.previousImage, key)) {
      if (!_selectPreviousImage(step: imageStep)) {
        _showFloatingMessage(t('detect.hudNoPrevious'));
      }
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.nextImage, key)) {
      if (!_selectNextImage(step: imageStep)) {
        _showFloatingMessage(t('detect.hudNoNext'));
      }
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.zoomIn, key)) {
      _setZoom(_zoom + 10);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.zoomOut, key)) {
      _setZoom(_zoom - 10);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.hbbMode, key)) {
      _activateAnnotationMode(_AnnotationMode.hbb);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.obbMode, key)) {
      _activateAnnotationMode(_AnnotationMode.obb);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.segMode, key)) {
      _activateAnnotationMode(_AnnotationMode.seg);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.deleteSelected, key)) {
      _deleteSelectedAnnotation();
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.hideClassLabels, key)) {
      setState(() => _showClassLabels = !_showClassLabels);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.rotateObbLeft5, key)) {
      _rotateSelectedAnnotation(-5);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.rotateObbLeft1, key)) {
      _rotateSelectedAnnotation(-1);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.rotateObbRight1, key)) {
      _rotateSelectedAnnotation(1);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.rotateObbRight5, key)) {
      _rotateSelectedAnnotation(5);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.aiAnnotateCurrent, key)) {
      unawaited(_runAiAnnotateCurrent());
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(_ShortcutAction.aiAnnotateAll, key)) {
      unawaited(_runAiAnnotateAll());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _toggleThemeMode() {
    final nextDarkMode = !_darkMode;
    setState(() {
      _darkMode = nextDarkMode;
      _appSettings = _appSettings.copyWith(darkMode: nextDarkMode);
    });
    _themeModeNotifier.value = nextDarkMode ? ThemeMode.dark : ThemeMode.light;
    _ConfigStore.saveSettings(_appSettings);
  }

  void _updateShortcut(_ShortcutAction action, LogicalKeyboardKey key) {
    setState(() {
      _shortcutConfig = _shortcutConfig.copyWith(action: action, key: key);
    });
    _saveKeybindings();
  }

  void _resetShortcuts() {
    setState(() => _shortcutConfig = _ShortcutConfig.defaults());
    _saveKeybindings();
  }

  void _clearRecentItems() {
    setState(() {
      _recentFolders.clear();
      _recentFiles.clear();
    });
    _saveHistory();
  }

  void _showTopMenu() {
    _topMenuHideTimer?.cancel();
    if (!_topMenuVisible) {
      setState(() => _topMenuVisible = true);
    }
  }

  void _scheduleTopMenuHide() {
    _topMenuHideTimer?.cancel();
    _topMenuHideTimer = Timer(_topMenuAutoHideDelay, () {
      if (!mounted || !_topMenuVisible) {
        return;
      }
      setState(() => _topMenuVisible = false);
    });
  }

  Future<void> _showKeySettings() async {
    setState(() => _shortcutDialogOpen = true);
    await showDialog<void>(
      context: context,
      builder: (context) => _ShortcutSettingsDialog(
        config: _shortcutConfig,
        onShortcutChanged: _updateShortcut,
        onReset: _resetShortcuts,
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() => _shortcutDialogOpen = false);
    _keyboardFocusNode.requestFocus();
  }

  Future<void> _showSettings() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _SettingsDialog(
        initialSettings: _appSettings,
        cacheSizeBytes: _ConfigStore.cacheSizeInBytes(),
        onSave: _saveAppSettings,
        onClearCache: _clearCacheData,
      ),
    );
    if (mounted) {
      _keyboardFocusNode.requestFocus();
    }
  }

  Future<void> _showAboutDialog() async {
    await _showAboutDialogForContext(context);
    if (mounted) {
      _keyboardFocusNode.requestFocus();
    }
  }

  Future<void> _showLogViewerDialog() async {
    if (!mounted) return;
    await _showLogViewerDialogForContext(
      context: context,
      onMessage: _showFloatingMessage,
    );
    if (mounted) {
      _keyboardFocusNode.requestFocus();
    }
  }

  Future<int> _clearCacheData() async {
    setState(() {
      _recentFolders.clear();
      _recentFiles.clear();
      _labelClasses.clear();
      _annotationsByImage.clear();
      _imageSplits.clear();
      _importedDataset = null;
      _undoStack.clear();
      _redoStack.clear();
      _activeClassId = null;
      _selectedAnnotationId = null;
    });
    _saveHistory();
    unawaited(_saveAnnotationDatabaseNow());
    return _ConfigStore.cacheSizeInBytes();
  }

  void _startCollaborationPolling() {
    _collaborationPollTimer?.cancel();
    _collaborationPollTimer = Timer.periodic(
      const Duration(milliseconds: 350),
      (_) => _pollCollaborationEvents(),
    );
  }

  void _restartCollaborationDiscovery() {
    if (_collaborationMode != _CollaborationMode.off) {
      return;
    }
    unawaited(
      _RustVideoBackend.collaborationCommand(
        request: {'action': 'start_discovery', 'port': _collaborationPort},
      ).catchError((Object error) {
        _log(
          'COLLAB',
          'Discovery start failed: $error',
          level: _LogLevel.warning,
        );
        return <String, dynamic>{};
      }),
    );
  }

  Future<void> _pollCollaborationEvents() async {
    if (_collaborationPollInFlight) {
      return;
    }
    _collaborationPollInFlight = true;
    try {
      final events = await _RustVideoBackend.collaborationPollEvents(
        maxEvents: 50,
      );
      if (!mounted || events.isEmpty) {
        return;
      }
      for (final event in events) {
        _handleCollaborationEvent(event);
      }
    } on Object catch (error) {
      _log('COLLAB', 'Event poll failed: $error', level: _LogLevel.debug);
    } finally {
      _collaborationPollInFlight = false;
    }
  }

  void _handleCollaborationEvent(Map<String, dynamic> event) {
    switch (_collaborationString(event, 'type')) {
      case 'host_found':
        _upsertDiscoveredHost(event);
        break;
      case 'join_request':
        _handleCollaborationJoinRequest(event);
        break;
      case 'tcp_message':
        _handleCollaborationTcpMessage(event);
        break;
      case 'client_disconnected':
        _markCollaborationPeerOffline(_collaborationString(event, 'userId'));
        break;
      case 'host_disconnected':
        if (_collaborationMode == _CollaborationMode.client) {
          _startCollaborationReconnect();
        }
        break;
      case 'network_error':
        _log(
          'COLLAB',
          'Network error: ${event['scope'] ?? '-'} ${event['error'] ?? ''}',
          level: _LogLevel.warning,
        );
        if (_collaborationMode == _CollaborationMode.host &&
            _collaborationString(event, 'scope') == 'host_tcp') {
          setState(() {
            _collaborationMode = _CollaborationMode.off;
            _collaborationPeers.clear();
            _pendingCollaborationJoinRequests.clear();
          });
          _showFloatingMessage(t('collab.networkError'));
          unawaited(
            _RustVideoBackend.collaborationCommand(
                  request: const {'action': 'stop'},
                )
                .catchError((Object error) {
                  _log(
                    'COLLAB',
                    'Stop after host TCP error failed: $error',
                    level: _LogLevel.debug,
                  );
                  return <String, dynamic>{};
                })
                .whenComplete(_restartCollaborationDiscovery),
          );
        }
        break;
      default:
        break;
    }
  }

  void _upsertDiscoveredHost(Map<String, dynamic> event) {
    if (_collaborationMode == _CollaborationMode.host) {
      return;
    }
    final hostId = _collaborationString(event, 'hostId');
    if (hostId.isEmpty || hostId == _collaborationHostId) {
      return;
    }
    final host = _CollaborationDiscoveredHost(
      hostId: hostId,
      hostName: _collaborationString(event, 'hostName').trim().isEmpty
          ? 'Host'
          : _collaborationString(event, 'hostName'),
      address: _collaborationString(event, 'address'),
      port: _collaborationInt(event, 'port', fallback: _collaborationPort),
      online: true,
    );
    setState(() {
      final index = _collaborationDiscoveredHosts.indexWhere(
        (item) => item.hostId == host.hostId,
      );
      if (index >= 0) {
        _collaborationDiscoveredHosts[index] = host;
      } else {
        _collaborationDiscoveredHosts.add(host);
      }
      if (_selectedCollaborationHostId == null ||
          !_collaborationDiscoveredHosts.any(
            (item) => item.hostId == _selectedCollaborationHostId,
          )) {
        _selectedCollaborationHostId = host.hostId;
      }
      _collaborationDiscoveredHosts.sort(
        (a, b) => a.hostName.toLowerCase().compareTo(b.hostName.toLowerCase()),
      );
    });
  }

  void _handleCollaborationJoinRequest(Map<String, dynamic> event) {
    if (_collaborationMode != _CollaborationMode.host) {
      return;
    }
    final userId = _collaborationString(event, 'userId');
    if (userId.isEmpty || _pendingCollaborationJoinRequests.contains(userId)) {
      return;
    }
    _pendingCollaborationJoinRequests.add(userId);
    unawaited(_confirmCollaborationJoin(event));
  }

  Future<void> _confirmCollaborationJoin(Map<String, dynamic> event) async {
    final userId = _collaborationString(event, 'userId');
    final userName = _collaborationString(event, 'userName').trim().isEmpty
        ? 'User'
        : _collaborationString(event, 'userName');
    final address = _collaborationString(event, 'address');
    final colorValue = _collaborationInt(
      event,
      'colorValue',
      fallback: _collaborationColorForId(userId).toARGB32(),
    );
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('collab.joinRequestTitle')),
        content: Text(
          '${t('collab.joinRequestBody')}\n$userName#${_shortCollaborationId(userId)}\n$address',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t('collab.reject')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t('collab.allow')),
          ),
        ],
      ),
    );
    _pendingCollaborationJoinRequests.remove(userId);
    if (!mounted) {
      return;
    }
    if (allow == true) {
      final permissions = const _CollaborationPermissions();
      final assignmentStart = _collaborationStartIndex
          .clamp(1, math.max(1, _images.length))
          .toInt();
      final assignmentEnd = _collaborationEndIndex
          .clamp(assignmentStart, math.max(1, _images.length))
          .toInt();
      setState(() {
        _upsertCollaborationPeer(
          _CollaborationPeer(
            userId: userId,
            userName: userName,
            colorValue: colorValue,
            address: address,
            online: true,
            assignmentStart: assignmentStart,
            assignmentEnd: assignmentEnd,
            permissions: permissions,
          ),
        );
      });
      await _sendCollaborationCommand({
        'action': 'host_accept',
        'userId': userId,
        'hostId': _collaborationHostId,
        'assignmentStart': assignmentStart,
        'assignmentEnd': assignmentEnd,
        'canEditOthers': permissions.canEditOthers,
        'canDeleteOthers': permissions.canDeleteOthers,
        'canChangeClass': permissions.canChangeClass,
      });
      _sendCollaborationMessageToPeer(
        userId,
        _collaborationProjectSnapshotMessage(
          assignmentStart: assignmentStart,
          assignmentEnd: assignmentEnd,
        ),
      );
      _broadcastCollaborationMessage({
        'type': 'peer_joined',
        'userId': userId,
        'userName': userName,
        'colorValue': colorValue,
        'address': address,
      });
      _scheduleAnnotationDatabaseSave();
      _showFloatingMessage(t('collab.joinAccepted'));
      _log('COLLAB', 'Join accepted: user=$userId, address=$address');
    } else {
      await _sendCollaborationCommand({
        'action': 'host_reject',
        'userId': userId,
        'reason': 'rejected',
      });
      _log('COLLAB', 'Join rejected: user=$userId, address=$address');
    }
  }

  void _handleCollaborationTcpMessage(Map<String, dynamic> event) {
    final message = _collaborationMap(event['message']);
    switch (_collaborationString(message, 'type')) {
      case 'join_accepted':
        setState(() {
          _collaborationMode = _CollaborationMode.client;
          _collaborationJoining = false;
          _collaborationReconnecting = false;
          _collaborationReconnectAttempts = 0;
          _collaborationReconnectTimer?.cancel();
          _collaborationStartIndex = _collaborationInt(
            message,
            'assignmentStart',
            fallback: 1,
          );
          _collaborationEndIndex = _collaborationInt(
            message,
            'assignmentEnd',
            fallback: math.max(1, _images.length),
          );
          final permissions = _collaborationMap(message['permissions']);
          _collaborationSelfPermissions = _CollaborationPermissions(
            canEditOthers: _collaborationBool(permissions, 'canEditOthers'),
            canDeleteOthers: _collaborationBool(permissions, 'canDeleteOthers'),
            canChangeClass: _collaborationBool(permissions, 'canChangeClass'),
          );
          final host = _connectedCollaborationHost;
          if (host != null) {
            _upsertCollaborationPeer(
              _CollaborationPeer(
                userId: host.hostId,
                userName: host.hostName,
                address: '${host.address}:${host.port}',
                colorValue: _collaborationColorForId(host.hostId).toARGB32(),
                online: true,
              ),
            );
          }
        });
        unawaited(_saveCollaborationAnnotationDatabaseNow('join accepted'));
        _showFloatingMessage(t('collab.joined'));
        _log('COLLAB', 'Join accepted by host');
        break;
      case 'join_rejected':
        setState(() => _collaborationJoining = false);
        _showFloatingMessage(t('collab.joinRejected'));
        _disconnectCollaborationClient(clearProject: true);
        break;
      case 'permission_update':
        final permissions = _collaborationMap(message['permissions']);
        setState(() {
          _collaborationSelfPermissions = _CollaborationPermissions(
            canEditOthers: _collaborationBool(permissions, 'canEditOthers'),
            canDeleteOthers: _collaborationBool(permissions, 'canDeleteOthers'),
            canChangeClass: _collaborationBool(permissions, 'canChangeClass'),
          );
          _collaborationStartIndex = _collaborationInt(
            message,
            'assignmentStart',
            fallback: _collaborationStartIndex,
          );
          _collaborationEndIndex = _collaborationInt(
            message,
            'assignmentEnd',
            fallback: _collaborationEndIndex,
          );
          _moveToFirstAuthorizedCollaborationImage();
        });
        unawaited(
          _saveCollaborationAnnotationDatabaseNow('permissions updated'),
        );
        _showFloatingMessage(t('collab.permissionsUpdated'));
        break;
      case 'assignment_update':
        setState(() {
          _collaborationStartIndex = _collaborationInt(
            message,
            'assignmentStart',
            fallback: _collaborationStartIndex,
          );
          _collaborationEndIndex = _collaborationInt(
            message,
            'assignmentEnd',
            fallback: _collaborationEndIndex,
          );
          _moveToFirstAuthorizedCollaborationImage();
        });
        unawaited(
          _saveCollaborationAnnotationDatabaseNow('assignment updated'),
        );
        break;
      case 'peer_joined':
        final userId = _collaborationString(message, 'userId');
        if (userId.isNotEmpty && userId != _collaborationAuthorId) {
          setState(() {
            _upsertCollaborationPeer(
              _CollaborationPeer(
                userId: userId,
                userName: _collaborationString(message, 'userName'),
                colorValue: _collaborationInt(
                  message,
                  'colorValue',
                  fallback: _collaborationColorForId(userId).toARGB32(),
                ),
                address: _collaborationString(message, 'address'),
                online: true,
              ),
            );
          });
          unawaited(_saveCollaborationAnnotationDatabaseNow('peer joined'));
        }
        break;
      case 'annotation_snapshot':
        _applyCollaborationAnnotationSnapshot(
          message,
          fromUserId: _collaborationString(event, 'fromUserId'),
        );
        break;
      case 'class_snapshot':
        if (_collaborationMode == _CollaborationMode.client) {
          _applyCollaborationClassSnapshot(message);
        }
        break;
      case 'project_snapshot':
        if (_collaborationMode == _CollaborationMode.client) {
          _applyCollaborationProjectSnapshot(message);
        }
        break;
      default:
        break;
    }
  }

  void _publishCurrentCollaborationAnnotations() {
    if (_collaborationMode == _CollaborationMode.off ||
        !_selectedImageAuthorized) {
      return;
    }
    final image = _selectedImage;
    if (image == null) {
      return;
    }
    final limitedToOwnAnnotations =
        _collaborationMode == _CollaborationMode.client &&
        !_collaborationSelfPermissions.canEditOthers &&
        !_collaborationSelfPermissions.canDeleteOthers &&
        !_collaborationSelfPermissions.canChangeClass;
    final annotations = limitedToOwnAnnotations
        ? _currentAnnotations
              .where(
                (annotation) =>
                    annotation.authorId.isEmpty ||
                    annotation.authorId == _collaborationAuthorId,
              )
              .toList(growable: false)
        : _currentAnnotations;
    final message = <String, Object?>{
      'type': 'annotation_snapshot',
      'imagePath': image.path,
      'imageIndex': _selectedImageIndex + 1,
      'sourceUserId': _collaborationAuthorId,
      'authoritative': !limitedToOwnAnnotations,
      if (limitedToOwnAnnotations) 'authorScope': _collaborationAuthorId,
      if (_collaborationMode == _CollaborationMode.host)
        'classes': _collaborationClassesPayload(),
      'annotations': [
        for (final annotation in annotations)
          _collaborationAnnotationToJson(annotation),
      ],
    };
    if (_collaborationMode == _CollaborationMode.host) {
      _sendCollaborationMessageToAuthorizedPeers(message, _selectedImageIndex);
    } else {
      unawaited(
        _sendCollaborationCommand({
          'action': 'send_host',
          'message': jsonEncode(message),
        }),
      );
    }
  }

  Map<String, Object?> _collaborationProjectSnapshotMessage({
    int? assignmentStart,
    int? assignmentEnd,
  }) {
    final start = assignmentStart ?? _collaborationStartIndex;
    final end = assignmentEnd ?? _collaborationEndIndex;
    return {
      'type': 'project_snapshot',
      'projectKey': _databaseProjectKey(),
      'assignmentStart': start,
      'assignmentEnd': end,
      'images': [
        for (var index = 0; index < _images.length; index++)
          {
            'path': _images[index].path,
            'name': _images[index].name,
            'split': _imageSplits[_pathKey(_images[index].path)] ?? 'train',
            'width':
                (_displaySizeForImagePath(_images[index].path) ?? Size.zero)
                    .width,
            'height':
                (_displaySizeForImagePath(_images[index].path) ?? Size.zero)
                    .height,
            'index': index + 1,
            if (index + 1 >= start && index + 1 <= end)
              'bytesBase64': _collaborationImageBytesBase64(
                _images[index].path,
              ),
          },
      ],
      'classes': _collaborationClassesPayload(),
      'annotationsByImage': [
        for (var index = 0; index < _images.length; index++)
          if (index + 1 >= start && index + 1 <= end)
            {
              'imageIndex': index + 1,
              'imagePath': _images[index].path,
              'annotations': [
                for (final annotation in _annotationsForImagePath(
                  _images[index].path,
                ))
                  _collaborationAnnotationToJson(annotation),
              ],
            },
      ],
    };
  }

  List<Map<String, Object?>> _collaborationClassesPayload() {
    return [
      for (final labelClass in _labelClasses)
        {
          'id': labelClass.id,
          'name': labelClass.name,
          'color': labelClass.colorValue,
        },
    ];
  }

  Map<String, Object?> _collaborationClassSnapshotMessage() {
    return {
      'type': 'class_snapshot',
      'classes': _collaborationClassesPayload(),
    };
  }

  void _replaceLabelClassesFromCollaboration(List<_LabelClass> classes) {
    _labelClasses
      ..clear()
      ..addAll(classes);
    if (_activeClassId == null ||
        !_labelClasses.any((item) => item.id == _activeClassId)) {
      _activeClassId = _labelClasses.isEmpty ? null : _labelClasses.first.id;
    }
    _classSerial = math.max(_classSerial, _nextClassSerialFor(classes));
  }

  String _collaborationImageBytesBase64(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        return '';
      }
      return base64Encode(file.readAsBytesSync());
    } on Object catch (error) {
      _log(
        'COLLAB',
        'Image payload read failed: path=$path, error=$error',
        level: _LogLevel.warning,
      );
      return '';
    }
  }

  String _collaborationLocalImagePath({
    required String remotePath,
    required String name,
    required String bytesBase64,
  }) {
    if (File(remotePath).existsSync() || bytesBase64.trim().isEmpty) {
      return remotePath;
    }
    try {
      final bytes = base64Decode(bytesBase64);
      final cacheDir = Directory(
        '${_ConfigStore.projectDirectory.path}\\collaboration_cache',
      );
      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }
      final fileName = _collaborationCacheFileName(remotePath, name);
      final file = File('${cacheDir.path}\\$fileName');
      file.writeAsBytesSync(bytes);
      return file.path;
    } on Object catch (error) {
      _log(
        'COLLAB',
        'Image payload write failed: path=$remotePath, error=$error',
        level: _LogLevel.warning,
      );
      return remotePath;
    }
  }

  void _applyCollaborationProjectSnapshot(Map<String, dynamic> message) {
    final rawImages = message['images'];
    if (rawImages is! List) {
      return;
    }

    final nextImages = <_ImageItem>[];
    final nextSplits = <String, String>{};
    final nextSizes = <String, Size>{};
    final remoteToLocalImagePath = <String, String>{};
    for (final rawImage in rawImages) {
      final image = _collaborationMap(rawImage);
      final path = _collaborationString(image, 'path');
      if (path.isEmpty) {
        continue;
      }
      final name = _collaborationString(image, 'name').trim().isEmpty
          ? _fileName(path)
          : _collaborationString(image, 'name');
      final localPath = _collaborationLocalImagePath(
        remotePath: path,
        name: name,
        bytesBase64: _collaborationString(image, 'bytesBase64'),
      );
      final imageKey = _pathKey(localPath);
      remoteToLocalImagePath[_pathKey(path)] = localPath;
      nextImages.add(_ImageItem(path: localPath, name: name));
      nextSplits[imageKey] = _collaborationString(image, 'split').trim().isEmpty
          ? 'train'
          : _collaborationString(image, 'split');
      nextSizes[imageKey] = Size(
        _collaborationDouble(image, 'width'),
        _collaborationDouble(image, 'height'),
      );
    }
    if (nextImages.isEmpty) {
      return;
    }

    final nextClasses = _collaborationClassesFromJson(message['classes']);
    final nextClassSerial = _nextClassSerialFor(nextClasses);

    final nextAnnotations = <String, List<_AnnotationRegion>>{};
    var maxAnnotationSerial = _annotationSerial;
    final rawAnnotationsByImage = message['annotationsByImage'];
    if (rawAnnotationsByImage is List) {
      for (final rawEntry in rawAnnotationsByImage) {
        final entry = _collaborationMap(rawEntry);
        final imagePath = _collaborationString(entry, 'imagePath');
        final imageIndex =
            _collaborationInt(entry, 'imageIndex', fallback: 0) - 1;
        final localImagePath = imageIndex >= 0 && imageIndex < nextImages.length
            ? nextImages[imageIndex].path
            : remoteToLocalImagePath[_pathKey(imagePath)] ?? imagePath;
        if (localImagePath.isEmpty) {
          continue;
        }
        final rawAnnotations = entry['annotations'];
        if (rawAnnotations is! List) {
          continue;
        }
        final annotations = rawAnnotations
            .map(_collaborationAnnotationFromJson)
            .whereType<_AnnotationRegion>()
            .toList();
        for (final annotation in annotations) {
          final match = RegExp(r'^ann_(\d+)$').firstMatch(annotation.id);
          if (match != null) {
            final serial = int.tryParse(match.group(1) ?? '');
            if (serial != null && serial >= maxAnnotationSerial) {
              maxAnnotationSerial = serial + 1;
            }
          }
        }
        nextAnnotations[_pathKey(localImagePath)] = annotations;
      }
    }

    final snapshotStart = _collaborationInt(
      message,
      'assignmentStart',
      fallback: _collaborationStartIndex,
    );
    final snapshotEnd = _collaborationInt(
      message,
      'assignmentEnd',
      fallback: _collaborationEndIndex,
    );
    final firstAuthorizedIndex = (snapshotStart - 1)
        .clamp(0, nextImages.length - 1)
        .toInt();
    setState(() {
      _collaborationStartIndex = snapshotStart;
      _collaborationEndIndex = snapshotEnd;
      _images
        ..clear()
        ..addAll(nextImages);
      _imageSplits
        ..clear()
        ..addAll(nextSplits);
      _imageDisplaySizes
        ..clear()
        ..addAll(nextSizes);
      _replaceLabelClassesFromCollaboration(nextClasses);
      _annotationsByImage
        ..clear()
        ..addAll(nextAnnotations);
      _importedDataset = null;
      _selectedImageIndex = firstAuthorizedIndex;
      _selectedAnnotationId = null;
      _activeClassId = nextClasses.isEmpty ? null : nextClasses.first.id;
      _classSerial = math.max(_classSerial, nextClassSerial);
      _annotationSerial = math.max(_annotationSerial, maxAnnotationSerial);
      _undoStack.clear();
      _redoStack.clear();
      _moveToFirstAuthorizedCollaborationImage();
      _activeSection = 'label';
    });
    unawaited(_saveCollaborationAnnotationDatabaseNow('project snapshot'));
  }

  void _applyCollaborationClassSnapshot(Map<String, dynamic> message) {
    if (message['classes'] is! List) {
      return;
    }
    final nextClasses = _collaborationClassesFromJson(message['classes']);
    setState(() {
      _replaceLabelClassesFromCollaboration(nextClasses);
    });
    unawaited(_saveCollaborationAnnotationDatabaseNow('class snapshot'));
  }

  Map<String, Object?> _collaborationAnnotationToJson(
    _AnnotationRegion annotation,
  ) {
    final rect = annotation.rect;
    final authorId = annotation.authorId.trim().isEmpty
        ? _collaborationAuthorId
        : annotation.authorId;
    final authorName = annotation.authorName.trim().isEmpty
        ? _currentAnnotatorName
        : annotation.authorName;
    final authorColor = annotation.authorColorValue == 0
        ? _currentAnnotatorColorValue
        : annotation.authorColorValue;
    return {
      'id': annotation.id,
      'mode': annotation.mode.name,
      'classId': annotation.classId,
      'left': rect.left,
      'top': rect.top,
      'right': rect.right,
      'bottom': rect.bottom,
      'rotation': annotation.rotationDegrees,
      'points': [
        for (final point in annotation.points) {'x': point.dx, 'y': point.dy},
      ],
      'authorId': authorId,
      'authorName': authorName,
      'authorColor': authorColor,
    };
  }

  _AnnotationRegion _withCollaborationAuthorFallback(
    _AnnotationRegion annotation,
    String fallbackUserId,
  ) {
    final userId = annotation.authorId.trim().isEmpty
        ? fallbackUserId.trim()
        : annotation.authorId;
    if (userId.isEmpty) {
      return annotation;
    }
    final peer = _collaborationPeers
        .where((item) => item.userId == userId)
        .firstOrNullValue;
    final peerName = peer?.userName.trim() ?? '';
    final peerColor = peer?.colorValue;
    final authorName = annotation.authorName.trim().isEmpty
        ? userId == _collaborationAuthorId
              ? _currentAnnotatorName
              : (peerName.isNotEmpty ? peerName : 'User')
        : annotation.authorName;
    final authorColor = annotation.authorColorValue == 0
        ? userId == _collaborationAuthorId
              ? _currentAnnotatorColorValue
              : (peerColor ?? _collaborationColorForId(userId).toARGB32())
        : annotation.authorColorValue;
    return annotation.copyWith(
      authorId: userId,
      authorName: authorName,
      authorColorValue: authorColor,
    );
  }

  void _applyCollaborationAnnotationSnapshot(
    Map<String, dynamic> message, {
    required String fromUserId,
  }) {
    if (_collaborationMode == _CollaborationMode.off) {
      return;
    }
    final imageIndex =
        _collaborationInt(message, 'imageIndex', fallback: 0) - 1;
    if (imageIndex < 0 || imageIndex >= _images.length) {
      return;
    }
    if (_collaborationMode == _CollaborationMode.host &&
        fromUserId.isNotEmpty) {
      final peer = _collaborationPeers
          .where((item) => item.userId == fromUserId)
          .firstOrNullValue;
      if (peer == null || !_collaborationPeerCanAccessImage(peer, imageIndex)) {
        return;
      }
    }
    if (_collaborationMode == _CollaborationMode.client &&
        !_isImageIndexAuthorized(imageIndex)) {
      return;
    }
    final rawAnnotations = message['annotations'];
    if (rawAnnotations is! List) {
      return;
    }
    final hasClassPayload = message['classes'] is List;
    final nextClasses = hasClassPayload
        ? _collaborationClassesFromJson(message['classes'])
        : const <_LabelClass>[];
    final sourceUserId = fromUserId.trim().isNotEmpty
        ? fromUserId.trim()
        : _collaborationString(message, 'sourceUserId').trim();
    final authorScope = _collaborationString(message, 'authorScope').trim();
    final authoritative = _collaborationBool(message, 'authoritative');
    final incoming = rawAnnotations
        .map(_collaborationAnnotationFromJson)
        .whereType<_AnnotationRegion>()
        .map(
          (annotation) =>
              _withCollaborationAuthorFallback(annotation, sourceUserId),
        )
        .toList(growable: false);
    final imageKey = _pathKey(_images[imageIndex].path);
    final incomingIds = {for (final item in incoming) item.id};
    final incomingAuthors = {
      for (final item in incoming)
        if (item.authorId.isNotEmpty) item.authorId,
    };
    setState(() {
      if (hasClassPayload) {
        _replaceLabelClassesFromCollaboration(nextClasses);
      }
      final annotations = _annotationsByImage.putIfAbsent(imageKey, () => []);
      if (authoritative) {
        annotations.removeWhere((item) => !incomingIds.contains(item.id));
      } else {
        final scopedAuthors = {
          ...incomingAuthors,
          if (authorScope.isNotEmpty) authorScope,
          if (authorScope.isEmpty && sourceUserId.isNotEmpty) sourceUserId,
        };
        annotations.removeWhere(
          (item) =>
              scopedAuthors.contains(item.authorId) &&
              !incomingIds.contains(item.id),
        );
      }
      for (final annotation in incoming) {
        final index = annotations.indexWhere(
          (item) => item.id == annotation.id,
        );
        if (index >= 0) {
          annotations[index] = annotation;
        } else {
          annotations.add(annotation);
        }
      }
    });
    unawaited(_saveCollaborationAnnotationDatabaseNow('annotation snapshot'));
    if (_collaborationMode == _CollaborationMode.host) {
      _sendCollaborationMessageToAuthorizedPeers(
        {
          ...message,
          'sourceUserId': fromUserId,
          'classes': _collaborationClassesPayload(),
        },
        imageIndex,
        excludeUserId: fromUserId,
      );
    }
  }

  void _upsertCollaborationPeer(_CollaborationPeer peer) {
    final index = _collaborationPeers.indexWhere(
      (item) => item.userId == peer.userId,
    );
    if (index >= 0) {
      _collaborationPeers[index] = _collaborationPeers[index].copyWith(
        userName: peer.userName,
        colorValue: peer.colorValue,
        address: peer.address,
        online: peer.online,
        assignmentStart: peer.assignmentStart,
        assignmentEnd: peer.assignmentEnd,
        permissions: peer.permissions,
      );
    } else {
      _collaborationPeers.add(peer);
    }
  }

  void _markCollaborationPeerOffline(String userId) {
    if (userId.isEmpty) {
      return;
    }
    setState(() {
      final index = _collaborationPeers.indexWhere(
        (peer) => peer.userId == userId,
      );
      if (index >= 0) {
        _collaborationPeers[index] = _collaborationPeers[index].copyWith(
          online: false,
        );
      }
    });
  }

  Future<void> _sendCollaborationCommand(Map<String, Object?> request) async {
    try {
      await _RustVideoBackend.collaborationCommand(request: request);
    } on Object catch (error) {
      _log(
        'COLLAB',
        'Command failed: ${request['action'] ?? '-'} $error',
        level: _LogLevel.warning,
      );
      if (mounted) {
        _showFloatingMessage(t('collab.networkError'));
      }
    }
  }

  void _sendCollaborationMessageToPeer(
    String userId,
    Map<String, Object?> message,
  ) {
    unawaited(
      _sendCollaborationCommand({
        'action': 'send_peer',
        'userId': userId,
        'message': jsonEncode(message),
      }),
    );
  }

  void _broadcastCollaborationMessage(Map<String, Object?> message) {
    if (_collaborationMode != _CollaborationMode.host) {
      return;
    }
    unawaited(
      _sendCollaborationCommand({
        'action': 'broadcast',
        'message': jsonEncode(message),
      }),
    );
  }

  void _broadcastCollaborationClassSnapshot(String reason) {
    if (_collaborationMode != _CollaborationMode.host) {
      return;
    }
    _broadcastCollaborationMessage(_collaborationClassSnapshotMessage());
    _log(
      'COLLAB',
      'Class snapshot broadcast: reason=$reason, classes=${_labelClasses.length}',
      level: _LogLevel.debug,
    );
  }

  void _broadcastCollaborationProjectSnapshot(String reason) {
    if (_collaborationMode != _CollaborationMode.host) {
      return;
    }
    var count = 0;
    for (final peer in _collaborationPeers) {
      if (!peer.online) {
        continue;
      }
      _sendCollaborationMessageToPeer(
        peer.userId,
        _collaborationProjectSnapshotMessage(
          assignmentStart: peer.assignmentStart,
          assignmentEnd: peer.assignmentEnd,
        ),
      );
      count += 1;
    }
    _log(
      'COLLAB',
      'Project snapshot broadcast: reason=$reason, peers=$count, images=${_images.length}',
      level: _LogLevel.debug,
    );
  }

  void _broadcastCollaborationAllAnnotations(String reason) {
    if (_collaborationMode != _CollaborationMode.host || _images.isEmpty) {
      return;
    }
    for (var index = 0; index < _images.length; index++) {
      final image = _images[index];
      _sendCollaborationMessageToAuthorizedPeers({
        'type': 'annotation_snapshot',
        'imagePath': image.path,
        'imageIndex': index + 1,
        'sourceUserId': _collaborationAuthorId,
        'authoritative': true,
        'classes': _collaborationClassesPayload(),
        'annotations': [
          for (final annotation in _annotationsForImagePath(image.path))
            _collaborationAnnotationToJson(annotation),
        ],
      }, index);
    }
    _log(
      'COLLAB',
      'Annotation snapshots broadcast: reason=$reason, images=${_images.length}',
      level: _LogLevel.debug,
    );
  }

  bool _collaborationPeerCanAccessImage(
    _CollaborationPeer peer,
    int zeroBasedIndex,
  ) {
    if (!peer.online || _images.isEmpty) {
      return false;
    }
    final start = peer.assignmentStart.clamp(1, _images.length).toInt();
    final end = peer.assignmentEnd.clamp(start, _images.length).toInt();
    final imageIndex = zeroBasedIndex + 1;
    return imageIndex >= start && imageIndex <= end;
  }

  void _sendCollaborationMessageToAuthorizedPeers(
    Map<String, Object?> message,
    int zeroBasedImageIndex, {
    String? excludeUserId,
  }) {
    if (_collaborationMode != _CollaborationMode.host) {
      return;
    }
    for (final peer in _collaborationPeers) {
      if (peer.userId == excludeUserId) {
        continue;
      }
      if (!_collaborationPeerCanAccessImage(peer, zeroBasedImageIndex)) {
        continue;
      }
      _sendCollaborationMessageToPeer(peer.userId, message);
    }
  }

  void _setCollaborationUserName(String value) {
    setState(() => _collaborationUserName = value.trim());
  }

  void _setCollaborationPort(int value) {
    setState(() => _collaborationPort = value);
    _restartCollaborationDiscovery();
  }

  void _startCollaborationHost() {
    if (_images.isEmpty) {
      _showFloatingMessage(t('collab.openProjectFirst'));
      return;
    }
    final imageCount = _images.length;
    setState(() {
      _collaborationMode = _CollaborationMode.host;
      _collaborationJoining = false;
      _collaborationPeers.clear();
      _collaborationStartIndex = 1;
      _collaborationEndIndex = math.max(1, imageCount);
    });
    unawaited(_startCollaborationHostNetwork(imageCount));
  }

  Future<void> _startCollaborationHostNetwork(int imageCount) async {
    try {
      await _RustVideoBackend.collaborationCommand(
        request: {
          'action': 'start_host',
          'hostId': _collaborationHostId,
          'hostName': _currentAnnotatorName,
          'userId': _collaborationAuthorId,
          'userName': _currentAnnotatorName,
          'port': _collaborationPort,
          'projectId': _databaseProjectKey(),
          'imageCount': imageCount,
        },
      );
      _log(
        'COLLAB',
        'Host mode enabled: hostId=$_collaborationHostId, port=$_collaborationPort',
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _collaborationMode = _CollaborationMode.off);
      _showFloatingMessage(t('collab.networkError'));
      _log('COLLAB', 'Host start failed: $error', level: _LogLevel.error);
      _restartCollaborationDiscovery();
    }
  }

  void _joinCollaborationHost() {
    if (_collaborationJoining) {
      return;
    }
    final selectedHost = _collaborationDiscoveredHosts
        .where((host) => host.hostId == _selectedCollaborationHostId)
        .firstOrNullValue;
    if (selectedHost == null) {
      _showFloatingMessage(t('collab.selectHostFirst'));
      return;
    }
    unawaited(_joinCollaborationHostNetwork(selectedHost));
  }

  Future<void> _joinCollaborationHostNetwork(
    _CollaborationDiscoveredHost selectedHost,
  ) async {
    setState(() => _collaborationJoining = true);
    try {
      _connectedCollaborationHost = selectedHost;
      await _RustVideoBackend.collaborationCommand(
        request: {
          'action': 'join_host',
          'hostId': selectedHost.hostId,
          'address': selectedHost.address,
          'port': selectedHost.port,
          'userId': _collaborationAuthorId,
          'userName': _currentAnnotatorName,
          'colorValue': _currentAnnotatorColorValue,
        },
      );
      if (!mounted) {
        return;
      }
      setState(() => _collaborationJoining = false);
      _log(
        'COLLAB',
        'Join request sent: user=$_currentAnnotatorLabel, host=${selectedHost.hostId}, address=${selectedHost.address}:${selectedHost.port}',
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      _connectedCollaborationHost = null;
      setState(() => _collaborationJoining = false);
      _showFloatingMessage(t('collab.networkError'));
      _log('COLLAB', 'Join failed: $error', level: _LogLevel.error);
      _restartCollaborationDiscovery();
    }
  }

  void _startCollaborationReconnect() {
    if (_collaborationReconnecting) {
      return;
    }
    final host = _connectedCollaborationHost;
    if (host == null) {
      _disconnectCollaborationClient(clearProject: true);
      return;
    }
    setState(() {
      _collaborationReconnecting = true;
      _collaborationReconnectAttempts = 0;
      _selectedAnnotationId = null;
    });
    _log(
      'COLLAB',
      'Host disconnected, reconnecting: host=${host.hostId}',
      level: _LogLevel.warning,
    );
    _scheduleCollaborationReconnectAttempt(immediate: true);
  }

  void _scheduleCollaborationReconnectAttempt({bool immediate = false}) {
    _collaborationReconnectTimer?.cancel();
    _collaborationReconnectTimer = Timer(
      immediate ? Duration.zero : const Duration(seconds: 3),
      _attemptCollaborationReconnect,
    );
  }

  Future<void> _attemptCollaborationReconnect() async {
    if (!_collaborationReconnecting) {
      return;
    }
    final host = _connectedCollaborationHost;
    if (host == null) {
      _disconnectCollaborationClient(clearProject: true);
      return;
    }
    if (_collaborationReconnectAttempts >= 5) {
      _showFloatingMessage(t('collab.reconnectFailed'));
      _disconnectCollaborationClient(clearProject: true);
      return;
    }
    setState(() => _collaborationReconnectAttempts += 1);
    try {
      await _RustVideoBackend.collaborationCommand(
        request: {
          'action': 'join_host',
          'hostId': host.hostId,
          'address': host.address,
          'port': host.port,
          'userId': _collaborationAuthorId,
          'userName': _currentAnnotatorName,
          'colorValue': _currentAnnotatorColorValue,
        },
      );
      _log(
        'COLLAB',
        'Reconnect attempt sent: $_collaborationReconnectAttempts/5',
        level: _LogLevel.warning,
      );
    } on Object catch (error) {
      _log(
        'COLLAB',
        'Reconnect attempt failed: $_collaborationReconnectAttempts/5, error=$error',
        level: _LogLevel.warning,
      );
    }
    if (_collaborationReconnecting) {
      _scheduleCollaborationReconnectAttempt();
    }
  }

  void _cancelCollaborationReconnect() {
    _showFloatingMessage(t('collab.reconnectCancelled'));
    _disconnectCollaborationClient(clearProject: true);
  }

  void _disconnectCollaborationClient({required bool clearProject}) {
    _collaborationReconnectTimer?.cancel();
    setState(() {
      _collaborationMode = _CollaborationMode.off;
      _collaborationJoining = false;
      _collaborationReconnecting = false;
      _collaborationReconnectAttempts = 0;
      _collaborationPeers.clear();
      _pendingCollaborationJoinRequests.clear();
      _selectedCollaborationHostId = null;
      _connectedCollaborationHost = null;
      _collaborationSelfPermissions = const _CollaborationPermissions();
      _selectedAnnotationId = null;
      if (clearProject) {
        _clearCurrentProjectState();
      }
    });
    unawaited(
      _RustVideoBackend.collaborationCommand(request: const {'action': 'stop'})
          .catchError((Object error) {
            _log(
              'COLLAB',
              'Client disconnect stop failed: $error',
              level: _LogLevel.debug,
            );
            return <String, dynamic>{};
          })
          .whenComplete(_restartCollaborationDiscovery),
    );
  }

  void _stopCollaboration() {
    final wasClient = _collaborationMode == _CollaborationMode.client;
    if (!wasClient) {
      _databaseSaveTimer?.cancel();
      unawaited(_saveAnnotationDatabaseNow());
    }
    setState(() {
      _collaborationMode = _CollaborationMode.off;
      _collaborationJoining = false;
      _collaborationReconnecting = false;
      _collaborationReconnectAttempts = 0;
      _collaborationPeers.clear();
      _selectedCollaborationHostId = null;
      _connectedCollaborationHost = null;
      _pendingCollaborationJoinRequests.clear();
      _selectedAnnotationId = null;
      if (wasClient) {
        _clearCurrentProjectState();
      }
    });
    _collaborationReconnectTimer?.cancel();
    unawaited(
      _RustVideoBackend.collaborationCommand(request: const {'action': 'stop'})
          .catchError((Object error) {
            _log('COLLAB', 'Stop failed: $error', level: _LogLevel.warning);
            return <String, dynamic>{};
          })
          .whenComplete(_restartCollaborationDiscovery),
    );
    _log('COLLAB', 'Collaboration stopped');
  }

  void _setCollaborationPeerPermissions(
    _CollaborationPeerPermissionResult result,
  ) {
    final max = math.max(1, _images.length);
    final assignmentStart = result.assignmentStart.clamp(1, max).toInt();
    final assignmentEnd = result.assignmentEnd
        .clamp(assignmentStart, max)
        .toInt();
    setState(() {
      final index = _collaborationPeers.indexWhere(
        (peer) => peer.userId == result.userId,
      );
      if (index >= 0) {
        _collaborationPeers[index] = _collaborationPeers[index].copyWith(
          assignmentStart: assignmentStart,
          assignmentEnd: assignmentEnd,
          permissions: result.permissions,
        );
      }
    });
    _log(
      'COLLAB',
      'Peer permissions updated: user=${result.userId}, assignment=$assignmentStart-$assignmentEnd, edit=${result.permissions.canEditOthers}, delete=${result.permissions.canDeleteOthers}, class=${result.permissions.canChangeClass}',
      level: _LogLevel.debug,
    );
    _sendCollaborationMessageToPeer(result.userId, {
      'type': 'permission_update',
      'assignmentStart': assignmentStart,
      'assignmentEnd': assignmentEnd,
      'permissions': {
        'canEditOthers': result.permissions.canEditOthers,
        'canDeleteOthers': result.permissions.canDeleteOthers,
        'canChangeClass': result.permissions.canChangeClass,
      },
    });
    _sendCollaborationMessageToPeer(
      result.userId,
      _collaborationProjectSnapshotMessage(
        assignmentStart: assignmentStart,
        assignmentEnd: assignmentEnd,
      ),
    );
    _scheduleAnnotationDatabaseSave();
  }

  @override
  Widget build(BuildContext context) {
    final labelPage = _activeSection == 'label';

    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                _TopMenuBar(
                  visible: _topMenuVisible,
                  recentFolders: _recentFolders
                      .map((entry) => entry.path)
                      .toList(),
                  recentFiles: _recentFiles.map((entry) => entry.path).toList(),
                  languageOptions: _languageOptions,
                  activeLanguageCode: _activeLanguageCode,
                  projectActionsLocked: _projectLockedByCollaboration,
                  onOpenFile: () => _openImageFile(),
                  onOpenFolder: () => _openImageFolder(),
                  onOpenRecentFolder: (path) =>
                      unawaited(_openRecentFolder(path)),
                  onOpenRecentFile: (path) => unawaited(_openRecentFile(path)),
                  onClearRecent: _clearRecentItems,
                  onExit: () => SystemNavigator.pop(),
                  onImportDataset: _importYoloDataset,
                  onExportDataset: _showExportDialog,
                  onShowTrainingHistory: _showTrainingHistoryDialog,
                  onUndo: _undoAnnotationChange,
                  onRedo: _redoAnnotationChange,
                  onCopy: _copySelectedAnnotation,
                  onPaste: _pasteAnnotation,
                  onShowSettings: _showSettings,
                  onShowLogs: _showLogViewerDialog,
                  onShowHelp: _showKeySettings,
                  onShowAbout: _showAboutDialog,
                  onProjectActionBlocked: () =>
                      _showFloatingMessage(t('collab.disconnectFirst')),
                  onLanguageSelected: _changeLanguage,
                  onPointerEnter: _showTopMenu,
                  onPointerExit: _scheduleTopMenuHide,
                ),
                Expanded(
                  child: Row(
                    children: [
                      _PrimarySidebar(
                        activeSection: _activeSection,
                        collapsed: _sidebarCollapsed,
                        onCollapseChanged: (value) {
                          setState(() => _sidebarCollapsed = value);
                        },
                        onSectionSelected: (section) {
                          _log(
                            'NAV',
                            'Switched to: $section',
                            level: _LogLevel.debug,
                          );
                          setState(() => _activeSection = section);
                        },
                      ),
                      Expanded(
                        child: IndexedStack(
                          index: _activeSection == 'label'
                              ? 0
                              : _activeSection == 'train'
                              ? 1
                              : _activeSection == 'crop'
                              ? 2
                              : _activeSection == 'collaboration'
                              ? 3
                              : _activeSection == 'database'
                              ? 5
                              : 4,
                          children: [
                            _LabelPage(
                              status: widget.status,
                              images: _images,
                              selectedImage: _selectedImageForLabel,
                              selectedImageIndex: _selectedImageIndex,
                              unauthorized:
                                  _collaborationClientMode &&
                                  !_selectedImageAuthorized,
                              zoom: _zoom,
                              viewportOffset: _labelViewportOffset,
                              activeTool: _activeTool,
                              activeMode: _activeAnnotationMode,
                              imageSplit: _selectedImageSplit,
                              activeClassId: _activeClassId,
                              labelClasses: _labelClasses,
                              annotationsByImage: _annotationsByImage,
                              annotations: _currentAnnotationsForLabel,
                              sam3ClickPrompts:
                                  _currentSam3ClickPromptsForLabel,
                              sam3PreviewAnnotations:
                                  _currentSam3ClickPreviewForLabel,
                              selectedAnnotationId: _selectedAnnotationId,
                              showClassLabels: _showClassLabels,
                              classesEditable: !_collaborationClientMode,
                              onImageSelected: _selectImage,
                              onImageContextMenu: _showImageContextMenu,
                              onPointerSignal: _handlePointerSignal,
                              onViewportOffsetChanged: _setLabelViewportOffset,
                              onToolSelected: _selectTool,
                              onSelectMode: () => _selectTool('select'),
                              onModeSelected: _activateAnnotationMode,
                              onImageSplitChanged: _setSelectedImageSplit,
                              onEnsureClass: _ensureActiveClass,
                              onAnnotationCreated: _createAnnotation,
                              onSegAnnotationCreated: _createSegAnnotation,
                              onAnnotationSelected: _selectAnnotation,
                              onAnnotationUpdated: _updateAnnotation,
                              onAnnotationDeleted: _deleteAnnotation,
                              onAnnotationDragStarted: _pushAnnotationSnapshot,
                              onClassSelected: _selectLabelClass,
                              onClassAdded: () => _addLabelClass(),
                              onClassEdited: _editLabelClass,
                              onClassColorChanged: _chooseLabelClassColor,
                              onClassDeleted: _deleteLabelClass,
                              onClassReordered: _reorderLabelClass,
                              onToggleClassLabels: () => setState(
                                () => _showClassLabels = !_showClassLabels,
                              ),
                              onAnnotationClassChanged: _changeAnnotationClass,
                              onSam3ClickPrompt: _handleSam3ClickPrompt,
                              aiPanelVisible: _aiPanelVisible,
                              onAiConfigPressed: () {
                                setState(
                                  () => _aiPanelVisible = !_aiPanelVisible,
                                );
                              },
                              onImageDisplaySizeChanged: (size) {
                                _imageDisplaySize = size;
                                final key = _selectedImageKey;
                                if (key != null && size != Size.zero) {
                                  _imageDisplaySizes[key] = size;
                                  _scheduleAnnotationDatabaseSave();
                                }
                              },
                            ),
                            _TrainPage(
                              key: _trainPageKey,
                              settings: _appSettings,
                            ),
                            _CropPage(exportPath: _appSettings.exportPath),
                            _CollaborationPage(
                              mode: _collaborationMode,
                              hostId: _collaborationHostId,
                              userId: _collaborationUserId,
                              userName: _collaborationUserName,
                              userColor: Color(_currentAnnotatorColorValue),
                              port: _collaborationPort,
                              imageCount: _images.length,
                              assignmentStart: _collaborationStartIndex,
                              assignmentEnd: _collaborationEndIndex,
                              discoveredHosts: _collaborationDiscoveredHosts,
                              selectedHostId: _selectedCollaborationHostId,
                              joining: _collaborationJoining,
                              peers: _collaborationPeers,
                              onUserNameChanged: _setCollaborationUserName,
                              onPortChanged: _setCollaborationPort,
                              onHostSelected: (hostId) => setState(
                                () => _selectedCollaborationHostId = hostId,
                              ),
                              onStartHost: _startCollaborationHost,
                              onJoinClient: _joinCollaborationHost,
                              onStop: _stopCollaboration,
                              onPeerPermissionsChanged:
                                  _setCollaborationPeerPermissions,
                            ),
                            _DetectVideoPage(
                              settings: _appSettings,
                              shortcutConfig: _shortcutConfig,
                              session: _detectVideoSession,
                            ),
                            const _DatabasePage(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (labelPage)
                  _BottomControls(
                    zoom: _zoom,
                    zoomLocked: _zoomLocked,
                    darkMode: _darkMode,
                    onZoomChanged: _setZoom,
                    onResetView: _resetZoomAndViewport,
                    onToggleZoomLock: _toggleZoomLock,
                    onToggleThemeMode: _toggleThemeMode,
                    onOpenKeySettings: _showKeySettings,
                  ),
              ],
            ),
            if (labelPage && _aiPanelVisible)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final viewport = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    final panelSize = _clampAiAssistPanelSize(
                      _aiAssistPanelSize,
                      viewport,
                    );
                    final defaultOffset = Offset(
                      math.max(
                        _aiAssistPanelMargin,
                        constraints.maxWidth -
                            panelSize.width -
                            _toolbarWidth -
                            16,
                      ),
                      _topMenuHeight + 18,
                    );
                    final panelOffset = _clampAiAssistPanelOffset(
                      _aiAssistPanelOffset ?? defaultOffset,
                      viewport,
                      panelSize,
                    );
                    return Stack(
                      children: [
                        Positioned(
                          left: panelOffset.dx,
                          top: panelOffset.dy,
                          child: _AiAssistFloatingPanel(
                            width: panelSize.width,
                            height: panelSize.height,
                            initialConfig: _aiAssistConfig,
                            imageCount: _images.length,
                            pythonPath: _appSettings.pythonPath,
                            onClose: () =>
                                setState(() => _aiPanelVisible = false),
                            onDrag: (delta) => _moveAiAssistPanel(
                              delta,
                              viewport,
                              panelSize,
                              panelOffset,
                            ),
                            onResize: (delta) => _resizeAiAssistPanel(
                              delta,
                              viewport,
                              panelSize,
                              panelOffset,
                            ),
                            onConfigSaved: _saveAiAssistConfig,
                            onSave: _handleAiAssistSave,
                            onAnnotateCurrent: _runAiAnnotateCurrentWithConfig,
                            onAnnotateAll: _runAiAnnotateAllWithConfig,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            if (_importingDataset)
              const Positioned.fill(child: _ImportBlockingOverlay()),
            if (_aiAnnotating)
              Positioned.fill(
                child: _ImportBlockingOverlay(message: t('ai.annotating')),
              ),
            if (_collaborationReconnecting)
              Positioned.fill(
                child: _CollaborationReconnectOverlay(
                  attempts: _collaborationReconnectAttempts,
                  onCancel: _cancelCollaborationReconnect,
                ),
              ),
            if (_videoFullscreenVisible)
              Positioned.fill(
                child: _VideoFullscreenOverlay(
                  session: _detectVideoSession,
                  shortcutConfig: _shortcutConfig,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
