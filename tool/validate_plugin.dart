import 'dart:io';
import 'dart:typed_data';

import 'package:bottogram/plugins/manifest.dart';

/// Validates a local package with exactly the parser used by Bottogram import.
Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && {'--help', '-h'}.contains(arguments.single)) {
    stdout.writeln('Usage: dart run tool/validate_plugin.dart <plugin.json>');
    return;
  }
  if (arguments.length != 1 || arguments.single.startsWith('-')) {
    stderr.writeln('Usage: dart run tool/validate_plugin.dart <plugin.json>');
    exitCode = 64;
    return;
  }

  try {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in File(arguments.single).openRead()) {
      if (bytes.length + chunk.length > maxPluginBytes) {
        throw const PluginException('The plugin file exceeds 256 KiB.');
      }
      bytes.add(chunk);
    }
    final manifest = PluginManifest.parse(bytes.takeBytes());
    final execution = manifest.executable
        ? '${manifest.automations.length} automations'
        : 'setup only; no automations';
    stdout.writeln('Valid: ${manifest.storageKey} ($execution).');
  } on PluginException catch (error) {
    stderr.writeln('Invalid plugin: ${error.message}');
    exitCode = 1;
  } on FileSystemException {
    stderr.writeln('Could not read the plugin file.');
    exitCode = 1;
  }
}
