// =============================================================================
// database_table_panel.dart - Database Table Panel / 数据库表主面板
// =============================================================================
// Main table browser: action tabs (browse/structure/SQL), project filter,
// scrollable DataTable with row selection, and pagination controls.
//
// 主表浏览器：操作标签（浏览/结构/SQL）、项目过滤器、可滚动 DataTable 和分页控件。
// =============================================================================

import 'package:flutter/material.dart';

import '../../services/i18n.dart';
import '../../theme/theme_helpers.dart';
import 'database_detail_widgets.dart';

class DatabaseTablePanel extends StatefulWidget {
  const DatabaseTablePanel({
    required this.activeAction,
    required this.activeTable,
    required this.selectedProjectId,
    required this.imageFilterId,
    required this.projects,
    required this.columns,
    required this.rows,
    required this.selectedRowIndex,
    required this.pageIndex,
    required this.rowsPerPage,
    required this.sqlController,
    required this.sqlStatus,
    required this.onActionSelected,
    required this.onProjectSelected,
    required this.onRunSql,
    required this.onRowsPerPageChanged,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onRowSelected,
    required this.onShowImageAnnotations,
    required this.onClearImageFilter,
    required this.onDeleteLogRange,
  });

  final String activeAction;
  final String activeTable;
  final String? selectedProjectId;
  final String? imageFilterId;
  final List<Map<String, String>> projects;
  final List<String> columns;
  final List<Map<String, String>> rows;
  final int? selectedRowIndex;
  final int pageIndex;
  final int rowsPerPage;
  final TextEditingController sqlController;
  final String sqlStatus;
  final ValueChanged<String> onActionSelected;
  final ValueChanged<String?> onProjectSelected;
  final VoidCallback onRunSql;
  final ValueChanged<int> onRowsPerPageChanged;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;
  final ValueChanged<int> onRowSelected;
  final VoidCallback? onShowImageAnnotations;
  final VoidCallback? onClearImageFilter;
  final VoidCallback? onDeleteLogRange;

  @override
  State<DatabaseTablePanel> createState() => _DatabaseTablePanelState();
}

class _DatabaseTablePanelState extends State<DatabaseTablePanel> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  String get activeAction => widget.activeAction;
  String get activeTable => widget.activeTable;
  String? get selectedProjectId => widget.selectedProjectId;
  String? get imageFilterId => widget.imageFilterId;
  List<Map<String, String>> get projects => widget.projects;
  List<String> get columns => widget.columns;
  List<Map<String, String>> get rows => widget.rows;
  int? get selectedRowIndex => widget.selectedRowIndex;
  int get pageIndex => widget.pageIndex;
  int get rowsPerPage => widget.rowsPerPage;
  TextEditingController get sqlController => widget.sqlController;
  String get sqlStatus => widget.sqlStatus;
  ValueChanged<String> get onActionSelected => widget.onActionSelected;
  ValueChanged<String?> get onProjectSelected => widget.onProjectSelected;
  VoidCallback get onRunSql => widget.onRunSql;
  ValueChanged<int> get onRowsPerPageChanged => widget.onRowsPerPageChanged;
  VoidCallback? get onPreviousPage => widget.onPreviousPage;
  VoidCallback? get onNextPage => widget.onNextPage;
  ValueChanged<int> get onRowSelected => widget.onRowSelected;
  VoidCallback? get onShowImageAnnotations => widget.onShowImageAnnotations;
  VoidCallback? get onClearImageFilter => widget.onClearImageFilter;
  VoidCallback? get onDeleteLogRange => widget.onDeleteLogRange;

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DatabasePanel(
      child: Column(
        children: [
          _DatabaseActionTabs(
            activeAction: activeAction,
            onActionSelected: onActionSelected,
          ),
          Divider(height: 1, color: appBorderColor(dark)),
          if (activeAction == 'browse')
            _DatabaseBrowseToolbar(
              projects: projects,
              selectedProjectId: selectedProjectId,
              imageFilterId: imageFilterId,
              onProjectSelected: onProjectSelected,
              onClearImageFilter: onClearImageFilter,
              onShowImageAnnotations: onShowImageAnnotations,
              onDeleteLogRange: onDeleteLogRange,
            ),
          if (activeAction == 'sql')
            _DatabaseSqlEditor(
              controller: sqlController,
              status: sqlStatus,
              onRun: onRunSql,
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  activeAction == 'sql'
                      ? Icons.terminal
                      : activeAction == 'structure'
                      ? Icons.schema_outlined
                      : databaseTableIcon(activeTable),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  activeAction == 'sql'
                      ? t('database.sqlResult')
                      : activeAction == 'structure'
                      ? t('database.structure')
                      : t('database.table.$activeTable'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(width: 10),
                Chip(
                  label: Text('${t('database.rows')}: ${rows.length}'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: appBorderColor(dark)),
          Expanded(
            child: rows.isEmpty
                ? Center(child: Text(t('database.noRows')))
                : Scrollbar(
                    controller: _horizontalController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    child: SingleChildScrollView(
                      controller: _horizontalController,
                      scrollDirection: Axis.horizontal,
                      child: Scrollbar(
                        controller: _verticalController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _verticalController,
                          child: DataTable(
                            showCheckboxColumn: false,
                            headingRowHeight: 38,
                            dataRowMinHeight: 36,
                            dataRowMaxHeight: 48,
                            columns: [
                              for (final column in columns)
                                DataColumn(
                                  label: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minWidth: 90,
                                      maxWidth: 220,
                                    ),
                                    child: Text(
                                      column,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                            ],
                            rows: [
                              for (var index = 0; index < rows.length; index++)
                                DataRow(
                                  selected: selectedRowIndex == index,
                                  onSelectChanged: (_) => onRowSelected(index),
                                  cells: [
                                    for (final column in columns)
                                      DataCell(
                                        DatabaseValueCell(
                                          column: column,
                                          value: rows[index][column] ?? '',
                                        ),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          if (activeAction == 'browse')
            _DatabasePaginationBar(
              pageIndex: pageIndex,
              rowsPerPage: rowsPerPage,
              canGoPrevious: onPreviousPage != null,
              canGoNext: onNextPage != null,
              onRowsPerPageChanged: onRowsPerPageChanged,
              onPreviousPage: onPreviousPage,
              onNextPage: onNextPage,
            ),
        ],
      ),
    );
  }
}

class _DatabasePaginationBar extends StatelessWidget {
  const _DatabasePaginationBar({
    required this.pageIndex,
    required this.rowsPerPage,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onRowsPerPageChanged,
    required this.onPreviousPage,
    required this.onNextPage,
  });

  final int pageIndex;
  final int rowsPerPage;
  final bool canGoPrevious;
  final bool canGoNext;
  final ValueChanged<int> onRowsPerPageChanged;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: appPanelColor(dark),
        border: Border(top: BorderSide(color: appBorderColor(dark))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(t('database.rowsPerPage')),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: rowsPerPage,
            items: const [
              DropdownMenuItem(value: 50, child: Text('50')),
              DropdownMenuItem(value: 100, child: Text('100')),
              DropdownMenuItem(value: 200, child: Text('200')),
            ],
            onChanged: (value) {
              if (value != null) {
                onRowsPerPageChanged(value);
              }
            },
          ),
          const SizedBox(width: 18),
          IconButton(
            tooltip: t('database.previousPage'),
            onPressed: canGoPrevious ? onPreviousPage : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text('${t('database.page')} ${pageIndex + 1}'),
          IconButton(
            tooltip: t('database.nextPage'),
            onPressed: canGoNext ? onNextPage : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _DatabaseActionTabs extends StatelessWidget {
  const _DatabaseActionTabs({
    required this.activeAction,
    required this.onActionSelected,
  });

  final String activeAction;
  final ValueChanged<String> onActionSelected;

  @override
  Widget build(BuildContext context) {
    const actions = [
      ('browse', Icons.table_rows_outlined, 'database.browse'),
      ('structure', Icons.schema_outlined, 'database.structure'),
      ('sql', Icons.terminal, 'database.sql'),
    ];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: [
          for (final action in actions)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                selected: activeAction == action.$1,
                avatar: Icon(action.$2, size: 16),
                label: Text(t(action.$3)),
                onSelected: (_) => onActionSelected(action.$1),
              ),
            ),
        ],
      ),
    );
  }
}

class _DatabaseBrowseToolbar extends StatelessWidget {
  const _DatabaseBrowseToolbar({
    required this.projects,
    required this.selectedProjectId,
    required this.imageFilterId,
    required this.onProjectSelected,
    required this.onClearImageFilter,
    required this.onShowImageAnnotations,
    required this.onDeleteLogRange,
  });

  final List<Map<String, String>> projects;
  final String? selectedProjectId;
  final String? imageFilterId;
  final ValueChanged<String?> onProjectSelected;
  final VoidCallback? onClearImageFilter;
  final VoidCallback? onShowImageAnnotations;
  final VoidCallback? onDeleteLogRange;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final selected =
        selectedProjectId != null &&
            projects.any((project) => project['id'] == selectedProjectId)
        ? selectedProjectId
        : '';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: appPanelColor(dark),
        border: Border(bottom: BorderSide(color: appBorderColor(dark))),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 320,
            child: DropdownButtonFormField<String>(
              initialValue: selected,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: t('database.projectFilter'),
                isDense: true,
              ),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(t('database.allProjects')),
                ),
                for (final project in projects)
                  DropdownMenuItem(
                    value: project['id'] ?? '',
                    child: Text(
                      '${project['id'] ?? ''}  ${project['name'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => onProjectSelected(
                value == null || value.isEmpty ? null : value,
              ),
            ),
          ),
          if (imageFilterId != null)
            Chip(
              label: Text('${t('database.imageFilter')}: $imageFilterId'),
              visualDensity: VisualDensity.compact,
            ),
          if (onShowImageAnnotations != null)
            OutlinedButton.icon(
              onPressed: onShowImageAnnotations,
              icon: const Icon(Icons.edit_note, size: 18),
              label: Text(t('database.viewImageAnnotations')),
            ),
          if (onClearImageFilter != null)
            OutlinedButton.icon(
              onPressed: onClearImageFilter,
              icon: const Icon(Icons.filter_alt_off, size: 18),
              label: Text(t('database.clearImageFilter')),
            ),
          if (onDeleteLogRange != null)
            OutlinedButton.icon(
              onPressed: onDeleteLogRange,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(t('logs.deleteRange')),
            ),
        ],
      ),
    );
  }
}

class _DatabaseSqlEditor extends StatelessWidget {
  const _DatabaseSqlEditor({
    required this.controller,
    required this.status,
    required this.onRun,
  });

  final TextEditingController controller;
  final String status;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: appPanelColor(dark),
        border: Border(bottom: BorderSide(color: appBorderColor(dark))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t('database.sqlHelp'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: onRun,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text(t('database.runSql')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            minLines: 3,
            maxLines: 6,
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              hintText: 'SELECT * FROM images LIMIT 100;',
              suffixIcon: IconButton(
                tooltip: t('database.runSql'),
                onPressed: onRun,
                icon: const Icon(Icons.keyboard_return),
              ),
            ),
            onSubmitted: (_) => onRun(),
          ),
          if (status.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              status,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
