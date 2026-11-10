/// The browser receives structured, bot-scoped data. It never accepts a file
/// path or executes SQL supplied through a table name, column or filter.
abstract interface class DatabaseBrowserSource {
  Future<List<DatabaseTable>> tables();
  Future<int> count(String table);
  Future<DatabaseTableSchema> schema(String table);
  Future<DatabaseRowsPage> rows(DatabaseRowsRequest request);
}

class DatabaseBrowseException implements Exception {
  const DatabaseBrowseException(this.message);
  final String message;
  @override
  String toString() => message;
}

class DatabaseTable {
  const DatabaseTable({required this.name, this.internal = false});
  final String name;
  final bool internal;
  factory DatabaseTable.fromMap(Map value) => DatabaseTable(
    name: value['name'] as String,
    internal: value['internal'] == true,
  );
}

class DatabaseColumn {
  const DatabaseColumn({
    required this.name,
    this.type = '',
    this.notNull = false,
    this.defaultValue,
    this.primaryKey = 0,
  });
  final String name, type;
  final bool notNull;
  final Object? defaultValue;
  final int primaryKey;
  factory DatabaseColumn.fromMap(Map value) => DatabaseColumn(
    name: value['name'] as String,
    type: value['type'] as String? ?? '',
    notNull: value['notNull'] == true || value['notNull'] == 1,
    defaultValue: value['defaultValue'],
    primaryKey: value['primaryKey'] as int? ?? 0,
  );
}

class DatabaseIndex {
  const DatabaseIndex({
    required this.name,
    this.unique = false,
    this.columns = const [],
  });
  final String name;
  final bool unique;
  final List<String> columns;
  factory DatabaseIndex.fromMap(Map value) => DatabaseIndex(
    name: value['name'] as String,
    unique: value['unique'] == true || value['unique'] == 1,
    columns: List<String>.from(value['columns'] as List? ?? []),
  );
}

class DatabaseTableSchema {
  const DatabaseTableSchema({required this.columns, this.indexes = const []});
  final List<DatabaseColumn> columns;
  final List<DatabaseIndex> indexes;
  factory DatabaseTableSchema.fromMap(Map value) => DatabaseTableSchema(
    columns:
        (value['columns'] as List)
            .map((v) => DatabaseColumn.fromMap(v as Map))
            .toList(),
    indexes:
        (value['indexes'] as List? ?? [])
            .map((v) => DatabaseIndex.fromMap(v as Map))
            .toList(),
  );
}

enum DatabaseFilterOperator { equals, contains, isNull, isNotNull }

class DatabaseRowsRequest {
  const DatabaseRowsRequest({
    required this.table,
    this.limit = 50,
    this.offset = 0,
    this.sortColumn,
    this.descending = false,
    this.filterColumn,
    this.filterOperator = DatabaseFilterOperator.equals,
    this.filterValue = '',
  });
  final String table;
  final int limit, offset;
  final String? sortColumn, filterColumn;
  final bool descending;
  final DatabaseFilterOperator filterOperator;
  final String filterValue;
  Map<String, dynamic> toMap() => {
    'table': table,
    'limit': limit,
    'offset': offset,
    if (sortColumn != null) 'sortColumn': sortColumn,
    'descending': descending,
    if (filterColumn != null) ...{
      'filterColumn': filterColumn,
      'filterOperator': filterOperator.name,
      'filterValue': filterValue,
    },
  };
}

class DatabaseRowsPage {
  const DatabaseRowsPage({
    required this.columns,
    required this.rows,
    this.hasMore = false,
  });
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  final bool hasMore;
  factory DatabaseRowsPage.fromMap(Map value) => DatabaseRowsPage(
    columns: List<String>.from(value['columns'] as List),
    rows:
        (value['rows'] as List)
            .map((v) => Map<String, dynamic>.from(v as Map))
            .toList(),
    hasMore: value['hasMore'] == true,
  );
}
