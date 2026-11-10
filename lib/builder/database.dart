import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'sqlite_native.dart';
import 'database_inspector.dart';
import 'values.dart';

typedef _Authorize = SqliteAuthorizerCallback;
typedef _Progress = SqliteProgressCallback;

/// SQLite's documented authorizer, progress handler and limits are bound through
/// dart:ffi and Database.handle. No package-internal API or SQL text filtering.
class _SqlGuards {
  _SqlGuards(this.db) {
    _authorizer = setSqliteAuthorizer;
    _progress = (database, instructions, callback, context) {
      if (setSqliteProgressHandler(database, instructions, callback, context) !=
          0) {
        throw StateError('SQLite progress handler unavailable.');
      }
    };
    final limit = setSqliteLimit;
    for (final entry in {
      0: 1048576,
      1: 65536,
      2: 128,
      3: 100,
      4: 25,
      5: 1000000,
      6: 32,
      7: 0,
      8: 1024,
      9: 256,
      10: 16,
      11: 0,
    }.entries) {
      limit(db.handle.cast<Void>(), entry.key, entry.value);
    }
    _authCallback = NativeCallable<_Authorize>.isolateLocal(
      _authorize,
      exceptionalReturn: 1,
    );
    _progressCallback = NativeCallable<_Progress>.isolateLocal(
      (Pointer<Void> _) => _clock.elapsedMicroseconds > 2000000 ? 1 : 0,
      exceptionalReturn: 1,
    );
    if (_authorizer(
          db.handle.cast<Void>(),
          _authCallback.nativeFunction,
          nullptr,
        ) !=
        0) {
      throw StateError('SQLite authorizer unavailable.');
    }
  }
  final Database db;
  late final int Function(
    Pointer<Void>,
    Pointer<NativeFunction<_Authorize>>,
    Pointer<Void>,
  )
  _authorizer;
  late final void Function(
    Pointer<Void>,
    int,
    Pointer<NativeFunction<_Progress>>,
    Pointer<Void>,
  )
  _progress;
  late final NativeCallable<_Authorize> _authCallback;
  late final NativeCallable<_Progress> _progressCallback;
  bool guest = false;
  final Stopwatch _clock = Stopwatch();
  bool inspection = false;
  static const _functions = {
    'abs',
    'avg',
    'changes',
    'char',
    'coalesce',
    'concat',
    'concat_ws',
    'count',
    'date',
    'datetime',
    'format',
    'glob',
    'hex',
    'ifnull',
    'iif',
    'instr',
    'json',
    'json_array',
    'json_array_length',
    'json_extract',
    'json_insert',
    'json_object',
    'json_patch',
    'json_quote',
    'json_remove',
    'json_replace',
    'json_set',
    'json_type',
    'json_valid',
    'julianday',
    'last_insert_rowid',
    'length',
    'like',
    'likelihood',
    'likely',
    'lower',
    'ltrim',
    'max',
    'min',
    'nullif',
    'printf',
    'quote',
    'random',
    'randomblob',
    'replace',
    'round',
    'rtrim',
    'sign',
    'sqlite_version',
    'strftime',
    'substr',
    'substring',
    'sum',
    'time',
    'timediff',
    'total',
    'trim',
    'typeof',
    'unicode',
    'unixepoch',
    'unlikely',
    'upper',
    'zeroblob',
    'row_number',
    'rank',
    'dense_rank',
    'lag',
    'lead',
    'first_value',
    'last_value',
    'nth_value',
    'ntile',
    'percent_rank',
    'cume_dist',
    'group_concat',
    'string_agg',
  };
  int _authorize(
    Pointer<Void> _,
    int action,
    Pointer<Utf8> one,
    Pointer<Utf8> two,
    Pointer<Utf8> database,
    Pointer<Utf8> source,
  ) {
    if (!guest) return 0;
    String text(Pointer<Utf8> v) =>
        v == nullptr ? '' : v.toDartString().toLowerCase();
    final a = text(one), b = text(two), namespace = text(database);
    if (namespace.isNotEmpty && namespace != 'main') return 1;
    if (inspection) {
      if (action == 19) {
        return {'table_xinfo', 'index_list', 'index_info'}.contains(a) ? 0 : 1;
      }
      if (action == 31) return _functions.contains(b) ? 0 : 1;
      return {20, 21, 33}.contains(action) ? 0 : 1;
    }
    if (a.startsWith('_bottogram_') || b.startsWith('_bottogram_')) return 1;
    if (action == 31) return _functions.contains(b) ? 0 : 1;
    // ATTACH, DETACH, PRAGMA, transaction control, virtual/temp tables and
    // unknown future actions are denied. Ordinary user tables remain editable.
    return {
          1,
          2,
          7,
          8,
          9,
          10,
          11,
          16,
          17,
          18,
          20,
          21,
          23,
          26,
          27,
          28,
          33,
        }.contains(action)
        ? 0
        : 1;
  }

  void beginGuest() {
    _clock
      ..reset()
      ..start();
    guest = true;
    _progress(
      db.handle.cast<Void>(),
      1000,
      _progressCallback.nativeFunction,
      nullptr,
    );
  }

  void checkDeadline() {
    if (_clock.elapsedMicroseconds > 2000000) {
      throw const BuilderFailure('SQL exceeded its 2-second execution limit.');
    }
  }

  void endGuest() {
    guest = false;
    inspection = false;
    _clock.stop();
    _progress(db.handle.cast<Void>(), 0, nullptr, nullptr);
  }

  void close() {
    _authorizer(db.handle.cast<Void>(), nullptr, nullptr);
    _progress(db.handle.cast<Void>(), 0, nullptr, nullptr);
    _authCallback.close();
    _progressCallback.close();
  }
}

class _BotDatabase {
  _BotDatabase(String path) {
    if (FileSystemEntity.typeSync(path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const BuilderFailure(
        'The bot database path must not be a symbolic link.',
      );
    }
    db = sqlite3.open(path);
    try {
      if (probeSqliteSecurity(db.handle.cast<Void>()) != 7 ||
          sqliteSecurityCoreVersion() != sqlite3.version.versionNumber) {
        throw const BuilderFailure(
          'The packaged SQLite security checks failed.',
        );
      }
      db.execute('PRAGMA trusted_schema=OFF');
      db.execute('PRAGMA foreign_keys=ON');
      db.execute('PRAGMA busy_timeout=2000');
      db.execute('PRAGMA max_page_count=262144');
      db.execute(
        'CREATE TABLE IF NOT EXISTS _bottogram_values(scope TEXT NOT NULL, owner TEXT NOT NULL, name TEXT NOT NULL, value TEXT NOT NULL, PRIMARY KEY(scope,owner,name)) WITHOUT ROWID',
      );
    } catch (_) {
      db.close();
      rethrow;
    }
  }
  late final Database db;
  _SqlGuards? _guards;
  _SqlGuards get guards {
    try {
      return _guards ??= _SqlGuards(db);
    } catch (_) {
      throw const BuilderFailure(
        'This SQLite build lacks the security hooks required for user SQL.',
      );
    }
  }

  List<Map<String, dynamic>> read(String scope, String owner) => db
      .select(
        'SELECT name,value FROM _bottogram_values WHERE scope=? AND owner=?',
        [scope, owner],
      )
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
  void write(String scope, String owner, String name, String? value) {
    if (value == null) {
      db.execute(
        'DELETE FROM _bottogram_values WHERE scope=? AND owner=? AND name=?',
        [scope, owner, name],
      );
    } else {
      db.execute(
        'INSERT INTO _bottogram_values VALUES(?,?,?,?) ON CONFLICT(scope,owner,name) DO UPDATE SET value=excluded.value',
        [scope, owner, name, value],
      );
    }
  }

  Map<String, dynamic> query(String sql, List<dynamic> parameters) {
    // Fail before preparing any user SQL if the native build lacks a guard.
    final guard = guards;
    if (utf8.encode(sql).length > 65536 || parameters.length > 256) {
      throw const BuilderFailure(
        'SQL is limited to 64 KiB and 256 parameters.',
      );
    }
    final before = db.select('SELECT total_changes() AS n').single['n'] as int;
    db.execute('BEGIN');
    PreparedStatement? statement;
    try {
      final schemaVersion =
          db.select('PRAGMA main.schema_version').single['schema_version']
              as int;
      guard.beginGuest();
      statement = db.prepare(sql, checkNoTail: true, vtab: false);
      final cursor = statement.selectCursor(
        parameters.map<Object?>((v) {
          if (v == null || v is String || v is num) return v;
          if (v is bool) return v ? 1 : 0;
          throw const BuilderFailure('SQL parameters must be scalar values.');
        }).toList(),
      );
      final rows = <Map<String, dynamic>>[];
      var bytes = 0;
      while (cursor.moveNext()) {
        if (rows.length >= 500) {
          throw const BuilderFailure(
            'SQL results exceed 500 rows. Add LIMIT or use pagination.',
          );
        }
        final row = <String, dynamic>{};
        for (final column in cursor.columnNames) {
          final value = cursor.current[column];
          row[column] = value is Uint8List
              ? {'base64': base64Encode(value)}
              : value;
        }
        bytes += utf8.encode(jsonEncode(row)).length;
        if (bytes > 1048576) {
          throw const BuilderFailure(
            'SQL results exceed 1 MiB. Select fewer columns or rows.',
          );
        }
        rows.add(row);
      }
      final columns = List<String>.of(cursor.columnNames);
      statement.close();
      statement = null;
      // Metadata is read through fixed trusted statements, while the guest's
      // progress handler and wall-clock deadline remain active. Validate DDL
      // before commit so foreign keys cannot poison later host variable writes.
      guard.guest = false;
      guard.checkDeadline();
      final changedSchemaVersion =
          db.select('PRAGMA main.schema_version').single['schema_version']
              as int;
      if (changedSchemaVersion != schemaVersion) {
        _validateGuestSchema(guard);
      }
      guard.checkDeadline();
      guard.endGuest();
      final output = {
        'rows': rows,
        'columns': columns,
        'affectedRows':
            (db.select('SELECT total_changes() AS n').single['n'] as int) -
            before,
        'lastInsertRowId': db.lastInsertRowId,
      };
      db.execute('COMMIT');
      return output;
    } catch (error) {
      statement?.close();
      guard.endGuest();
      db.execute('ROLLBACK');
      if (error is BuilderFailure) rethrow;
      // SQLite exception strings include SQL and bound values. Never log them.
      if (error is SqliteException) {
        throw BuilderFailure(
          'SQL failed (SQLite ${error.resultCode}). Check syntax, parameters, permissions and the 2-second execution limit.',
        );
      }
      throw const BuilderFailure('SQL execution failed.');
    }
  }

  void _validateGuestSchema(_SqlGuards guard) {
    final statement = db.prepare(
      'SELECT type,name FROM main.sqlite_schema',
      checkNoTail: true,
    );
    try {
      final cursor = statement.selectCursor();
      while (cursor.moveNext()) {
        guard.checkDeadline();
        final name = cursor.current['name'] as String;
        final type = cursor.current['type'] as String;
        if (name.toLowerCase().startsWith('_bottogram_') &&
            !(name == '_bottogram_values' && type == 'table')) {
          throw const BuilderFailure(
            'User SQL cannot create reserved database objects.',
          );
        }
        if (type != 'table') continue;
        // Names come only from SQLite metadata and are quoted as identifiers.
        final quoted = '"${name.replaceAll('"', '""')}"';
        final foreignKeys = db.select('PRAGMA main.foreign_key_list($quoted)');
        guard.checkDeadline();
        for (final foreignKey in foreignKeys) {
          if ((foreignKey['table'] as String).toLowerCase().startsWith(
            '_bottogram_',
          )) {
            throw const BuilderFailure(
              'User tables cannot reference reserved database tables.',
            );
          }
        }
      }
    } finally {
      statement.close();
    }
  }

  Map<String, dynamic> diagnostics() {
    final guard = guards;
    final row = db
        .select(
          'SELECT sqlite_version() AS version, sqlite_source_id() AS sourceId',
        )
        .single;
    return {
      'version': row['version'],
      'sourceId': row['sourceId'],
      'authorizer': true,
      'progressHandler': true,
      'variableLimit': setSqliteLimit(db.handle.cast<Void>(), 9, -1),
      'coreVersion': sqliteSecurityCoreVersion(),
      'guardInstalled': identical(guard, _guards),
    };
  }

  Map<String, dynamic> inspect(String operation, Map<String, dynamic> args) {
    final guard = guards;
    try {
      guard.beginGuest();
      guard.inspection = true;
      return inspectBotDatabase(db, operation, args);
    } catch (error) {
      if (error is BuilderFailure) rethrow;
      throw const BuilderFailure(
        'Database inspection failed or exceeded its execution limit.',
      );
    } finally {
      guard.endGuest();
    }
  }

  void close() {
    _guards?.close();
    db.close();
  }
}

/// A single worker keeps SQL off the UI isolate. Up to four connections remain
/// open, with independent files selected exclusively by a validated bot hash.
class BotDatabases {
  BotDatabases({this.root});
  final String? root;
  Isolate? _isolate;
  SendPort? _port;
  Future<void>? _opening;
  Future<void> _requestTail = Future<void>.value();
  Future<void>? _closing;
  int _pendingRequests = 0;
  Completer<void>? _drained;
  Future<void> _open() async {
    final directory = Directory(
      root ?? p.join((await getApplicationSupportDirectory()).path, 'bot_data'),
    );
    await directory.create(recursive: true);
    final inbox = ReceivePort();
    try {
      _isolate = await Isolate.spawn(_databaseWorker, (
        inbox.sendPort,
        await directory.resolveSymbolicLinks(),
      ));
      final response = await inbox.first.timeout(const Duration(seconds: 15));
      if (response is! SendPort) {
        throw const BuilderFailure('SQLite could not be initialized.');
      }
      _port = response;
    } catch (_) {
      _isolate?.kill();
      _isolate = null;
      _port = null;
      _opening = null;
      rethrow;
    } finally {
      inbox.close();
    }
  }

  Future<dynamic> _request(
    String bot,
    String operation, [
    Map<String, dynamic> args = const {},
  ]) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(bot)) {
      throw const BuilderFailure('Invalid bot database identity.');
    }
    // Requests submitted during shutdown belong to the next worker session.
    // Do not count them until shutdown completes, or close would wait on work
    // that is itself waiting for close.
    while (_closing != null) {
      final closing = _closing!;
      try {
        await closing;
      } catch (_) {
        // The close caller observes shutdown failures. Its finally cleanup
        // permits a later request to start a fresh worker.
      }
    }
    _pendingRequests++;
    try {
      return await _performRequest(bot, operation, args);
    } finally {
      _pendingRequests--;
      if (_pendingRequests == 0) {
        final drained = _drained;
        _drained = null;
        drained?.complete();
      }
    }
  }

  Future<dynamic> _performRequest(
    String bot,
    String operation,
    Map<String, dynamic> args,
  ) {
    // The worker executes synchronously. Queue here so the reply deadline
    // measures this request's execution, not time behind other bot requests.
    final result = _requestTail.then((_) => _sendRequest(bot, operation, args));
    _requestTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Future<dynamic> _sendRequest(
    String bot,
    String operation,
    Map<String, dynamic> args,
  ) async {
    try {
      await (_opening ??= _open());
    } catch (_) {
      _opening = null;
      rethrow;
    }
    final reply = ReceivePort();
    try {
      _port!.send((reply.sendPort, bot, operation, args));
      final result =
          await reply.first.timeout(const Duration(seconds: 15)) as Map;
      if (result['error'] != null) {
        throw BuilderFailure(result['error'] as String);
      }
      return result['value'];
    } on TimeoutException {
      throw const BuilderFailure(
        'The database worker did not respond. Its outcome is unknown; inspect data before retrying writes.',
      );
    } finally {
      reply.close();
    }
  }

  Future<Map<String, dynamic>> read(
    String bot,
    String scope,
    String owner,
  ) async {
    final rows =
        await _request(bot, 'read', {'scope': scope, 'owner': owner}) as List;
    return {
      for (final row in rows)
        row['name'] as String: jsonDecode(row['value'] as String),
    };
  }

  Future<void> write(
    String bot,
    String scope,
    String owner,
    String name,
    dynamic value, {
    bool remove = false,
  }) async {
    await _request(bot, 'write', {
      'scope': scope,
      'owner': owner,
      'name': name,
      'value': remove ? null : jsonEncode(value),
    });
  }

  Future<Map<String, dynamic>> query(
    String bot,
    String sql,
    List<dynamic> parameters,
  ) async => Map<String, dynamic>.from(
    await _request(bot, 'query', {'sql': sql, 'parameters': parameters}) as Map,
  );
  Future<void> remove(String bot) async {
    await _request(bot, 'remove');
  }

  Future<Map<String, dynamic>> diagnostics(String bot) async =>
      Map<String, dynamic>.from(await _request(bot, 'diagnostics') as Map);
  Future<Map<String, dynamic>> inspect(
    String bot,
    String operation,
    Map<String, dynamic> args,
  ) async => Map<String, dynamic>.from(
    await _request(bot, 'inspect', {'operation': operation, 'args': args})
        as Map,
  );

  Future<void> removeVariable(String bot, String scope, String name) async {
    await _request(bot, 'removeVariable', {'scope': scope, 'name': name});
  }

  Future<void> close() => _closing ??= _close().whenComplete(() {
    _closing = null;
  });

  Future<void> _close() async {
    ReceivePort? reply;
    try {
      if (_pendingRequests > 0) {
        await (_drained ??= Completer<void>()).future;
      }
      // Pending requests include initialization, so the worker is now either
      // ready and idle or has already failed and been cleaned up by _open.
      final port = _port;
      if (port != null) {
        reply = ReceivePort();
        port.send((reply.sendPort, '', 'close', <String, dynamic>{}));
        await reply.first.timeout(const Duration(seconds: 5));
      }
    } finally {
      reply?.close();
      _isolate?.kill();
      _port = null;
      _isolate = null;
      _opening = null;
      _drained = null;
    }
  }
}

void _databaseWorker((SendPort, String) arguments) {
  final (parent, root) = arguments;
  final inbox = ReceivePort();
  final databases = <String, _BotDatabase>{};
  try {
    registerSqliteSecurityBridge();
    parent.send(inbox.sendPort);
  } catch (_) {
    parent.send('SQLite native library is unavailable.');
    inbox.close();
    return;
  }
  inbox.listen((dynamic message) {
    final (
      SendPort reply,
      String bot,
      String operation,
      Map<String, dynamic> args,
    ) = message as (SendPort, String, String, Map<String, dynamic>);
    try {
      if (operation == 'close') {
        for (final db in databases.values) {
          db.close();
        }
        databases.clear();
        reply.send({'value': null});
        inbox.close();
        return;
      }
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(bot)) {
        throw const BuilderFailure('Invalid bot database identity.');
      }
      final path = p.join(root, '$bot.sqlite');
      if (operation == 'remove') {
        databases.remove(bot)?.close();
        for (final suffix in ['', '-wal', '-shm', '-journal']) {
          final file = File('$path$suffix');
          if (file.existsSync()) file.deleteSync();
        }
        reply.send({'value': null});
        return;
      }
      var db = databases.remove(bot);
      if (db == null) {
        if (databases.length >= 4) {
          databases.remove(databases.keys.first)!.close();
        }
        db = _BotDatabase(path);
      }
      databases[bot] = db;
      final dynamic value;
      switch (operation) {
        case 'read':
          value = db.read(args['scope'] as String, args['owner'] as String);
        case 'write':
          db.write(
            args['scope'] as String,
            args['owner'] as String,
            args['name'] as String,
            args['value'] as String?,
          );
          value = null;
        case 'query':
          value = db.query(
            args['sql'] as String,
            List<dynamic>.from(args['parameters'] as List),
          );
        case 'diagnostics':
          value = db.diagnostics();
        case 'inspect':
          value = db.inspect(
            args['operation'] as String,
            Map<String, dynamic>.from(args['args'] as Map),
          );
        case 'removeVariable':
          db.db.execute(
            'DELETE FROM _bottogram_values WHERE scope=? AND name=?',
            [args['scope'], args['name']],
          );
          value = null;
        default:
          throw const BuilderFailure('Unknown database operation.');
      }
      reply.send({'value': value});
    } catch (error) {
      reply.send({
        'error': error is BuilderFailure
            ? error.message
            : 'Bot database operation failed.',
      });
    }
  });
}
