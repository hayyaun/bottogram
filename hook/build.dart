import 'package:hooks/hooks.dart';
import 'package:code_assets/code_assets.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'dart:io';
import 'package:crypto/crypto.dart';

/// The sqlite3 dependency builds the pinned core with its documented source
/// hook. This separate asset contains only the trusted security bridge and uses
/// SQLite's public extension ABI to share that core's function table.
void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }
    const sources = {
      'sqlite3.c':
          '0c657666d819f261cc4007526ad57e1669de9949df7a8ea847aa284a2bf0ee52',
      'sqlite3.h':
          'd6c84557261893439b341d2e6c35187ae3ea24fbfd843ad94616f72d89242b8c',
      'sqlite3ext.h':
          '48963abfefb41ac329ef9d706acb5eadba952a99a748285c9ded6b5e0942721b',
    };
    for (final entry in sources.entries) {
      final file = File.fromUri(
        input.packageRoot.resolve('native/sqlite/${entry.key}'),
      );
      if ((await sha256.bind(file.openRead()).first).toString() !=
          entry.value) {
        throw StateError(
          'Pinned SQLite source verification failed: ${entry.key}',
        );
      }
      output.dependencies.add(file.uri);
    }
    final bridge = CBuilder.library(
      name: 'bottogram_sqlite_guard',
      packageName: input.packageName,
      assetName: 'builder/sqlite_native.dart',
      sources: ['native/sqlite/sqlite_guard.c'],
      includes: ['native/sqlite'],
    );
    await bridge.run(input: input, output: output);
  });
}
