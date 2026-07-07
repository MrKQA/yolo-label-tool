part of '../../main.dart';

class _DatabaseExplorerSidebar extends StatelessWidget {
  const _DatabaseExplorerSidebar({
    required this.overview,
    required this.activeTable,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onTableSelected,
  });

  final Map<String, dynamic>? overview;
  final String activeTable;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final ValueChanged<String> onTableSelected;

  @override
  Widget build(BuildContext context) {
    final tables = overview?['tables'] is List
        ? overview!['tables'] as List
        : const [];
    final tableCounts = <String, String>{};
    for (final table in tables) {
      if (table is Map) {
        tableCounts['${table['name'] ?? ''}'] = '${table['rows'] ?? 0}';
      }
    }
    return _DatabasePanel(
      child: Column(
        children: [
          SizedBox(
            height: 42,
            child: Row(
              children: [
                IconButton(
                  tooltip: expanded
                      ? t('sidebar.collapse')
                      : t('sidebar.expand'),
                  onPressed: onToggleExpanded,
                  icon: Icon(
                    expanded ? Icons.keyboard_tab : Icons.table_rows_outlined,
                    size: 18,
                  ),
                ),
                if (expanded)
                  Expanded(
                    child: Text(
                      t('database.tables'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: _borderColor(context)),
          Expanded(
            child: ListView(
              padding: EdgeInsets.all(expanded ? 10 : 4),
              children: [
                for (final spec in _databaseTableSpecs)
                  _DatabaseTreeButton(
                    icon: spec.icon,
                    label: t('database.table.${spec.name}'),
                    trailing: tableCounts[spec.name] ?? '',
                    selected: activeTable == spec.name,
                    collapsed: !expanded,
                    onPressed: () => onTableSelected(spec.name),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
