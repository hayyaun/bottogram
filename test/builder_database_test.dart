import 'dart:io';
import 'package:bottogram/builder/database.dart';
import 'package:bottogram/builder/store.dart';
import 'package:bottogram/builder/values.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late BotDatabases databases;
  final first = builderBotId('first'), second = builderBotId('second');
  setUp(() async {
    root = await Directory.systemTemp.createTemp('bottogram-sql-');
    databases = BotDatabases(root: root.path);
  });
  tearDown(() async {
    await databases.close();
    await root.delete(recursive: true);
  });
  test(
    'each bot has independent persistent tables and bound scalar values',
    () async {
      await databases.query(
        first,
        'CREATE TABLE scores(user_id INTEGER PRIMARY KEY, score INTEGER NOT NULL)',
        [],
      );
      await databases.query(first, 'INSERT INTO scores VALUES(?,?)', [12, 20]);
      expect(
        (await databases.query(
          first,
          'SELECT score FROM scores WHERE user_id=?',
          [12],
        ))['rows'],
        [
          {'score': 20},
        ],
      );
      await expectLater(
        databases.query(second, 'SELECT * FROM scores', []),
        throwsA(isA<BuilderFailure>()),
      );
      await databases.close();
      databases = BotDatabases(root: root.path);
      expect(
        (await databases.query(
          first,
          'SELECT count(*) AS n FROM scores',
          [],
        ))['rows'],
        [
          {'n': 1},
        ],
      );
    },
  );
  test(
    'ATTACH, file output, extensions and reserved table operations are denied',
    () async {
      for (final sql in [
        "ATTACH DATABASE '${root.path}/foreign.sqlite' AS foreign_db",
        "VACUUM INTO '${root.path}/escape.sqlite'",
        'PRAGMA writable_schema=ON',
        "SELECT load_extension('untrusted')",
        "SELECT readfile('/etc/passwd')",
        'DROP TABLE _bottogram_values',
        'SELECT * FROM _bottogram_values',
        'ALTER TABLE _bottogram_values RENAME TO stolen',
        'CREATE TRIGGER sabotage AFTER INSERT ON _bottogram_values BEGIN DELETE FROM _bottogram_values; END',
        'CREATE VIRTUAL TABLE files USING fts5(content)',
      ]) {
        await expectLater(
          databases.query(first, sql, []),
          throwsA(isA<BuilderFailure>()),
          reason: sql,
        );
      }
      expect(File('${root.path}/escape.sqlite').existsSync(), false);
      expect(File('${root.path}/foreign.sqlite').existsSync(), false);
      await databases.write(first, 'user', '1', 'score', 42);
      expect(await databases.read(first, 'user', '1'), {'score': 42});
    },
  );
  test(
    'multiple statements and excessive results roll back the statement',
    () async {
      await databases.query(first, 'CREATE TABLE items(id INTEGER)', []);
      await expectLater(
        databases.query(
          first,
          'INSERT INTO items VALUES(1); INSERT INTO items VALUES(2)',
          [],
        ),
        throwsA(isA<BuilderFailure>()),
      );
      expect(
        (await databases.query(
          first,
          'SELECT count(*) AS n FROM items',
          [],
        ))['rows'],
        [
          {'n': 0},
        ],
      );
      await expectLater(
        databases.query(
          first,
          'WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<501) SELECT x FROM n',
          [],
        ),
        throwsA(isA<BuilderFailure>()),
      );
    },
  );
  test(
    'scope values persist independently and deletion affects one bot',
    () async {
      await databases.write(first, 'user', '1', 'score', 12);
      await databases.write(first, 'user', '2', 'score', 24);
      await databases.write(second, 'user', '1', 'score', 48);
      expect(await databases.read(first, 'user', '1'), {'score': 12});
      expect(await databases.read(first, 'user', '2'), {'score': 24});
      await databases.remove(first);
      expect(await databases.read(first, 'user', '1'), isEmpty);
      expect(await databases.read(second, 'user', '1'), {'score': 48});
    },
  );
}
