import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/detection.dart';
import '../../services/i18n.dart';
import '../../theme/theme_helpers.dart';

typedef CamAnalysisRunner =
    Future<CamAnalysisResult> Function(CamAnalysisOptions options);

Future<void> showCamAnalysisDialog(
  BuildContext context, {
  required AiModelClassesResult? initialModelInfo,
  required Future<AiModelClassesResult>? modelInfo,
  required double initialThreshold,
  required CamAnalysisRunner onAnalyze,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _CamAnalysisDialog(
      initialModelInfo: initialModelInfo,
      modelInfo: modelInfo,
      initialThreshold: initialThreshold,
      onAnalyze: onAnalyze,
    ),
  );
}

class _CamAnalysisDialog extends StatefulWidget {
  const _CamAnalysisDialog({
    required this.initialModelInfo,
    required this.modelInfo,
    required this.initialThreshold,
    required this.onAnalyze,
  });

  final AiModelClassesResult? initialModelInfo;
  final Future<AiModelClassesResult>? modelInfo;
  final double initialThreshold;
  final CamAnalysisRunner onAnalyze;

  @override
  State<_CamAnalysisDialog> createState() => _CamAnalysisDialogState();
}

class _CamAnalysisDialogState extends State<_CamAnalysisDialog> {
  String _mode = 'bbox';
  String _smoothing = 'none';
  int _targetClassId = -1;
  late double _threshold;
  late List<AiModelClass> _classes;
  late String _modelTask;
  bool _loadingModelInfo = false;
  bool _running = false;
  CamAnalysisResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _threshold = widget.initialThreshold.clamp(0.01, 1.0).toDouble();
    final initialInfo = widget.initialModelInfo;
    _classes = initialInfo?.classes ?? const [];
    _modelTask = initialInfo?.task ?? 'detect';
    if (initialInfo == null && widget.modelInfo != null) {
      _loadingModelInfo = true;
      _loadModelInfo(widget.modelInfo!);
    }
  }

  Future<void> _loadModelInfo(Future<AiModelClassesResult> future) async {
    try {
      final info = await future;
      if (!mounted) {
        return;
      }
      setState(() {
        _classes = info.classes;
        _modelTask = info.task;
        _loadingModelInfo = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingModelInfo = false;
        _error = '${t('detect.camModelInfoFailed')}: $error';
      });
    }
  }

  Future<void> _draw() async {
    if (_running) {
      return;
    }
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final result = await widget.onAnalyze(
        CamAnalysisOptions(
          mode: _mode,
          smoothing: _smoothing,
          targetClassId: _mode == 'bbox' ? _targetClassId : -1,
          threshold: _threshold,
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() => _result = result);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final result = _result;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: mathMin(screen.width - 48, 1420),
        height: mathMin(screen.height - 48, 920),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 10, 12),
              child: Row(
                children: [
                  const Icon(Icons.analytics_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('detect.camTitle'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (result != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${result.family} | ${result.task} | '
                            '${result.device} | ${result.durationMs} ms | '
                            '${t('detect.camBoxes')} '
                            '${result.analyzedBoxes}/${result.detectedBoxes}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: borderColor(context)),
            _CamControls(
              classes: _classes,
              modelTask: _modelTask,
              mode: _mode,
              smoothing: _smoothing,
              targetClassId: _targetClassId,
              threshold: _threshold,
              running: _running,
              loadingModelInfo: _loadingModelInfo,
              onModeChanged: (value) => setState(() => _mode = value),
              onSmoothingChanged: (value) => setState(() => _smoothing = value),
              onClassChanged: (value) => setState(() => _targetClassId = value),
              onThresholdChanged: (value) => setState(() => _threshold = value),
              onDraw: _draw,
            ),
            if (_error != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _error!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            Expanded(
              child: result == null
                  ? Center(
                      child: Text(
                        _loadingModelInfo
                            ? t('detect.camModelInfoLoading')
                            : _running
                            ? t('detect.camRunning')
                            : t('detect.camDrawHint'),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : _CamResultsView(outputs: result.outputs),
            ),
            if (result != null && result.targetLayers.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: borderColor(context))),
                ),
                child: Text(
                  '${t('detect.camTargetLayers')}: '
                  '${result.targetLayers.join(', ')}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CamControls extends StatelessWidget {
  const _CamControls({
    required this.classes,
    required this.modelTask,
    required this.mode,
    required this.smoothing,
    required this.targetClassId,
    required this.threshold,
    required this.running,
    required this.loadingModelInfo,
    required this.onModeChanged,
    required this.onSmoothingChanged,
    required this.onClassChanged,
    required this.onThresholdChanged,
    required this.onDraw,
  });

  final List<AiModelClass> classes;
  final String modelTask;
  final String mode;
  final String smoothing;
  final int targetClassId;
  final double threshold;
  final bool running;
  final bool loadingModelInfo;
  final ValueChanged<String> onModeChanged;
  final ValueChanged<String> onSmoothingChanged;
  final ValueChanged<int> onClassChanged;
  final ValueChanged<double> onThresholdChanged;
  final VoidCallback onDraw;

  @override
  Widget build(BuildContext context) {
    final semanticEnabled = modelTask.toLowerCase() == 'segment';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      color: panelColor(context),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String>(
              initialValue: mode,
              decoration: InputDecoration(
                labelText: t('detect.camMode'),
                isDense: true,
              ),
              items: [
                DropdownMenuItem(
                  value: 'aggregate',
                  child: Text(t('detect.camModeAggregate')),
                ),
                DropdownMenuItem(
                  value: 'bbox',
                  child: Text(t('detect.camModeBbox')),
                ),
                DropdownMenuItem(
                  value: 'semantic',
                  enabled: semanticEnabled,
                  child: Tooltip(
                    message: semanticEnabled
                        ? t('detect.camModeSemanticHelp')
                        : t('detect.camSemanticRequiresSeg'),
                    child: Text(t('detect.camModeSemantic')),
                  ),
                ),
              ],
              onChanged: running
                  ? null
                  : (value) {
                      if (value != null) {
                        onModeChanged(value);
                      }
                    },
            ),
          ),
          Tooltip(
            message: t('detect.camSmoothingHelp'),
            waitDuration: const Duration(milliseconds: 350),
            child: SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                initialValue: smoothing,
                decoration: InputDecoration(
                  labelText: t('detect.camSmoothing'),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem(
                    value: 'none',
                    child: Text(t('detect.camSmoothNone')),
                  ),
                  const DropdownMenuItem(
                    value: 'aug',
                    child: Text('aug_smooth'),
                  ),
                  const DropdownMenuItem(
                    value: 'aug_eigen',
                    child: Text('aug + eigen smooth'),
                  ),
                ],
                onChanged: running
                    ? null
                    : (value) {
                        if (value != null) {
                          onSmoothingChanged(value);
                        }
                      },
              ),
            ),
          ),
          if (mode == 'bbox')
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<int>(
                initialValue: targetClassId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: t('detect.camClass'),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem(
                    value: -1,
                    child: Text(t('detect.camAllClasses')),
                  ),
                  for (final item in classes)
                    DropdownMenuItem(
                      value: item.id,
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: running
                    ? null
                    : (value) {
                        if (value != null) {
                          onClassChanged(value);
                        }
                      },
              ),
            ),
          SizedBox(
            width: 270,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${t('detect.camThreshold')} '
                  '${threshold.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Slider(
                  value: threshold,
                  min: 0.01,
                  max: 1,
                  divisions: 99,
                  label: threshold.toStringAsFixed(2),
                  onChanged: running ? null : onThresholdChanged,
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: running || loadingModelInfo ? null : onDraw,
            icon: running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.brush_outlined),
            label: Text(running ? t('detect.camRunning') : t('detect.camDraw')),
          ),
        ],
      ),
    );
  }
}

class _CamResultsView extends StatelessWidget {
  const _CamResultsView({required this.outputs});

  final List<CamAnalysisOutput> outputs;

  static const _methodOrder = <String>[
    'eigen_cam',
    'grad_cam',
    'grad_cam_plus_plus',
    'xgrad_cam',
    'score_cam',
  ];

  static const double _rowHeaderWidth = 132;
  static const double _columnWidth = 268;
  static const double _headerHeight = 44;
  static const double _tileHeight = 280;
  static const double _spacing = 12;

  @override
  Widget build(BuildContext context) {
    CamAnalysisOutput? original;
    final comparisons = <CamAnalysisOutput>[];
    for (final output in outputs) {
      if (output.id == 'original_detect' && original == null) {
        original = output;
      } else {
        comparisons.add(output);
      }
    }

    final methodIds = <String>[
      for (final id in _methodOrder)
        if (comparisons.any((output) => output.id == id)) id,
      for (final output in comparisons)
        if (!_methodOrder.contains(output.id) &&
            !comparisons
                .take(comparisons.indexOf(output))
                .any((previous) => previous.id == output.id))
          output.id,
    ];
    final layerOutputs = <int, CamAnalysisOutput>{};
    for (final output in comparisons) {
      layerOutputs.putIfAbsent(output.targetLayerIndex, () => output);
    }
    final layerIndexes = layerOutputs.keys.toList()
      ..sort((left, right) {
        if (left < 0) {
          return right < 0 ? left.compareTo(right) : -1;
        }
        if (right < 0) {
          return 1;
        }
        return left.compareTo(right);
      });
    final matrix = <String, Map<int, CamAnalysisOutput>>{};
    for (final output in comparisons) {
      matrix
          .putIfAbsent(output.id, () => <int, CamAnalysisOutput>{})
          .putIfAbsent(output.targetLayerIndex, () => output);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomScrollView(
          slivers: [
            if (original != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: mathMin(420, constraints.maxWidth - 32),
                      height: 280,
                      child: _CamResultTile(output: original),
                    ),
                  ),
                ),
              ),
            if (methodIds.isNotEmpty && layerIndexes.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: _rowHeaderWidth,
                        child: Column(
                          children: [
                            const SizedBox(height: _headerHeight),
                            for (var index = 0;
                                index < methodIds.length;
                                index++) ...[
                              _CamMatrixHeader(
                                width: _rowHeaderWidth,
                                height: _tileHeight,
                                label: _camMethodLabel(methodIds[index]),
                                alignment: Alignment.centerLeft,
                              ),
                              if (index < methodIds.length - 1)
                                const SizedBox(height: _spacing),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: _spacing),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width:
                                layerIndexes.length * _columnWidth +
                                (layerIndexes.length - 1) * _spacing,
                            child: Column(
                              children: [
                                SizedBox(
                                  height: _headerHeight,
                                  child: Row(
                                    children: [
                                      for (var index = 0;
                                          index < layerIndexes.length;
                                          index++) ...[
                                        _CamMatrixHeader(
                                          width: _columnWidth,
                                          height: _headerHeight,
                                          label: _camLayerLabel(
                                            layerOutputs[layerIndexes[index]]!,
                                          ),
                                        ),
                                        if (index < layerIndexes.length - 1)
                                          const SizedBox(width: _spacing),
                                      ],
                                    ],
                                  ),
                                ),
                                for (var rowIndex = 0;
                                    rowIndex < methodIds.length;
                                    rowIndex++) ...[
                                  SizedBox(
                                    height: _tileHeight,
                                    child: Row(
                                      children: [
                                        for (var columnIndex = 0;
                                            columnIndex < layerIndexes.length;
                                            columnIndex++) ...[
                                          SizedBox(
                                            width: _columnWidth,
                                            child: _buildCamMatrixTile(
                                              matrix[methodIds[rowIndex]]?[
                                                  layerIndexes[columnIndex]],
                                            ),
                                          ),
                                          if (columnIndex <
                                              layerIndexes.length - 1)
                                            const SizedBox(width: _spacing),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (rowIndex < methodIds.length - 1)
                                    const SizedBox(height: _spacing),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

Widget _buildCamMatrixTile(CamAnalysisOutput? output) {
  if (output == null) {
    return const _CamMissingResultTile();
  }
  return _CamResultTile(output: output, showLabel: false);
}

class _CamMatrixHeader extends StatelessWidget {
  const _CamMatrixHeader({
    required this.width,
    required this.height,
    required this.label,
    this.alignment = Alignment.center,
  });

  final double width;
  final double height;
  final String label;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: panelColor(context),
        border: Border.all(color: borderColor(context)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );
  }
}

class _CamMissingResultTile extends StatelessWidget {
  const _CamMissingResultTile();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: panelColor(context),
        border: Border.all(color: borderColor(context)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}

class _CamResultTile extends StatelessWidget {
  const _CamResultTile({required this.output, this.showLabel = true});

  final CamAnalysisOutput output;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final imageFile = File(output.path);
    return Tooltip(
      message: _camOutputExplanation(output.id),
      waitDuration: const Duration(milliseconds: 350),
      child: Material(
        color: panelColor(context),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: borderColor(context)),
          borderRadius: BorderRadius.circular(6),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: imageFile.existsSync()
              ? () => _showZoomViewer(context, output)
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ColoredBox(
                  color: Colors.black,
                  child: imageFile.existsSync()
                      ? Image.file(
                          imageFile,
                          fit: BoxFit.contain,
                          cacheWidth: 720,
                          filterQuality: FilterQuality.medium,
                        )
                      : const Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white70,
                          ),
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    if (showLabel)
                      Expanded(
                        child: Text(
                          output.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    if (!showLabel) const Spacer(),
                    if (output.durationMs > 0)
                      Text(
                        '${output.durationMs} ms',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(width: 6),
                    const Icon(Icons.zoom_in, size: 18),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _camMethodLabel(String id) {
  switch (id) {
    case 'eigen_cam':
      return 'EigenCAM';
    case 'grad_cam':
      return 'Grad-CAM';
    case 'grad_cam_plus_plus':
      return 'Grad-CAM++';
    case 'xgrad_cam':
      return 'XGrad-CAM';
    case 'score_cam':
      return 'ScoreCAM';
    default:
      return id;
  }
}

String _camLayerLabel(CamAnalysisOutput output) {
  if (output.targetLayerIndex < 0) {
    return 'Auto';
  }
  final moduleMatch = RegExp(r'model\.(\d+)').firstMatch(output.targetLayerName);
  if (moduleMatch != null) {
    return 'Layer ${moduleMatch.group(1)}';
  }
  return 'Layer ${output.targetLayerIndex + 1}';
}

String _camOutputExplanation(String id) {
  switch (id) {
    case 'original_detect':
      return t('detect.camHelpOriginal');
    case 'eigen_cam':
      return t('detect.camHelpEigen');
    case 'grad_cam':
      return t('detect.camHelpGrad');
    case 'grad_cam_plus_plus':
      return t('detect.camHelpGradPlus');
    case 'xgrad_cam':
      return t('detect.camHelpXGrad');
    case 'score_cam':
      return t('detect.camHelpScore');
    default:
      return t('detect.camOpenPreview');
  }
}

Future<void> _showZoomViewer(
  BuildContext context,
  CamAnalysisOutput output,
) async {
  final provider = FileImage(File(output.path));
  await showDialog<void>(
    context: context,
    builder: (context) =>
        _CamZoomViewer(title: output.label, provider: provider),
  );
  await provider.evict();
}

class _CamZoomViewer extends StatefulWidget {
  const _CamZoomViewer({required this.title, required this.provider});

  final String title;
  final ImageProvider provider;

  @override
  State<_CamZoomViewer> createState() => _CamZoomViewerState();
}

class _CamZoomViewerState extends State<_CamZoomViewer> {
  final TransformationController _transformationController =
      TransformationController();

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _scaleBy(double factor) {
    final matrix = _transformationController.value.clone();
    final currentScale = matrix.getMaxScaleOnAxis();
    final nextScale = (currentScale * factor).clamp(0.25, 8.0).toDouble();
    final change = nextScale / currentScale;
    _transformationController.value = matrix
      ..multiply(Matrix4.diagonal3Values(change, change, 1));
  }

  void _reset() {
    _transformationController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: Colors.black,
      child: SizedBox(
        width: mathMin(screen.width - 40, 1600),
        height: mathMin(screen.height - 40, 1000),
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 0.25,
                maxScale: 8,
                panEnabled: true,
                scaleEnabled: true,
                clipBehavior: Clip.hardEdge,
                child: SizedBox.expand(
                  child: Image(
                    image: widget.provider,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              top: 12,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  _ViewerIconButton(
                    tooltip: t('bottom.zoomOut'),
                    icon: Icons.remove,
                    onPressed: () => _scaleBy(0.8),
                  ),
                  const SizedBox(width: 6),
                  _ViewerIconButton(
                    tooltip: t('bottom.reset'),
                    icon: Icons.center_focus_strong,
                    onPressed: _reset,
                  ),
                  const SizedBox(width: 6),
                  _ViewerIconButton(
                    tooltip: t('bottom.zoomIn'),
                    icon: Icons.add,
                    onPressed: () => _scaleBy(1.25),
                  ),
                  const SizedBox(width: 6),
                  _ViewerIconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    icon: Icons.close,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerIconButton extends StatelessWidget {
  const _ViewerIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black.withAlpha(160),
      ),
      icon: Icon(icon),
    );
  }
}

double mathMin(double a, double b) => a < b ? a : b;
