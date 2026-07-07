part of '../../main.dart';

class _TrainingParameterPanel extends StatelessWidget {
  const _TrainingParameterPanel({
    required this.parameters,
    required this.stringParameters,
    required this.batchMode,
    required this.batchSize,
    required this.batchRatio,
    required this.ampEnabled,
    required this.deviceOptions,
    required this.selectedDeviceIds,
    required this.batchArgument,
    required this.deviceArgument,
    required this.onChanged,
    required this.onStringChanged,
    required this.onBatchModeChanged,
    required this.onBatchSizeChanged,
    required this.onBatchRatioChanged,
    required this.onAmpChanged,
    required this.onDeviceChanged,
    required this.onReset,
  });

  final VoidCallback onReset;

  final Map<String, double> parameters;
  final Map<String, String> stringParameters;
  final _BatchMode batchMode;
  final double batchSize;
  final double batchRatio;
  final bool ampEnabled;
  final List<_TrainingDeviceOption> deviceOptions;
  final Set<String> selectedDeviceIds;
  final String batchArgument;
  final String deviceArgument;
  final void Function(String key, double value) onChanged;
  final void Function(String key, String value) onStringChanged;
  final ValueChanged<_BatchMode> onBatchModeChanged;
  final ValueChanged<double> onBatchSizeChanged;
  final ValueChanged<double> onBatchRatioChanged;
  final ValueChanged<bool> onAmpChanged;
  final void Function(String id, bool selected) onDeviceChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('train.parameters'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              children: [
                _ParameterSectionTitle(title: t('train.coreParameters')),
                _BatchParameterEditor(
                  mode: batchMode,
                  batchSize: batchSize,
                  batchRatio: batchRatio,
                  argumentValue: batchArgument,
                  onModeChanged: onBatchModeChanged,
                  onBatchSizeChanged: onBatchSizeChanged,
                  onBatchRatioChanged: onBatchRatioChanged,
                ),
                _AmpParameterEditor(value: ampEnabled, onChanged: onAmpChanged),
                _DeviceParameterEditor(
                  options: deviceOptions,
                  selectedIds: selectedDeviceIds,
                  argumentValue: deviceArgument,
                  onChanged: onDeviceChanged,
                ),
                for (final entry in parameters.entries)
                  _ParameterEditor(
                    name: entry.key,
                    value: entry.value,
                    onChanged: (value) => onChanged(entry.key, value),
                  ),
                for (final entry in stringParameters.entries)
                  _StringParameterEditor(
                    name: entry.key,
                    value: entry.value,
                    options:
                        _trainingStringParameterOptions[entry.key] ??
                        const <String>[],
                    onChanged: (value) => onStringChanged(entry.key, value),
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onReset,
                    icon: const Icon(Icons.restart_alt, size: 16),
                    label: Text(t('action.reset')),
                  ),
                ),
                _ParameterSectionTitle(title: t('train.tuningTitle')),
                _TrainingTuningTips(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ParameterSectionTitle extends StatelessWidget {
  const _ParameterSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _BatchParameterEditor extends StatelessWidget {
  const _BatchParameterEditor({
    required this.mode,
    required this.batchSize,
    required this.batchRatio,
    required this.argumentValue,
    required this.onModeChanged,
    required this.onBatchSizeChanged,
    required this.onBatchRatioChanged,
  });

  final _BatchMode mode;
  final double batchSize;
  final double batchRatio;
  final String argumentValue;
  final ValueChanged<_BatchMode> onModeChanged;
  final ValueChanged<double> onBatchSizeChanged;
  final ValueChanged<double> onBatchRatioChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      waitDuration: const Duration(milliseconds: 500),
      message: _parameterHelp('batch'),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ParameterHeader(name: 'batch', value: 'batch=$argumentValue'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  selected: mode == _BatchMode.fixed,
                  label: Text(t('train.batchFixed')),
                  onSelected: (_) => onModeChanged(_BatchMode.fixed),
                ),
                ChoiceChip(
                  selected: mode == _BatchMode.autoGpu60,
                  label: Text(t('train.batchAuto60')),
                  onSelected: (_) => onModeChanged(_BatchMode.autoGpu60),
                ),
                ChoiceChip(
                  selected: mode == _BatchMode.autoGpuRatio,
                  label: Text(t('train.batchRatio')),
                  onSelected: (_) => onModeChanged(_BatchMode.autoGpuRatio),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (mode == _BatchMode.fixed)
              _CompactSlider(
                value: batchSize,
                min: 1,
                max: 128,
                divisions: 127,
                label: batchSize.round().toString(),
                onChanged: onBatchSizeChanged,
                integer: true,
              )
            else if (mode == _BatchMode.autoGpuRatio)
              _CompactSlider(
                value: batchRatio,
                min: 0.10,
                max: 0.95,
                divisions: 85,
                label: batchRatio.toStringAsFixed(2),
                onChanged: onBatchRatioChanged,
              )
            else
              Text(t('train.batchAuto60Help')),
          ],
        ),
      ),
    );
  }
}

class _AmpParameterEditor extends StatelessWidget {
  const _AmpParameterEditor({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      waitDuration: const Duration(milliseconds: 500),
      message: _parameterHelp('amp'),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('amp'),
        subtitle: Text('amp=${value ? 1 : 0}'),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

class _DeviceParameterEditor extends StatelessWidget {
  const _DeviceParameterEditor({
    required this.options,
    required this.selectedIds,
    required this.argumentValue,
    required this.onChanged,
  });

  final List<_TrainingDeviceOption> options;
  final Set<String> selectedIds;
  final String argumentValue;
  final void Function(String id, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      waitDuration: const Duration(milliseconds: 500),
      message: _parameterHelp('device'),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ParameterHeader(name: 'device', value: 'device=$argumentValue'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in options)
                  FilterChip(
                    selected: selectedIds.contains(option.id),
                    label: Text(option.label),
                    onSelected: (selected) => onChanged(option.id, selected),
                    avatar: Icon(
                      selectedIds.contains(option.id)
                          ? Icons.check_circle
                          : Icons.memory_outlined,
                      size: 18,
                    ),
                  ),
              ],
            ),
            if (options.length == 1 && options.first.id == 'cpu')
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  t('train.noGpuDetected'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ParameterHeader extends StatelessWidget {
  const _ParameterHeader({required this.name, required this.value});

  final String name;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: _parameterNameWidth, child: Text(name)),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _CompactSlider extends StatelessWidget {
  const _CompactSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
    this.integer = false,
    this.enabled = true,
  });

  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;
  final bool integer;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: label,
            onChanged: enabled ? onChanged : null,
          ),
        ),
        _NumericParameterField(
          value: value,
          label: label,
          min: min,
          max: max,
          integer: integer,
          enabled: enabled,
          onSubmitted: onChanged,
        ),
      ],
    );
  }
}

class _NumericParameterField extends StatefulWidget {
  const _NumericParameterField({
    required this.value,
    required this.label,
    required this.min,
    required this.max,
    required this.integer,
    required this.onSubmitted,
    this.normalize,
    this.enabled = true,
  });

  final double value;
  final String label;
  final double min;
  final double max;
  final bool integer;
  final bool enabled;
  final double Function(double value)? normalize;
  final ValueChanged<double> onSubmitted;

  @override
  State<_NumericParameterField> createState() => _NumericParameterFieldState();
}

class _NumericParameterFieldState extends State<_NumericParameterField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.label);
    _focusNode = FocusNode(debugLabel: 'parameter-value');
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _NumericParameterField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus &&
        oldWidget.value != widget.value &&
        _controller.text != widget.label) {
      _controller.text = widget.label;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _commit();
    }
  }

  void _commit() {
    if (!widget.enabled) {
      return;
    }
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null) {
      _controller.text = widget.label;
      return;
    }
    var next = parsed.clamp(widget.min, widget.max).toDouble();
    if (widget.integer) {
      next = next.roundToDouble();
    }
    next = widget.normalize?.call(next) ?? next;
    widget.onSubmitted(next);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        enabled: widget.enabled,
        textAlign: TextAlign.right,
        keyboardType: TextInputType.numberWithOptions(decimal: !widget.integer),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            widget.integer ? RegExp(r'[0-9]') : RegExp(r'[0-9.]'),
          ),
        ],
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}

class _TrainingTuningTips extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _controlColor(context),
        border: Border.all(color: _borderColor(context)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          t('train.tuningTips'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _ImageSizeParameterEditor extends StatelessWidget {
  const _ImageSizeParameterEditor({
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final index = _nearestImageSizeIndex(value);
    final currentSize = _imageSizeOptions[index];
    return Tooltip(
      waitDuration: const Duration(milliseconds: 500),
      message: _parameterHelp('imgsz'),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            const SizedBox(width: _parameterNameWidth, child: Text('imgsz')),
            Expanded(
              child: Slider(
                value: index.toDouble(),
                min: 0,
                max: (_imageSizeOptions.length - 1).toDouble(),
                divisions: _imageSizeOptions.length - 1,
                label: currentSize.toString(),
                onChanged: enabled
                    ? (sliderIndex) {
                        final nextIndex = sliderIndex.round().clamp(
                          0,
                          _imageSizeOptions.length - 1,
                        );
                        onChanged(_imageSizeOptions[nextIndex].toDouble());
                      }
                    : null,
              ),
            ),
            _NumericParameterField(
              value: currentSize.toDouble(),
              label: currentSize.toString(),
              min: _imageSizeOptions.first.toDouble(),
              max: _imageSizeOptions.last.toDouble(),
              integer: true,
              normalize: _nearestImageSizeValue,
              enabled: enabled,
              onSubmitted: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _ParameterEditor extends StatelessWidget {
  const _ParameterEditor({
    required this.name,
    required this.value,
    required this.onChanged,
  });

  final String name;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    if (name == 'imgsz') {
      return _ImageSizeParameterEditor(value: value, onChanged: onChanged);
    }

    final integerLike = {
      'epochs',
      'imgsz',
      'workers',
      'patience',
    }.contains(name);
    final min = _minForParameter(name);
    final max = _maxForParameter(name);
    final divisions = integerLike ? (max - min).round() : 100;
    final label = _formatParameterValue(name, value);
    return Tooltip(
      waitDuration: const Duration(milliseconds: 500),
      message: _parameterHelp(name),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            SizedBox(width: _parameterNameWidth, child: Text(name)),
            Expanded(
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                label: label,
                onChanged: onChanged,
              ),
            ),
            _NumericParameterField(
              value: value,
              label: label,
              min: min,
              max: max,
              integer: integerLike,
              normalize: (input) => _normalizeParameterValue(name, input),
              onSubmitted: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _StringParameterEditor extends StatelessWidget {
  const _StringParameterEditor({
    required this.name,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String name;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final choices = options.contains(value) ? options : [value, ...options];
    return Tooltip(
      waitDuration: const Duration(milliseconds: 500),
      message: _parameterHelp(name),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            SizedBox(width: _parameterNameWidth, child: Text(name)),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: value,
                isDense: true,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                items: [
                  for (final choice in choices)
                    DropdownMenuItem<String>(
                      value: choice,
                      child: Text(choice, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (next) {
                  if (next != null) {
                    onChanged(next);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
