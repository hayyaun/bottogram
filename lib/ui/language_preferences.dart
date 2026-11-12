import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';

import '../store/app_preferences.dart';

enum AppLanguage {
  system(null),
  english(Locale('en')),
  persian(Locale('fa'));

  const AppLanguage(this.locale);
  final Locale? locale;
}

/// The language is a device preference, separate from bot configuration.
class LanguagePreferences extends ChangeNotifier {
  LanguagePreferences({Box<String>? box}) {
    ready = _load(box);
  }

  static const _key = 'app_language';
  late final Future<void> ready;
  Box<String>? _box;
  AppLanguage _language = AppLanguage.system;
  bool _disposed = false;
  bool saving = false;
  bool saveFailed = false;

  AppLanguage get language => _language;
  bool get available => _box != null;

  Future<void> _load(Box<String>? box) async {
    try {
      _box = box ?? await Hive.openBox<String>(appPreferencesBoxName);
      _language = switch (_box!.get(_key)) {
        'en' => AppLanguage.english,
        'fa' => AppLanguage.persian,
        _ => AppLanguage.system,
      };
    } catch (_) {
      _box = null;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> setLanguage(AppLanguage language) async {
    await ready;
    if (_disposed || saving || !available || language == _language) return;
    saving = true;
    saveFailed = false;
    notifyListeners();
    try {
      final code = language.locale?.languageCode;
      if (code == null) {
        await _box!.delete(_key);
      } else {
        await _box!.put(_key, code);
      }
      _language = language;
    } catch (_) {
      saveFailed = true;
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
