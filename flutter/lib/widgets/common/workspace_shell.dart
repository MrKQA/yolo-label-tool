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

  final List<ImageItem> _images = [];
  final List<RecentEntry> _recentFolders = [];
  final List<RecentEntry> _recentFiles = [];
  final List<LabelClass> _labelClasses = [];
  final Map<String, List<AnnotationRegion>> _annotationsByImage = {};
  final Map<String, String> _imageSplits = {};
  final List<List<AnnotationRegion>> _undoStack = [];
  final List<List<AnnotationRegion>> _redoStack = [];
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
  AnnotationMode _activeAnnotationMode = AnnotationMode.hbb;
  AnnotationRegion? _copiedAnnotation;
  Size? _imageDisplaySize;
  final Map<String, Size> _imageDisplaySizes = {};
  ShortcutConfig _shortcutConfig = ShortcutConfig.defaults();
  AppSettings _appSettings = const AppSettings.empty();
  ImportedDataset? _importedDataset;
  AiAssistConfig? _aiAssistConfig;
  bool _aiAnnotating = false;
  final Map<String, List<Sam3ClickPromptPoint>> _sam3ClickPromptsByImage = {};
  final Map<String, Sam3ClickPreviewState> _sam3ClickPreviewsByImage = {};
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

  ImageItem? get _selectedImage {
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

  ImageItem? get _selectedImageForLabel {
    if (!_selectedImageAuthorized) {
      return null;
    }
    return _selectedImage;
  }

  List<AnnotationRegion> get _currentAnnotationsForLabel {
    if (!_selectedImageAuthorized) {
      return const [];
    }
    return _currentAnnotations;
  }

  bool get _sam3ClickModeActive {
    final config = _aiAssistConfig;
    return _aiPanelVisible &&
        config != null &&
        config.backend == AiAssistBackend.sam3 &&
        config.sam3PromptMode == AiSam3PromptMode.click;
  }

  List<Sam3ClickPromptPoint> get _currentSam3ClickPromptsForLabel {
    if (!_sam3ClickModeActive || !_selectedImageAuthorized) {
      return const [];
    }
    final imageKey = _selectedImageKey;
    if (imageKey == null) {
      return const [];
    }
    return _sam3ClickPromptsByImage[imageKey] ?? const [];
  }

  List<AnnotationRegion> get _currentSam3ClickPreviewForLabel {
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
    return image == null ? null : pathKey(image.path);
  }

  List<AnnotationRegion> get _currentAnnotations {
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
    return _imageSplits[pathKey(image.path)] ?? 'train';
  }

  List<AnnotationRegion> _annotationsForImagePath(String path) {
    return _annotationsByImage[pathKey(path)] ?? const [];
  }

  Size? _displaySizeForImagePath(String path) {
    final key = pathKey(path);
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
        this._publishCurrentCollaborationAnnotations();
      }
      return;
    }
    try {
      final result = await RustBackend.saveLabelDatabase(
        payload: _databasePayload(),
      );
      _log(
        'DB',
        'Label database saved: images=${result['images'] ?? '-'}, classes=${result['classes'] ?? '-'}, annotations=${result['annotations'] ?? '-'}',
        level: _LogLevel.debug,
      );
      if (!_applyingCollaborationAnnotationSnapshot) {
        this._publishCurrentCollaborationAnnotations();
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
      final result = await RustBackend.saveLabelDatabase(
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
      final result = await RustBackend.loadLabelDatabase(
        payload: _databasePayload(
          includeClasses: false,
          includeAnnotations: false,
        ),
      );
      final loadedClasses = _labelClassesFromDatabase(result['classes']);
      final loadedAnnotations = _annotationsFromDatabase(
        result['annotations'],
        {for (final image in _images) pathKey(image.path)},
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
          final imageKey = pathKey(image.path);
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
    this._startCollaborationPolling();
    _resetCollaborationRuntimeForStartup();
    this._scheduleTopMenuHide();
  }

  void _resetCollaborationRuntimeForStartup() {
    unawaited(
      RustBackend.collaborationCommand(request: const {'action': 'stop'})
          .catchError((Object error) {
            _log(
              'COLLAB',
              'Startup collaboration reset failed: $error',
              level: _LogLevel.debug,
            );
            return <String, dynamic>{};
          })
          .whenComplete(this._restartCollaborationDiscovery),
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
      RustBackend.collaborationCommand(
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
    final history = ConfigStore.loadHistory();
    final keybindings = ConfigStore.loadKeybindings();
    final settings = ConfigStore.loadSettings();
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
    ConfigStore.saveSettings(settings);
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
      compare: naturalCompare,
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
    setCurrentLanguageStrings(strings);
    setState(() => _activeLanguageCode = code);
    _log('SETTINGS', 'Language changed: $code');
    this._showTopMenu();
  }


  bool _touchRecent(List<RecentEntry> items, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    final key = pathKey(trimmed);
    final existingIndex = items.indexWhere((item) => pathKey(item.path) == key);
    if (existingIndex >= 0) {
      items.removeAt(existingIndex);
    }
    items.insert(0, RecentEntry(path: trimmed, timestamp: DateTime.now()));
    if (items.length > configRecentHistoryLimit) {
      items.removeRange(configRecentHistoryLimit, items.length);
    }
    return true;
  }
  void _saveHistory() {
    ConfigStore.saveHistory(
      HistoryConfig(folders: _recentFolders, files: _recentFiles),
    );
  }

  void _saveKeybindings() {
    ConfigStore.saveKeybindings(_shortcutConfig);
  }

  void _saveAppSettings(AppSettings settings) {
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
    ConfigStore.saveSettings(nextSettings);
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
      ConfigStore.saveLabelResumePosition(
        LabelResumePosition(
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
      final position = ConfigStore.loadLabelResumePosition(
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
      _images.add(ImageItem.fromPath(path));
      _imageSplits[pathKey(path)] = 'train';
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

    final files = imageFilesInDirectory(folderPath);
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
        ..addAll(files.map(ImageItem.fromPath));
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
          (entry) => pathKey(entry.path) == pathKey(path),
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
          (entry) => pathKey(entry.path) == pathKey(path),
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
      _images.insertAll(insertIndex, newPaths.map(ImageItem.fromPath));
      for (final path in newPaths) {
        _imageSplits.putIfAbsent(pathKey(path), () => 'train');
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
    this._broadcastCollaborationProjectSnapshot('images inserted');
    _scheduleLabelResumePositionSave();
    _scheduleAnnotationDatabaseSave();
  }

  int _imageIndexOfPath(String path) {
    final key = pathKey(path);
    return _images.indexWhere((image) => pathKey(image.path) == key);
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
      _imageSplits.remove(pathKey(removed.path));
      _annotationsByImage.remove(pathKey(removed.path));
      _sam3ClickPromptsByImage.remove(pathKey(removed.path));
      _sam3ClickPreviewsByImage.remove(pathKey(removed.path));
      _sam3ClickAnnotationIdsByImage.remove(pathKey(removed.path));
      _selectedImageIndex = _images.isEmpty
          ? 0
          : _selectedImageIndex.clamp(0, _images.length - 1);
      _selectedAnnotationId = null;
      _undoStack.clear();
      _redoStack.clear();
    });
    _log('LABEL', 'Image removed: $removedPath, total=${_images.length}');
    this._broadcastCollaborationProjectSnapshot('image deleted');
    _scheduleLabelResumePositionSave();
    _scheduleAnnotationDatabaseSave();
  }

  void _setSelectedImageSplit(String split) {
    final imageKey = _selectedImageKey;
    if (imageKey == null || !datasetSplits.contains(split)) {
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
    showTrainingHistoryRecordsDialog(
      context: context,
      history: ConfigStore.loadTrainingHistory().entries,
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
      final project = await loadImportedYoloProject(
        yamlPath: file.path,
        ensureImageDisplaySize: this._computeImageDisplaySize,
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

  void _showFloatingMessage(String message) {
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;
    entry = OverlayEntry(builder: (_) => FloatingMessage(message: message));
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

  void _saveAiAssistConfig(AiAssistConfig config) {
    setState(() => _aiAssistConfig = config);
    if (config.backend == AiAssistBackend.sam3) {
      ConfigStore.saveLastSam3ModelPath(config.modelPath);
    }
    final sam3Detail = config.backend == AiAssistBackend.sam3
        ? ', sam3Mode=${config.sam3OutputMode.wireName}, prompt=${config.sam3PromptMode.wireName}, ${config.sam3Runtime.logSummary}'
        : '';
    _log(
      'AI',
      'AI assist config saved: backend=${config.backend.wireName}, model=${fileName(config.modelPath)}, classes=${config.selectedClassIds.length}, conf=${config.confThreshold.toStringAsFixed(2)}, imgsz=${config.imageSize}, range=${config.startIndex}-${config.endIndex}$sam3Detail',
    );
  }

  Future<AiAssistConfig?> _ensureAiAssistConfig() async {
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

  Future<void> _runAiAnnotateCurrentWithConfig(AiAssistConfig config) async {
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

  Future<void> _runAiAnnotateAllWithConfig(AiAssistConfig config) async {
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
    final points = _sam3ClickPromptsByImage[pathKey(imagePath)] ?? const [];
    return points.map((point) => point.wireLine).join('\n');
  }

  bool _sam3ClickHasPositivePoint(String imagePath) {
    final points = _sam3ClickPromptsByImage[pathKey(imagePath)] ?? const [];
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
        config.backend != AiAssistBackend.sam3 ||
        config.sam3PromptMode != AiSam3PromptMode.click ||
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
    final point = Sam3ClickPromptPoint(
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

  Future<void> _runSam3ClickPreview(AiAssistConfig config) async {
    final image = _selectedImage;
    final imageKey = _selectedImageKey;
    if (_aiAnnotating ||
        image == null ||
        imageKey == null ||
        config.backend != AiAssistBackend.sam3 ||
        config.sam3PromptMode != AiSam3PromptMode.click) {
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
      final result = await RustBackend.aiAnnotateImage(
        backend: config.backend.wireName,
        pythonPath: _appSettings.pythonPath.trim(),
        modelPath: config.modelPath,
        inputPath: image.path,
        classIds: config.selectedClassIds.toList()..sort(),
        confThreshold: config.confThreshold,
        iouThreshold: 0.45,
        imgsz: config.imageSize,
        device: 'auto',
        samMode: AiSam3OutputMode.seg.wireName,
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
      final displaySize = await this._computeImageDisplaySize(image.path);
      final annotations = _sam3PreviewAnnotationsFromResult(
        result: result,
        displaySize: displaySize,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _sam3ClickPreviewsByImage[imageKey] = Sam3ClickPreviewState(
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
      final failure = classifyAiFailure(error);
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
      _showFloatingMessage('${t('ai.failed')}: ${shortAiError(error)}');
    } finally {
      if (mounted) {
        setState(() => _aiAnnotating = false);
      }
    }
  }

  List<AnnotationRegion> _sam3PreviewAnnotationsFromResult({
    required AiAnnotationResult result,
    required Size displaySize,
  }) {
    if (result.width <= 0 || result.height <= 0) {
      return const [];
    }
    final annotations = <AnnotationRegion>[];
    for (var index = 0; index < result.masks.length; index += 1) {
      final mask = result.masks[index];
      final points = scaleAiPoints(
        mask.points,
        sourceSize: Size(result.width, result.height),
        displaySize: displaySize,
      );
      if (points.length < 3) {
        continue;
      }
      final bounds = pointsBounds(points).intersect(Offset.zero & displaySize);
      if (bounds.width < 2 || bounds.height < 2) {
        continue;
      }
      annotations.add(
        AnnotationRegion(
          id: 'sam3_preview_$index',
          mode: AnnotationMode.seg,
          rect: bounds,
          classId: _activeClassId ?? -1,
          points: points,
        ),
      );
    }
    return annotations;
  }

  Future<void> _commitSam3ClickPreview(AiAssistConfig config) async {
    final image = _selectedImage;
    final imageKey = _selectedImageKey;
    if (image == null ||
        imageKey == null ||
        config.backend != AiAssistBackend.sam3 ||
        config.sam3PromptMode != AiSam3PromptMode.click) {
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
    this._pushAnnotationSnapshot();
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
      this._broadcastCollaborationClassSnapshot('sam3 click preview saved');
    }
    if (added > 0 || classesChanged) {
      _scheduleAnnotationDatabaseSave();
    }
    _log('AI', 'SAM3 click preview saved: image=${image.name}, added=$added');
    _showFloatingMessage('${t('ai.done')} ($added)');
  }

  Future<void> _handleAiAssistSave(AiAssistConfig config) async {
    if (config.backend == AiAssistBackend.sam3 &&
        config.sam3PromptMode == AiSam3PromptMode.click) {
      await _commitSam3ClickPreview(config);
    }
  }

  Future<String?> _promptSam3ClickSaveClassName(AiAssistConfig config) async {
    final activeClass = _activeClassId == null
        ? null
        : this._classById(_activeClassId!);
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
    AiAssistConfig config,
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
    if (config.backend == AiAssistBackend.yolo &&
        config.selectedClassIds.isEmpty) {
      _log(
        'AI',
        'AI annotation blocked: no classes selected',
        level: _LogLevel.warning,
      );
      _showFloatingMessage(t('ai.noSelectedClasses'));
      return;
    }
    if (config.backend == AiAssistBackend.sam3 &&
        config.sam3PromptMode == AiSam3PromptMode.text &&
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
        config.backend == AiAssistBackend.sam3 &&
        config.sam3PromptMode == AiSam3PromptMode.click;
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
      'AI annotation started: backend=${config.backend.wireName}, targets=${targetIndices.length}, model=${fileName(config.modelPath)}, classes=${config.selectedClassIds.length}, conf=${config.confThreshold.toStringAsFixed(2)}, imgsz=${config.imageSize}, sam3Mode=${config.sam3OutputMode.wireName}, prompt=${config.sam3PromptMode.wireName}, clickPoints=${samClickPointsText.trim().isEmpty ? 0 : samClickPointsText.trim().split('\n').length}, samPromptFrame=$samPromptFrameIndex, ${config.sam3Runtime.logSummary}',
    );

    setState(() => _aiAnnotating = true);
    await WidgetsBinding.instance.endOfFrame;
    var added = 0;
    final classCountBefore = _labelClasses.length;
    try {
      if (targetIndices.length == 1 &&
          targetIndices.first == _selectedImageIndex) {
        this._pushAnnotationSnapshot();
      }
      if (targetIndices.length == 1) {
        final image = _images[targetIndices.first];
        final result = await RustBackend.aiAnnotateImage(
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
        final displaySize = await this._computeImageDisplaySize(image.path);
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
        final results = await RustBackend.aiAnnotateImages(
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
          final displaySize = await this._computeImageDisplaySize(imagePath);
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
        this._broadcastCollaborationClassSnapshot('ai classes changed');
      }
      if (added > 0 || classesChanged || isSam3ClickMode) {
        _scheduleAnnotationDatabaseSave();
      }
      _showFloatingMessage('${t('ai.done')} ($added)');
    } on Object catch (error) {
      final failure = classifyAiFailure(error);
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
      _showFloatingMessage('${t('ai.failed')}: ${shortAiError(error)}');
    } finally {
      if (mounted) {
        setState(() => _aiAnnotating = false);
      }
    }
  }

  int _applyAiAnnotationResult({
    required String imagePath,
    required Size displaySize,
    required AiAnnotationResult result,
    required AiAssistConfig config,
    String? classNameOverride,
  }) {
    if (result.width <= 0 || result.height <= 0) {
      return 0;
    }
    final imageKey = pathKey(imagePath);
    final annotations = _annotationsByImage.putIfAbsent(imageKey, () => []);
    var count = 0;
    if (config.backend == AiAssistBackend.sam3) {
      final replaceSam3ClickAnnotations =
          config.sam3PromptMode == AiSam3PromptMode.click;
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
        final points = scaleAiPoints(
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
        final bounds = pointsBounds(
          points,
        ).intersect(Offset.zero & displaySize);
        if (bounds.width < 2 || bounds.height < 2) {
          continue;
        }
        final mode = config.sam3OutputMode.annotationMode;
        final id = 'ann_${_annotationSerial++}';
        if (mode == AnnotationMode.seg) {
          annotations.add(
            AnnotationRegion(
              id: id,
              mode: AnnotationMode.seg,
              rect: bounds,
              classId: classId,
              points: points,
              authorId: _collaborationAuthorId,
              authorName: _currentAnnotatorName,
              authorColorValue: _currentAnnotatorColorValue,
            ),
          );
        } else if (mode == AnnotationMode.obb) {
          final oriented = minimumAreaRect(points);
          annotations.add(
            AnnotationRegion.fromRect(
              id: id,
              mode: AnnotationMode.obb,
              rect: oriented.rect.intersect(Offset.zero & displaySize),
              classId: classId,
              authorId: _collaborationAuthorId,
              authorName: _currentAnnotatorName,
              authorColorValue: _currentAnnotatorColorValue,
            ).copyWith(rotationDegrees: oriented.rotationDegrees),
          );
        } else {
          annotations.add(
            AnnotationRegion.fromRect(
              id: id,
              mode: AnnotationMode.hbb,
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
        'SAM3 annotations applied: image=${fileName(imagePath)}, mode=${config.sam3OutputMode.wireName}, prompt=${config.sam3PromptMode.wireName}, masks=${result.masks.length}, added=$count',
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

  AnnotationRegion? _annotationFromAiBox({
    required AiPredictionBox box,
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
    return AnnotationRegion.fromRect(
      id: 'ann_${_annotationSerial++}',
      mode: AnnotationMode.hbb,
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
      LabelClass(id: id, name: name, colorValue: this._nextClassColor().toARGB32()),
    );
    _activeClassId ??= id;
    return id;
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

    if (isEditableTextFocused()) {
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
        this._undoAnnotationChange();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyY) {
        this._redoAnnotationChange();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyC) {
        this._copySelectedAnnotation();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyV) {
        this._pasteAnnotation();
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

    if (_shortcutConfig.matches(ShortcutAction.previousImage, key)) {
      if (!_selectPreviousImage(step: imageStep)) {
        _showFloatingMessage(t('detect.hudNoPrevious'));
      }
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(ShortcutAction.nextImage, key)) {
      if (!_selectNextImage(step: imageStep)) {
        _showFloatingMessage(t('detect.hudNoNext'));
      }
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(ShortcutAction.zoomIn, key)) {
      _setZoom(_zoom + 10);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(ShortcutAction.zoomOut, key)) {
      _setZoom(_zoom - 10);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(ShortcutAction.hbbMode, key)) {
      this._activateAnnotationMode(AnnotationMode.hbb);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(ShortcutAction.obbMode, key)) {
      this._activateAnnotationMode(AnnotationMode.obb);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(ShortcutAction.segMode, key)) {
      this._activateAnnotationMode(AnnotationMode.seg);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(ShortcutAction.deleteSelected, key)) {
      this._deleteSelectedAnnotation();
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(ShortcutAction.hideClassLabels, key)) {
      setState(() => _showClassLabels = !_showClassLabels);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(ShortcutAction.rotateObbLeft5, key)) {
      this._rotateSelectedAnnotation(-5);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(ShortcutAction.rotateObbLeft1, key)) {
      this._rotateSelectedAnnotation(-1);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(ShortcutAction.rotateObbRight1, key)) {
      this._rotateSelectedAnnotation(1);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(ShortcutAction.rotateObbRight5, key)) {
      this._rotateSelectedAnnotation(5);
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(ShortcutAction.aiAnnotateCurrent, key)) {
      unawaited(_runAiAnnotateCurrent());
      return KeyEventResult.handled;
    }
    if (_shortcutConfig.matches(ShortcutAction.aiAnnotateAll, key)) {
      unawaited(_runAiAnnotateAll());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
                  onClearRecent: this._clearRecentItems,
                  onExit: () => SystemNavigator.pop(),
                  onImportDataset: _importYoloDataset,
                  onExportDataset: this._showExportDialog,
                  onShowTrainingHistory: _showTrainingHistoryDialog,
                  onUndo: this._undoAnnotationChange,
                  onRedo: this._redoAnnotationChange,
                  onCopy: this._copySelectedAnnotation,
                  onPaste: this._pasteAnnotation,
                  onShowSettings: this._showSettings,
                  onShowLogs: this._showLogViewerDialog,
                  onShowHelp: this._showKeySettings,
                  onShowAbout: this._showAboutDialog,
                  onProjectActionBlocked: () =>
                      _showFloatingMessage(t('collab.disconnectFirst')),
                  onLanguageSelected: _changeLanguage,
                  onPointerEnter: this._showTopMenu,
                  onPointerExit: this._scheduleTopMenuHide,
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
                              onToolSelected: this._selectTool,
                              onSelectMode: () => this._selectTool('select'),
                              onModeSelected: this._activateAnnotationMode,
                              onImageSplitChanged: _setSelectedImageSplit,
                              onEnsureClass: this._ensureActiveClass,
                              onAnnotationCreated: this._createAnnotation,
                              onSegAnnotationCreated: this._createSegAnnotation,
                              onAnnotationSelected: this._selectAnnotation,
                              onAnnotationUpdated: this._updateAnnotation,
                              onAnnotationDeleted: this._deleteAnnotation,
                              onAnnotationDragStarted: this._pushAnnotationSnapshot,
                              onClassSelected: this._selectLabelClass,
                              onClassAdded: () => this._addLabelClass(),
                              onClassEdited: this._editLabelClass,
                              onClassColorChanged: this._chooseLabelClassColor,
                              onClassDeleted: this._deleteLabelClass,
                              onClassReordered: this._reorderLabelClass,
                              onToggleClassLabels: () => setState(
                                () => _showClassLabels = !_showClassLabels,
                              ),
                              onAnnotationClassChanged: this._changeAnnotationClass,
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
                            CropPage(exportPath: _appSettings.exportPath),
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
                              onUserNameChanged: this._setCollaborationUserName,
                              onPortChanged: this._setCollaborationPort,
                              onHostSelected: (hostId) => setState(
                                () => _selectedCollaborationHostId = hostId,
                              ),
                              onStartHost: this._startCollaborationHost,
                              onJoinClient: this._joinCollaborationHost,
                              onStop: this._stopCollaboration,
                              onPeerPermissionsChanged:
                                  this._setCollaborationPeerPermissions,
                            ),
                            _DetectVideoPage(
                              settings: _appSettings,
                              shortcutConfig: _shortcutConfig,
                              session: _detectVideoSession,
                            ),
                            const DatabasePage(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (labelPage)
                  BottomControls(
                    zoom: _zoom,
                    zoomLocked: _zoomLocked,
                    darkMode: _darkMode,
                    onZoomChanged: _setZoom,
                    onResetView: _resetZoomAndViewport,
                    onToggleZoomLock: _toggleZoomLock,
                    onToggleThemeMode: this._toggleThemeMode,
                    onOpenKeySettings: this._showKeySettings,
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
              const Positioned.fill(child: ImportBlockingOverlay()),
            if (_aiAnnotating)
              Positioned.fill(
                child: ImportBlockingOverlay(message: t('ai.annotating')),
              ),
            if (_collaborationReconnecting)
              Positioned.fill(
                child: CollaborationReconnectOverlay(
                  attempts: _collaborationReconnectAttempts,
                  onCancel: this._cancelCollaborationReconnect,
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
