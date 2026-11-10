import 'dart:io';

import 'package:bottogram/builder/database.dart';
import 'package:bottogram/builder/store.dart';
import 'package:bottogram/builder/values.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late BotDatabases databases;
  final bot = builderBotId('database-queue-regression');

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bottogram-sql-queue-');
    databases = BotDatabases(root: root.path);
    await databases.query(bot, 'CREATE TABLE entries(value INTEGER)', []);
  });

  tearDown(() async {
    await databases.close();
    await root.delete(recursive: true);
  });

  test(
    'queue waiting does not expire a write before the worker executes it',
    () async {
      // Nine independently bounded queries occupy the single worker for about
      // 18 seconds. Previously every reply timer started at submission, so the
      // last queries and this INSERT failed after 15 seconds despite executing.
      final failures = <Future<void>>[];
      for (var index = 0; index < 9; index++) {
        failures.add(
          expectLater(
            databases.query(
              bot,
              'WITH RECURSIVE endless(n) AS '
              '(VALUES(1) UNION ALL SELECT n+1 FROM endless) '
              'SELECT sum(n) AS total FROM endless',
              [],
            ),
            throwsA(
              isA<BuilderFailure>().having(
                (failure) => failure.message,
                'SQLite interruption rather than an RPC timeout',
                contains('SQLite 9'),
              ),
            ),
            reason: 'Queued runaway query $index must reach its own SQL limit.',
          ),
        );
      }

      final insertion = databases.query(bot, 'INSERT INTO entries VALUES(?)', [
        42,
      ]);
      await Future.wait<void>([
        ...failures,
        expectLater(insertion, completion(containsPair('affectedRows', 1))),
      ]);
      expect(
        (await databases.query(bot, 'SELECT value FROM entries', []))['rows'],
        [
          {'value': 42},
        ],
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  test('a failed queued request does not poison subsequent requests', () async {
    final failure = expectLater(
      databases.query(bot, 'INSERT INTO missing_table VALUES(1)', []),
      throwsA(isA<BuilderFailure>()),
    );
    final insertion = expectLater(
      databases.query(bot, 'INSERT INTO entries VALUES(?)', [7]),
      completion(containsPair('affectedRows', 1)),
    );

    await Future.wait<void>([failure, insertion]);
    expect(
      (await databases.query(bot, 'SELECT value FROM entries', []))['rows'],
      [
        {'value': 7},
      ],
    );
  });
}
