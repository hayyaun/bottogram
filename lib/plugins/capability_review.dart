import 'package:flutter/material.dart';

import '../runtime/registry.dart';
import '../runtime/telegram_config.dart';
import '../runtime/telegram_interaction.dart';
import 'manifest.dart';

List<String> pluginCommands(PluginManifest manifest) => {
  for (final automation in manifest.automations)
    ..._commands(automation.trigger),
}.toList();

Iterable<String> _commands(ComponentDefinition trigger) sync* {
  switch (trigger.type) {
    case 'telegram.command.v1':
      yield trigger.config['command'] as String;
    case 'telegram.command.v2':
      yield* (trigger.config['commands'] as List).cast<String>();
    case interactionTrigger:
      for (final route in interactionRoutes(trigger.config)) {
        if (route['kind'] == 'command') yield route['name'] as String;
      }
  }
}

String automationSummary(AutomationDefinition automation) {
  final trigger = automation.trigger;
  if (trigger.type == 'telegram.command.v1') {
    return '/${trigger.config['command']} · all chats';
  }
  if (trigger.type == 'telegram.command.v2') {
    final commands = (trigger.config['commands'] as List)
        .map((command) => '/$command')
        .join(' · ');
    final chats = (trigger.config['chatTypes'] as List).join(', ');
    return '$commands · $chats chats';
  }
  if (trigger.type == interactionTrigger) {
    final commands = _commands(
      trigger,
    ).map((command) => '/$command').join(' · ');
    if (commands.isEmpty) return 'Private-chat buttons and widgets';
    final role = trigger.config['audience'] == 'admin'
        ? 'admin only'
        : 'private chats';
    return '$commands · $role';
  }
  return 'Scheduled checks · every ${trigger.config['intervalSeconds']} seconds';
}

/// Reviews declarations for any plugin; no installed package is special-cased.
class PluginCapabilityReview extends StatelessWidget {
  const PluginCapabilityReview({super.key, required this.plugin, this.fields});
  final PluginManifest plugin;
  final Map<String, String>? fields;

  String _fieldLabel(String key) =>
      plugin.fields.firstWhere((field) => field.key == key).label;

  String _headerDescription(MapEntry<String, dynamic> header) {
    final binding = header.value;
    if (binding is String) return 'Header: ${header.key} (literal value)';
    final transform = switch (binding['transform']) {
      'value' => 'field value',
      'url.origin' => 'URL origin',
      'url.authority' => 'URL host and port',
      _ => 'field value',
    };
    return 'Header: ${header.key} ← ${_fieldLabel(binding['field'] as String)} ($transform)';
  }

  String _authenticationDescription(Map<String, dynamic> authentication) {
    final method = authentication['type'] == 'bearer'
        ? 'Bearer token'
        : 'Custom header ${authentication['header']}';
    return 'Authentication: $method ← ${_fieldLabel(authentication['secretField'] as String)} (secure storage)';
  }

  String _destination(Map<String, dynamic> target) {
    final field = plugin.fields.firstWhere(
      (f) => f.key == target['originField'],
    );
    if (fields != null) {
      try {
        return '${field.label} → ${resolveWebAppTarget(target, fields!)}';
      } catch (_) {
        // Invalid configured values are never echoed by the review surface.
      }
    }
    return '${field.label} → ${target['path']} (HTTPS)';
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (plugin.telegram?['menuButton'] != null) ...[
        const SizedBox(height: 12),
        Text(
          'Menu button: ${plugin.telegram!['menuButton']['text'] ?? 'Commands'}',
        ),
      ],
      for (final target in webAppTargets(
        telegram: plugin.telegram,
        actionConfigs: plugin.automations.expand(
          (a) => a.actions.map((c) => c.config),
        ),
      ).map(_destination).toSet()) ...[
        const SizedBox(height: 8),
        Text('Mini App: $target'),
      ],
      for (final automation in plugin.automations) ...[
        const SizedBox(height: 12),
        Text(automationSummary(automation)),
        if (automation.destinationField case final String field)
          Text(
            'Posts to Telegram chats: ${_fieldLabel(field)}'
            '${fields?[field]?.trim().isNotEmpty == true ? ' → ${fields![field]}' : ' (optional)'}',
          ),
        if (automation.enabledBySetting != null)
          Text(
            'Controlled by: ${plugin.settings.firstWhere((s) => s.key == automation.enabledBySetting).label}',
          ),
        for (final component in [
          automation.trigger,
          ...automation.actions,
        ]) ...[
          if (component.type == 'telegram.notify-admin.v1')
            const Text('Sends notifications to the configured admin.'),
          if (component.config['photo'] case final Map<String, dynamic> photo)
            Text(
              'Downloads photos: ${_fieldLabel(photo['originField'] as String)} → ${photo['path']}',
            ),
          for (final request in AutomationRegistry.standard.requestsFor(
            component,
          )) ...[
            Text('GET ${request['url']}'),
            for (final header
                in (request['headers'] as Map<String, dynamic>? ??
                        const <String, dynamic>{})
                    .entries)
              Text(_headerDescription(header)),
            if (request['authentication'] != null)
              Text(
                _authenticationDescription(
                  request['authentication'] as Map<String, dynamic>,
                ),
              ),
          ],
        ],
      ],
    ],
  );
}
