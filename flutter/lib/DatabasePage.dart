// DatabasePage.dart - MySQL-style Database Browser / 类 MySQL 数据库浏览页
//
// Provides a read-oriented table explorer for AnnotationConfig.db. Table access
// is routed through Rust whitelisted queries instead of arbitrary SQL execution.
//
// 提供面向查看的 AnnotationConfig.db 表浏览器。所有查询都走 Rust 白名单接口，
// 不执行用户输入 SQL，避免误删或破坏标注数据。

part of 'main.dart';

const _databaseTableSpecs = [
  _DatabaseTableSpec('projects', Icons.account_tree_outlined),
  _DatabaseTableSpec('images', Icons.image_outlined),
  _DatabaseTableSpec('classes', Icons.palette_outlined),
  _DatabaseTableSpec('annotations', Icons.edit_note),
  _DatabaseTableSpec('collaboration_permissions', Icons.verified_user_outlined),
  _DatabaseTableSpec('app_config', Icons.tune_outlined),
  _DatabaseTableSpec('app_logs', Icons.article_outlined),
  _DatabaseTableSpec('training_terminal_logs', Icons.terminal),
];

const _databaseDetailPanelDefaultWidth = 330.0;
const _databaseDetailPanelMinWidth = 260.0;
const _databaseDetailPanelMaxWidth = 640.0;
const _databaseMainTableMinWidth = 520.0;

class _DatabasePage extends StatefulWidget {
  const _DatabasePage();

  @override
  State<_DatabasePage> createState() => _DatabasePageState();
}

class _DatabasePageState extends State<_DatabasePage> {
  final TextEditingController _sqlController = TextEditingController(
    text: 'SELECT * FROM projects LIMIT 100;',
  );
  Map<String, dynamic>? _overview;
  List<Map<String, String>> _projectRows = const [];
  List<String> _columns = const [];
  List<Map<String, String>> _rows = const [];
  String _activeTable = 'projects';
  String _activeAction = 'browse';
  String? _selectedProjectId;
  String? _annotationImageFilterId;
  int _pageIndex = 0;
  int _rowsPerPage = 50;
  bool _tableBrowserExpanded = true;
  double _detailPanelWidth = _databaseDetailPanelDefaultWidth;
  int? _selectedRowIndex;
  String _trainingLogText = '';
  String _sqlStatus = '';
  String? _errorMessage;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void dispose() {
    _sqlController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final overview = await _ConfigStore.databaseOverview();
      final projectTable = await _ConfigStore.databaseTable(table: 'projects');
      final projectRows = _rowsFromTable(projectTable);
      final validProjectIds = projectRows.map((row) => row['id']).toSet();
      final projectId = validProjectIds.contains(_selectedProjectId)
          ? _selectedProjectId
          : null;
      final tableData = await _loadActionData(projectId: projectId);
      if (!mounted) {
        return;
      }
      setState(() {
        _overview = overview;
        _projectRows = projectRows;
        _selectedProjectId = projectId;
        _columns = _columnsFromTable(tableData);
        _rows = _rowsFromTable(tableData);
        _selectedRowIndex = null;
        _trainingLogText = '';
        if (_activeAction == 'sql') {
          _sqlStatus = _sqlStatusFromTable(tableData);
        }
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '$error';
        _loading = false;
      });
    }
  }

  Future<Map<String, dynamic>> _loadActionData({String? projectId}) async {
    if (_activeAction == 'structure') {
      return _loadStructureData(_activeTable);
    }
    if (_activeAction == 'sql') {
      return _ConfigStore.databaseSqlQuery(sql: _sqlController.text);
    }
    return _loadTableData(
      table: _activeTable,
      projectId: projectId,
      imageId: _annotationImageFilterId,
    );
  }

  Future<Map<String, dynamic>> _loadTableData({
    required String table,
    String? projectId,
    String? imageId,
  }) async {
    if (table == 'training_terminal_logs') {
      final dates = await _ConfigStore.trainingLogDates();
      final start = (_pageIndex * _rowsPerPage)
          .clamp(0, dates.length)
          .toInt();
      final end = (start + _rowsPerPage).clamp(0, dates.length).toInt();
      return {
        'columns': ['date'],
        'rows': [
          for (final date in dates.sublist(start, end)) {'date': date},
        ],
      };
    }
    return _ConfigStore.databaseTable(
      table: table,
      projectId: table == 'projects' ? '' : (projectId ?? ''),
      imageId: table == 'annotations' ? (imageId ?? '') : '',
      limit: _rowsPerPage,
      offset: _pageIndex * _rowsPerPage,
    );
  }

  Future<Map<String, dynamic>> _loadStructureData(String table) {
    if (table == 'training_terminal_logs') {
      return Future.value({
        'columns': ['field', 'type', 'note'],
        'rows': [
          {
            'field': 'date',
            'type': 'TEXT',
            'note': t('database.virtualTable'),
          },
        ],
      });
    }
    return _ConfigStore.databaseSqlQuery(sql: 'PRAGMA table_info($table);');
  }

  List<String> _columnsFromTable(Map<String, dynamic> tableData) {
    final columns = tableData['columns'];
    if (columns is! List) {
      return const [];
    }
    return columns.map((item) => '$item').toList(growable: false);
  }

  List<Map<String, String>> _rowsFromTable(Map<String, dynamic> tableData) {
    final rows = tableData['rows'];
    if (rows is! List) {
      return const [];
    }
    return rows
        .whereType<Map>()
        .map(
          (row) => row.map(
            (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
          ),
        )
        .toList(growable: false);
  }

  Future<void> _selectProject(String? projectId) async {
    setState(() {
      _selectedProjectId = projectId;
      _annotationImageFilterId = null;
      _pageIndex = 0;
    });
    await _reload();
  }

  void _toggleTableBrowser() {
    setState(() => _tableBrowserExpanded = !_tableBrowserExpanded);
  }

  void _resizeDetailPanel(double deltaX, double maxWidth) {
    setState(() {
      _detailPanelWidth = (_detailPanelWidth - deltaX)
          .clamp(_databaseDetailPanelMinWidth, maxWidth)
          .toDouble();
    });
  }

  Future<void> _selectTable(String table) async {
    setState(() {
      _activeTable = table;
      _activeAction = 'browse';
      _pageIndex = 0;
      if (table != 'training_terminal_logs') {
        _sqlController.text = _defaultSqlForTable(table);
      }
      if (table != 'annotations') {
        _annotationImageFilterId = null;
      }
    });
    await _reload();
  }

  Future<void> _selectAction(String action) async {
    setState(() {
      _activeAction = action;
      _pageIndex = 0;
      _selectedRowIndex = null;
      _trainingLogText = '';
      _sqlStatus = '';
      if (action == 'sql' && _activeTable != 'training_terminal_logs') {
        _sqlController.text = _defaultSqlForTable(_activeTable);
      }
    });
    await _reload();
  }

  Future<void> _runSqlQuery() async {
    setState(() {
      _activeAction = 'sql';
      _loading = true;
      _errorMessage = null;
      _selectedRowIndex = null;
    });
    try {
      final tableData = await _ConfigStore.databaseSqlQuery(
        sql: _sqlController.text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _columns = _columnsFromTable(tableData);
        _rows = _rowsFromTable(tableData);
        _sqlStatus = _sqlStatusFromTable(tableData);
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _showAnnotationsForSelectedImage() async {
    final row = _selectedRow;
    final imageId = row?['id'];
    if (imageId == null || imageId.isEmpty) {
      return;
    }
    setState(() {
      _activeTable = 'annotations';
      _activeAction = 'browse';
      _annotationImageFilterId = imageId;
      _pageIndex = 0;
    });
    await _reload();
  }

  Future<void> _clearImageFilter() async {
    setState(() {
      _annotationImageFilterId = null;
      _pageIndex = 0;
    });
    await _reload();
  }

  Future<void> _changeRowsPerPage(int value) async {
    setState(() {
      _rowsPerPage = value.clamp(50, 200).toInt();
      _pageIndex = 0;
    });
    await _reload();
  }

  Future<void> _movePage(int delta) async {
    if (delta < 0 && _pageIndex == 0) {
      return;
    }
    if (delta > 0 && _rows.length < _rowsPerPage) {
      return;
    }
    setState(() {
      _pageIndex = (_pageIndex + delta).clamp(0, 1 << 30).toInt();
      _selectedRowIndex = null;
    });
    await _reload();
  }

  Future<void> _deleteVisibleLogRange() async {
    final dates = _rows
        .map((row) => row['date'] ?? row['log_date'] ?? '')
        .where((date) => _dateFromString(date) != null)
        .toSet()
        .toList()
      ..sort();
    final range = await _pickDateRange(dates);
    if (range == null) {
      return;
    }
    final startDate = _dateString(range.start);
    final endDate = _dateString(range.end);
    final deleted = _activeTable == 'training_terminal_logs'
        ? await _ConfigStore.deleteTrainingLogsByDateRange(startDate, endDate)
        : _ConfigStore.deleteLogsByDateRange(startDate, endDate);
    _showDatabaseMessage('${t('logs.deleted')}: $deleted');
    await _reload();
  }

  Future<DateTimeRange?> _pickDateRange(List<String> dates) async {
    final parsedDates = dates
        .map(_dateFromString)
        .whereType<DateTime>()
        .toList(growable: false);
    if (parsedDates.isEmpty) {
      _showDatabaseMessage(t('logs.noLogs'));
      return null;
    }
    var firstDate = parsedDates.first;
    var lastDate = parsedDates.first;
    for (final date in parsedDates.skip(1)) {
      if (date.isBefore(firstDate)) {
        firstDate = date;
      }
      if (date.isAfter(lastDate)) {
        lastDate = date;
      }
    }
    return showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: DateTimeRange(start: firstDate, end: lastDate),
      helpText: t('logs.selectDeleteRange'),
    );
  }

  void _selectRow(int index) {
    setState(() {
      _selectedRowIndex = index;
      if (_activeTable == 'images') {
        _annotationImageFilterId = _rows[index]['id'];
      }
    });
    if (_activeTable == 'training_terminal_logs') {
      unawaited(_loadTrainingLogDetail(_rows[index]['date'] ?? ''));
    }
  }

  Future<void> _loadTrainingLogDetail(String date) async {
    if (date.isEmpty) {
      return;
    }
    final text = await _ConfigStore.readTrainingLogForDate(date);
    if (!mounted) {
      return;
    }
    setState(() => _trainingLogText = text);
  }

  void _showDatabaseMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Map<String, String>? get _selectedRow {
    final index = _selectedRowIndex;
    if (index == null || index < 0 || index >= _rows.length) {
      return null;
    }
    return _rows[index];
  }

  String _sqlStatusFromTable(Map<String, dynamic> tableData) {
    final rowCount = tableData['rowCount'] ?? _rowsFromTable(tableData).length;
    final truncated = tableData['truncated'] == true
        ? ' ${t('database.truncated')}'
        : '';
    return '${t('database.sqlRows')}: $rowCount$truncated';
  }

  @override
  Widget build(BuildContext context) {
    final dbPath = '${_overview?['dbPath'] ?? _ConfigStore.databaseFile.path}';
    final cleanupText =
        '${t('database.cleanedImages')}: ${_overview?['cleanupDeletedImages'] ?? 0}  '
        '${t('database.cleanedProjects')}: ${_overview?['cleanupDeletedProjects'] ?? 0}';
    return Container(
      color: _workspaceColor(context),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('database.title'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$dbPath    $cleanupText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : () => unawaited(_reload()),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(t('database.refresh')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compactTables = constraints.maxWidth < 980;
                final showDetailPanel = constraints.maxWidth >= 1180;
                final tableBrowserExpanded =
                    _tableBrowserExpanded && !compactTables;
                final browserWidth = tableBrowserExpanded ? 260.0 : 44.0;
                final maxDetailPanelWidth = math
                    .min(
                      _databaseDetailPanelMaxWidth,
                      constraints.maxWidth -
                          browserWidth -
                          _databaseMainTableMinWidth -
                          40,
                    )
                    .clamp(
                      _databaseDetailPanelMinWidth,
                      _databaseDetailPanelMaxWidth,
                    )
                    .toDouble();
                final detailPanelWidth = _detailPanelWidth
                    .clamp(
                      _databaseDetailPanelMinWidth,
                      maxDetailPanelWidth,
                    )
                    .toDouble();
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      width: tableBrowserExpanded ? 260 : 44,
                      child: _DatabaseExplorerSidebar(
                        overview: _overview,
                        activeTable: _activeTable,
                        expanded: tableBrowserExpanded,
                        onToggleExpanded: _toggleTableBrowser,
                        onTableSelected: (table) =>
                            unawaited(_selectTable(table)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DatabaseTablePanel(
                        activeAction: _activeAction,
                        activeTable: _activeTable,
                        selectedProjectId: _selectedProjectId,
                        imageFilterId: _annotationImageFilterId,
                        projects: _projectRows,
                        columns: _columns,
                        rows: _rows,
                        selectedRowIndex: _selectedRowIndex,
                        pageIndex: _pageIndex,
                        rowsPerPage: _rowsPerPage,
                        sqlController: _sqlController,
                        sqlStatus: _sqlStatus,
                        onActionSelected: (action) =>
                            unawaited(_selectAction(action)),
                        onProjectSelected: (id) =>
                            unawaited(_selectProject(id)),
                        onRunSql: () => unawaited(_runSqlQuery()),
                        onRowsPerPageChanged: (value) =>
                            unawaited(_changeRowsPerPage(value)),
                        onPreviousPage: _pageIndex == 0
                            ? null
                            : () => unawaited(_movePage(-1)),
                        onNextPage: _rows.length < _rowsPerPage
                            ? null
                            : () => unawaited(_movePage(1)),
                        onRowSelected: _selectRow,
                        onShowImageAnnotations:
                            _activeAction == 'browse' &&
                                _activeTable == 'images' &&
                                _selectedRow != null
                            ? () =>
                                unawaited(_showAnnotationsForSelectedImage())
                            : null,
                        onClearImageFilter:
                            _activeAction == 'browse' &&
                                _activeTable == 'annotations' &&
                                _annotationImageFilterId != null
                            ? () => unawaited(_clearImageFilter())
                            : null,
                        onDeleteLogRange:
                            _activeAction == 'browse' &&
                                (_activeTable == 'app_logs' ||
                                    _activeTable == 'training_terminal_logs')
                            ? () => unawaited(_deleteVisibleLogRange())
                            : null,
                      ),
                    ),
                    if (showDetailPanel) ...[
                      const SizedBox(width: 8),
                      _DatabaseDetailResizeHandle(
                        onDrag: (deltaX) => _resizeDetailPanel(
                          deltaX,
                          maxDetailPanelWidth,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: detailPanelWidth,
                        child: _DatabaseRowDetailPanel(
                          activeTable: _activeTable,
                          row: _selectedRow,
                          trainingLogText: _trainingLogText,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

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

class _DatabaseTablePanel extends StatefulWidget {
  const _DatabaseTablePanel({
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
  State<_DatabaseTablePanel> createState() => _DatabaseTablePanelState();
}

class _DatabaseTablePanelState extends State<_DatabaseTablePanel> {
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
    return _DatabasePanel(
      child: Column(
        children: [
          _DatabaseActionTabs(
            activeAction: activeAction,
            onActionSelected: onActionSelected,
          ),
          Divider(height: 1, color: _borderColor(context)),
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
                      : _tableIcon(activeTable),
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
          Divider(height: 1, color: _borderColor(context)),
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
                                        _DatabaseValueCell(
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
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _panelColor(context),
        border: Border(top: BorderSide(color: _borderColor(context))),
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
    final selected = selectedProjectId != null &&
            projects.any((project) => project['id'] == selectedProjectId)
        ? selectedProjectId
        : '';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _isDarkMode(context)
            ? const Color(0xFF1B1038)
            : const Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: _borderColor(context))),
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
              onChanged: (value) =>
                  onProjectSelected(value == null || value.isEmpty ? null : value),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isDarkMode(context)
            ? const Color(0xFF120A25)
            : const Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: _borderColor(context))),
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

class _DatabaseRowDetailPanel extends StatelessWidget {
  const _DatabaseRowDetailPanel({
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
    return _DatabasePanel(
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
                        color: _isDarkMode(context)
                            ? const Color(0xFF120A25)
                            : const Color(0xFFF8FAFC),
                        border: Border.all(color: _borderColor(context)),
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

class _DatabaseDetailResizeHandle extends StatelessWidget {
  const _DatabaseDetailResizeHandle({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    final color = _borderColor(context);
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
                color: color.withValues(alpha: _isDarkMode(context) ? 0.9 : 1),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DatabaseValueCell extends StatelessWidget {
  const _DatabaseValueCell({required this.column, required this.value});

  final String column;
  final String value;

  @override
  Widget build(BuildContext context) {
    final color = column == 'color_hex' ? _colorFromHex(value) : null;
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
                border: Border.all(color: _borderColor(context)),
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

class _DatabaseTreeButton extends StatelessWidget {
  const _DatabaseTreeButton({
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
        ? (_isDarkMode(context)
              ? _darkControlBackground
              : const Color(0xFFEFF6FF))
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

class _DatabasePanel extends StatelessWidget {
  const _DatabasePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _panelColor(context),
        border: Border.all(color: _borderColor(context)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );
  }
}

class _DatabaseTableSpec {
  const _DatabaseTableSpec(this.name, this.icon);

  final String name;
  final IconData icon;
}

IconData _tableIcon(String table) {
  return _databaseTableSpecs
      .where((spec) => spec.name == table)
      .map((spec) => spec.icon)
      .firstOrNullValue ?? Icons.table_chart_outlined;
}

String _defaultSqlForTable(String table) {
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

DateTime? _dateFromString(String value) {
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

String _dateString(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
