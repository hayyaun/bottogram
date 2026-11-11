import 'dart:async';
import 'dart:convert';

import 'components.dart';
import 'ports.dart';
import 'registry.dart';

const interactionTrigger = 'telegram.interaction.v1';
final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final _page = RegExp(r'^[1-9][0-9]{0,3}$');

Iterable<Json> interactionRoutes(Json config) =>
    (config['routes'] as List).cast<Json>();

void validateInteraction(Json config) {
  final routes = config['routes'];
  AutomationRegistry.keys(config, {'routes', 'audience', 'failureText'});
  AutomationRegistry.string(config['failureText'], 500);
  if (!{null, 'admin', 'visitor'}.contains(config['audience']) ||
      routes is! List ||
      routes.isEmpty ||
      routes.length > 12) {
    AutomationRegistry.invalid();
  }
  for (final route in routes.map(AutomationRegistry.object)) {
    AutomationRegistry.keys(route, {'kind', 'name', 'prefix', 'argument'});
    final name = AutomationRegistry.string(route['name'], 32);
    if (!RegExp(r'^[a-z][a-z0-9_-]{0,31}$').hasMatch(name) ||
        !{'command', 'callback', 'widget'}.contains(route['kind']) ||
        !{'none', 'page', 'uuid'}.contains(route['argument']) ||
        route['kind'] == 'command' && name.contains('-')) {
      AutomationRegistry.invalid();
    }
    final prefix = route['prefix'];
    if (prefix != null &&
        (route['kind'] != 'command' ||
            route['argument'] == 'none' ||
            !RegExp(
              r'^[a-z0-9_]{1,20}$',
            ).hasMatch(AutomationRegistry.string(prefix, 20)))) {
      AutomationRegistry.invalid();
    }
  }
}

class TelegramInteractionTrigger extends TelegramEventTrigger {
  TelegramInteractionTrigger(Json config, RuntimeContext context) {
    for (final route in interactionRoutes(config)) {
      final kind = route['kind'] as String;
      final name = route['name'] as String;
      final prefix = route['prefix'] as String? ?? '';
      final argument = route['argument'];
      void receive(Json event) {
        if (isClosed ||
            event['chatType'] != 'private' ||
            event['senderId'] is! String ||
            event['senderId'] != event['chatId'] ||
            (config['audience'] == 'admin' &&
                event['senderId'] != context.adminId) ||
            (config['audience'] == 'visitor' &&
                event['senderId'] == context.adminId)) {
          return;
        }
        final args = event['arguments'] as List? ?? const [];
        if (args.length > 1) return;
        var input = args.firstOrNull as String? ?? '';
        if (utf8.encode(input).length > 64) return;
        if (kind != 'command') {
          if (argument == 'none') {
            if (input != name) return;
            input = '';
          } else {
            if (!input.startsWith('$name:')) return;
            input = input.substring(name.length + 1);
            if (input.isEmpty) return;
          }
        }
        if (!input.startsWith(prefix)) return;
        input = input.substring(prefix.length);
        final parsed = switch (argument) {
          'none' when input.isEmpty => const <String, dynamic>{},
          'page' when input.isEmpty => const {'page': 1},
          'page' when _page.hasMatch(input) => {'page': int.parse(input)},
          'uuid' when _uuid.hasMatch(input) => {'argument': input},
          _ => null,
        };
        if (parsed == null) return;
        if (!enqueue({...event, ...parsed})) {
          unawaited(
            context.telegram
                .send(
                  event['chatId'] as String,
                  config['failureText'] as String,
                )
                .catchError((Object _) {}),
          );
        }
      }

      if (kind == 'command') {
        context.telegram.command(name, receive);
      } else {
        context.interactions.interaction(kind, receive);
      }
    }
  }
}
