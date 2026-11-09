import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'setting.dart';
import '../runtime/registry.dart';

const maxPluginBytes = 256 * 1024;

class PluginException implements Exception {
  const PluginException(this.message);
  final String message;
  @override
  String toString() => message;
}

enum PluginFieldType { text, secret, integer }

class PluginField {
  const PluginField({
    required this.key,
    required this.label,
    required this.type,
    required this.required,
    this.helpText,
    this.defaultValue,
    this.min,
    this.max,
  });

  final String key;
  final String label;
  final PluginFieldType type;
  final bool required;
  final String? helpText;
  final String? defaultValue;
  final int? min;
  final int? max;

  String? validate(String value) {
    if (value.trim().isEmpty) return required ? '$label is required.' : null;
    if (value.length > 4096) return '$label is too long.';
    if (type == PluginFieldType.integer) {
      final number = int.tryParse(value.trim());
      if (number == null) return 'Enter a whole number.';
      if (min != null && number < min!) return 'Minimum: $min.';
      if (max != null && number > max!) return 'Maximum: $max.';
    }
    return null;
  }
}

String? validateAdminId(String? value) {
  final text = value?.trim() ?? '';
  final number = int.tryParse(text);
  if (!RegExp(r'^[1-9][0-9]*$').hasMatch(text) ||
      number == null ||
      number > 4503599627370495) {
    return 'Enter your positive numeric Telegram user ID.';
  }
  return null;
}

class PluginManifest {
  PluginManifest._(
    this.source,
    this.id,
    this.name,
    this.version,
    this.description,
    this.fields,
    this.requiresAdmin,
    this.settings,
    this.automations,
  );

  final String source;
  final String id;
  final String name;
  final String version;
  final String? description;
  final List<PluginField> fields;
  final bool requiresAdmin;
  final List<PluginSetting> settings;
  final List<AutomationDefinition> automations;
  bool get executable => automations.isNotEmpty;
  Map<String, Object> settingValues(Map<String, Object?> saved) {
    if (saved.keys.any((key) => !settings.any((s) => s.key == key))) {
      throw const PluginException('Unsupported plugin setting.');
    }
    final result = <String, Object>{};
    for (final setting in settings) {
      final value =
          saved.containsKey(setting.key)
              ? saved[setting.key]
              : setting.defaultValue;
      if (setting.validate(value) != null) {
        throw const PluginException(
          'Plugin settings do not match their declared types or bounds.',
        );
      }
      result[setting.key] = value!;
    }
    return result;
  }

  String get digest => sha256.convert(utf8.encode(source)).toString();
  String get storageKey => '$id@$version';

  /// Legacy packages remain setup-only; v2 resolves registered host components.
  static PluginManifest parse(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxPluginBytes) {
      throw const PluginException('Choose a JSON plugin file up to 256 KiB.');
    }
    late String source;
    late Map<String, dynamic> data;
    try {
      source = utf8.decode(bytes);
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      data = decoded;
    } catch (_) {
      throw const PluginException(
        'The plugin must be a valid UTF-8 JSON object.',
      );
    }
    void reject(String message) => throw PluginException(message);
    void keys(Map<String, dynamic> map, Set<String> allowed) {
      if (map.keys.any((key) => !allowed.contains(key))) {
        reject('The plugin contains unsupported properties.');
      }
    }

    keys(data, {
      'manifestVersion',
      'id',
      'name',
      'version',
      'hostApiMajor',
      'engine',
      'executionStatus',
      'description',
      'requiresBotFields',
      'setupFields',
      'settings',
      'automations',
    });
    final live =
        data['manifestVersion'] is int &&
        data['hostApiMajor'] is int &&
        data['manifestVersion'] == 2 &&
        data['hostApiMajor'] == 2;
    if (!live &&
        (data['manifestVersion'] is! int ||
            data['hostApiMajor'] is! int ||
            data['manifestVersion'] != 1 ||
            data['hostApiMajor'] != 1)) {
      reject('This plugin needs a different Bottogram plugin API version.');
    }
    if ((!live && data['engine'] != 'poll-to-telegram.v1') ||
        (live && data.containsKey('engine'))) {
      reject('The requested plugin engine is not supported.');
    }
    if (data['executionStatus'] != (live ? 'live' : 'setup-only') ||
        (!live && data.containsKey('automations'))) {
      reject(
        'This release supports setup-only plugins; live execution is not available yet.',
      );
    }
    String text(dynamic value, String label, int length) {
      if (value is! String || value.trim().isEmpty || value.length > length) {
        reject('Invalid plugin $label.');
      }
      return (value as String).trim();
    }

    final id = text(data['id'], 'ID', 100);
    if (!RegExp(r'^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$').hasMatch(id)) {
      reject(
        'Use a lowercase plugin ID with letters, numbers, dots or hyphens.',
      );
    }
    final version = text(data['version'], 'version', 40);
    if (!RegExp(
      r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$',
    ).hasMatch(version)) {
      reject('Plugin versions must use major.minor.patch.');
    }
    final name = text(data['name'], 'name', 100);
    final description =
        data['description'] == null
            ? null
            : text(data['description'], 'description', 500);
    final requires = data['requiresBotFields'] ?? <dynamic>[];
    if (requires is! List ||
        requires.any((v) => v != 'adminTelegramUserId') ||
        requires.toSet().length != requires.length) {
      reject('The plugin requests unsupported shared bot fields.');
    }
    final rawFields = data['setupFields'];
    if (rawFields is! List || rawFields.length > 32) {
      reject('setupFields must be a list of at most 32 fields.');
    }
    final fields = <PluginField>[];
    final seen = <String>{};
    for (final raw in rawFields as List) {
      if (raw is! Map<String, dynamic>) reject('Invalid setup field.');
      final field = raw as Map<String, dynamic>;
      keys(field, {
        'key',
        'label',
        'type',
        'required',
        'helpText',
        'default',
        'min',
        'max',
      });
      final key = text(field['key'], 'field key', 64);
      if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(key) ||
          {'name', 'token', 'botToken', 'adminTelegramUserId'}.contains(key) ||
          !seen.add(key)) {
        reject(
          'Plugin field keys must be unique and cannot duplicate common bot fields.',
        );
      }
      final type =
          PluginFieldType.values
              .where((v) => v.name == field['type'])
              .firstOrNull;
      if (type == null || field['required'] is! bool) {
        reject('Invalid setup field type or required flag.');
      }
      final min = field['min'];
      final max = field['max'];
      if ((min != null && min is! int) ||
          (max != null && max is! int) ||
          (type != PluginFieldType.integer && (min != null || max != null)) ||
          (min is int && max is int && min > max)) {
        reject('Invalid numeric field bounds.');
      }
      final defaultValue = field['default'];
      if (defaultValue != null &&
          (type == PluginFieldType.secret ||
              (defaultValue is! String && defaultValue is! int))) {
        reject(
          'Secret fields cannot include defaults; other defaults must be text or integers.',
        );
      }
      final parsed = PluginField(
        key: key,
        label: text(field['label'], 'field label', 100),
        type: type!,
        required: field['required'] as bool,
        helpText:
            field['helpText'] == null
                ? null
                : text(field['helpText'], 'field help', 300),
        defaultValue: defaultValue?.toString(),
        min: min as int?,
        max: max as int?,
      );
      if (parsed.defaultValue != null &&
          parsed.validate(parsed.defaultValue!) != null) {
        reject('A field default does not satisfy its validation.');
      }
      fields.add(parsed);
    }
    final rawSettings = data['settings'] ?? <dynamic>[];
    if (rawSettings is! List || rawSettings.length > 32) {
      reject('settings must be a list of at most 32 preferences.');
    }
    final settings = <PluginSetting>[];
    try {
      for (final raw in rawSettings as List) {
        settings.add(PluginSetting.parse(raw, seen));
      }
    } on FormatException catch (error) {
      reject(error.message);
    }
    List<AutomationDefinition> automations = const [];
    if (live) {
      try {
        automations = AutomationRegistry.standard.parse(data['automations']);
        for (final automation in automations) {
          if (automation.enabledBySetting != null &&
              !settings.any(
                (s) =>
                    s.key == automation.enabledBySetting &&
                    s.defaultValue is bool,
              )) {
            reject('An automation must reference a boolean setting.');
          }
          for (final component in [automation.trigger, ...automation.actions]) {
            if (component.type == 'telegram.notify-admin.v1' &&
                !(requires as List).contains('adminTelegramUserId')) {
              reject('Admin notifications require the shared admin field.');
            }
            for (final request in AutomationRegistry.standard.requestsFor(
              component,
            )) {
              final auth = request['authentication'];
              if (auth is Map &&
                  !fields.any(
                    (f) =>
                        f.key == auth['secretField'] &&
                        f.type == PluginFieldType.secret &&
                        f.required,
                  )) {
                reject(
                  'Bearer authentication must reference a required secret field.',
                );
              }
              final storefront = request['storefrontUrlField'];
              if (storefront != null &&
                  !fields.any(
                    (f) =>
                        f.key == storefront &&
                        f.type == PluginFieldType.text &&
                        f.required,
                  )) {
                reject(
                  'The storefront URL must reference a required text field.',
                );
              }
            }
          }
        }
      } on FormatException catch (error) {
        reject(error.message);
      }
    }
    return PluginManifest._(
      source,
      id,
      name,
      version,
      description,
      List.unmodifiable(fields),
      (requires as List).contains('adminTelegramUserId'),
      List.unmodifiable(settings),
      automations,
    );
  }
}
