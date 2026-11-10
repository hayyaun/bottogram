import 'dart:convert';

import '../runtime/registry.dart';
import '../runtime/telegram_config.dart';
import 'bot_setup.dart';
import 'manifest.dart';

/// The host derives compatibility from installed definitions and the current
/// setup. A package cannot authorize state reuse by declaring an upgrade flag.
class PluginUpgradePlan {
  const PluginUpgradePlan._({
    required this.current,
    required this.target,
    required this.preservedAutomationIds,
    required this.addedAutomationIds,
    required this.removedAutomationIds,
    required this.replacedAutomationIds,
  });

  final PluginManifest current;
  final PluginManifest target;
  final List<String> preservedAutomationIds;
  final List<String> addedAutomationIds;
  final List<String> removedAutomationIds;
  final List<String> replacedAutomationIds;

  static PluginUpgradePlan review(
    PluginManifest current,
    PluginManifest target,
    BotSetup setup,
  ) {
    if (current.id != target.id ||
        comparePluginVersions(target.version, current.version) <= 0 ||
        setup.pluginKey != current.storageKey ||
        setup.pluginDigest != current.digest ||
        !current.executable ||
        !target.executable) {
      throw const PluginException(
        'Choose a newer live version of this bot’s installed plugin.',
      );
    }
    if (current.requiresAdmin != target.requiresAdmin ||
        canonicalJson(_fieldSchema(current)) !=
            canonicalJson(_fieldSchema(target)) ||
        canonicalJson(_settingSchema(current)) !=
            canonicalJson(_settingSchema(target))) {
      throw const PluginException(
        'This update changes setup fields or settings. A compatible update must retain the current configuration contract.',
      );
    }
    // All field semantics and effective preferences remain identical, as do the
    // instance, token, admin, values and secure key references during publishing.
    target.settingValues(setup.settings);
    for (final field in target.fields) {
      if (field.type != PluginFieldType.secret &&
          field.validate(setup.values[field.key] ?? '') != null) {
        throw const PluginException(
          'The saved parameters do not satisfy the new plugin. Update them before changing version.',
        );
      }
    }
    try {
      for (final reference in webAppTargets(
        telegram: target.telegram,
        actionConfigs: target.automations.expand(
          (automation) => automation.actions.map((action) => action.config),
        ),
      )) {
        resolveWebAppTarget(reference, setup.values);
      }
    } catch (_) {
      throw const PluginException(
        'The saved public URL cannot be used by the new plugin. Configure a valid HTTPS origin before updating; the current version has not changed.',
      );
    }
    final before = {for (final a in current.automations) a.id: a};
    final after = {for (final a in target.automations) a.id: a};
    final preserved = <String>[];
    final removed = <String>[];
    final replaced = <String>[];
    for (final entry in before.entries) {
      final next = after[entry.key];
      if (next != null &&
          canonicalJson(_automation(entry.value)) ==
              canonicalJson(_automation(next))) {
        preserved.add(entry.key);
      } else {
        // Replacing navigation commands may deliberately retire queued command
        // replies. Background sources must retain their behavior and progress;
        // a changed polling definition needs a separately designed transition.
        if (!_command(entry.value) || (next != null && !_command(next))) {
          throw const PluginException(
            'This update removes or changes a background automation. Its progress cannot be safely reused by this update path.',
          );
        }
        (next == null ? removed : replaced).add(entry.key);
      }
    }
    return PluginUpgradePlan._(
      current: current,
      target: target,
      preservedAutomationIds: List.unmodifiable(preserved),
      addedAutomationIds: List.unmodifiable(
        after.keys.where((id) => !before.containsKey(id)),
      ),
      removedAutomationIds: List.unmodifiable(removed),
      replacedAutomationIds: List.unmodifiable(replaced),
    );
  }
}

int comparePluginVersions(String left, String right) {
  final a = left.split('.').map(BigInt.parse).toList();
  final b = right.split('.').map(BigInt.parse).toList();
  for (var i = 0; i < 3; i++) {
    final result = a[i].compareTo(b[i]);
    if (result != 0) return result;
  }
  return 0;
}

bool _command(AutomationDefinition a) =>
    {'telegram.command.v1', 'telegram.command.v2'}.contains(a.trigger.type);

Map<String, dynamic> _fieldSchema(PluginManifest manifest) => {
  for (final f in manifest.fields)
    f.key: {
      'type': f.type.name,
      'required': f.required,
      'default': f.defaultValue,
      'min': f.min,
      'max': f.max,
    },
};

Map<String, dynamic> _settingSchema(PluginManifest manifest) => {
  for (final s in manifest.settings)
    s.key: {
      'type': s.type.name,
      'default': s.defaultValue,
      'min': s.min,
      'max': s.max,
      'minLength': s.minLength,
      'maxLength': s.maxLength,
      'choices': s.choices.map((c) => c.value).toList(),
    },
};

Map<String, dynamic> _automation(AutomationDefinition a) => {
  'id': a.id,
  'enabledBySetting': a.enabledBySetting,
  'trigger': {'type': a.trigger.type, 'config': a.trigger.config},
  'actions': a.actions
      .map((c) => {'id': c.id, 'type': c.type, 'config': c.config})
      .toList(),
};

/// Object key order is presentation; array order and every scalar are behavior.
String canonicalJson(dynamic value) => jsonEncode(_canonical(value));

dynamic _canonical(dynamic value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}
