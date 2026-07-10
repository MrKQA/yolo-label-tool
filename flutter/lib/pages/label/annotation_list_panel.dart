// Annotation list panel for the label page.

part of '../../main.dart';

class _AnnotationListPanel extends StatelessWidget {
  const _AnnotationListPanel({
    required this.annotations,
    required this.labelClasses,
    required this.selectedAnnotationId,
    required this.onAnnotationSelected,
    required this.onAnnotationClassChanged,
  });

  final List<AnnotationRegion> annotations;
  final List<LabelClass> labelClasses;
  final String? selectedAnnotationId;
  final ValueChanged<String?> onAnnotationSelected;
  final void Function(String annotationId, int classId)
  onAnnotationClassChanged;

  @override
  Widget build(BuildContext context) {
    if (annotations.isEmpty) {
      return Center(child: Text(t('label.noAnnotations')));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
      itemCount: annotations.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final annotation = annotations[index];
        final selected = annotation.id == selectedAnnotationId;
        final labelClass = labelClasses
            .where((item) => item.id == annotation.classId)
            .firstOrNullValue;
        final authorLabel = annotation.authorName.trim().isEmpty
            ? ''
            : annotation.authorName;
        final authorColor = annotation.authorColorValue == 0
            ? null
            : Color(annotation.authorColorValue);
        final selectedBorderColor = selected
            ? (authorColor ?? Theme.of(context).colorScheme.primary)
            : _borderColor(context);
        final selectedBackgroundColor = selected && authorColor != null
            ? authorColor.withValues(alpha: _isDarkMode(context) ? 0.24 : 0.14)
            : Theme.of(context).colorScheme.primaryContainer;
        return Tooltip(
          waitDuration: const Duration(milliseconds: 350),
          message: _annotationCoordinateTooltip(annotation),
          child: Material(
            color: selected ? selectedBackgroundColor : _controlColor(context),
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: () => onAnnotationSelected(annotation.id),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: selectedBorderColor),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${index + 1}. ${annotation.mode.label}',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const Spacer(),
                        if (labelClass != null)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: labelClass.color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const SizedBox.square(dimension: 14),
                          ),
                      ],
                    ),
                    if (authorLabel.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (authorColor != null)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: authorColor,
                                shape: BoxShape.circle,
                              ),
                              child: const SizedBox.square(dimension: 10),
                            ),
                          if (authorColor != null) const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              authorLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      initialValue: annotation.classId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                      items: [
                        for (final labelClass in labelClasses)
                          DropdownMenuItem(
                            value: labelClass.id,
                            child: Text(
                              labelClass.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (classId) {
                        if (classId != null) {
                          onAnnotationClassChanged(annotation.id, classId);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

String _annotationCoordinateTooltip(AnnotationRegion annotation) {
  final rect = annotation.rect;
  final lines = [
    '${annotation.mode.label} 图片坐标',
    'left=${_coord(rect.left)}, top=${_coord(rect.top)}',
    'right=${_coord(rect.right)}, bottom=${_coord(rect.bottom)}',
    'center=(${_coord(rect.center.dx)}, ${_coord(rect.center.dy)})',
    'size=${_coord(rect.width)} x ${_coord(rect.height)}',
  ];
  if (annotation.mode == AnnotationMode.obb) {
    lines.add('rotation=${annotation.rotationDegrees.toStringAsFixed(1)}°');
  }
  if (annotation.mode == AnnotationMode.seg && annotation.points.isNotEmpty) {
    lines.add('points=${annotation.points.length}');
    final previewPoints = annotation.points
        .take(6)
        .map((point) {
          return '(${_coord(point.dx)}, ${_coord(point.dy)})';
        })
        .join(' ');
    lines.add(previewPoints);
    if (annotation.points.length > 6) {
      lines.add('...');
    }
  }
  return lines.join('\n');
}

String _coord(double value) => value.toStringAsFixed(1);
