import 'dart:convert';

import '../runtime/http_headers.dart';
import '../runtime/origin.dart';
import '../runtime/ports.dart';
import '../runtime/registry.dart';
import '../runtime/telegram_config.dart';
import '../runtime/telegram_interaction.dart';
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
    required this.removedFields,
  });

  final PluginManifest current;
  final PluginManifest target;
  final List<String> preservedAutomationIds;
  final List<String> addedAutomationIds;
  final List<String> removedAutomationIds;
  final List<String> replacedAutomationIds;
  final List<PluginField> removedFields;

  /// Catalog candidates are already sorted from newest to oldest.
  static PluginManifest? firstCompatibleTarget(
    PluginManifest current,
    BotSetup setup,
    Iterable<PluginManifest> candidates,
  ) {
    for (final target in candidates) {
      try {
        review(current, target, setup);
        return target;
      } on PluginException {
        // The review screen can still explain why an installed version is blocked.
      }
    }
    return null;
  }

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
        canonicalJson(_settingSchema(current)) !=
            canonicalJson(_settingSchema(target))) {
      throw const PluginException(
        'This update changes setup fields or settings. A compatible update must retain the current configuration contract.',
      );
    }
    final aliases = _fieldAliases(current, target, setup);
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
          canonicalJson(_automation(entry.value, aliases: aliases)) ==
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
      removedFields: List.unmodifiable(
        current.fields.where((field) => aliases.containsKey(field.key)),
      ),
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

bool _command(AutomationDefinition a) => {
  'telegram.command.v1',
  'telegram.command.v2',
  interactionTrigger,
}.contains(a.trigger.type);

Map<String, String> _fieldAliases(
  PluginManifest current,
  PluginManifest target,
  BotSetup setup,
) {
  final before = _fieldSchema(current);
  final after = _fieldSchema(target);
  const changedContract = PluginException(
    'This update changes the configuration contract. Existing fields must retain their semantics and new fields must be optional with no default.',
  );
  if (before.entries.any(
        (entry) =>
            after.containsKey(entry.key) &&
            canonicalJson(entry.value) != canonicalJson(after[entry.key]),
      ) ||
      target.fields
          .where((field) => !before.containsKey(field.key))
          .any(
            (field) =>
                field.type == PluginFieldType.secret ||
                field.required ||
                field.defaultValue != null ||
                setup.values.containsKey(field.key),
          )) {
    throw changedContract;
  }

  final aliases = <String, String>{};
  final removed = current.fields.where(
    (field) => !after.containsKey(field.key),
  );
  if (removed.isEmpty) return aliases;
  final registry = AutomationRegistry.standard;
  final boundOrigins = {
    for (final automation in current.automations.where((a) => !_command(a)))
      for (final component in [automation.trigger, ...automation.actions])
        for (final request in registry.requestsFor(component))
          for (final binding in headerFieldBindings(request))
            if (binding.transform == 'url.origin' ||
                binding.transform == 'url.authority')
              binding.field,
  };
  for (final field in removed) {
    if (field.type != PluginFieldType.text ||
        !field.required ||
        !boundOrigins.contains(field.key)) {
      throw changedContract;
    }
    final origin = parseConfiguredOrigin(setup.values[field.key] ?? '');
    final matches = target.fields.where((candidate) {
      if (origin == null ||
          !before.containsKey(candidate.key) ||
          candidate.type != PluginFieldType.text ||
          !candidate.required) {
        return false;
      }
      final retained = parseConfiguredOrigin(setup.values[candidate.key] ?? '');
      return retained?.origin == origin.origin &&
          retained?.authority == origin.authority;
    }).toList();
    if (matches.length != 1) {
      throw const PluginException(
        'The saved URL for a field removed by this version does not match a single retained origin. The current plugin and polling progress have been kept.',
      );
    }
    aliases[field.key] = matches.single.key;
  }
  return aliases;
}

Json _configWithAliases(
  ComponentDefinition component,
  Map<String, String> aliases,
) {
  if (aliases.isEmpty) return component.config;
  final requests = AutomationRegistry.standard.requestsFor(component).toSet();
  dynamic rewrite(dynamic value) {
    if (value is List) return value.map(rewrite).toList();
    if (value is! Json) return value;
    final headers = value['headers'];
    if (requests.contains(value) && headers is Json) {
      return {
        ...value,
        'headers': {
          for (final entry in headers.entries)
            entry.key: switch (entry.value) {
              {
                'field': final String field,
                'transform': 'url.origin' || 'url.authority',
              }
                  when aliases.containsKey(field) =>
                {...entry.value as Json, 'field': aliases[field]},
              _ => entry.value,
            },
        },
      };
    }
    return {for (final entry in value.entries) entry.key: rewrite(entry.value)};
  }

  return rewrite(component.config) as Json;
}

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

Json _automation(
  AutomationDefinition a, {
  Map<String, String> aliases = const {},
}) => {
  'id': a.id,
  'enabledBySetting': a.enabledBySetting,
  'trigger': {
    'type': a.trigger.type,
    'config': _configWithAliases(a.trigger, aliases),
  },
  'actions': a.actions
      .map(
        (c) => {
          'id': c.id,
          'type': c.type,
          'config': _configWithAliases(c, aliases),
        },
      )
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
