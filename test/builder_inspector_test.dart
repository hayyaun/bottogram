import 'dart:io';

import 'package:bottogram/builder/database.dart';
import 'package:bottogram/builder/store.dart';
import 'package:bottogram/builder/values.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late BotDatabases databases;
  final first = builderBotId('inspector-first');
  final second = builderBotId('inspector-second');

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bottogram-inspector-');
    databases = BotDatabases(root: root.path);
  });
  tearDown(() async {
    await databases.close();
    await root.delete(recursive: true);
  });

  test(
    'quoted identifiers and generated columns survive schema and row inspection',
    () async {
      const table = 'odd"; table';
      const column = 'quoted" column';
      const index = 'odd" index';
      await databases.query(
        first,
        'CREATE TABLE ${_quote(table)} ('
        'id INTEGER PRIMARY KEY, ${_quote(column)} TEXT NOT NULL, '
        'base INTEGER DEFAULT 3, twice INTEGER GENERATED ALWAYS AS (base * 2) STORED)',
        [],
      );
      await databases.query(
        first,
        'CREATE UNIQUE INDEX ${_quote(index)} ON ${_quote(table)} (${_quote(column)}, base)',
        [],
      );
      await databases.query(
        first,
        'INSERT INTO ${_quote(table)} (id, ${_quote(column)}) VALUES (?, ?)',
        [1, 'a value'],
      );

      final tables =
          (await databases.inspect(first, 'tables', {}))['tables'] as List;
      expect(tables, contains(equals({'name': table, 'internal': false})));
      expect(
        tables,
        contains(equals({'name': '_bottogram_values', 'internal': true})),
      );
      final schema = await databases.inspect(first, 'schema', {'table': table});
      final columns = schema['columns'] as List;
      expect(columns.map((column) => column['name']), [
        'id',
        'quoted" column',
        'base',
        'twice',
      ]);
      expect(columns.first['primaryKey'], 1);
      expect(columns[1]['notNull'], true);
      expect(columns[2]['defaultValue'], '3');
      expect(
        schema['indexes'],
        contains(
          equals({
            'name': index,
            'unique': true,
            'columns': [column, 'base'],
          }),
        ),
      );
      final page = await databases.inspect(first, 'rows', {
        'table': table,
        'limit': 10,
      });
      expect(page['columns'], ['id', column, 'base', 'twice']);
      expect(page['rows'], [
        {'id': 1, column: 'a value', 'base': 3, 'twice': 6},
      ]);
      expect(page['hasMore'], false);
    },
  );

  test(
    'filters bind SQL-looking values, preserve literal wildcards and handle nulls',
    () async {
      await databases.query(
        first,
        'CREATE TABLE samples(id INTEGER PRIMARY KEY, value TEXT)',
        [],
      );
      for (final row in [
        [1, "' OR 1=1 --"],
        [2, '100%_done'],
        [3, '100xxdone'],
        [4, null],
      ]) {
        await databases.query(first, 'INSERT INTO samples VALUES (?, ?)', row);
      }
      Future<Map<String, dynamic>> filter(String operator, [String? value]) =>
          databases.inspect(first, 'rows', {
            'table': 'samples',
            'limit': 10,
            'filterColumn': 'value',
            'filterOperator': operator,
            if (value != null) 'filterValue': value,
          });
      expect((await filter('equals', "' OR 1=1 --"))['rows'], [
        {'id': 1, 'value': "' OR 1=1 --"},
      ]);
      expect((await filter('contains', '%_'))['rows'], [
        {'id': 2, 'value': '100%_done'},
      ]);
      expect((await filter('isNull'))['rows'], [
        {'id': 4, 'value': null},
      ]);
      expect(((await filter('isNotNull'))['rows'] as List).length, 3);
      expect(
        await databases.inspect(first, 'count', {
          'table': 'samples',
          'filterColumn': 'value',
          'filterOperator': 'contains',
          'filterValue': '%_',
        }),
        {'count': 1},
      );
    },
  );

  test(
    'pagination uses primary-key order, descending sort and accurate hasMore',
    () async {
      await databases.query(
        first,
        'CREATE TABLE items(id INTEGER PRIMARY KEY, label TEXT)',
        [],
      );
      await databases.query(
        first,
        'WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<23) '
        "INSERT INTO items SELECT x, 'item' FROM n",
        [],
      );
      final one = await databases.inspect(first, 'rows', {
        'table': 'items',
        'limit': 10,
      });
      final two = await databases.inspect(first, 'rows', {
        'table': 'items',
        'limit': 10,
        'offset': 10,
      });
      final three = await databases.inspect(first, 'rows', {
        'table': 'items',
        'limit': 10,
        'offset': 20,
      });
      expect(
        (one['rows'] as List).map((row) => row['id']),
        List.generate(10, (index) => index + 1),
      );
      expect(
        (two['rows'] as List).map((row) => row['id']),
        List.generate(10, (index) => index + 11),
      );
      expect((three['rows'] as List).map((row) => row['id']), [21, 22, 23]);
      expect(one['hasMore'], true);
      expect(two['hasMore'], true);
      expect(three['hasMore'], false);
      final reversed = await databases.inspect(first, 'rows', {
        'table': 'items',
        'limit': 10,
        'sortColumn': 'id',
        'descending': true,
      });
      expect((reversed['rows'] as List).first['id'], 23);
      expect(await databases.inspect(first, 'count', {'table': 'items'}), {
        'count': 23,
      });
    },
  );

  test('reserved data and BLOB previews stay inside the selected bot', () async {
    await databases.write(first, 'user', '1', 'score', 12);
    await databases.write(second, 'user', '1', 'score', 99);
    final firstValues = await databases.inspect(first, 'rows', {
      'table': '_bottogram_values',
      'limit': 10,
    });
    final secondValues = await databases.inspect(second, 'rows', {
      'table': '_bottogram_values',
      'limit': 10,
    });
    expect((firstValues['rows'] as List).single['value'], '12');
    expect((secondValues['rows'] as List).single['value'], '99');
    await databases.query(
      first,
      'CREATE TABLE binary_values(id INTEGER PRIMARY KEY, data BLOB, note TEXT)',
      [],
    );
    await databases.query(
      first,
      "INSERT INTO binary_values VALUES(1, X'0001FF', NULL)",
      [],
    );
    final page = await databases.inspect(first, 'rows', {
      'table': 'binary_values',
      'limit': 10,
    });
    expect(page['rows'], [
      {
        'id': 1,
        'data': {'base64': 'AAH/'},
        'note': null,
      },
    ]);
    await expectLater(
      databases.inspect(second, 'rows', {
        'table': 'binary_values',
        'limit': 10,
      }),
      throwsA(isA<BuilderFailure>()),
    );
  });

  test(
    'unknown identifiers and unsafe operation shapes cannot change the database',
    () async {
      await databases.query(
        first,
        'CREATE TABLE safe(id INTEGER PRIMARY KEY)',
        [],
      );
      for (final args in <Map<String, dynamic>>[
        {'table': 'safe; DROP TABLE safe; --', 'limit': 10},
        {
          'table': 'safe',
          'sortColumn': 'id DESC; DROP TABLE safe',
          'limit': 10,
        },
        {
          'table': 'safe',
          'filterColumn': 'missing',
          'filterValue': '1',
          'limit': 10,
        },
        {
          'table': 'safe',
          'filterColumn': 'id',
          'filterOperator': 'unknown',
          'filterValue': '1',
          'limit': 10,
        },
        {'table': 'safe', 'limit': 11},
        {'table': 'safe', 'limit': 10, 'offset': -1},
        {'table': 'safe', 'limit': 10, 'descending': 'true'},
      ]) {
        await expectLater(
          databases.inspect(first, 'rows', args),
          throwsA(isA<BuilderFailure>()),
        );
      }
      await expectLater(
        databases.inspect('../escape', 'tables', {}),
        throwsA(isA<BuilderFailure>()),
      );
      await expectLater(
        databases.inspect(first, 'execute', {'sql': 'DROP TABLE safe'}),
        throwsA(isA<BuilderFailure>()),
      );
      expect(await databases.inspect(first, 'count', {'table': 'safe'}), {
        'count': 0,
      });
    },
  );

  test(
    'result-size rejection leaves data intact and a narrower filter works',
    () async {
      await databases.query(
        first,
        'CREATE TABLE large_rows(id INTEGER PRIMARY KEY, body BLOB)',
        [],
      );
      await databases.query(
        first,
        'WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<10) '
        'INSERT INTO large_rows SELECT x, zeroblob(92160) FROM n',
        [],
      );
      await expectLater(
        databases.inspect(first, 'rows', {'table': 'large_rows', 'limit': 10}),
        throwsA(isA<BuilderFailure>()),
      );
      expect(await databases.inspect(first, 'count', {'table': 'large_rows'}), {
        'count': 10,
      });
      final page = await databases.inspect(first, 'rows', {
        'table': 'large_rows',
        'limit': 10,
        'filterColumn': 'id',
        'filterOperator': 'equals',
        'filterValue': '1',
      });
      expect((page['rows'] as List).length, 1);
      expect(page['hasMore'], false);
    },
  );
}

String _quote(String identifier) => '"${identifier.replaceAll('"', '""')}"';
