import 'dart:convert';
import 'package:hive/hive.dart';
import 'ports.dart';

/// Optional progress capability used only for reviewed updates of stopped bots.
abstract interface class NamespaceProgressStore implements ProgressStore {
  Future<void> copyNamespace(String source, String destination);
}

/// Existing progress storage; updates stage records before publishing a new pin.
class HiveProgressStore implements NamespaceProgressStore {
  Future<Box<String>>? _box;
  Future<Box<String>> get _ready =>
      _box ??= Hive.openBox<String>('automation_progress_v1');
  @override
  Future<Json> read(String key) async {
    final raw = (await _ready).get(key);
    return raw == null ? {} : jsonDecode(raw) as Json;
  }

  @override
  Future<void> write(String key, Json value) async {
    final encoded = jsonEncode(value);
    if (utf8.encode(encoded).length > 2 * 1024 * 1024) {
      throw const RuntimeFailure(
        'Automation progress exceeds 2 MiB.',
        permanent: true,
      );
    }
    await (await _ready).put(key, encoded);
  }

  @override
  Future<void> removeInstance(String instanceId) async {
    final box = await _ready;
    await box.deleteAll(
      box.keys
          .where((k) => k is String && k.startsWith('$instanceId:'))
          .toList(),
    );
  }

  @override
  Future<void> copyNamespace(String source, String destination) async {
    final from = source.split(':');
    final to = destination.split(':');
    if (from.length != 3 ||
        to.length != 3 ||
        from[0] != to[0] ||
        from[2] != to[2] ||
        from.any((part) => part.isEmpty) ||
        to.any((part) => part.isEmpty) ||
        source == destination) {
      throw const RuntimeFailure(
        'Invalid progress update scope.',
        permanent: true,
      );
    }
    final box = await _ready;
    bool belongs(String key, String prefix) =>
        key == prefix || key.startsWith('$prefix:');
    // The source belongs to the stopped current pin. Destination records are
    // unpublished staging data from an earlier interrupted attempt. Rebuild
    // those records on retry without modifying the source namespace.
    final sourceKeys = box.keys
        .whereType<String>()
        .where((k) => belongs(k, source))
        .toList();
    await box.deleteAll(
      box.keys
          .whereType<String>()
          .where((k) => belongs(k, destination))
          .toList(),
    );
    for (final key in sourceKeys) {
      final raw = box.get(key);
      if (raw != null) {
        await box.put('$destination${key.substring(source.length)}', raw);
      }
    }
    await box.flush();
    for (final key in sourceKeys) {
      if (box.get('$destination${key.substring(source.length)}') !=
          box.get(key)) {
        throw const RuntimeFailure(
          'Polling progress could not be verified. The plugin version was not changed.',
          permanent: true,
        );
      }
    }
  }
}
