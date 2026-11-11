import 'dart:convert';

import 'package:hive/hive.dart';

const appPreferencesBoxName = 'app_preferences';

/// Device preferences record which bots the user left enabled. The bot records
/// and exported configurations keep their existing format.
class BotRunPreferences {
  static const _key = 'running_bots';

  Future<Set<String>> read() async {
    final box = await Hive.openBox<String>(appPreferencesBoxName);
    final value = box.get(_key);
    if (value == null) return {};
    return (jsonDecode(value) as List).cast<String>().toSet();
  }

  Future<void> write(Set<String> bots) async {
    final box = await Hive.openBox<String>(appPreferencesBoxName);
    await box.put(_key, jsonEncode(bots.toList()));
    await box.flush();
  }
}
