import 'ports.dart';
import 'components.dart';
import 'triggers/http_list_poll.dart';
import 'telegram_config.dart';

typedef TriggerFactory =
    AutomationTrigger Function(Json config, RuntimeContext context);
typedef ActionFactory =
    AutomationAction Function(Json config, RuntimeContext context);
typedef ConfigValidator = void Function(Json config);
typedef RequestConfigurations = Iterable<Json> Function(Json config);

Iterable<Json> _requestConfiguration(Json config) sync* {
  if (config['request'] is Json) yield config['request'] as Json;
}

Iterable<Json> _listRequests(Json config) sync* {
  yield config['request'] as Json;
  if (config['lookup'] != null) yield config['lookup']['request'] as Json;
}

class ComponentRegistration<T> {
  const ComponentRegistration(
    this.validate,
    this.create, {
    this.requests = _requestConfiguration,
  });
  final ConfigValidator validate;
  final T create;
  final RequestConfigurations requests;
}

class ComponentDefinition {
  const ComponentDefinition(this.type, this.config, {this.id});
  final String type;
  final Json config;
  final String? id;
}

class AutomationDefinition {
  const AutomationDefinition(
    this.id,
    this.trigger,
    this.actions,
    this.enabledBySetting,
  );
  final String id;
  final ComponentDefinition trigger;
  final List<ComponentDefinition> actions;
  final String? enabledBySetting;
}

/// Schema and implementation share a registration. A type is never accepted
/// merely because a JSON file names it.
class AutomationRegistry {
  AutomationRegistry({required this.triggers, required this.actions});
  final Map<String, ComponentRegistration<TriggerFactory>> triggers;
  final Map<String, ComponentRegistration<ActionFactory>> actions;
  Iterable<Json> requestsFor(ComponentDefinition component) =>
      (triggers[component.type] ?? actions[component.type])!.requests(
        component.config,
      );
  // Built-in registrations follow the loaded code without resetting running
  // automations. Each runner retains the registry instance it started with.
  static AutomationRegistry get standard => AutomationRegistry(
    triggers: Map.unmodifiable({
      'http.poll.v1': ComponentRegistration(_poll, HttpPollTrigger.new),
      'http.poll-list.v1': ComponentRegistration(
        _listPoll,
        HttpListPollTrigger.new,
        requests: _listRequests,
      ),
      'telegram.command.v1': ComponentRegistration((c) {
        keys(c, {'command', 'arguments'});
        if (c['arguments'] != null && c['arguments'] != 'page') invalid();
        string(c['command'], 32);
        if (!RegExp(r'^[a-z][a-z0-9_]{0,31}$').hasMatch(c['command'])) {
          invalid();
        }
      }, TelegramCommandTrigger.new),
      'telegram.command.v2': ComponentRegistration((c) {
        keys(c, {'commands', 'chatTypes', 'arguments'});
        final commands = c['commands'];
        if (commands is! List ||
            commands.isEmpty ||
            commands.length > 16 ||
            commands.toSet().length != commands.length) {
          invalid();
        }
        for (final command in commands) {
          if (!RegExp(
            r'^[a-z][a-z0-9_]{0,31}$',
          ).hasMatch(string(command, 32))) {
            invalid();
          }
        }
        final chatTypes = c['chatTypes'];
        if (chatTypes is! List ||
            chatTypes.isEmpty ||
            chatTypes.length > 4 ||
            chatTypes.toSet().length != chatTypes.length ||
            chatTypes.any(
              (type) =>
                  !{'private', 'group', 'supergroup', 'channel'}.contains(type),
            )) {
          invalid();
        }
        if (c['arguments'] != 'ignore') invalid();
      }, TelegramCommandTrigger.new),
    }),
    actions: Map.unmodifiable({
      'http.get-json.v1': ComponentRegistration((c) {
        keys(c, {'request', 'resultKey', 'pagination'});
        if (c['pagination'] != null) {
          final p = object(c['pagination']);
          keys(p, {'pageSize'});
          if (p['pageSize'] is! int ||
              p['pageSize'] < 1 ||
              p['pageSize'] > 10) {
            invalid();
          }
        }
        _request(object(c['request']));
        identifier(c['resultKey']);
      }, HttpGetAction.new),
      'telegram.notify-admin.v1': ComponentRegistration(
        _message,
        (c, ctx) => TelegramMessageAction(c, ctx, adminOnly: true),
      ),
      'telegram.reply.v1': ComponentRegistration(
        _message,
        (c, ctx) => TelegramMessageAction(c, ctx, adminOnly: false),
      ),
      'telegram.reply.v2': ComponentRegistration((c) {
        keys(c, {'text', 'inlineKeyboard'});
        _template(c['text']);
        validateInlineKeyboard(c['inlineKeyboard']);
      }, (c, ctx) => TelegramMessageAction(c, ctx, adminOnly: false)),
    }),
  );

  List<AutomationDefinition> parse(dynamic raw) {
    if (raw is! List || raw.isEmpty || raw.length > 16) invalid();
    final ids = <String>{};
    final commands = <String>{};
    return List.unmodifiable(
      (raw).map((value) {
        final a = object(value);
        keys(a, {'id', 'enabledBySetting', 'trigger', 'actions'});
        identifier(a['id']);
        if (!ids.add(a['id'])) invalid();
        if (a['enabledBySetting'] != null) identifier(a['enabledBySetting']);
        ComponentDefinition component(dynamic raw, bool trigger) {
          final c = object(raw);
          keys(c, trigger ? {'type', 'config'} : {'id', 'type', 'config'});
          final type = string(c['type'], 100);
          final config = object(c['config']);
          final registration = trigger ? triggers[type] : actions[type];
          if (registration == null) {
            throw FormatException(
              'Unsupported ${trigger ? 'trigger' : 'action'} type: $type.',
            );
          }
          if (!trigger) identifier(c['id']);
          registration.validate(config);
          return ComponentDefinition(type, config, id: c['id'] as String?);
        }

        final t = component(a['trigger'], true);
        if (t.type == 'telegram.command.v1' ||
            t.type == 'telegram.command.v2') {
          for (final command
              in t.type == 'telegram.command.v1'
                  ? [t.config['command']]
                  : t.config['commands'] as List) {
            if (!commands.add(command as String)) invalid();
          }
        }
        final list = a['actions'];
        if (list is! List || list.isEmpty || list.length > 16) invalid();
        final actionIds = <String>{};
        final parsed = (list).map((v) => component(v, false)).toList();
        for (final action in parsed) {
          if (!actionIds.add(action.id!)) invalid();
          if ((action.type == 'telegram.reply.v1' ||
                  action.type == 'telegram.reply.v2') &&
              t.type != 'telegram.command.v1' &&
              t.type != 'telegram.command.v2') {
            throw const FormatException(
              'Reply actions require a Telegram command trigger.',
            );
          }
          if (action.type == 'telegram.reply.v2' &&
              (t.type != 'telegram.command.v2' ||
                  (t.config['chatTypes'] as List).length != 1 ||
                  (t.config['chatTypes'] as List).single != 'private')) {
            throw const FormatException(
              'Mini App replies require a private-chat command trigger.',
            );
          }
        }
        return AutomationDefinition(
          a['id'],
          t,
          List.unmodifiable(parsed),
          a['enabledBySetting'] as String?,
        );
      }),
    );
  }

  static Never invalid() =>
      throw const FormatException('Invalid automation configuration.');
  static Json object(dynamic v) {
    if (v is! Json) invalid();
    return v;
  }

  static void keys(Json c, Set<String> allowed) {
    if (c.keys.any((k) => !allowed.contains(k))) invalid();
  }

  static String string(dynamic v, int max) {
    if (v is! String || v.trim().isEmpty || v.length > max) invalid();
    return v;
  }

  static void identifier(dynamic v) {
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_-]{0,63}$').hasMatch(string(v, 64))) {
      invalid();
    }
  }

  static void path(dynamic v) {
    if (!RegExp(
      r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)*$',
    ).hasMatch(string(v, 200))) {
      invalid();
    }
  }

  static void _request(Json c, {Set<String>? pathParameters}) {
    keys(c, {
      'method',
      'url',
      'authentication',
      'headers',
      'storefrontUrlField',
    });
    if (c['method'] != 'GET') invalid();
    final u = Uri.tryParse(string(c['url'], 2048));
    if (u == null ||
        (u.scheme != 'https' &&
            !(u.scheme == 'http' &&
                {'127.0.0.1', '::1', '[::1]', 'localhost'}.contains(u.host))) ||
        u.host.isEmpty ||
        u.userInfo.isNotEmpty ||
        u.hasFragment ||
        c['url'].contains('{{')) {
      invalid();
    }
    if (pathParameters != null) {
      final found = <String>{};
      // Bind only complete path segments; credentials, scheme, host and query
      // are never populated by a lookup value or message template.
      if (u.authority.contains('{') ||
          u.authority.contains('}') ||
          u.query.contains('{') ||
          u.query.contains('}')) {
        invalid();
      }
      for (final segment in u.pathSegments) {
        final match = RegExp(
          r'^\{([a-zA-Z][a-zA-Z0-9_]*)\}$',
        ).firstMatch(segment);
        if (match != null) {
          if (!pathParameters.contains(match[1])) invalid();
          found.add(match[1]!);
        } else if (segment.contains('{') || segment.contains('}')) {
          invalid();
        }
      }
      if (found.length != pathParameters.length) invalid();
    }
    if (c['authentication'] != null) {
      final a = object(c['authentication']);
      keys(a, {'type', 'secretField'});
      if (a['type'] != 'bearer') invalid();
      identifier(a['secretField']);
    }
    if (c['storefrontUrlField'] != null) identifier(c['storefrontUrlField']);
    if (c['headers'] != null) {
      final h = object(c['headers']);
      for (final e in h.entries) {
        if (!{'origin', 'x-storefront-host'}.contains(e.key.toLowerCase())) {
          invalid();
        }
        final v = string(e.value, 2048);
        if (v.contains('\r') || v.contains('\n') || v.contains('{{')) invalid();
      }
    }
  }

  static void _poll(Json c) {
    keys(c, {
      'intervalSeconds',
      'initialSync',
      'request',
      'response',
      'pagination',
    });
    if (c['intervalSeconds'] is! int ||
        c['intervalSeconds'] < 30 ||
        c['intervalSeconds'] > 86400 ||
        !{'baseline', 'replay'}.contains(c['initialSync'])) {
      invalid();
    }
    _request(object(c['request']));
    final r = object(c['response']);
    keys(r, {'itemsPath', 'itemIdPath', 'checkpointPath'});
    for (final k in ['itemsPath', 'itemIdPath', 'checkpointPath']) {
      path(r[k]);
    }
    final p = object(c['pagination']);
    keys(p, {'cursorQueryParameter', 'nextPagePath', 'hasMorePath'});
    identifier(p['cursorQueryParameter']);
    path(p['nextPagePath']);
    path(p['hasMorePath']);
  }

  static void _listPoll(Json c) {
    keys(c, {
      'intervalSeconds',
      'initialSync',
      'lookup',
      'request',
      'response',
      'pagination',
      'filter',
    });
    if (c['intervalSeconds'] is! int ||
        c['intervalSeconds'] < 30 ||
        c['intervalSeconds'] > 86400 ||
        !{'baseline', 'replay'}.contains(c['initialSync'])) {
      invalid();
    }
    final parameters = <String>{};
    if (c['lookup'] != null) {
      final l = object(c['lookup']);
      keys(l, {'request', 'bindings'});
      _request(object(l['request']));
      final bindings = object(l['bindings']);
      if (bindings.isEmpty || bindings.length > 8) invalid();
      for (final e in bindings.entries) {
        identifier(e.key);
        path(e.value);
        parameters.add(e.key);
      }
    }
    _request(object(c['request']), pathParameters: parameters);
    final r = object(c['response']);
    keys(r, {'itemsPath', 'itemIdPath'});
    path(r['itemsPath']);
    path(r['itemIdPath']);
    final p = object(c['pagination']);
    keys(p, {
      'limitQueryParameter',
      'offsetQueryParameter',
      'pageSize',
      'maxPages',
      'pageDelaySeconds',
    });
    identifier(p['limitQueryParameter']);
    identifier(p['offsetQueryParameter']);
    if (p['limitQueryParameter'] == p['offsetQueryParameter'] ||
        p['pageSize'] is! int ||
        p['pageSize'] < 1 ||
        p['pageSize'] > 100 ||
        p['maxPages'] is! int ||
        p['maxPages'] < 1 ||
        p['maxPages'] > 10000 ||
        p['pageDelaySeconds'] is! int ||
        p['pageDelaySeconds'] < 1 ||
        p['pageDelaySeconds'] > 60) {
      invalid();
    }
    if (c['filter'] != null) {
      final f = object(c['filter']);
      keys(f, {'path', 'equals'});
      path(f['path']);
      final value = f['equals'];
      if (value is String) {
        string(value, 256);
      } else if (value is! bool && (value is! num || !value.isFinite)) {
        invalid();
      }
    }
  }

  static void _message(Json c) {
    keys(c, {'text', 'list'});
    _template(c['text']);
    if (c['list'] != null) {
      final l = object(c['list']);
      keys(l, {'itemsPath', 'itemText', 'emptyText'});
      path(l['itemsPath']);
      _template(l['itemText']);
      string(l['emptyText'], 500);
    }
  }

  static void _template(dynamic value) {
    final text = string(value, 4096);
    final remainder = text.replaceAll(
      RegExp(r'\{\{(event|item)\.[a-zA-Z0-9_.]+\}\}'),
      '',
    );
    if (remainder.contains('{{') || remainder.contains('}}')) invalid();
  }
}
