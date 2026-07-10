part of '../../main.dart';

class _AiAssistFloatingPanel extends StatefulWidget {
  const _AiAssistFloatingPanel({
    required this.initialConfig,
    required this.imageCount,
    required this.pythonPath,
    required this.width,
    required this.height,
    required this.onClose,
    required this.onDrag,
    required this.onResize,
    required this.onConfigSaved,
    required this.onSave,
    required this.onAnnotateCurrent,
    required this.onAnnotateAll,
  });

  final AiAssistConfig? initialConfig;
  final int imageCount;
  final String pythonPath;
  final double width;
  final double height;
  final VoidCallback onClose;
  final ValueChanged<Offset> onDrag;
  final ValueChanged<Offset> onResize;
  final ValueChanged<AiAssistConfig> onConfigSaved;
  final Future<void> Function(AiAssistConfig config) onSave;
  final Future<void> Function(AiAssistConfig config) onAnnotateCurrent;
  final Future<void> Function(AiAssistConfig config) onAnnotateAll;

  @override
  State<_AiAssistFloatingPanel> createState() => _AiAssistFloatingPanelState();
}

class _AiAssistFloatingPanelState extends State<_AiAssistFloatingPanel> {
  late final TextEditingController _startController;
  late final TextEditingController _endController;
  late final TextEditingController _sam3PromptController;
  AiAssistBackend _backend = AiAssistBackend.yolo;
  String? _yoloModelPath;
  String? _sam3ModelPath;
  List<AiModelClass> _classes = const [];
  Set<int> _selectedClassIds = <int>{};
  double _confThreshold = 0.25;
  AiSam3OutputMode _sam3OutputMode = AiSam3OutputMode.seg;
  AiSam3PromptMode _sam3PromptMode = AiSam3PromptMode.text;
  AiSam3RuntimeConfig _sam3Runtime = const AiSam3RuntimeConfig();
  bool _loadingClasses = false;
  String? _error;

  String? get _modelPath =>
      _backend == AiAssistBackend.sam3 ? _sam3ModelPath : _yoloModelPath;

  set _modelPath(String? value) {
    if (_backend == AiAssistBackend.sam3) {
      _sam3ModelPath = value;
    } else {
      _yoloModelPath = value;
    }
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialConfig;
    _backend = initial?.backend ?? AiAssistBackend.yolo;
    if (initial?.backend == AiAssistBackend.sam3) {
      _sam3ModelPath = initial?.modelPath;
    } else {
      _yoloModelPath = initial?.modelPath;
    }
    final savedSam3ModelPath = ConfigStore.loadLastSam3ModelPath();
    if (savedSam3ModelPath.isNotEmpty) {
      _sam3ModelPath = savedSam3ModelPath;
    }
    _classes = initial?.classes ?? const [];
    _selectedClassIds = initial?.selectedClassIds.toSet() ?? <int>{};
    _confThreshold = normalizeAiConfidence(initial?.confThreshold ?? 0.25);
    _sam3OutputMode = initial?.sam3OutputMode ?? AiSam3OutputMode.seg;
    _sam3PromptMode = initial?.sam3PromptMode ?? AiSam3PromptMode.text;
    _sam3Runtime = initial?.sam3Runtime ?? const AiSam3RuntimeConfig();
    _startController = TextEditingController(
      text: (initial?.startIndex ?? 1).toString(),
    );
    _endController = TextEditingController(
      text: (initial?.endIndex ?? math.max(1, widget.imageCount)).toString(),
    );
    _sam3PromptController = TextEditingController(
      text: initial?.sam3PromptText ?? '',
    );
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    _sam3PromptController.dispose();
    super.dispose();
  }

  Future<void> _chooseModel() async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: _backend == AiAssistBackend.sam3
              ? 'SAM3 checkpoint'
              : 'YOLO AI model',
          extensions: _backend == AiAssistBackend.sam3
              ? const ['pt', 'pth', 'safetensors']
              : const ['pt', 'onnx'],
        ),
      ],
    );
    if (file == null) {
      return;
    }
    final path = file.path;
    if (_backend == AiAssistBackend.yolo &&
        !path.toLowerCase().endsWith('.pt')) {
      setState(() {
        _modelPath = path;
        _classes = const [];
        _selectedClassIds = <int>{};
        _error = t('ai.onnxNotSupported');
      });
      return;
    }
    if (_backend == AiAssistBackend.sam3) {
      setState(() {
        _modelPath = path;
        _error = null;
      });
      ConfigStore.saveLastSam3ModelPath(path);
      _saveDraftIfValid();
      return;
    }
    final pythonPath = widget.pythonPath.trim();
    if (pythonPath.isEmpty) {
      setState(() => _error = t('detect.pythonNotConfigured'));
      return;
    }
    setState(() {
      _modelPath = path;
      _loadingClasses = true;
      _error = null;
    });
    try {
      final result = await RustBackend.aiModelClasses(
        pythonPath: pythonPath,
        modelPath: path,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _classes = result.classes;
        _selectedClassIds = result.classes.map((item) => item.id).toSet();
        _loadingClasses = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _classes = const [];
        _selectedClassIds = <int>{};
        _loadingClasses = false;
        _error = '${t('ai.readClassesFailed')}: $error';
      });
    }
  }

  AiAssistConfig? _configFromFields({bool showErrors = true}) {
    final modelPath = _modelPath;
    if (modelPath == null || modelPath.trim().isEmpty) {
      if (showErrors) {
        setState(() => _error = t('ai.chooseModelFirst'));
      }
      return null;
    }
    if (_backend == AiAssistBackend.yolo && _selectedClassIds.isEmpty) {
      if (showErrors) {
        setState(() => _error = t('ai.noSelectedClasses'));
      }
      return null;
    }
    if (_backend == AiAssistBackend.sam3 &&
        _sam3PromptMode == AiSam3PromptMode.text &&
        _sam3PromptController.text.trim().isEmpty) {
      if (showErrors) {
        setState(() => _error = t('ai.sam3PromptRequired'));
      }
      return null;
    }
    final start = int.tryParse(_startController.text.trim()) ?? 1;
    final end = int.tryParse(_endController.text.trim()) ?? start;
    final maxIndex = math.max(1, widget.imageCount);
    final normalizedStart = start.clamp(1, maxIndex).toInt();
    final normalizedEnd = end.clamp(normalizedStart, maxIndex).toInt();
    return AiAssistConfig(
      backend: _backend,
      modelPath: modelPath,
      classes: _classes,
      selectedClassIds: _selectedClassIds.toSet(),
      startIndex: normalizedStart,
      endIndex: normalizedEnd,
      confThreshold: normalizeAiConfidence(_confThreshold),
      imageSize: _backend == AiAssistBackend.sam3
          ? math.max(_sam3Runtime.maxImageWidth, _sam3Runtime.maxImageHeight)
          : 640,
      sam3OutputMode: _sam3OutputMode,
      sam3PromptMode: _sam3PromptMode,
      sam3PromptText: _sam3PromptController.text,
      sam3Runtime: _sam3Runtime,
    );
  }

  void _saveDraftIfValid() {
    final config = _configFromFields(showErrors: false);
    if (config != null) {
      widget.onConfigSaved(config);
    }
  }

  Future<void> _save() async {
    final config = _configFromFields();
    if (config == null) {
      return;
    }
    widget.onConfigSaved(config);
    setState(() => _error = null);
    await widget.onSave(config);
  }

  Future<void> _annotateCurrent() async {
    final config = _configFromFields();
    if (config == null) {
      return;
    }
    widget.onConfigSaved(config);
    setState(() => _error = null);
    await widget.onAnnotateCurrent(config);
  }

  Future<void> _annotateAll() async {
    final config = _configFromFields();
    if (config == null) {
      return;
    }
    widget.onConfigSaved(config);
    setState(() => _error = null);
    await widget.onAnnotateAll(config);
  }

  Future<void> _editSam3Runtime() async {
    final next = await showDialog<AiSam3RuntimeConfig>(
      context: context,
      builder: (context) => Sam3RuntimeDialog(initial: _sam3Runtime),
    );
    if (next == null || !mounted) {
      return;
    }
    setState(() {
      _sam3Runtime = next;
      _error = null;
    });
    _saveDraftIfValid();
  }

  Widget _rangeFields() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _startController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: t('ai.startImageIndex'),
              isDense: true,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('-'),
        ),
        Expanded(
          child: TextField(
            controller: _endController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: t('ai.endImageIndex'),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _confidenceSlider({required bool disabled}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${t('ai.confidence')} ${_confThreshold.toStringAsFixed(2)}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Slider(
          min: 0.05,
          max: 0.95,
          divisions: 18,
          value: normalizeAiConfidence(_confThreshold),
          label: normalizeAiConfidence(_confThreshold).toStringAsFixed(2),
          onChanged: disabled
              ? null
              : (value) {
                  setState(() {
                    _confThreshold = normalizeAiConfidence(value);
                  });
                },
        ),
      ],
    );
  }

  Widget _modelRow({required bool disabled}) {
    final modelPath = _modelPath;
    final sam3Selected =
        _backend == AiAssistBackend.sam3 &&
        modelPath != null &&
        modelPath.trim().isNotEmpty;
    final displayText = sam3Selected ? fileName(modelPath) : modelPath;
    return Row(
      children: [
        Expanded(
          child: sam3Selected
              ? Row(
                  children: [
                    Flexible(
                      child: Text(
                        displayText ?? t('ai.noModel'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 18,
                    ),
                  ],
                )
              : Text(
                  displayText ?? t('ai.noModel'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: disabled ? null : _chooseModel,
          icon: const Icon(Icons.folder_open, size: 16),
          label: Text(t('ai.chooseModel')),
        ),
      ],
    );
  }

  Widget _yoloTab({required bool disabled}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _modelRow(disabled: disabled),
        const SizedBox(height: 14),
        _rangeFields(),
        const SizedBox(height: 14),
        _confidenceSlider(disabled: disabled),
        const SizedBox(height: 8),
        if (_loadingClasses)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: CircularProgressIndicator(),
            ),
          )
        else
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: _borderColor(context)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ExpansionTile(
              initiallyExpanded: true,
              title: Text(t('ai.classes')),
              subtitle: Text(
                '${_selectedClassIds.length} / ${_classes.length}',
              ),
              children: [
                CheckboxListTile(
                  dense: true,
                  value:
                      _classes.isNotEmpty &&
                      _selectedClassIds.length == _classes.length,
                  onChanged: _classes.isEmpty
                      ? null
                      : (value) {
                          setState(() {
                            _selectedClassIds = value == true
                                ? _classes.map((item) => item.id).toSet()
                                : <int>{};
                          });
                        },
                  title: Text(t('ai.selectAllClasses')),
                ),
                for (final item in _classes)
                  CheckboxListTile(
                    dense: true,
                    value: _selectedClassIds.contains(item.id),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedClassIds.add(item.id);
                        } else {
                          _selectedClassIds.remove(item.id);
                        }
                      });
                    },
                    title: Text('${item.id}: ${item.name}'),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _sam3Tab({required bool disabled}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _modelRow(disabled: disabled),
        const SizedBox(height: 14),
        _rangeFields(),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: SegmentedButton<AiSam3OutputMode>(
                segments: const [
                  ButtonSegment(
                    value: AiSam3OutputMode.hbb,
                    label: Text('HBB'),
                  ),
                  ButtonSegment(
                    value: AiSam3OutputMode.obb,
                    label: Text('OBB'),
                  ),
                  ButtonSegment(
                    value: AiSam3OutputMode.seg,
                    label: Text('SEG'),
                  ),
                ],
                selected: {_sam3OutputMode},
                onSelectionChanged: disabled
                    ? null
                    : (value) {
                        setState(() => _sam3OutputMode = value.first);
                        _saveDraftIfValid();
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SegmentedButton<AiSam3PromptMode>(
          segments: [
            ButtonSegment(
              value: AiSam3PromptMode.text,
              label: Text(t('ai.sam3PromptText')),
            ),
            ButtonSegment(
              value: AiSam3PromptMode.click,
              label: Text(t('ai.sam3PromptClick')),
            ),
          ],
          selected: {_sam3PromptMode},
          onSelectionChanged: disabled
              ? null
              : (value) {
                  setState(() => _sam3PromptMode = value.first);
                  _saveDraftIfValid();
                },
        ),
        const SizedBox(height: 12),
        if (_sam3PromptMode == AiSam3PromptMode.text)
          TextField(
            controller: _sam3PromptController,
            minLines: 3,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: t('ai.sam3PromptLabel'),
              hintText: t('ai.sam3PromptHint'),
              alignLabelWithHint: true,
            ),
          )
        else
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
              border: Border.all(color: _borderColor(context)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                '${t('ai.sam3ClickHint')}\n${t('ai.sam3ClickLocalOnly')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        const SizedBox(height: 12),
        _confidenceSlider(disabled: disabled),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: disabled ? null : _editSam3Runtime,
          icon: const Icon(Icons.tune, size: 16),
          label: Text(t('ai.sam3RuntimeConfig')),
        ),
        const SizedBox(height: 8),
        Text(
          _sam3Runtime.logSummary,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final disabled = _loadingClasses;
    final sam3ClickMode =
        _backend == AiAssistBackend.sam3 &&
        _sam3PromptMode == AiSam3PromptMode.click;

    return Material(
      elevation: 18,
      color: _panelColor(context),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: _borderColor(context)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DefaultTabController(
                  length: 2,
                  initialIndex: _backend.index,
                  child: Column(
                    children: [
                      MouseRegion(
                        cursor: SystemMouseCursors.move,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanUpdate: (details) =>
                              widget.onDrag(details.delta),
                          child: Container(
                            height: 46,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: _controlColor(context),
                              border: Border(
                                bottom: BorderSide(
                                  color: _borderColor(context),
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.auto_awesome, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    t('ai.configTitle'),
                                    style: textTheme.titleMedium,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  tooltip: t('action.close'),
                                  onPressed: widget.onClose,
                                  icon: const Icon(Icons.close, size: 18),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      TabBar(
                        onTap: (index) {
                          setState(() {
                            _backend = AiAssistBackend.values[index];
                            _error = null;
                          });
                          _saveDraftIfValid();
                        },
                        tabs: const [
                          Tab(text: 'YOLO'),
                          Tab(text: 'SAM3'),
                        ],
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_backend == AiAssistBackend.yolo)
                                _yoloTab(disabled: disabled)
                              else
                                _sam3Tab(disabled: disabled),
                              if (_error != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  _error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.tonalIcon(
                                    onPressed: disabled
                                        ? null
                                        : _annotateCurrent,
                                    icon: const Icon(
                                      Icons.image_search_outlined,
                                      size: 17,
                                    ),
                                    label: Text(
                                      sam3ClickMode
                                          ? t('ai.sam3ClickPreview')
                                          : t('ai.annotateCurrent'),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Tooltip(
                                    message: sam3ClickMode
                                        ? t('ai.sam3ClickLocalOnly')
                                        : '',
                                    child: FilledButton.icon(
                                      onPressed: disabled ? null : _annotateAll,
                                      icon: const Icon(
                                        Icons.auto_awesome_motion,
                                        size: 17,
                                      ),
                                      label: Text(t('ai.annotateAll')),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: widget.onClose,
                                  child: Text(t('action.cancel')),
                                ),
                                const SizedBox(width: 10),
                                OutlinedButton(
                                  onPressed: disabled
                                      ? null
                                      : () => unawaited(_save()),
                                  child: Text(t('action.save')),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpLeftDownRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) => widget.onResize(details.delta),
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.open_in_full,
                          size: 14,
                          color: _primaryTextColor(
                            context,
                          ).withValues(alpha: 0.72),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
