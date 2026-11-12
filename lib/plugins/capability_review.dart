import 'package:bottogram/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../runtime/telegram_presentation.dart';
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

String automationSummary(
  BuildContext context,
  AutomationDefinition automation,
) {
  final trigger = automation.trigger;
  if (trigger.type == 'telegram.command.v1') {
    return context.strings.automationAllChats(
      context.leftToRightText('/${trigger.config['command']}'),
    );
  }
  if (trigger.type == 'telegram.command.v2') {
    final commands = (trigger.config['commands'] as List)
        .map((command) => '/$command')
        .join(' · ');
    final chats = (trigger.config['chatTypes'] as List).join(', ');
    return context.strings.automationSelectedChats(
      context.leftToRightText(commands),
      chats,
    );
  }
  if (trigger.type == interactionTrigger) {
    final commands = _commands(
      trigger,
    ).map((command) => '/$command').join(' · ');
    if (commands.isEmpty) return context.strings.automationPrivateWidgets;
    final role = trigger.config['audience'] == 'admin'
        ? context.strings.automationAdminOnly
        : context.strings.automationPrivateChats;
    return '${context.leftToRightText(commands)} · $role';
  }
  return context.strings.automationScheduledChecks(
    trigger.config['intervalSeconds'].toString(),
  );
}

/// Reviews declarations for any plugin; no installed package is special-cased.
class PluginCapabilityReview extends StatelessWidget {
  const PluginCapabilityReview({super.key, required this.plugin, this.fields});
  final PluginManifest plugin;
  final Map<String, String>? fields;

  String _fieldLabel(String key) =>
      plugin.fields.firstWhere((field) => field.key == key).label;

  String _headerDescription(
    BuildContext context,
    MapEntry<String, dynamic> header,
  ) {
    final binding = header.value;
    if (binding is String) {
      return context.strings.automationLiteralHeader(header.key);
    }
    final transform = switch (binding['transform']) {
      'value' => context.strings.automationHeaderFieldValue,
      'url.origin' => context.strings.automationHeaderUrlOrigin,
      'url.authority' => context.strings.automationHeaderUrlAuthority,
      _ => context.strings.automationHeaderFieldValue,
    };
    return context.strings.automationMappedHeader(
      header.key,
      _fieldLabel(binding['field'] as String),
      transform,
    );
  }

  String _authenticationDescription(
    BuildContext context,
    Map<String, dynamic> authentication,
  ) {
    final method = authentication['type'] == 'bearer'
        ? context.strings.automationBearerToken
        : context.strings.automationCustomHeader(
            authentication['header'].toString(),
          );
    return context.strings.automationAuthentication(
      method,
      _fieldLabel(authentication['secretField'] as String),
    );
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
          context.strings.pluginMenuButton(
            '${plugin.telegram!['menuButton']['text'] ?? context.strings.commands}',
          ),
        ),
      ],
      for (final target in webAppTargets(
        telegram: plugin.telegram,
        actionConfigs: plugin.automations.expand(
          (a) => a.actions.map((c) => c.config),
        ),
      ).map(_destination).toSet()) ...[
        const SizedBox(height: 8),
        Text(context.strings.miniAppDestination(target)),
      ],
      for (final automation in plugin.automations) ...[
        const SizedBox(height: 12),
        Text(automationSummary(context, automation)),
        if (automation.destinationField case final String field)
          Text(
            context.strings.telegramDestinations(
              _fieldLabel(field),
              fields?[field]?.trim().isNotEmpty == true
                  ? ' → ${fields![field]}'
                  : context.strings.optionalDestinationSuffix,
            ),
          ),
        if (automation.enabledBySetting != null)
          Text(
            context.strings.automationEnabledBy(
              plugin.settings
                  .firstWhere((s) => s.key == automation.enabledBySetting)
                  .label,
            ),
          ),
        for (final component in [
          automation.trigger,
          ...automation.actions,
        ]) ...[
          if (component.type == 'telegram.notify-admin.v1')
            Text(context.strings.sendsNotificationsToAllConfiguredAdmins),
          for (final photo in presentationPhotos(component.config))
            Text(
              context.strings.automationPhotoRequest(
                _fieldLabel(photo['originField'] as String),
                '${photo['path']}',
              ),
            ),
          for (final request in AutomationRegistry.standard.requestsFor(
            component,
          )) ...[
            Text(
              context.strings.automationGetRequest(
                context.leftToRightText('${request['url']}'),
              ),
            ),
            for (final header
                in (request['headers'] as Map<String, dynamic>? ??
                        const <String, dynamic>{})
                    .entries)
              Text(_headerDescription(context, header)),
            if (request['authentication'] != null)
              Text(
                _authenticationDescription(
                  context,
                  request['authentication'] as Map<String, dynamic>,
                ),
              ),
          ],
        ],
      ],
    ],
  );
}
