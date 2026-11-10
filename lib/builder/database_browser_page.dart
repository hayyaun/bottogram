import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ui/design.dart';
import 'database_browser_source.dart';

class DatabaseBrowserPage extends StatefulWidget {
  const DatabaseBrowserPage({
    super.key,
    required this.botName,
    required this.source,
  });
  final String botName;
  final DatabaseBrowserSource source;
  @override
  State<DatabaseBrowserPage> createState() => _DatabaseBrowserPageState();
}

class _DatabaseBrowserPageState extends State<DatabaseBrowserPage> {
  List<DatabaseTable> _tables = [];
  final _counts = <String, Future<int>>{};
  String _search = '';
  String? _error;
  bool _loading = true;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DatabaseBrowserPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) {
      _tables = [];
      _counts.clear();
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tables = List<DatabaseTable>.of(await widget.source.tables());
      if (!mounted || generation != _generation) return;
      tables.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      setState(() {
        _tables = tables;
        _counts.clear();
        _loading = false;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = _message(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _tables
        .where((t) => t.name.toLowerCase().contains(_search.toLowerCase()))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.botName} · Database',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh tables',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _ReadOnlyLabel(),
                const SizedBox(height: 14),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Find a table',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => _search = value),
                ),
                const SizedBox(height: 10),
                Text(
                  '${_tables.length} ${_tables.length == 1 ? 'table' : 'tables'} · counts load as tables become visible',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null) _ErrorNotice(message: _error!, retry: _load),
          Expanded(
            child: _loading && _tables.isEmpty
                ? const Center(child: Text('Opening database…'))
                : visible.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _tables.isEmpty
                            ? 'No tables yet. Tables will appear when this bot stores data.'
                            : 'No tables match this name.',
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final table = visible[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        leading: Icon(
                          table.internal
                              ? Icons.lock_outline
                              : Icons.table_chart_outlined,
                        ),
                        title: Text(
                          table.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: FutureBuilder<int>(
                          future: _counts.putIfAbsent(
                            table.name,
                            () => widget.source.count(table.name),
                          ),
                          builder: (context, snapshot) {
                            final suffix = table.internal
                                ? ' · Internal table'
                                : '';
                            if (snapshot.hasError) {
                              return Text('Count unavailable$suffix');
                            }
                            if (!snapshot.hasData) {
                              return Text('Counting rows…$suffix');
                            }
                            return Text(
                              '${snapshot.data} ${snapshot.data == 1 ? 'row' : 'rows'}$suffix',
                            );
                          },
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DatabaseTablePage(
                              botName: widget.botName,
                              table: table,
                              source: widget.source,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class DatabaseTablePage extends StatefulWidget {
  const DatabaseTablePage({
    super.key,
    required this.botName,
    required this.table,
    required this.source,
  });
  final String botName;
  final DatabaseTable table;
  final DatabaseBrowserSource source;
  @override
  State<DatabaseTablePage> createState() => _DatabaseTablePageState();
}

class _DatabaseTablePageState extends State<DatabaseTablePage> {
  final _horizontal = ScrollController(), _vertical = ScrollController();
  DatabaseTableSchema? _schema;
  DatabaseRowsPage? _page;
  int _offset = 0, _limit = 50, _generation = 0, _countGeneration = 0;
  String? _sortColumn, _filterColumn, _error, _countError;
  bool _descending = false, _loading = true;
  int? _count;
  DatabaseFilterOperator _filterOperator = DatabaseFilterOperator.equals;
  String _filterValue = '';
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final schema = await widget.source.schema(widget.table.name);
      if (!mounted) return;
      setState(() => _schema = schema);
      final loading = _load();
      _refreshCount();
      await loading;
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _message(error);
        });
      }
    }
  }

  Future<void> _refreshCount() async {
    final generation = ++_countGeneration;
    setState(() {
      _count = null;
      _countError = null;
    });
    try {
      final count = await widget.source.count(widget.table.name);
      if (mounted && generation == _countGeneration) {
        setState(() => _count = count);
      }
    } catch (_) {
      if (mounted && generation == _countGeneration) {
        setState(() => _countError = 'Count unavailable');
      }
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _page = null;
    });
    try {
      final page = await widget.source.rows(
        DatabaseRowsRequest(
          table: widget.table.name,
          limit: _limit,
          offset: _offset,
          sortColumn: _sortColumn,
          descending: _descending,
          filterColumn: _filterColumn,
          filterOperator: _filterOperator,
          filterValue: _filterValue,
        ),
      );
      if (mounted && generation == _generation) {
        setState(() {
          _page = page;
          _loading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && generation == _generation && _vertical.hasClients) {
            _vertical.jumpTo(0);
          }
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = _message(error);
        });
      }
    }
  }

  void _resetPage() {
    _offset = 0;
    _load();
  }

  Future<void> _filter() async {
    final schema = _schema;
    if (schema == null || schema.columns.isEmpty) return;
    final selected = await showDialog<_FilterSelection>(
      context: context,
      builder: (_) => _FilterDialog(
        columns: schema.columns,
        column: _filterColumn,
        operator: _filterOperator,
        value: _filterValue,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _filterColumn = selected.column;
      _filterOperator = selected.operator;
      _filterValue = selected.value;
    });
    _resetPage();
  }

  Future<void> _structure() async {
    final schema = _schema;
    if (schema == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${widget.table.name} · Structure'),
        content: SizedBox(
          width: 740,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Column')),
                      DataColumn(label: Text('Type')),
                      DataColumn(label: Text('Required')),
                      DataColumn(label: Text('Primary key')),
                      DataColumn(label: Text('Default')),
                    ],
                    rows: [
                      for (final column in schema.columns)
                        DataRow(
                          cells: [
                            DataCell(SelectableText(column.name)),
                            DataCell(
                              Text(column.type.isEmpty ? 'Any' : column.type),
                            ),
                            DataCell(Text(column.notNull ? 'Yes' : 'No')),
                            DataCell(
                              Text(
                                column.primaryKey == 0
                                    ? '—'
                                    : '${column.primaryKey}',
                              ),
                            ),
                            DataCell(
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 240,
                                ),
                                child: SelectableText(
                                  column.defaultValue?.toString() ?? '—',
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text('Indexes', style: Theme.of(context).textTheme.titleMedium),
                if (schema.indexes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('No indexes'),
                  ),
                for (final index in schema.indexes)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: SelectableText(index.name),
                    subtitle: Text(
                      '${index.unique ? 'Unique · ' : ''}${index.columns.isEmpty ? 'Expression index' : index.columns.join(', ')}',
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.table.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Table structure',
            onPressed: _schema == null ? null : _structure,
            icon: const Icon(Icons.account_tree_outlined),
          ),
          IconButton(
            tooltip: 'Refresh data',
            onPressed: _loading
                ? null
                : () {
                    if (_schema == null) {
                      _initialize();
                    } else {
                      _load();
                      _refreshCount();
                    }
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.botName} · ${_count == null ? _countError ?? 'Counting rows…' : '$_count total rows'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(child: _ReadOnlyLabel()),
                    TextButton.icon(
                      onPressed: _schema == null ? null : _filter,
                      icon: const Icon(Icons.filter_list, size: 18),
                      label: Text(
                        _filterColumn == null ? 'Filter' : 'Filtered',
                      ),
                    ),
                  ],
                ),
                if (_filterColumn != null)
                  InputChip(
                    deleteButtonTooltipMessage: 'Clear filter',
                    label: Text(
                      '$_filterColumn · ${_operatorLabel(_filterOperator)}${_filterOperator == DatabaseFilterOperator.isNull || _filterOperator == DatabaseFilterOperator.isNotNull ? '' : ' · $_filterValue'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onDeleted: () {
                      setState(() {
                        _filterColumn = null;
                        _filterValue = '';
                      });
                      _resetPage();
                    },
                  ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            _ErrorNotice(
              message: _error!,
              retry: _schema == null ? _initialize : _load,
            ),
          Expanded(
            child: page == null
                ? Center(
                    child: Text(
                      _loading
                          ? 'Loading rows…'
                          : 'Data is unavailable. Refresh to try again.',
                    ),
                  )
                : page.rows.isEmpty
                ? const Center(child: Text('No rows to display.'))
                : _grid(page),
          ),
          _pagination(page),
        ],
      ),
    );
  }

  Widget _grid(DatabaseRowsPage page) => LayoutBuilder(
    builder: (context, constraints) {
      final index = _sortColumn == null
          ? -1
          : page.columns.indexOf(_sortColumn!);
      return Scrollbar(
        controller: _vertical,
        child: SingleChildScrollView(
          controller: _vertical,
          child: Scrollbar(
            controller: _horizontal,
            thumbVisibility: true,
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _horizontal,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  headingRowColor: WidgetStatePropertyAll(
                    Theme.of(context).colorScheme.surfaceContainerLow,
                  ),
                  headingRowHeight: 64,
                  dataRowMinHeight: 48,
                  dataRowMaxHeight: 64,
                  horizontalMargin: 16,
                  columnSpacing: 24,
                  sortColumnIndex: index < 0 ? null : index + 1,
                  sortAscending: !_descending,
                  columns: [
                    const DataColumn(label: Text('#')),
                    for (final name in page.columns)
                      DataColumn(
                        label: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: Text(name, overflow: TextOverflow.ellipsis),
                        ),
                        onSort: (_, ascending) {
                          setState(() {
                            _sortColumn = name;
                            _descending = !ascending;
                          });
                          _resetPage();
                        },
                      ),
                  ],
                  rows: [
                    for (final (rowIndex, row) in page.rows.indexed)
                      DataRow(
                        cells: [
                          DataCell(
                            Text(
                              '${_offset + rowIndex + 1}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          for (final column in page.columns)
                            DataCell(
                              SizedBox(
                                width: 180,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    _display(row[column]),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: row[column] == null
                                        ? Theme.of(
                                            context,
                                          ).textTheme.bodySmall?.copyWith(
                                            fontStyle: FontStyle.italic,
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                              onTap: () => _cell(column, row[column]),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  Widget _pagination(DatabaseRowsPage? page) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Rows'),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _limit,
                items: [
                  for (final n in [10, 25, 50])
                    DropdownMenuItem(value: n, child: Text('$n')),
                ],
                onChanged: _loading
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _limit = value);
                          _resetPage();
                        }
                      },
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                page == null || page.rows.isEmpty
                    ? '0 shown'
                    : '${_offset + 1}–${_offset + page.rows.length}',
              ),
              IconButton(
                tooltip: 'Previous page',
                onPressed: _loading || _offset == 0
                    ? null
                    : () {
                        _offset = (_offset - _limit).clamp(0, _offset);
                        _load();
                      },
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Next page',
                onPressed: _loading || page?.hasMore != true
                    ? null
                    : () {
                        _offset += _limit;
                        _load();
                      },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  Future<void> _cell(String column, Object? value) async {
    final content = _detail(value);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(column),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _type(value),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                SelectableText(content),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: content));
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

String _message(Object error) => error is DatabaseBrowseException
    ? error.message
    : 'The database could not be read. Refresh and try again.';
String _operatorLabel(DatabaseFilterOperator operator) => switch (operator) {
  DatabaseFilterOperator.equals => 'equals',
  DatabaseFilterOperator.contains => 'contains',
  DatabaseFilterOperator.isNull => 'is NULL',
  DatabaseFilterOperator.isNotNull => 'is not NULL',
};
Uint8List? _blob(Object? value) {
  if (value is Uint8List) return value;
  if (value is Map && value.length == 1 && value['base64'] is String) {
    try {
      return base64Decode(value['base64'] as String);
    } on FormatException {
      return null;
    }
  }
  return null;
}

String _type(Object? value) {
  if (value == null) return 'NULL';
  final blob = _blob(value);
  if (blob != null) return 'BLOB · ${blob.length} bytes';
  return value is int
      ? 'INTEGER'
      : value is double
      ? 'REAL'
      : value is String
      ? 'TEXT · ${value.length} characters'
      : 'VALUE';
}

String _display(Object? value) {
  if (value == null) return 'NULL';
  final blob = _blob(value);
  if (blob != null) return 'BLOB · ${blob.length} bytes';
  return value == '' ? '(empty text)' : value.toString();
}

String _detail(Object? value) {
  if (value == null) return 'NULL';
  final blob = _blob(value);
  return blob == null ? value.toString() : base64Encode(blob);
}

class _ReadOnlyLabel extends StatelessWidget {
  const _ReadOnlyLabel();
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.lock_outline,
        size: 14,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 6),
      Flexible(
        child: Text('Read only', style: Theme.of(context).textTheme.bodySmall),
      ),
    ],
  );
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BNotice(message: message, error: true),
        TextButton(onPressed: retry, child: const Text('Try again')),
      ],
    ),
  );
}

class _FilterSelection {
  const _FilterSelection(this.column, this.operator, this.value);
  final String column, value;
  final DatabaseFilterOperator operator;
}

class _FilterDialog extends StatefulWidget {
  const _FilterDialog({
    required this.columns,
    required this.column,
    required this.operator,
    required this.value,
  });
  final List<DatabaseColumn> columns;
  final String? column;
  final DatabaseFilterOperator operator;
  final String value;
  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  late String _column = widget.column ?? widget.columns.first.name;
  late DatabaseFilterOperator _operator = widget.operator;
  late final _value = TextEditingController(text: widget.value);
  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Filter rows'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _column,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Column'),
              items: [
                for (final c in widget.columns)
                  DropdownMenuItem(
                    value: c.name,
                    child: Text(c.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _column = value);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<DatabaseFilterOperator>(
              initialValue: _operator,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Comparison'),
              items: [
                for (final op in DatabaseFilterOperator.values)
                  DropdownMenuItem(value: op, child: Text(_operatorLabel(op))),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _operator = value);
              },
            ),
            if (_operator == DatabaseFilterOperator.equals ||
                _operator == DatabaseFilterOperator.contains) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _value,
                maxLength: 4096,
                decoration: const InputDecoration(
                  labelText: 'Value',
                  helperText: 'Text is matched literally.',
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _FilterSelection(_column, _operator, _value.text),
        ),
        child: const Text('Apply'),
      ),
    ],
  );
}
