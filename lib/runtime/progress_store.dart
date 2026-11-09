import 'dart:convert';
import 'package:hive/hive.dart';
import 'ports.dart';

/// New runtime state only; no conversion or rewrite of existing bot records.
class HiveProgressStore implements ProgressStore {
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
}
