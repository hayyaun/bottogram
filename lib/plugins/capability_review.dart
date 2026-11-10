import 'package:flutter/material.dart';

import '../runtime/registry.dart';
import '../runtime/telegram_config.dart';
import 'manifest.dart';

List<String> pluginCommands(PluginManifest manifest) => [
  for (final automation in manifest.automations)
    if (automation.trigger.type == 'telegram.command.v1')
      automation.trigger.config['command'] as String
    else if (automation.trigger.type == 'telegram.command.v2')
      ...List<String>.from(automation.trigger.config['commands'] as List),
];

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
  return 'Scheduled checks · every ${trigger.config['intervalSeconds']} seconds';
}

/// Reviews declarations for any plugin; no installed package is special-cased.
class PluginCapabilityReview extends StatelessWidget {
  const PluginCapabilityReview({super.key, required this.plugin, this.fields});
  final PluginManifest plugin;
  final Map<String, String>? fields;

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
        Text('Menu button: ${plugin.telegram!['menuButton']['text']}'),
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
          for (final request in AutomationRegistry.standard.requestsFor(
            component,
          ))
            Text('GET ${request['url']}'),
        ],
      ],
    ],
  );
}
