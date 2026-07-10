import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../models/detection.dart';
import '../models/export.dart';
import '../services/i18n.dart';

const _yamlTypeGroup = XTypeGroup(label: 'YAML', extensions: ['yaml', 'yml']);

class YoloExportSettingsDialog extends StatefulWidget {
  const YoloExportSettingsDialog({
    required this.initial,
    required this.onManualExport,
  });

  final YoloExportSettings initial;
  final Future<ModelExportResult> Function(YoloExportSettings settings)
  onManualExport;

  @override
  State<YoloExportSettingsDialog> createState() =>
      _YoloExportSettingsDialogState();
}

class _YoloExportSettingsDialogState
    extends State<YoloExportSettingsDialog> {
  late String _format;
  late bool _autoExport;
  late bool _dynamic;
  late bool _nms;
  late bool _simplify;
  late String _quantize;
  late final TextEditingController _imgszController;
  late final TextEditingController _batchController;
  late final TextEditingController _dataController;
  late final TextEditingController _fractionController;
  late final TextEditingController _deviceController;
  late final TextEditingController _opsetController;
  bool _manualExporting = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load(widget.initial);
  }

  void _load(YoloExportSettings settings) {
    _format = settings.format == 'onnx' ? 'onnx' : 'openvino';
    _autoExport = settings.autoExportAfterTraining;
    _dynamic = settings.dynamic;
    _nms = settings.nms;
    _simplify = settings.simplify;
    _quantize = _normalizeExportQuantize(settings.quantize);
    _imgszController = TextEditingController(text: settings.imgsz.toString());
    _batchController = TextEditingController(text: settings.batch.toString());
    _dataController = TextEditingController(text: settings.dataPath);
    _fractionController = TextEditingController(
      text: settings.fraction.toStringAsFixed(2),
    );
    _deviceController = TextEditingController(text: settings.device);
    _opsetController = TextEditingController(
      text: settings.opset <= 0 ? '' : settings.opset.toString(),
    );
  }

  @override
  void dispose() {
    _imgszController.dispose();
    _batchController.dispose();
    _dataController.dispose();
    _fractionController.dispose();
    _deviceController.dispose();
    _opsetController.dispose();
    super.dispose();
  }

  YoloExportSettings _settingsFromFields() {
    return YoloExportSettings(
      format: _format,
      autoExportAfterTraining: _autoExport,
      imgsz: _positiveInt(_imgszController.text, 640),
      batch: _positiveInt(_batchController.text, 1),
      quantize: _quantize,
      dynamic: _dynamic,
      nms: _nms,
      dataPath: _isInt8Quantize ? _dataController.text.trim() : '',
      fraction: _fraction(_fractionController.text),
      device: _format == 'onnx' ? _deviceController.text.trim() : '',
      simplify: _simplify,
      opset: _positiveInt(_opsetController.text, 0),
    );
  }

  bool get _isInt8Quantize => _isInt8QuantizeValue(_quantize);

  bool get _showDataWarning =>
      _isInt8Quantize && _dataController.text.trim().isEmpty;

  String _normalizeExportQuantize(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == '8' || normalized == 'int8' || normalized == 'w8a8') {
      return '8';
    }
    if (normalized == '16' || normalized == 'fp16' || normalized == 'w16a16') {
      return '16';
    }
    if (normalized == '32' || normalized == 'fp32' || normalized == 'w32a32') {
      return '32';
    }
    return '';
  }

  bool _isInt8QuantizeValue(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == '8' || normalized == 'int8' || normalized == 'w8a8';
  }

  int _positiveInt(String text, int fallback) {
    final parsed = int.tryParse(text.trim());
    if (parsed == null || parsed < 0) {
      return fallback;
    }
    return parsed;
  }

  double _fraction(String text) {
    final parsed = double.tryParse(text.trim());
    if (parsed == null || !parsed.isFinite) {
      return 1.0;
    }
    return parsed.clamp(0.01, 1.0).toDouble();
  }

  Future<void> _chooseDataYaml() async {
    final file = await openFile(acceptedTypeGroups: [_yamlTypeGroup]);
    if (file == null) {
      return;
    }
    setState(() => _dataController.text = file.path);
  }

  void _reset() {
    final defaults = const YoloExportSettings();
    setState(() {
      _format = defaults.format;
      _autoExport = defaults.autoExportAfterTraining;
      _dynamic = defaults.dynamic;
      _nms = defaults.nms;
      _simplify = defaults.simplify;
      _quantize = defaults.quantize;
      _imgszController.text = defaults.imgsz.toString();
      _batchController.text = defaults.batch.toString();
      _dataController.text = defaults.dataPath;
      _fractionController.text = defaults.fraction.toStringAsFixed(2);
      _deviceController.text = defaults.device;
      _opsetController.text = '';
      _message = null;
    });
  }

  Future<void> _manualExport() async {
    setState(() {
      _manualExporting = true;
      _message = null;
    });
    try {
      final result = await widget.onManualExport(_settingsFromFields());
      if (mounted) {
        setState(() => _message = '${t('train.exportDone')}: ${result.outputPath}');
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _message = '${t('train.exportFailed')}: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _manualExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnnx = _format == 'onnx';
    return AlertDialog(
      title: Text(t('train.exportSettings')),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ExportParameterTooltip(
                name: 'format',
                child: DropdownButtonFormField<String>(
                  initialValue: _format,
                  decoration: InputDecoration(
                    labelText: t('train.exportFormat'),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'openvino',
                      child: Text('OpenVINO'),
                    ),
                    DropdownMenuItem(value: 'onnx', child: Text('ONNX')),
                  ],
                  onChanged: _manualExporting
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _format = value);
                          }
                        },
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _ExportTextField(
                    controller: _imgszController,
                    label: 'imgsz',
                    width: 120,
                    enabled: !_manualExporting,
                  ),
                  _ExportTextField(
                    controller: _batchController,
                    label: 'batch',
                    width: 120,
                    enabled: !_manualExporting,
                  ),
                  SizedBox(
                    width: 160,
                    child: _ExportParameterTooltip(
                      name: 'quantize',
                      child: DropdownButtonFormField<String>(
                        initialValue: _quantize,
                        decoration: const InputDecoration(
                          labelText: 'quantize',
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: '',
                            child: Text('FP32 / 默认'),
                          ),
                          DropdownMenuItem(value: '16', child: Text('FP16')),
                          DropdownMenuItem(value: '8', child: Text('INT8')),
                        ],
                        onChanged: _manualExporting
                            ? null
                            : (value) {
                                setState(() {
                                  _quantize = value ?? '';
                                  if (!_isInt8QuantizeValue(_quantize)) {
                                    _dataController.clear();
                                  }
                                });
                              },
                      ),
                    ),
                  ),
                  _ExportTextField(
                    controller: _fractionController,
                    label: 'fraction',
                    width: 120,
                    enabled: !_manualExporting,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _ExportParameterTooltip(
                name: 'dynamic',
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('dynamic'),
                  value: _dynamic,
                  onChanged: _manualExporting
                      ? null
                      : (value) => setState(() => _dynamic = value),
                ),
              ),
              _ExportParameterTooltip(
                name: 'nms',
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('nms'),
                  value: _nms,
                  onChanged: _manualExporting
                      ? null
                      : (value) => setState(() => _nms = value),
                ),
              ),
              if (isOnnx) ...[
                _ExportParameterTooltip(
                  name: 'simplify',
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('simplify'),
                    value: _simplify,
                    onChanged: _manualExporting
                        ? null
                        : (value) => setState(() => _simplify = value),
                  ),
                ),
                _ExportTextField(
                  controller: _opsetController,
                  label: 'opset',
                  width: 160,
                  enabled: !_manualExporting,
                  hint: 'auto',
                ),
              ],
              const SizedBox(height: 8),
              _ExportParameterTooltip(
                name: 'data',
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _dataController,
                        enabled: !_manualExporting && _isInt8Quantize,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'data',
                          hintText: _isInt8Quantize
                              ? 'data.yaml'
                              : t('train.exportDataOnlyInt8'),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _manualExporting || !_isInt8Quantize
                          ? null
                          : _chooseDataYaml,
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: Text(t('action.select')),
                    ),
                    if (_showDataWarning) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: t('train.exportDataMissing'),
                        child: Icon(
                          Icons.error,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isOnnx) ...[
                const SizedBox(height: 12),
                _ExportParameterTooltip(
                  name: 'device',
                  child: TextField(
                    controller: _deviceController,
                    enabled: !_manualExporting,
                    decoration: const InputDecoration(
                      labelText: 'device',
                      hintText: 'cpu / 0 / mps',
                      isDense: true,
                    ),
                  ),
                ),
              ],
              _ExportParameterTooltip(
                name: 'autoExport',
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('train.autoExportAfterTraining')),
                  value: _autoExport,
                  onChanged: _manualExporting
                      ? null
                      : (value) => setState(() => _autoExport = value),
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 8),
                Text(_message!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _manualExporting ? null : _reset,
          child: Text(t('action.reset')),
        ),
        OutlinedButton.icon(
          onPressed: _manualExporting ? null : _manualExport,
          icon: _manualExporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.output_outlined, size: 16),
          label: Text(t('train.exportNow')),
        ),
        TextButton(
          onPressed: _manualExporting ? null : () => Navigator.pop(context),
          child: Text(t('action.cancel')),
        ),
        FilledButton(
          onPressed: _manualExporting
              ? null
              : () => Navigator.pop(context, _settingsFromFields()),
          child: Text(t('action.save')),
        ),
      ],
    );
  }
}

class _ExportTextField extends StatelessWidget {
  const _ExportTextField({
    required this.controller,
    required this.label,
    required this.width,
    required this.enabled,
    this.hint,
    this.helpName,
  });

  final TextEditingController controller;
  final String label;
  final double width;
  final bool enabled;
  final String? hint;
  final String? helpName;

  @override
  Widget build(BuildContext context) {
    return _ExportParameterTooltip(
      name: helpName ?? label,
      child: SizedBox(
        width: width,
        child: TextField(
          controller: controller,
          enabled: enabled,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            isDense: true,
          ),
        ),
      ),
    );
  }
}

class _ExportParameterTooltip extends StatelessWidget {
  const _ExportParameterTooltip({required this.name, required this.child});

  final String name;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      waitDuration: const Duration(milliseconds: 500),
      message: _exportParameterHelp(name),
      child: child,
    );
  }
}

String _exportParameterHelp(String name) {
  return t('train.exportParam.$name');
}
