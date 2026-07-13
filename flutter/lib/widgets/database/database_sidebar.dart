// =============================================================================
// database_sidebar.dart - Database Explorer Sidebar / 数据库浏览侧边栏
// =============================================================================
// Collapsible table explorer sidebar listing all whitelisted database tables
// with row counts, icons, and active-table highlighting.
//
// 可折叠的表浏览侧边栏：列出所有白名单数据库表，含行数、图标和当前表高亮。
// =============================================================================

import 'package:flutter/material.dart';

import '../../services/i18n.dart';
import '../../theme/theme_helpers.dart';
import 'database_detail_widgets.dart';

class DatabaseExplorerSidebar extends StatelessWidget {
  const DatabaseExplorerSidebar({
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DatabasePanel(
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
          Divider(height: 1, color: appBorderColor(dark)),
          Expanded(
            child: ListView(
              padding: EdgeInsets.all(expanded ? 10 : 4),
              children: [
                for (final spec in databaseTableSpecs)
                  DatabaseTreeButton(
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
