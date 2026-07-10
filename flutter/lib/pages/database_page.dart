// database_page.dart - MySQL-style Database Browser / 类 MySQL 数据库浏览页
//
// Provides a read-oriented table explorer for AnnotationConfig.db. Table access
// is routed through Rust whitelisted queries instead of arbitrary SQL execution.
//
// 提供面向查看的 AnnotationConfig.db 表浏览器。所有查询都走 Rust 白名单接口，
// 不执行用户输入 SQL，避免误删或破坏标注数据。

part of '../main.dart';

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
      final overview = await ConfigStore.databaseOverview();
      final projectTable = await ConfigStore.databaseTable(table: 'projects');
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
      return ConfigStore.databaseSqlQuery(sql: _sqlController.text);
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
      final dates = await ConfigStore.trainingLogDates();
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
    return ConfigStore.databaseTable(
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
    return ConfigStore.databaseSqlQuery(sql: 'PRAGMA table_info($table);');
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
      final tableData = await ConfigStore.databaseSqlQuery(
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
        ? await ConfigStore.deleteTrainingLogsByDateRange(startDate, endDate)
        : ConfigStore.deleteLogsByDateRange(startDate, endDate);
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
    final text = await ConfigStore.readTrainingLogForDate(date);
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
    final dbPath = '${_overview?['dbPath'] ?? ConfigStore.databaseFile.path}';
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

