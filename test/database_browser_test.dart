import 'package:bottogram/builder/database_browser_adapter.dart';
import 'package:bottogram/builder/database_browser_source.dart';
import 'package:bottogram/builder/values.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final id = 'a' * 64;
  test(
    'every inspection stays bound to the same bot and passes names as data',
    () async {
      final calls = <(String, String, Map<String, dynamic>)>[];
      final source = BotDatabaseBrowserSource(
        botId: id,
        inspect: (bot, operation, args) async {
          calls.add((bot, operation, args));
          return switch (operation) {
            'tables' => {
              'tables': [
                {'name': 'odd"table', 'internal': false},
              ],
            },
            'count' => {'count': 25},
            'schema' => {
              'columns': [
                {
                  'name': 'display name',
                  'type': 'TEXT',
                  'notNull': 1,
                  'primaryKey': 0,
                  'defaultValue': "''",
                },
              ],
              'indexes': [
                {
                  'name': 'idx',
                  'unique': true,
                  'columns': ['display name'],
                },
              ],
            },
            'rows' => {
              'columns': ['display name'],
              'rows': [
                {'display name': 'hello'},
              ],
              'hasMore': true,
            },
            _ => throw StateError('Unexpected operation'),
          };
        },
      );
      expect((await source.tables()).single.name, 'odd"table');
      expect(await source.count('odd"table'), 25);
      final schema = await source.schema('odd"table');
      expect(schema.columns.single.notNull, true);
      expect(schema.indexes.single.unique, true);
      final page = await source.rows(
        const DatabaseRowsRequest(
          table: 'odd"table',
          offset: 10,
          limit: 10,
          sortColumn: 'display name',
          descending: true,
          filterColumn: 'display name',
          filterOperator: DatabaseFilterOperator.contains,
          filterValue: "' OR 1=1 --",
        ),
      );
      expect(page.hasMore, true);
      expect(calls.every((call) => call.$1 == id), true);
      expect(calls.last.$3, {
        'table': 'odd"table',
        'offset': 10,
        'limit': 10,
        'sortColumn': 'display name',
        'descending': true,
        'filterColumn': 'display name',
        'filterOperator': 'contains',
        'filterValue': "' OR 1=1 --",
      });
    },
  );
  test(
    'raw exception text is hidden; controlled worker failures remain useful',
    () async {
      final source = BotDatabaseBrowserSource(
        botId: id,
        inspect:
            (_, __, ___) async => throw StateError('secret SQL bound value'),
      );
      await expectLater(
        source.tables(),
        throwsA(
          isA<DatabaseBrowseException>().having(
            (e) => e.message,
            'message',
            isNot(contains('secret')),
          ),
        ),
      );
      final guarded = BotDatabaseBrowserSource(
        botId: id,
        inspect:
            (_, __, ___) async =>
                throw const BuilderFailure(
                  'Table no longer exists. Refresh the table list.',
                ),
      );
      await expectLater(
        guarded.tables(),
        throwsA(
          isA<DatabaseBrowseException>().having(
            (e) => e.message,
            'message',
            contains('Table no longer exists'),
          ),
        ),
      );
    },
  );
  test(
    'invalid identities, requests and oversized pages are rejected',
    () async {
      expect(
        () => BotDatabaseBrowserSource(
          botId: '../other-bot',
          inspect: (_, __, ___) async => {},
        ),
        throwsA(isA<DatabaseBrowseException>()),
      );
      var calls = 0;
      final source = BotDatabaseBrowserSource(
        botId: id,
        inspect: (_, __, ___) async {
          calls++;
          return {
            'columns': ['id'],
            'rows': List.generate(11, (i) => {'id': i}),
            'hasMore': false,
          };
        },
      );
      await expectLater(
        source.rows(const DatabaseRowsRequest(table: 'items', limit: 500)),
        throwsA(isA<DatabaseBrowseException>()),
      );
      expect(calls, 0);
      await expectLater(
        source.rows(const DatabaseRowsRequest(table: 'items', limit: 10)),
        throwsA(isA<DatabaseBrowseException>()),
      );
    },
  );
  test('NULL, text, numeric and binary representations survive decoding', () {
    final page = DatabaseRowsPage.fromMap({
      'columns': ['nil', 'text', 'number', 'blob'],
      'rows': [
        {
          'nil': null,
          'text': '',
          'number': 12.5,
          'blob': {'base64': 'AQI='},
        },
      ],
      'hasMore': false,
    });
    expect(page.rows.single, {
      'nil': null,
      'text': '',
      'number': 12.5,
      'blob': {'base64': 'AQI='},
    });
  });
}
