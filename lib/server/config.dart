import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../plugins/admin_ids.dart';
import '../plugins/bot_setup.dart';
import '../plugins/manifest.dart';

class ServerConfigException implements Exception {
  const ServerConfigException(this.message);
  final String message;
}

class ServerBotConfig {
  ServerBotConfig._(this.manifest, this.setup, this.token, this._secrets);

  final PluginManifest manifest;
  final BotSetup setup;
  final String token;
  final Map<String, String> _secrets;

  Future<String?> secret(String field) async => _secrets[field];

  static Future<ServerBotConfig> load(File file) async {
    final config = _jsonObject(
      await _read(file, 64 * 1024, 'bot config'),
      'bot config',
    );
    if (config.keys.any(
      (key) => !{
        'plugin',
        'tokenFile',
        'adminIds',
        'fields',
        'secretFiles',
        'settings',
      }.contains(key),
    )) {
      throw const ServerConfigException('The bot config has an unknown key.');
    }
    File configFile(Object? name, String label) {
      if (name is! String || name.trim().isEmpty || name.contains('\u0000')) {
        throw ServerConfigException('$label must be a file path.');
      }
      // Resolve relative paths beside the config file, not the working directory.
      return File(
        p.isAbsolute(name) ? name : p.join(file.absolute.parent.path, name),
      );
    }

    final manifest = PluginManifest.parse(
      await _read(
        configFile(config['plugin'], 'plugin'),
        maxPluginBytes,
        'plugin package',
      ),
    );
    if (!manifest.executable) {
      throw const ServerConfigException(
        'Choose a plugin package with live automations.',
      );
    }
    final token = await _readSecret(
      configFile(config['tokenFile'], 'tokenFile'),
      'bot token',
    );
    if (!RegExp(r'^[0-9]+:[A-Za-z0-9_-]+$').hasMatch(token)) {
      throw const ServerConfigException(
        'The bot token file has an invalid token.',
      );
    }

    final rawAdmins = config['adminIds'] ?? const [];
    if (rawAdmins is! List ||
        rawAdmins.any(
          (id) => id is! String || !RegExp(r'^[0-9]+$').hasMatch(id),
        )) {
      throw const ServerConfigException(
        'adminIds must be a list of numeric ID strings.',
      );
    }
    final adminIds = rawAdmins.isEmpty && !manifest.requiresAdmin
        ? const <String>[]
        : parseAdminIds(rawAdmins.join('\n'));
    if (adminIds == null) {
      throw const ServerConfigException(
        'Provide valid Telegram admin IDs for this plugin.',
      );
    }

    final fields = _optionalObject(config, 'fields');
    final secretFiles = _optionalObject(config, 'secretFiles');
    final definitions = {for (final field in manifest.fields) field.key: field};
    if (fields.keys.any(
      (key) =>
          !definitions.containsKey(key) ||
          definitions[key]!.type == PluginFieldType.secret,
    )) {
      throw const ServerConfigException(
        'fields may contain only declared non-secret plugin fields.',
      );
    }
    if (secretFiles.keys.any(
      (key) => definitions[key]?.type != PluginFieldType.secret,
    )) {
      throw const ServerConfigException(
        'secretFiles may contain only declared plugin secret fields.',
      );
    }
    final settings = manifest.settingValues(
      _optionalObject(config, 'settings'),
    );
    final values = <String, String>{};
    final secrets = <String, String>{};
    for (final field in manifest.fields) {
      final isSecret = field.type == PluginFieldType.secret;
      final String value;
      if (isSecret) {
        value = secretFiles.containsKey(field.key)
            ? await _readSecret(
                configFile(
                  secretFiles[field.key],
                  'Secret file for ${field.key}',
                ),
                'plugin secret file for ${field.key}',
              )
            : '';
      } else {
        final input = fields.containsKey(field.key)
            ? fields[field.key]
            : field.defaultValue ?? '';
        if (input is! String) {
          throw ServerConfigException(
            'Plugin field ${field.key} must be a string.',
          );
        }
        value = input;
      }
      if (field.validate(value) != null) {
        throw ServerConfigException(
          'Plugin field ${field.key} is missing or invalid.',
        );
      }
      if (value.isNotEmpty) (isSecret ? secrets : values)[field.key] = value;
    }
    final fingerprint = BotSetup.fingerprint(token);
    return ServerBotConfig._(
      manifest,
      BotSetup(
        instanceId: fingerprint,
        tokenFingerprint: fingerprint,
        adminIds: adminIds,
        pluginKey: manifest.storageKey,
        pluginDigest: manifest.digest,
        pluginName: manifest.name,
        values: values,
        secretFields: secrets.keys.toList(),
        settings: settings,
      ),
      token,
      secrets,
    );
  }
}

Map<String, Object?> _optionalObject(Map<String, Object?> config, String key) {
  if (!config.containsKey(key)) return const {};
  final value = config[key];
  if (value is! Map<String, Object?>) {
    throw ServerConfigException('$key must be a JSON object.');
  }
  return value;
}

Map<String, Object?> _jsonObject(List<int> bytes, String label) {
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is Map<String, Object?>) return decoded;
  } on FormatException {
    // A decoder exception can include the original input.
  }
  throw ServerConfigException('The $label must be a valid JSON object.');
}

Future<String> _readSecret(File file, String label) async {
  final bytes = await _read(file, 16 * 1024, label);
  try {
    return utf8.decode(bytes).trim();
  } on FormatException {
    throw ServerConfigException('The $label must be UTF-8 text.');
  }
}

Future<Uint8List> _read(File file, int limit, String label) async {
  final bytes = BytesBuilder(copy: false);
  try {
    if (await FileSystemEntity.type(file.path) != FileSystemEntityType.file) {
      throw ServerConfigException('The $label must be a readable file.');
    }
    await for (final chunk in file.openRead()) {
      if (bytes.length + chunk.length > limit) {
        throw ServerConfigException('The $label is too large.');
      }
      bytes.add(chunk);
    }
  } on FileSystemException {
    throw ServerConfigException('Could not read the $label.');
  }
  return bytes.takeBytes();
}
