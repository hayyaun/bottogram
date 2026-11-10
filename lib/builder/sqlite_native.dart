import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:sqlite3/sqlite3.dart';

typedef SqliteAuthorizerCallback =
    Int32 Function(
      Pointer<Void>,
      Int32,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );
typedef SqliteProgressCallback = Int32 Function(Pointer<Void>);
typedef _InitializeSecurity =
    Int32 Function(Pointer<Void>, Pointer<Pointer<Utf8>>, Pointer<Void>);

@Native<_InitializeSecurity>(symbol: 'sqlite3_bottogramsecurity_init')
external int _initializeSecurityExtension(
  Pointer<Void> database,
  Pointer<Pointer<Utf8>> error,
  Pointer<Void> api,
);

bool _registered = false;

/// Registers trusted application code with SQLite's documented extension API.
/// This does not enable SQL-level extension loading or create any SQL function.
/// Call in the database worker before opening any connection.
void registerSqliteSecurityBridge() {
  if (_registered) return;
  sqlite3.ensureExtensionLoaded(
    SqliteExtension(
      Native.addressOf<NativeFunction<_InitializeSecurity>>(
        _initializeSecurityExtension,
      ).cast<Void>(),
    ),
  );
  _registered = true;
}

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<NativeFunction<SqliteAuthorizerCallback>>,
    Pointer<Void>,
  )
>(symbol: 'bottogram_sqlite_set_authorizer')
external int setSqliteAuthorizer(
  Pointer<Void> database,
  Pointer<NativeFunction<SqliteAuthorizerCallback>> callback,
  Pointer<Void> context,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Int32,
    Pointer<NativeFunction<SqliteProgressCallback>>,
    Pointer<Void>,
  )
>(symbol: 'bottogram_sqlite_progress_handler')
external int setSqliteProgressHandler(
  Pointer<Void> database,
  int instructions,
  Pointer<NativeFunction<SqliteProgressCallback>> callback,
  Pointer<Void> context,
);

@Native<Int32 Function(Pointer<Void>, Int32, Int32)>(
  symbol: 'bottogram_sqlite_limit',
)
external int setSqliteLimit(Pointer<Void> database, int category, int value);

/// Verifies actual authorizer rejection and progress interruption on a fresh,
/// idle connection. Must run before its normal authorizer is installed.
/// A result of 7 proves all three required interfaces are functional.
@Native<Int32 Function(Pointer<Void>)>(
  symbol: 'bottogram_sqlite_security_probe',
)
external int probeSqliteSecurity(Pointer<Void> database);

/// The core version obtained from the API table supplied to this bridge.
/// Compare with package:sqlite3's version to check that the core is shared.
@Native<Int32 Function()>(symbol: 'bottogram_sqlite_core_version')
external int sqliteSecurityCoreVersion();
