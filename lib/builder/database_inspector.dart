import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'values.dart';

const _inspectionByteLimit = 1024 * 1024;
const _metadataItemLimit = 256;

/// Fixed read-only operations for the database browser. The caller must apply
/// its inspection authorizer and execution deadline to this connection.
/// Identifiers originate in validated SQLite metadata; filter values are bound.
Map<String, dynamic> inspectBotDatabase(
  Database db,
  String operation,
  Map<String, dynamic> args,
) {
  if (operation == 'tables') {
    final rows = db.select(
      "SELECT name FROM main.sqlite_schema WHERE type = 'table' "
      'ORDER BY name LIMIT ${_metadataItemLimit + 1}',
    );
    if (rows.length > _metadataItemLimit) {
      throw const BuilderFailure(
        'Database inspection is limited to 256 tables.',
      );
    }
    return _bounded({
      'tables': [
        for (final row in rows)
          {
            'name': row['name'] as String,
            'internal': _internal(row['name'] as String),
          },
      ],
    });
  }
  if (!{'count', 'schema', 'rows'}.contains(operation)) {
    throw const BuilderFailure('Unknown database inspection operation.');
  }
  final table = args['table'];
  if (table is! String || table.isEmpty) {
    throw const BuilderFailure('Choose a table to inspect.');
  }
  final exists = db.select(
    "SELECT name FROM main.sqlite_schema WHERE type = 'table' AND name = ?",
    [table],
  );
  if (exists.isEmpty) {
    throw const BuilderFailure('The selected table no longer exists.');
  }
  // table_xinfo includes generated columns that table_info omits.
  final info = db.select('PRAGMA main.table_xinfo(${_quote(table)})');
  if (info.isEmpty || info.length > _metadataItemLimit) {
    throw const BuilderFailure(
      'Table inspection requires between 1 and 256 columns.',
    );
  }
  final columns = [for (final row in info) row['name'] as String];
  _bounded({'columns': columns});

  if (operation == 'schema') {
    final indexes = db.select('PRAGMA main.index_list(${_quote(table)})');
    if (indexes.length > _metadataItemLimit) {
      throw const BuilderFailure('Table inspection is limited to 256 indexes.');
    }
    final output = <Map<String, dynamic>>[];
    for (final index in indexes) {
      final name = index['name'] as String;
      final details = db.select('PRAGMA main.index_info(${_quote(name)})');
      if (details.length > _metadataItemLimit) {
        throw const BuilderFailure(
          'Index inspection is limited to 256 columns.',
        );
      }
      output.add({
        'name': name,
        'unique': index['unique'] == 1,
        'columns': [
          for (final detail in details)
            detail['name'] as String? ?? '(expression)',
        ],
      });
      _bounded({'indexes': output});
    }
    return _bounded({
      'columns': [
        for (final row in info)
          {
            'name': row['name'] as String,
            'type': row['type'] as String,
            'notNull': row['notnull'] == 1,
            'defaultValue': row['dflt_value'],
            'primaryKey': row['pk'] as int,
          },
      ],
      'indexes': output,
    });
  }

  final (where, parameters) = _filter(args, columns);
  if (operation == 'count') {
    return {
      'count':
          db
                  .select(
                    'SELECT count(*) AS n FROM main.${_quote(table)}$where',
                    parameters,
                  )
                  .single['n']
              as int,
    };
  }

  final limit = args['limit'] ?? 25;
  final offset = args['offset'] ?? 0;
  if (limit is! int || !{10, 25, 50}.contains(limit)) {
    throw const BuilderFailure('Choose a page size of 10, 25 or 50 rows.');
  }
  if (offset is! int || offset < 0 || offset > 2147483647) {
    throw const BuilderFailure('Enter a valid nonnegative row offset.');
  }
  final sort = args['sortColumn'];
  if (sort != null && (sort is! String || !columns.contains(sort))) {
    throw const BuilderFailure('Choose an existing column to sort.');
  }
  final descending = args['descending'] ?? false;
  if (descending is! bool) {
    throw const BuilderFailure('Invalid sort direction.');
  }
  final primaryKeys = info.where((row) => (row['pk'] as int) > 0).toList()
    ..sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int));
  final sortColumns = <String>[
    if (sort is String) sort,
    for (final row in primaryKeys)
      if (row['name'] != sort) row['name'] as String,
  ];
  if (sortColumns.isEmpty) sortColumns.add(columns.first);
  final order = sortColumns
      .map((name) => '${_quote(name)} ${descending ? 'DESC' : 'ASC'}')
      .join(', ');
  final statement = db.prepare(
    'SELECT ${columns.map(_quote).join(', ')} '
    'FROM main.${_quote(table)}$where ORDER BY $order LIMIT ? OFFSET ?',
    checkNoTail: true,
  );
  try {
    final cursor = statement.selectCursor([...parameters, limit + 1, offset]);
    final result = <Map<String, dynamic>>[];
    var bytes = utf8.encode(jsonEncode({'columns': columns})).length;
    var hasMore = false;
    while (cursor.moveNext()) {
      if (result.length == limit) {
        hasMore = true;
        break;
      }
      final row = <String, dynamic>{};
      for (final name in columns) {
        final value = cursor.current[name];
        row[name] = switch (value) {
          Uint8List value => {'base64': base64Encode(value)},
          double value when !value.isFinite => value.toString(),
          _ => value,
        };
      }
      bytes += utf8.encode(jsonEncode(row)).length;
      if (bytes > _inspectionByteLimit) {
        throw const BuilderFailure(
          'This inspection exceeds 1 MiB. Choose fewer rows or a narrower filter.',
        );
      }
      result.add(row);
    }
    return _bounded({'columns': columns, 'rows': result, 'hasMore': hasMore});
  } finally {
    statement.close();
  }
}

(String, List<Object?>) _filter(
  Map<String, dynamic> args,
  List<String> columns,
) {
  final column = args['filterColumn'];
  if (column == null) return ('', const []);
  if (column is! String || !columns.contains(column)) {
    throw const BuilderFailure('Choose an existing column to filter.');
  }
  final operator = args['filterOperator'] ?? 'equals';
  final identifier = _quote(column);
  if (operator == 'isNull') return (' WHERE $identifier IS NULL', const []);
  if (operator == 'isNotNull') {
    return (' WHERE $identifier IS NOT NULL', const []);
  }
  if (!{'equals', 'contains'}.contains(operator)) {
    throw const BuilderFailure('Unknown column filter.');
  }
  final value = args['filterValue'];
  if (value is! String || utf8.encode(value).length > 4096) {
    throw const BuilderFailure('Filter values must be text up to 4 KiB.');
  }
  return operator == 'equals'
      ? (' WHERE $identifier = ?', [value])
      : (' WHERE instr(CAST($identifier AS TEXT), ?) > 0', [value]);
}

String _quote(String identifier) => '"${identifier.replaceAll('"', '""')}"';

bool _internal(String name) {
  final lower = name.toLowerCase();
  return lower.startsWith('_bottogram_') || lower.startsWith('sqlite_');
}

Map<String, dynamic> _bounded(Map<String, dynamic> value) {
  if (utf8.encode(jsonEncode(value)).length > _inspectionByteLimit) {
    throw const BuilderFailure('Database inspection exceeds 1 MiB.');
  }
  return value;
}
