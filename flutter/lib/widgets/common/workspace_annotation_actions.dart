part of '../../main.dart';

extension _WorkspaceShellAnnotationActions on _WorkspaceShellState {
  void _pushAnnotationSnapshot() {
    _undoStack.add(List<AnnotationRegion>.of(_currentAnnotations));
    if (_undoStack.length > 50) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void _restoreCurrentImageAnnotations(List<AnnotationRegion> snapshot) {
    final imageKey = _selectedImageKey;
    if (imageKey == null) {
      return;
    }
    _annotationsByImage[imageKey] = List<AnnotationRegion>.of(snapshot);
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
    _redoStack.add(List<AnnotationRegion>.of(_currentAnnotations));
    setState(() => _restoreCurrentImageAnnotations(snapshot));
    _scheduleAnnotationDatabaseSave();
  }

  void _redoAnnotationChange() {
    if (_redoStack.isEmpty) {
      return;
    }
    final snapshot = _redoStack.removeLast();
    _undoStack.add(List<AnnotationRegion>.of(_currentAnnotations));
    setState(() => _restoreCurrentImageAnnotations(snapshot));
    _scheduleAnnotationDatabaseSave();
  }

  void _activateAnnotationMode(AnnotationMode mode) {
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
      this._showExportDialog();
      return;
    }
    setState(() => _activeTool = tool);
  }

  LabelClass? _classById(int id) {
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
    final labelClass = LabelClass(
      id: id,
      name: name.trim(),
      colorValue: _nextClassColor().toARGB32(),
    );
    setState(() {
      _labelClasses.add(labelClass);
      _activeClassId = id;
    });
    this._broadcastCollaborationClassSnapshot('class added');
    _scheduleAnnotationDatabaseSave();
    return id;
  }

  Future<void> _editLabelClass(LabelClass labelClass) async {
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
    this._broadcastCollaborationClassSnapshot('class renamed');
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

  Future<void> _chooseLabelClassColor(LabelClass labelClass) async {
    if (_guardProjectChangeBlocked()) {
      return;
    }
    final currentColor = labelClass.color;
    final selected = await showWheelColorDialog(
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
    this._broadcastCollaborationClassSnapshot('class color changed');
    _scheduleAnnotationDatabaseSave();
  }

  void _deleteLabelClass(LabelClass labelClass) {
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
    this._broadcastCollaborationClassSnapshot('class deleted');
    this._broadcastCollaborationAllAnnotations('class deleted');
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
    this._broadcastCollaborationClassSnapshot('class reordered');
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
    final annotation = AnnotationRegion.fromRect(
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
    final annotation = AnnotationRegion(
      id: 'ann_${_annotationSerial++}',
      mode: AnnotationMode.seg,
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
    AnnotationRegion annotation, {
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

  void _updateAnnotation(AnnotationRegion annotation) {
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
    if (selected == null || selected.mode != AnnotationMode.obb) {
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
}
