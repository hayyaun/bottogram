import 'dart:io';

import 'package:bottogram/builder/database.dart';
import 'package:bottogram/builder/store.dart';
import 'package:bottogram/builder/values.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late BotDatabases databases;
  final bot = builderBotId('schema-guard');

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bottogram-schema-guard-');
    databases = BotDatabases(root: root.path);
    await databases.write(bot, 'user', '1', 'score', 7);
    await databases.write(bot, 'user', '1', 'protected', 888);
  });
  tearDown(() async {
    await databases.close();
    await root.delete(recursive: true);
  });

  Future<void> expectHostValuesHealthy() async {
    await databases.write(bot, 'user', '1', 'score', 8);
    expect(await databases.read(bot, 'user', '1'), {
      'score': 8,
      'protected': 888,
    });
    await databases.removeVariable(bot, 'user', 'score');
    expect(await databases.read(bot, 'user', '1'), {'protected': 888});
  }

  Future<List<String>> tables() async => [
    for (final table
        in (await databases.inspect(bot, 'tables', {}))['tables'] as List)
      table['name'] as String,
  ];

  test(
    'an empty malformed foreign key cannot poison host variable DML',
    () async {
      await expectLater(
        databases.query(
          bot,
          'CREATE TABLE poisoned(x TEXT REFERENCES _bottogram_values(value))',
          [],
        ),
        throwsA(isA<BuilderFailure>()),
      );
      expect(await tables(), isNot(contains('poisoned')));
      await expectHostValuesHealthy();
    },
  );

  test('deferred foreign keys to reserved tables are rolled back', () async {
    await expectLater(
      databases.query(
        bot,
        'CREATE TABLE deferred_child(scope TEXT,owner TEXT,name TEXT, '
        'FOREIGN KEY(scope,owner,name) REFERENCES _Bottogram_Values(scope,owner,name) '
        'ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED)',
        [],
      ),
      throwsA(isA<BuilderFailure>()),
    );
    expect(await tables(), isNot(contains('deferred_child')));
    await expectHostValuesHealthy();
  });

  test(
    'ALTER ADD REFERENCES rolls back only the rejected schema change',
    () async {
      await databases.query(
        bot,
        'CREATE TABLE notes(id INTEGER PRIMARY KEY)',
        [],
      );
      await databases.query(bot, 'INSERT INTO notes VALUES(1)', []);
      await expectLater(
        databases.query(
          bot,
          'ALTER TABLE notes ADD COLUMN ref TEXT REFERENCES _bottogram_values(value)',
          [],
        ),
        throwsA(isA<BuilderFailure>()),
      );
      final columns =
          (await databases.inspect(bot, 'schema', {
                'table': 'notes',
              }))['columns']
              as List;
      expect(columns.map((column) => column['name']), ['id']);
      await databases.query(bot, 'INSERT INTO notes VALUES(2)', []);
      expect(
        (await databases.query(
          bot,
          'SELECT id FROM notes ORDER BY id',
          [],
        ))['rows'],
        [
          {'id': 1},
          {'id': 2},
        ],
      );
      await expectHostValuesHealthy();
    },
  );

  test(
    'quoted user tables and ordinary cascading foreign keys remain usable',
    () async {
      const parent = 'parent"; reserved-looking text';
      const child = 'child" table';
      const key = 'key" column';
      await databases.query(
        bot,
        'CREATE TABLE ${_quote(parent)}(${_quote(key)} INTEGER PRIMARY KEY)',
        [],
      );
      await databases.query(
        bot,
        'CREATE TABLE ${_quote(child)}(id INTEGER PRIMARY KEY, parent_id INTEGER, '
        'FOREIGN KEY(parent_id) REFERENCES ${_quote(parent)}(${_quote(key)}) '
        'ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED)',
        [],
      );
      await databases.query(bot, 'INSERT INTO ${_quote(parent)} VALUES(?)', [
        1,
      ]);
      await databases.query(bot, 'INSERT INTO ${_quote(child)} VALUES(?,?)', [
        2,
        1,
      ]);
      expect(
        (await databases.query(
          bot,
          'SELECT id FROM ${_quote(child)}',
          [],
        ))['rows'],
        [
          {'id': 2},
        ],
      );
      await databases.query(bot, 'DELETE FROM ${_quote(parent)}', []);
      expect(
        (await databases.query(
          bot,
          'SELECT id FROM ${_quote(child)}',
          [],
        ))['rows'],
        isEmpty,
      );
      await expectHostValuesHealthy();
    },
  );

  test(
    'renaming a user table into the reserved namespace rolls back',
    () async {
      await databases.query(bot, 'CREATE TABLE ordinary(id INTEGER)', []);
      await databases.query(bot, 'INSERT INTO ordinary VALUES(12)', []);
      for (final reserved in ['_bottogram_shadow', '_BoTtOgRaM_shadow']) {
        await expectLater(
          databases.query(
            bot,
            'ALTER TABLE ordinary RENAME TO ${_quote(reserved)}',
            [],
          ),
          throwsA(isA<BuilderFailure>()),
        );
        expect(await tables(), contains('ordinary'));
        expect(await tables(), isNot(contains(reserved)));
      }
      expect(
        (await databases.query(bot, 'SELECT id FROM ordinary', []))['rows'],
        [
          {'id': 12},
        ],
      );
      await expectHostValuesHealthy();
    },
  );
}

String _quote(String identifier) => '"${identifier.replaceAll('"', '""')}"';
