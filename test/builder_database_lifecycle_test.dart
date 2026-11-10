import 'dart:io';

import 'package:bottogram/builder/database.dart';
import 'package:bottogram/builder/store.dart';
import 'package:bottogram/builder/values.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late BotDatabases databases;
  final bot = builderBotId('database-lifecycle-fixture');

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bottogram-db-lifecycle-');
    databases = BotDatabases(root: root.path);
  });
  tearDown(() async {
    await databases.close();
    await root.delete(recursive: true);
  });

  test(
    'immediate close waits for startup and a submitted write before reuse',
    () async {
      var writeFinished = false;
      final write = databases.write(bot, 'user', '1', 'score', 17).then((_) {
        writeFinished = true;
      });
      // No preliminary await: shutdown must include worker initialization.
      final close = databases.close();
      await close;
      expect(writeFinished, true);
      await write;

      // The same manager starts a fresh session and reads the durable write.
      expect(await databases.read(bot, 'user', '1'), {'score': 17});
    },
  );

  test(
    'concurrent close calls complete and requests during close reopen safely',
    () async {
      await databases.query(bot, 'CREATE TABLE saved(value INTEGER)', []);
      await databases.query(bot, 'INSERT INTO saved VALUES (?)', [42]);
      final first = databases.close();
      final second = databases.close();
      final afterClose = databases.query(bot, 'SELECT value FROM saved', []);
      await Future.wait([first, second]);
      expect((await afterClose)['rows'], [
        {'value': 42},
      ]);

      // Repeated idle close remains harmless and the manager stays reusable.
      await Future.wait([databases.close(), databases.close()]);
      expect(
        (await databases.query(bot, 'SELECT value FROM saved', []))['rows'],
        [
          {'value': 42},
        ],
      );
    },
  );

  test(
    'close drains a slow failing query and queued work before shutting down',
    () async {
      await databases.query(bot, 'CREATE TABLE retained(value INTEGER)', []);
      var slowFinished = false;
      final slow = databases
          .query(
            bot,
            'WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n) '
            'SELECT sum(x) FROM n',
            [],
          )
          .then<void>(
            (_) => fail('The unbounded query must hit its execution budget.'),
            onError: (Object error) {
              expect(error, isA<BuilderFailure>());
              slowFinished = true;
            },
          );
      var writeFinished = false;
      final write = databases
          .query(bot, 'INSERT INTO retained VALUES (?)', [7])
          .then((_) {
            writeFinished = true;
          });
      final close = databases.close();
      // This request belongs to the next session and must not deadlock drain.
      final reopened = databases.query(bot, 'SELECT value FROM retained', []);
      await close;
      expect(slowFinished, true);
      expect(writeFinished, true);
      await Future.wait([slow, write]);
      expect((await reopened)['rows'], [
        {'value': 7},
      ]);
    },
  );
}
