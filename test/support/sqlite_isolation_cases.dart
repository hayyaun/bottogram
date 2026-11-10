import 'dart:async';
import 'dart:io';

import 'package:bottogram/builder/database.dart';
import 'package:bottogram/builder/store.dart';
import 'package:bottogram/builder/values.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Runs against BotDatabases itself so native integration builds exercise the
/// packaged worker and library, rather than an unrelated system SQLite binary.
/// All writes, attempted escapes and cleanup remain inside a disposable root.
Future<Map<String, dynamic>> exerciseSqliteIsolation({
  required Directory root,
  void Function(String name)? onCasePassed,
}) async {
  var databases = BotDatabases(root: root.path);
  final first = builderBotId('native-isolation-bot-a');
  final second = builderBotId('native-isolation-bot-b');
  final completed = <String>[];
  void passed(String name) {
    completed.add(name);
    onCasePassed?.call(name);
  }

  Future<List<dynamic>> rows(
    String bot,
    String sql, [
    List<dynamic> parameters = const [],
  ]) async => (await databases.query(bot, sql, parameters))['rows'] as List;

  Future<void> rejected(
    String sql, {
    List<dynamic> parameters = const [],
  }) async {
    await expectLater(
      databases.query(first, sql, parameters),
      throwsA(isA<BuilderFailure>()),
      reason: sql,
    );
  }

  String literal(String value) => "'${value.replaceAll("'", "''")}'";
  final secondPath = p.join(root.path, '$second.sqlite');
  final escapePath = p.join(root.path, 'forbidden-output.sqlite');
  final textPath = p.join(root.path, 'outside-sentinel.txt');
  final sentinel = File(textPath);
  await sentinel.writeAsString('outside-sentinel-unchanged', flush: true);
  final clock = Stopwatch()..start();
  Map<String, dynamic>? diagnostics;
  var heartbeatCount = 0;
  var timeoutElapsedMs = 0;
  try {
    diagnostics = await databases.diagnostics(first);
    expect(diagnostics['version'], '3.54.1');
    expect(diagnostics['coreVersion'], 3054001);
    expect(
      diagnostics['sourceId'],
      '2026-10-16 14:45:20 555e07ef33f69a0957d24d8e555b702464a131d6f1607f4c3c1e4551e8e6ca76',
    );
    expect(diagnostics['authorizer'], isTrue);
    expect(diagnostics['progressHandler'], isTrue);
    expect(diagnostics['variableLimit'], 256);
    passed('packaged SQLite reports required native capabilities');

    for (final bot in [first, second]) {
      await databases.query(
        bot,
        'CREATE TABLE owned(id INTEGER PRIMARY KEY, value TEXT NOT NULL)',
        [],
      );
      await databases.query(
        bot,
        'CREATE INDEX owned_value_idx ON owned(value)',
        [],
      );
      await databases.query(bot, 'ALTER TABLE owned ADD COLUMN note TEXT', []);
    }
    final injectionText =
        "quote ' ; ATTACH DATABASE '$secondPath' AS other; --";
    final inserted = await databases.query(
      first,
      'INSERT INTO owned(id,value,note) VALUES(?,?,?) RETURNING id,value',
      [1, injectionText, 'bot-a-note'],
    );
    expect(inserted['rows'], [
      {'id': 1, 'value': injectionText},
    ]);
    expect(inserted['affectedRows'], 1);
    await databases.query(
      second,
      'INSERT INTO owned(id,value,note) VALUES(?,?,?)',
      [1, 'bot-b-secret', 'bot-b-note'],
    );
    expect(await rows(first, 'SELECT value FROM owned WHERE id=?', [1]), [
      {'value': injectionText},
    ]);
    expect(await rows(second, 'SELECT value FROM owned WHERE id=?', [1]), [
      {'value': 'bot-b-secret'},
    ]);
    await databases.query(first, 'UPDATE owned SET note=? WHERE id=?', [
      'updated-a-note',
      1,
    ]);
    await databases.query(first, 'INSERT INTO owned(id,value) VALUES(?,?)', [
      2,
      'temporary-a-value',
    ]);
    await databases.query(first, 'DELETE FROM owned WHERE id=?', [2]);
    expect(await rows(first, 'SELECT count(*) AS n FROM owned'), [
      {'n': 1},
    ]);
    passed('independent bot files support ordinary DDL and parameterized CRUD');

    await databases.write(first, 'user', '7', 'score', 12);
    await databases.write(first, 'user', '8', 'score', 24);
    await databases.write(first, 'bot', '', 'total', 36);
    await databases.write(second, 'user', '7', 'score', 48);
    await rejected(
      'CREATE TABLE poisoned_host_write('
      'value TEXT REFERENCES _bottogram_values(value) '
      'DEFERRABLE INITIALLY DEFERRED)',
    );
    expect(
      await rows(
        first,
        "SELECT count(*) AS n FROM sqlite_schema WHERE name='poisoned_host_write'",
      ),
      [
        {'n': 0},
      ],
    );
    await databases.write(first, 'user', '7', 'schema_probe', 1);
    await databases.removeVariable(first, 'user', 'schema_probe');
    expect(await databases.read(first, 'user', '7'), {'score': 12});
    expect(await databases.read(first, 'user', '8'), {'score': 24});
    expect(await databases.read(first, 'bot', ''), {'total': 36});
    expect(await databases.read(second, 'user', '7'), {'score': 48});
    await databases.close();
    databases = BotDatabases(root: root.path);
    expect(await databases.read(first, 'user', '7'), {'score': 12});
    expect(await rows(second, 'SELECT value FROM owned WHERE id=1'), [
      {'value': 'bot-b-secret'},
    ]);
    passed('host-managed values retain scope isolation and survive reopening');

    final secondBytes = await File(secondPath).readAsBytes();
    final attacks = <String>[
      'ATTACH DATABASE ${literal(secondPath)} AS neighbor',
      'ATTACH DATABASE ${literal(Uri.file(secondPath).toString())} AS neighbor',
      'VACUUM INTO ${literal(escapePath)}',
      'PRAGMA writable_schema=ON',
      'PRAGMA temp_store_directory=${literal(root.path)}',
      "SELECT load_extension('bottogram_nonexistent_test_extension')",
      'SELECT readfile(${literal(textPath)})',
      'SELECT writefile(${literal(textPath)}, ${literal('tampered')})',
      'CREATE VIRTUAL TABLE escape_module USING fts5(value)',
      'BEGIN',
      'SAVEPOINT guest_transaction',
    ];
    for (final attack in attacks) {
      await rejected(attack);
      expect(await File(secondPath).readAsBytes(), orderedEquals(secondBytes));
      expect(await sentinel.readAsString(), 'outside-sentinel-unchanged');
      expect(await File(escapePath).exists(), isFalse);
    }
    expect(await rows(second, 'SELECT value FROM owned WHERE id=1'), [
      {'value': 'bot-b-secret'},
    ]);
    passed('cross-bot ATTACH, external file access and unsafe operations fail');

    for (final sql in <String>[
      'SELECT * FROM _bottogram_values',
      'SELECT value FROM (SELECT value FROM _bottogram_values)',
      'WITH hidden AS (SELECT value FROM _bottogram_values) SELECT * FROM hidden',
      "UPDATE _bottogram_values SET value='999'",
      'DELETE FROM _bottogram_values',
      'DROP TABLE _bottogram_values',
      'ALTER TABLE _bottogram_values RENAME TO stolen',
      'CREATE TRIGGER direct_attack AFTER INSERT ON _bottogram_values '
          'BEGIN DELETE FROM _bottogram_values; END',
    ]) {
      await rejected(sql);
    }

    // SQLite may store a view or trigger definition before compiling its body.
    // Creation can therefore be rejected immediately or execution must fail.
    var viewCreated = false;
    try {
      await databases.query(
        first,
        'CREATE VIEW protected_leak AS SELECT value FROM _bottogram_values',
        [],
      );
      viewCreated = true;
    } on BuilderFailure {
      // Immediate denial is equally valid.
    }
    if (viewCreated) await rejected('SELECT * FROM protected_leak');

    var triggerCreated = false;
    try {
      await databases.query(
        first,
        'CREATE TRIGGER indirect_attack AFTER INSERT ON owned '
        "BEGIN UPDATE _bottogram_values SET value='999'; END",
        [],
      );
      triggerCreated = true;
    } on BuilderFailure {
      // Immediate denial is equally valid.
    }
    if (triggerCreated) {
      await rejected(
        'INSERT INTO owned(id,value) VALUES(?,?)',
        parameters: [3, 'must-roll-back'],
      );
      expect(await rows(first, 'SELECT count(*) AS n FROM owned WHERE id=3'), [
        {'n': 0},
      ]);
      await databases.query(first, 'DROP TRIGGER indirect_attack', []);
    }

    var foreignKeyCreated = false;
    try {
      await databases.query(
        first,
        'CREATE TABLE foreign_key_attack('
        'scope TEXT, owner TEXT, name TEXT, '
        'FOREIGN KEY(scope,owner,name) '
        'REFERENCES _bottogram_values(scope,owner,name) '
        'DEFERRABLE INITIALLY DEFERRED)',
        [],
      );
      foreignKeyCreated = true;
    } on BuilderFailure {
      // Immediate denial is equally valid.
    }
    if (foreignKeyCreated) {
      await rejected(
        'INSERT INTO foreign_key_attack VALUES(?,?,?)',
        parameters: ['user', '7', 'score'],
      );
      expect(
        await rows(first, 'SELECT count(*) AS n FROM foreign_key_attack'),
        [
          {'n': 0},
        ],
      );
    }
    expect(await databases.read(first, 'user', '7'), {'score': 12});
    expect(await databases.read(first, 'user', '8'), {'score': 24});
    expect(await databases.read(first, 'bot', ''), {'total': 36});
    passed(
      'reserved values resist direct, view, trigger and foreign-key access',
    );

    await databases.query(
      first,
      'CREATE TABLE rollback_probe(value INTEGER)',
      [],
    );
    await rejected(
      'INSERT INTO rollback_probe VALUES(1); '
      'INSERT INTO rollback_probe VALUES(2)',
    );
    await rejected(
      'WITH RECURSIVE sequence(n) AS '
      '(VALUES(1) UNION ALL SELECT n+1 FROM sequence WHERE n<501) '
      'INSERT INTO rollback_probe SELECT n FROM sequence RETURNING value',
    );
    expect(await rows(first, 'SELECT count(*) AS n FROM rollback_probe'), [
      {'n': 0},
    ]);
    await databases.query(first, 'INSERT INTO rollback_probe VALUES(?)', [42]);
    expect(await rows(first, 'SELECT value FROM rollback_probe'), [
      {'value': 42},
    ]);
    passed(
      'multi-statement and oversized writes fail atomically with recovery',
    );

    final heartbeat = Timer.periodic(
      const Duration(milliseconds: 20),
      (_) => heartbeatCount++,
    );
    final timeoutClock = Stopwatch()..start();
    try {
      await rejected(
        'WITH RECURSIVE endless(n) AS '
        '(VALUES(1) UNION ALL SELECT n+1 FROM endless) '
        'SELECT sum(n) AS total FROM endless',
      );
    } finally {
      timeoutClock.stop();
      heartbeat.cancel();
    }
    timeoutElapsedMs = timeoutClock.elapsedMilliseconds;
    expect(timeoutElapsedMs, greaterThan(500));
    expect(timeoutElapsedMs, lessThan(10000));
    expect(heartbeatCount, greaterThan(5));
    expect(await rows(first, 'SELECT value FROM rollback_probe'), [
      {'value': 42},
    ]);
    expect(await databases.read(first, 'user', '7'), {'score': 12});
    passed(
      'runaway SQL is interrupted while the UI isolate remains responsive',
    );

    await expectLater(
      databases.query('../other-bot', 'SELECT 1', []),
      throwsA(isA<BuilderFailure>()),
    );
    await databases.remove(first);
    expect(await File(p.join(root.path, '$first.sqlite')).exists(), isFalse);
    expect(await rows(second, 'SELECT value FROM owned WHERE id=1'), [
      {'value': 'bot-b-secret'},
    ]);
    expect(await databases.read(second, 'user', '7'), {'score': 48});
    passed('identity validation and deletion preserve neighboring bot data');

    return {
      'platform': Platform.operatingSystem,
      'diagnostics': diagnostics,
      'passedCases': completed,
      'timeoutElapsedMs': timeoutElapsedMs,
      'mainIsolateHeartbeats': heartbeatCount,
      'elapsedMs': clock.elapsedMilliseconds,
    };
  } finally {
    await databases.close();
  }
}
