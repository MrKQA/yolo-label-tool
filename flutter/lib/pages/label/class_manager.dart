// Class manager for the label page.

part of '../../main.dart';

class _ClassManager extends StatelessWidget {
  const _ClassManager({
    required this.activeClassId,
    required this.labelClasses,
    required this.showClassLabels,
    required this.classesEditable,
    required this.onClassSelected,
    required this.onClassAdded,
    required this.onClassEdited,
    required this.onClassColorChanged,
    required this.onClassDeleted,
    required this.onClassReordered,
    required this.onToggleClassLabels,
  });

  final int? activeClassId;
  final List<LabelClass> labelClasses;
  final bool showClassLabels;
  final bool classesEditable;
  final ValueChanged<int> onClassSelected;
  final VoidCallback onClassAdded;
  final ValueChanged<LabelClass> onClassEdited;
  final ValueChanged<LabelClass> onClassColorChanged;
  final ValueChanged<LabelClass> onClassDeleted;
  final void Function(int oldIndex, int newIndex) onClassReordered;
  final VoidCallback onToggleClassLabels;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t('label.classes'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Tooltip(
                message: t('label.addClass'),
                child: IconButton(
                  onPressed: classesEditable ? onClassAdded : null,
                  icon: const Icon(Icons.add),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onToggleClassLabels,
              icon: Icon(
                showClassLabels
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 17,
              ),
              label: Text(
                showClassLabels ? t('label.hideNames') : t('label.showNames'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: labelClasses.isEmpty
              ? Center(child: Text(t('label.noClasses')))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                  itemCount: labelClasses.length,
                  onReorderItem: classesEditable ? onClassReordered : (_, _) {},
                  buildDefaultDragHandles: false,
                  itemBuilder: (context, index) {
                    final labelClass = labelClasses[index];
                    return _ClassTile(
                      key: ValueKey(labelClass.id),
                      index: index,
                      labelClass: labelClass,
                      selected: labelClass.id == activeClassId,
                      editable: classesEditable,
                      onSelected: () => onClassSelected(labelClass.id),
                      onEdit: () => onClassEdited(labelClass),
                      onColor: () => onClassColorChanged(labelClass),
                      onDelete: () => onClassDeleted(labelClass),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ClassTile extends StatelessWidget {
  const _ClassTile({
    super.key,
    required this.index,
    required this.labelClass,
    required this.selected,
    required this.editable,
    required this.onSelected,
    required this.onEdit,
    required this.onColor,
    required this.onDelete,
  });

  final int index;
  final LabelClass labelClass;
  final bool selected;
  final bool editable;
  final VoidCallback onSelected;
  final VoidCallback onEdit;
  final VoidCallback onColor;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? colorScheme.primaryContainer : _controlColor(context),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onSelected,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? colorScheme.primary : _borderColor(context),
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: editable ? onColor : null,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: labelClass.color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const SizedBox.square(dimension: 18),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    labelClass.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: t('label.editClass'),
                  visualDensity: VisualDensity.compact,
                  onPressed: editable ? onEdit : null,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
                IconButton(
                  tooltip: t('label.deleteClass'),
                  visualDensity: VisualDensity.compact,
                  onPressed: editable ? onDelete : null,
                  icon: const Icon(Icons.close, size: 18),
                ),
                if (editable)
                  ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.drag_indicator, size: 18),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
