// =============================================================================
// database_detail_widgets.dart - Database Detail Widgets / 数据库详情组件
// =============================================================================
// Shared widgets for the database page: value cells with color preview, info
// rows, tree buttons, action tabs, browse toolbar, SQL editor, pagination bar,
// row detail panel, and resize handle.
//
// 数据库页共用组件：带颜色预览的值单元格、信息行、树按钮、操作标签、浏览工具栏、
// SQL 编辑器、分页栏、行详情面板和拖拽调整手柄。
// =============================================================================

import 'package:flutter/material.dart';

import '../../services/i18n.dart';
import '../../theme/theme_helpers.dart';

const databaseTableSpecs = [
  DatabaseTableSpec('projects', Icons.account_tree_outlined),
  DatabaseTableSpec('images', Icons.image_outlined),
  DatabaseTableSpec('classes', Icons.palette_outlined),
  DatabaseTableSpec('annotations', Icons.edit_note),
  DatabaseTableSpec('collaboration_permissions', Icons.verified_user_outlined),
  DatabaseTableSpec('app_config', Icons.tune_outlined),
  DatabaseTableSpec('app_logs', Icons.article_outlined),
  DatabaseTableSpec('training_terminal_logs', Icons.terminal),
];

class DatabaseRowDetailPanel extends StatelessWidget {
  const DatabaseRowDetailPanel({
    required this.activeTable,
    required this.row,
    required this.trainingLogText,
  });

  final String activeTable;
  final Map<String, String>? row;
  final String trainingLogText;

  @override
  Widget build(BuildContext context) {
    final row = this.row;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DatabasePanel(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: row == null
            ? Center(child: Text(t('database.selectRow')))
            : ListView(
                children: [
                  Text(
                    t('database.rowDetail'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  for (final entry in row.entries)
                    _DatabaseInfoRow(label: entry.key, value: entry.value),
                  if (activeTable == 'training_terminal_logs') ...[
                    const SizedBox(height: 14),
                    Text(
                      t('database.trainingTerminal'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: appControlColor(dark),
                        border: Border.all(color: appBorderColor(dark)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: SelectableText(
                          trainingLogText.trim().isEmpty
                              ? t('database.noTrainingLogs')
                              : trainingLogText,
                          style: const TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 12,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class DatabaseDetailResizeHandle extends StatelessWidget {
  const DatabaseDetailResizeHandle({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = appBorderColor(dark);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: SizedBox(
          width: 10,
          child: Center(
            child: Container(
              width: 3,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: dark ? 0.9 : 1),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DatabaseValueCell extends StatelessWidget {
  const DatabaseValueCell({required this.column, required this.value});

  final String column;
  final String value;

  @override
  Widget build(BuildContext context) {
    final color = column == 'color_hex' ? _colorFromHex(value) : null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 90, maxWidth: 220),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (color != null) ...[
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: color,
                border: Border.all(color: appBorderColor(dark)),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class DatabaseTreeButton extends StatelessWidget {
  const DatabaseTreeButton({
    required this.icon,
    required this.label,
    required this.trailing,
    required this.selected,
    this.collapsed = false,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String trailing;
  final bool selected;
  final bool collapsed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = selected
        ? colorScheme.primary
        : Theme.of(context).colorScheme.onSurface;
    final background = selected
        ? colorScheme.primaryContainer
        : Colors.transparent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 34,
            child: Row(
              children: [
                SizedBox(width: collapsed ? 0 : 8),
                Icon(icon, size: 18, color: foreground),
                if (!collapsed) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: foreground),
                    ),
                  ),
                  if (trailing.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      trailing,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DatabaseInfoRow extends StatelessWidget {
  const _DatabaseInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class DatabasePanel extends StatelessWidget {
  const DatabasePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: appPanelColor(dark),
        border: Border.all(color: appBorderColor(dark)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );
  }
}

class DatabaseTableSpec {
  const DatabaseTableSpec(this.name, this.icon);

  final String name;
  final IconData icon;
}

IconData databaseTableIcon(String table) {
  for (final spec in databaseTableSpecs) {
    if (spec.name == table) {
      return spec.icon;
    }
  }
  return Icons.table_chart_outlined;
}

String defaultSqlForDatabaseTable(String table) {
  if (table == 'training_terminal_logs') {
    return '-- ${t('database.virtualTable')}\nSELECT * FROM projects LIMIT 100;';
  }
  return 'SELECT * FROM $table LIMIT 100;';
}

Color? _colorFromHex(String value) {
  final normalized = value.trim().replaceFirst('#', '');
  if (normalized.length != 6) {
    return null;
  }
  final rgb = int.tryParse(normalized, radix: 16);
  if (rgb == null) {
    return null;
  }
  return Color(0xFF000000 | rgb);
}

DateTime? databaseDateFromString(String value) {
  final parts = value.split('-');
  if (parts.length != 3) {
    return null;
  }
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) {
    return null;
  }
  return DateTime(year, month, day);
}

String databaseDateString(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
