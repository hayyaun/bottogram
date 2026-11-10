# Pinned SQLite core

SQLite 3.54.1 is built from the unmodified upstream amalgamation using the
documented `package:sqlite3` source hook in the root pubspec. Default binary
optimizations are disabled so authorization and progress callbacks are retained.

Source: https://sqlite.org/2026/sqlite-autoconf-3540100.tar.gz

Archive SHA-256: `926ef8d3eab93fbf6e06011901273eec076b25594a4e1cdadd50c987f4f6d64e`

The root build hook verifies the vendored `sqlite3.c`, `sqlite3.h` and
`sqlite3ext.h` hashes. These upstream files are public domain; their notices are
retained. An update must deliberately replace the source/header set and hashes,
then pass the packaged native isolation tests for the supported targets.

`sqlite_guard.c` is application-owned. It receives the actual core's function
table through SQLite's public extension ABI, registered through the public
`Sqlite3.ensureExtensionLoaded` API. It does not register SQL functions or enable
SQL-level extension loading. This avoids system-library substitution, private
Dart bindings and dependence on unexported symbols in the package's binary.

Every new connection must pass functional authorization, progress interruption
and runtime-limit probes before user SQL is accepted. Tests execute real SQL
attempts against another bot's existing database, not only symbol checks.
