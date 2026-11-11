import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

import 'bot_setup.dart';
import 'manifest.dart';
import 'secret_vault.dart';
import 'upgrade.dart';

class PluginRepository extends ChangeNotifier {
  PluginRepository({
    SecretVault? vault,
    this.bundledAssets = const [
      'examples/plugins/inshopa.storefront.bottogram-plugin.json',
      'examples/plugins/inshopa.storefront.0.8.0.bottogram-plugin.json',
    ],
    AssetBundle? bundle,
  }) : vault = vault ?? PlatformSecretVault(),
       bundle = bundle ?? rootBundle;
  final SecretVault vault;
  final List<String> bundledAssets;
  final AssetBundle bundle;
  Box<String>? _packages;
  Box<dynamic>? _setups;
  Box<bool>? _defaults;
  Future<void>? _opening;
  Future<void> _tail = Future.value();

  Future<void> get ready => _opening ??= _open();
  Future<void> _open() async {
    _packages = await Hive.openBox<String>('plugin_packages_v1');
    _setups = await Hive.openBox<dynamic>('bot_setups_v1');
    _defaults = await Hive.openBox<bool>('plugin_defaults_v1');
    for (final path in bundledAssets) {
      final data = await bundle.load(path);
      final manifest = PluginManifest.parse(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      if (_defaults!.get(manifest.storageKey) == true) continue;
      // Preserve immutable installed definitions, including a same-version
      // local import. Mark once so an ordinary uninstall survives restart.
      if (!_packages!.containsKey(manifest.storageKey)) {
        await _packages!.put(manifest.storageKey, manifest.source);
      }
      await _defaults!.put(manifest.storageKey, true);
    }
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _tail.then((_) async {
      await ready;
      return operation();
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  List<PluginManifest> get installed {
    final entries = _packages?.values ?? <String>[];
    return entries
        .map(
          (raw) => PluginManifest.parse(Uint8List.fromList(utf8.encode(raw))),
        )
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  PluginManifest? manifestFor(BotSetup? setup) {
    if (setup == null || !setup.usesPlugin) return null;
    return installed
        .where(
          (p) =>
              p.storageKey == setup.pluginKey && p.digest == setup.pluginDigest,
        )
        .firstOrNull;
  }

  List<PluginManifest> newerLiveVersions(PluginManifest current) =>
      installed
          .where(
            (target) =>
                target.id == current.id &&
                target.executable &&
                comparePluginVersions(target.version, current.version) > 0,
          )
          .toList()
        ..sort((a, b) => comparePluginVersions(b.version, a.version));

  Future<void> install(PluginManifest manifest) => _serialize(() async {
    final old = _packages!.get(manifest.storageKey);
    if (old != null) {
      if (old == manifest.source) {
        throw const PluginException(
          'This plugin version is already installed.',
        );
      }
      throw const PluginException(
        'A different package already uses this ID and version. Choose a new version.',
      );
    }
    await _packages!.put(manifest.storageKey, manifest.source);
    notifyListeners();
  });

  int dependents(String key) =>
      _setups?.values
          .where((value) => value is Map && value['pluginKey'] == key)
          .length ??
      0;

  Future<void> uninstall(String key) => _serialize(() async {
    if (dependents(key) != 0) {
      throw const PluginException(
        'Delete bots using this version before uninstalling it.',
      );
    }
    await _packages!.delete(key);
    notifyListeners();
  });

  Future<BotSetup> prepare({
    required String token,
    required String adminId,
    PluginManifest? plugin,
    Map<String, String> parameters = const {},
  }) => _serialize(
    () => _prepare(
      token: token,
      adminId: adminId,
      plugin: plugin,
      parameters: parameters,
    ),
  );

  Future<BotSetup> _prepare({
    required String token,
    required String adminId,
    PluginManifest? plugin,
    Map<String, String> parameters = const {},
  }) async {
    if (validateAdminId(adminId) != null) {
      throw const PluginException('A valid admin ID is required.');
    }
    if (plugin != null && _packages!.get(plugin.storageKey) != plugin.source) {
      throw const PluginException(
        'The selected plugin version is no longer installed.',
      );
    }
    final values = <String, String>{};
    final secretValues = <String, String>{};
    for (final field in plugin?.fields ?? <PluginField>[]) {
      final value = parameters[field.key] ?? '';
      if (field.validate(value) != null) {
        throw const PluginException('Complete the plugin settings.');
      }
      if (value.isEmpty) continue;
      if (field.type == PluginFieldType.secret) {
        secretValues[field.key] = value;
      } else {
        values[field.key] = value;
      }
    }
    final random = Random.secure();
    final id = List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final setup = BotSetup(
      instanceId: id,
      tokenFingerprint: BotSetup.fingerprint(token),
      adminTelegramUserId: adminId.trim(),
      pluginKey: plugin?.storageKey,
      pluginDigest: plugin?.digest,
      pluginName: plugin?.name,
      values: values,
      secretFields: secretValues.keys.toList(),
      settings: plugin?.settingValues(const {}) ?? const {},
    );
    // Journal contains only references, never secret values. It permits recovery
    // if the process stops between creating the bot and attaching its settings.
    await _setups!.put('pending:$id', setup.toMap());
    try {
      for (final entry in secretValues.entries) {
        await vault.write(setup.secretKey(entry.key), entry.value);
      }
      return setup;
    } catch (_) {
      await _deleteSecrets(setup);
      await _setups!.delete('pending:$id');
      throw const PluginException(
        'Could not save plugin settings securely. Your bot was not created.',
      );
    }
  }

  Future<void> attach(dynamic botKey, BotSetup setup) => _serialize(() async {
    await _setups!.put(botKey, setup.toMap());
    await _setups!.delete('pending:${setup.instanceId}');
    notifyListeners();
  });

  Future<BotSetup?> setupFor(dynamic botKey, String token) async {
    await ready;
    final data = _setups!.get(botKey);
    if (data == null) return null;
    final setup = BotSetup.fromMap(data as Map);
    if (setup.tokenFingerprint != BotSetup.fingerprint(token)) {
      throw const PluginException('Stored bot settings do not match this bot.');
    }
    if (setup.pluginKey != null) {
      final raw = _packages!.get(setup.pluginKey);
      if (raw == null ||
          PluginManifest.parse(Uint8List.fromList(utf8.encode(raw))).digest !=
              setup.pluginDigest) {
        throw const PluginException(
          'The required plugin version is missing or has changed.',
        );
      }
    }
    return setup;
  }

  Future<void> discard(BotSetup setup) => _serialize(() async {
    await _deleteSecrets(setup);
    await _setups!.delete('pending:${setup.instanceId}');
  });

  Future<BotSetup> updateSettings(
    dynamic botKey,
    String token,
    Map<String, Object?> values,
  ) => _serialize(() async {
    final current = await setupFor(botKey, token);
    if (current == null || !current.usesPlugin) {
      throw const PluginException('This bot has no plugin settings.');
    }
    final raw = _packages!.get(current.pluginKey)!;
    final manifest = PluginManifest.parse(Uint8List.fromList(utf8.encode(raw)));
    final updated = current.withSettings(manifest.settingValues(values));
    await _setups!.put(botKey, updated.toMap());
    notifyListeners();
    return updated;
  });

  Future<PluginUpgradePlan> reviewUpgrade(
    dynamic botKey,
    String token,
    PluginManifest target,
  ) async {
    await ready;
    return _reviewUpgrade(botKey, token, target);
  }

  Future<PluginUpgradePlan> _reviewUpgrade(
    dynamic botKey,
    String token,
    PluginManifest target,
  ) async {
    final current = await setupFor(botKey, token);
    final manifest = manifestFor(current);
    if (current == null ||
        manifest == null ||
        _packages!.get(target.storageKey) != target.source) {
      throw const PluginException(
        'The current and selected plugin versions must both be installed.',
      );
    }
    return PluginUpgradePlan.review(manifest, target, current);
  }

  /// Ordinary reviewed configuration update, not a schema conversion/backfill.
  /// The caller holds this bot stopped so the source namespaces have no writers.
  Future<BotSetup> upgrade(
    dynamic botKey,
    String token,
    PluginManifest target, {
    required Future<void> Function(String source, String destination)
    copyNamespace,
  }) => _serialize(() async {
    final plan = await _reviewUpgrade(botKey, token, target);
    final current = (await setupFor(botKey, token))!;
    for (final id in plan.preservedAutomationIds) {
      await copyNamespace(
        '${current.instanceId}:${plan.current.digest}:$id',
        '${current.instanceId}:${target.digest}:$id',
      );
    }
    final removed = plan.removedFields.map((field) => field.key).toSet();
    final updated = BotSetup(
      instanceId: current.instanceId,
      tokenFingerprint: current.tokenFingerprint,
      adminTelegramUserId: current.adminTelegramUserId,
      pluginKey: target.storageKey,
      pluginDigest: target.digest,
      pluginName: target.name,
      values: {
        for (final entry in current.values.entries)
          if (!removed.contains(entry.key)) entry.key: entry.value,
      },
      secretFields: current.secretFields,
      settings: current.settings,
    );
    // Publish only after every unchanged automation namespace and receipt has
    // been staged durably. Failure beforehand leaves the current pin intact.
    await _setups!.put(botKey, updated.toMap());
    notifyListeners();
    return updated;
  });

  /// Stage new secrets before publishing the replacement setup. A fresh runtime
  /// identity isolates progress when configured parameters change.
  Future<BotSetup> updateParameters(
    dynamic botKey,
    String token, {
    required String adminId,
    required Map<String, String> parameters,
  }) => _serialize(() async {
    final current = await setupFor(botKey, token);
    final manifest = manifestFor(current);
    if (current == null || manifest == null) {
      throw const PluginException('The required plugin is unavailable.');
    }
    if (parameters.keys.any(
      (key) => !manifest.fields.any((f) => f.key == key),
    )) {
      throw const PluginException('Unknown plugin parameter.');
    }
    final values = <String, String>{};
    for (final field in manifest.fields) {
      var value = parameters[field.key] ?? current.values[field.key] ?? '';
      if (field.type == PluginFieldType.secret && value.isEmpty) {
        value = await vault.read(current.secretKey(field.key)) ?? '';
      }
      values[field.key] = value;
    }
    if (validateAdminId(adminId) != null ||
        manifest.fields.any(
          (field) => field.validate(values[field.key] ?? '') != null,
        )) {
      throw const PluginException(
        'Complete the plugin parameters and admin ID.',
      );
    }
    final sameAdmin = current.adminTelegramUserId == adminId.trim();
    final changed = <String>{};
    for (final field in manifest.fields) {
      final previous = field.type == PluginFieldType.secret
          ? await vault.read(current.secretKey(field.key)) ?? ''
          : current.values[field.key] ?? '';
      if (previous != values[field.key]) changed.add(field.key);
    }
    if (sameAdmin && changed.isEmpty) return current;
    if (sameAdmin && changed.every(manifest.destinationFields.contains)) {
      final updated = current.copyWith(
        values: {
          ...current.values,
          for (final field in changed) field: values[field]!.trim(),
        },
      );
      await _setups!.put(botKey, updated.toMap());
      notifyListeners();
      return updated;
    }
    final staged = await _prepare(
      token: token,
      adminId: adminId,
      plugin: manifest,
      parameters: values,
    );
    final updated = staged.withSettings(current.settings);
    try {
      await _setups!.put(botKey, updated.toMap());
    } catch (_) {
      await _deleteSecrets(staged);
      await _setups!.delete('pending:${staged.instanceId}');
      rethrow;
    }
    // The replacement is committed. Interrupted journal cleanup is recovered by
    // reconcile; never discard committed credentials because cleanup failed.
    try {
      await _setups!.delete('pending:${staged.instanceId}');
      await _deleteSecrets(current);
    } catch (_) {
      // A cleanup failure must not misreport the saved configuration as lost.
    }
    notifyListeners();
    return updated;
  });

  Future<void> reconcile(Map<dynamic, String> botTokens) => _serialize(
    () async {
      for (final key in _setups!.keys.toList()) {
        final setup = BotSetup.fromMap(_setups!.get(key) as Map);
        if (key is String && key.startsWith('pending:')) {
          final matches = botTokens.entries
              .where(
                (entry) =>
                    BotSetup.fingerprint(entry.value) == setup.tokenFingerprint,
              )
              .toList();
          final attached = _setups!.toMap().entries.any(
            (entry) =>
                entry.key != key &&
                entry.value is Map &&
                entry.value['instanceId'] == setup.instanceId,
          );
          if (matches.length == 1 && _setups!.get(matches.single.key) == null) {
            await _setups!.put(matches.single.key, setup.toMap());
          } else if (!attached) {
            await _deleteSecrets(setup);
          }
          await _setups!.delete(key);
        } else if (!botTokens.containsKey(key)) {
          await _deleteSecrets(setup);
          await _setups!.delete(key);
        }
      }
    },
  );
  Future<void> removeSetup(dynamic botKey) => _serialize(() async {
    final raw = _setups!.get(botKey);
    if (raw == null) return;
    final setup = BotSetup.fromMap(raw as Map);
    await _deleteSecrets(setup);
    await _setups!.delete(botKey);
    notifyListeners();
  });

  Future<void> _deleteSecrets(BotSetup setup) async {
    for (final field in setup.secretFields) {
      await vault.delete(setup.secretKey(field));
    }
  }
}
