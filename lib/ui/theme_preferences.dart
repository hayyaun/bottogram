import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

/// Device-local appearance preference. Missing or unknown values follow the system.
class ThemePreferences extends ChangeNotifier {
  ThemePreferences({Box<String>? box}) {
    ready = _load(box);
  }
  static const boxName = 'app_preferences';
  static const themeKey = 'theme_mode';
  late final Future<void> ready;
  Box<String>? _box;
  ThemeMode _mode = ThemeMode.system;
  bool _disposed = false;
  bool loading = true;
  bool saving = false;
  String? error;
  ThemeMode get mode => _mode;
  bool get available => !loading && _box != null;

  Future<void> _load(Box<String>? box) async {
    try {
      _box = box ?? await Hive.openBox<String>(boxName);
      _mode = switch (_box!.get(themeKey)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      error =
          'Appearance settings could not be loaded. Reopen Bottogram to try again.';
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> setMode(ThemeMode value) async {
    await ready;
    if (_disposed || saving || !available) return;
    saving = true;
    error = null;
    notifyListeners();
    try {
      await _box!.put(themeKey, value.name);
      _mode = value;
    } catch (_) {
      error = 'The theme preference could not be saved. Try again.';
    } finally {
      saving = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
