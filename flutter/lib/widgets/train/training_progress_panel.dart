part of '../../main.dart';

class _TrainingProgressPanel extends StatelessWidget {
  const _TrainingProgressPanel({
    required this.metrics,
    required this.points,
    required this.colors,
    required this.onColorChanged,
    required this.resourceUsage,
  });

  final _TrainingMetrics metrics;
  final List<_TrainingMetricPoint> points;
  final Map<String, int> colors;
  final void Function(String key) onColorChanged;
  final _TrainingResourceUsage resourceUsage;

  @override
  Widget build(BuildContext context) {
    final seriesList = _buildTrainingSeries(points, colors);
    if (seriesList.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TrainingResourcePanel(usage: resourceUsage),
            const SizedBox(height: 12),
            Expanded(child: Center(child: Text(t('train.chartPlaceholder')))),
          ],
        ),
      );
    }

    final minX = seriesList
        .expand((s) => s.spots)
        .map((s) => s.x)
        .fold<double>(double.infinity, math.min);
    final maxX = seriesList
        .expand((s) => s.spots)
        .map((s) => s.x)
        .fold<double>(double.negativeInfinity, math.max);
    final epochInterval = _trainingChartEpochInterval(points);

    // Group series into separate chart panels
    final lossGroup = <_TrainingChartSeries>[];
    final mapGroup = <_TrainingChartSeries>[];
    final prGroup = <_TrainingChartSeries>[];
    final lrGroup = <_TrainingChartSeries>[];

    for (final s in seriesList) {
      if (s.label == 'Train Loss' || s.label == 'Val Loss') {
        lossGroup.add(s);
      } else if (s.label.contains('mAP')) {
        mapGroup.add(s);
      } else if (s.label == 'Precision' || s.label == 'Recall') {
        prGroup.add(s);
      } else if (s.label == 'LR') {
        lrGroup.add(s);
      }
    }

    List<Widget> chartPanels = [];
    if (lossGroup.isNotEmpty) {
      chartPanels.add(
        _metricChart(
          context,
          t('train.chartLoss'),
          lossGroup,
          minX,
          maxX,
          epochInterval,
        ),
      );
    }
    if (mapGroup.isNotEmpty) {
      chartPanels.add(
        _metricChart(
          context,
          t('train.chartMap'),
          mapGroup,
          minX,
          maxX,
          epochInterval,
        ),
      );
    }
    if (prGroup.isNotEmpty) {
      chartPanels.add(
        _metricChart(
          context,
          t('train.chartPr'),
          prGroup,
          minX,
          maxX,
          epochInterval,
        ),
      );
    }
    if (lrGroup.isNotEmpty) {
      chartPanels.add(
        _metricChart(
          context,
          t('train.chartLr'),
          lrGroup,
          minX,
          maxX,
          epochInterval,
        ),
      );
    }

    Color legendColor(String key, int fallback) {
      return Color(colors[key] ?? fallback);
    }

    final legendItems = <(String, double?, Color)>[
      if (lossGroup.any((s) => s.label == 'Train Loss'))
        (
          'Train Loss',
          metrics.trainLoss,
          legendColor('Train Loss', 0xFF2563EB),
        ),
      if (lossGroup.any((s) => s.label == 'Val Loss'))
        ('Val Loss', metrics.valLoss, legendColor('Val Loss', 0xFFDC2626)),
      if (mapGroup.any((s) => s.label == 'mAP@0.5'))
        ('mAP@0.5', metrics.map50, legendColor('mAP@0.5', 0xFF16A34A)),
      if (mapGroup.any((s) => s.label == 'mAP@0.5:0.95'))
        (
          'mAP@0.5:0.95',
          metrics.map5095,
          legendColor('mAP@0.5:0.95', 0xFF9333EA),
        ),
      if (prGroup.any((s) => s.label == 'Precision'))
        ('Precision', metrics.precision, legendColor('Precision', 0xFFEA580C)),
      if (prGroup.any((s) => s.label == 'Recall'))
        ('Recall', metrics.recall, legendColor('Recall', 0xFF0891B2)),
      if (lrGroup.isNotEmpty) ('LR', metrics.lr, legendColor('LR', 0xFF64748B)),
    ].where((e) => e.$2 != null).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TrainingResourcePanel(usage: resourceUsage),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: ListView(children: chartPanels)),
                if (legendItems.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 160,
                    child: ListView(
                      children: [
                        for (final (label, value, color) in legendItems)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: () => onColorChanged(label),
                                  child: Tooltip(
                                    message: t('label.classColor'),
                                    child: Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: BorderRadius.circular(2),
                                        border: Border.all(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                          width: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                Text(
                                  value!.toStringAsFixed(4),
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrainingResourcePanel extends StatelessWidget {
  const _TrainingResourcePanel({required this.usage});

  final _TrainingResourceUsage usage;

  @override
  Widget build(BuildContext context) {
    final items = [
      _ResourcePercentItem(
        label: t('train.resourceCpu'),
        percent: usage.cpuPercent,
        color: const Color(0xFF2563EB),
      ),
      _ResourcePercentItem(
        label: t('train.resourceRam'),
        percent: usage.ramPercent,
        color: const Color(0xFF16A34A),
      ),
      _ResourcePercentItem(
        label: t('train.resourceGpu'),
        percent: usage.gpuPercent,
        color: const Color(0xFFEA580C),
      ),
      _ResourcePercentItem(
        label: t('train.resourceVram'),
        percent: usage.vramPercent,
        color: const Color(0xFF9333EA),
      ),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      children: [
        for (final item in items) _ResourcePercentIndicator(item: item),
      ],
    );
  }
}

class _ResourcePercentItem {
  const _ResourcePercentItem({
    required this.label,
    required this.percent,
    required this.color,
  });

  final String label;
  final double? percent;
  final Color color;
}

class _ResourcePercentIndicator extends StatelessWidget {
  const _ResourcePercentIndicator({required this.item});

  final _ResourcePercentItem item;

  @override
  Widget build(BuildContext context) {
    final percent = item.percent;
    final available = percent != null;
    final normalized = ((percent ?? 0) / 100).clamp(0.0, 1.0).toDouble();
    final color = available
        ? item.color
        : Theme.of(context).colorScheme.outline;
    final label = available ? '${percent.round()}%' : '--';
    return SizedBox(
      width: 112,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularPercentIndicator(
            radius: 30,
            lineWidth: 6,
            percent: normalized,
            animation: true,
            animateFromLastPercent: true,
            circularStrokeCap: CircularStrokeCap.round,
            progressColor: color,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
            center: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Consolas',
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

Widget _metricChart(
  BuildContext context,
  String title,
  List<_TrainingChartSeries> group,
  double minX,
  double maxX,
  double? epochInterval,
) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 160,
          child: LineChart(
            LineChartData(
              minX: minX,
              maxX: maxX,
              minY: 0,
              maxY: _trainingChartMaxY(group),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: _borderColor(context), strokeWidth: 1),
                getDrawingVerticalLine: (_) =>
                    FlLine(color: _borderColor(context), strokeWidth: 1),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: _borderColor(context)),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: epochInterval,
                    getTitlesWidget: (value, meta) => Text(
                      value.toInt().toString(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 38,
                    getTitlesWidget: (value, meta) => Text(
                      value.toStringAsFixed(value >= 1 ? 1 : 2),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
              lineBarsData: [
                for (final item in group)
                  LineChartBarData(
                    spots: item.spots,
                    color: item.color,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    isCurved: true,
                  ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => [
                    for (final spot in spots)
                      LineTooltipItem(
                        '${group[spot.barIndex].label}  '
                        '${spot.y.toStringAsFixed(4)}',
                        TextStyle(color: group[spot.barIndex].color),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _TrainingTerminalPanel extends StatelessWidget {
  const _TrainingTerminalPanel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final content = text.trim().isEmpty ? t('train.terminalPlaceholder') : text;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: _isDarkMode(context) ? const Color(0xFF090515) : Colors.black,
      child: Scrollbar(
        child: SingleChildScrollView(
          reverse: true,
          child: SelectableText(
            content,
            style: const TextStyle(
              color: Color(0xFFE5E7EB),
              fontFamily: 'Consolas',
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }
}

class _TrainingChartSeries {
  const _TrainingChartSeries({
    required this.label,
    required this.color,
    required this.spots,
  });

  final String label;
  final Color color;
  final List<FlSpot> spots;
}

List<_TrainingChartSeries> _buildTrainingSeries(
  List<_TrainingMetricPoint> points,
  Map<String, int> colors,
) {
  List<FlSpot> spotsFor(double? Function(_TrainingMetrics metrics) getter) {
    return [
      for (final point in points)
        if (getter(point.metrics) != null)
          FlSpot(point.epoch.toDouble(), getter(point.metrics)!),
    ];
  }

  Color seriesColor(String key, int fallback) => Color(colors[key] ?? fallback);

  return [
    _TrainingChartSeries(
      label: 'Train Loss',
      color: seriesColor('Train Loss', 0xFF2563EB),
      spots: spotsFor((metrics) => metrics.trainLoss),
    ),
    _TrainingChartSeries(
      label: 'Val Loss',
      color: seriesColor('Val Loss', 0xFFDC2626),
      spots: spotsFor((metrics) => metrics.valLoss),
    ),
    _TrainingChartSeries(
      label: 'mAP@0.5',
      color: seriesColor('mAP@0.5', 0xFF16A34A),
      spots: spotsFor((metrics) => metrics.map50),
    ),
    _TrainingChartSeries(
      label: 'mAP@0.5:0.95',
      color: seriesColor('mAP@0.5:0.95', 0xFF9333EA),
      spots: spotsFor((metrics) => metrics.map5095),
    ),
    _TrainingChartSeries(
      label: 'Precision',
      color: seriesColor('Precision', 0xFFEA580C),
      spots: spotsFor((metrics) => metrics.precision),
    ),
    _TrainingChartSeries(
      label: 'Recall',
      color: seriesColor('Recall', 0xFF0891B2),
      spots: spotsFor((metrics) => metrics.recall),
    ),
    _TrainingChartSeries(
      label: 'LR',
      color: seriesColor('LR', 0xFF64748B),
      spots: spotsFor((metrics) => metrics.lr),
    ),
  ].where((series) => series.spots.isNotEmpty).toList();
}

double _trainingChartMaxY(List<_TrainingChartSeries> series) {
  final maxValue = series
      .expand((item) => item.spots)
      .map((spot) => spot.y)
      .fold<double>(0, math.max);
  if (maxValue <= 0) {
    return 1;
  }
  return maxValue * 1.15;
}

double _trainingChartEpochInterval(List<_TrainingMetricPoint> points) {
  if (points.length <= 1) {
    return 1;
  }
  final minEpoch = points.map((point) => point.epoch).reduce(math.min);
  final maxEpoch = points.map((point) => point.epoch).reduce(math.max);
  return math.max(1, ((maxEpoch - minEpoch) / 6).ceil()).toDouble();
}
