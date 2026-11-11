import 'origin.dart';
import 'ports.dart';

void _keys(Json value, Set<String> allowed) {
  if (value.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('Unsupported Telegram configuration property.');
  }
}

Json _object(dynamic value) {
  if (value is! Json) {
    throw const FormatException('Invalid Telegram configuration object.');
  }
  return value;
}

void _label(dynamic value) {
  if (value is! String || value.trim().isEmpty || value.length > 64) {
    throw const FormatException(
      'Telegram button labels must contain 1–64 characters.',
    );
  }
}

bool validPathArgument(String value) =>
    RegExp(r'^[a-zA-Z0-9_-]{1,256}$').hasMatch(value);

void validateWebAppTarget(dynamic raw, {bool allowArgument = false}) {
  final target = _object(raw);
  _keys(target, {'originField', 'path', if (allowArgument) 'argumentPath'});
  final field = target['originField'];
  final rawPath = target['path'];
  final argumentPath = target['argumentPath'];
  if (argumentPath != null &&
      (argumentPath is! String ||
          !RegExp(
            r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)*$',
          ).hasMatch(argumentPath) ||
          rawPath is! String ||
          rawPath.split('/').where((s) => s == '{argument}').length != 1)) {
    throw const FormatException(
      'URL arguments must occupy a single path segment.',
    );
  }
  final path = argumentPath == null
      ? rawPath
      : (rawPath as String).replaceFirst('{argument}', 'argument');
  if (field is! String ||
      !RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,63}$').hasMatch(field) ||
      path is! String ||
      path.length > 2048 ||
      !path.startsWith('/') ||
      path.startsWith('//') ||
      RegExp(r'[\s\\{}]').hasMatch(path)) {
    throw const FormatException(
      'Mini App links require an origin field and a literal same-origin path.',
    );
  }
  final uri = Uri.tryParse(path);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException(
      'Mini App paths cannot include an authority, query or fragment.',
    );
  }
}

void validateInlineKeyboard(dynamic raw) {
  if (raw is! List || raw.isEmpty || raw.length > 8) {
    throw const FormatException('Inline keyboards require 1–8 rows.');
  }
  for (final row in raw) {
    if (row is! List || row.isEmpty || row.length > 8) {
      throw const FormatException('Inline keyboard rows require 1–8 buttons.');
    }
    for (final rawButton in row) {
      final button = _object(rawButton);
      _keys(button, {'text', 'webApp'});
      _label(button['text']);
      validateWebAppTarget(button['webApp']);
    }
  }
}

void validateTelegramConfig(dynamic raw) {
  final config = _object(raw);
  _keys(config, {'menuButton', 'commands', 'adminCommands'});
  if (config.isEmpty) {
    throw const FormatException(
      'Telegram configuration requires a menu button or command list.',
    );
  }
  if (config.containsKey('menuButton')) {
    final menu = _object(config['menuButton']);
    if (menu['type'] == 'commands') {
      _keys(menu, {'type'});
    } else {
      _keys(menu, {'text', 'webApp'});
      _label(menu['text']);
      validateWebAppTarget(menu['webApp']);
    }
  }
  if (config.containsKey('commands') || config.containsKey('adminCommands')) {
    final public = config['commands'];
    final admin = config['adminCommands'] ?? const [];
    if (public is! List || public.isEmpty || admin is! List) {
      throw const FormatException('Telegram command lists must be arrays.');
    }
    final commands = [...public, ...admin];
    if (commands.length > 100) {
      throw const FormatException(
        'Telegram command lists require 1–100 commands.',
      );
    }
    final names = <String>{};
    for (final rawCommand in commands) {
      final entry = _object(rawCommand);
      _keys(entry, {'command', 'description'});
      final command = entry['command'];
      final description = entry['description'];
      if (command is! String ||
          !RegExp(r'^[a-z0-9_]{1,32}$').hasMatch(command) ||
          !names.add(command)) {
        throw const FormatException(
          'Telegram commands must have unique names of 1–32 lowercase letters, digits or underscores.',
        );
      }
      if (description is! String ||
          description.trim().isEmpty ||
          description.length > 256 ||
          RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(description)) {
        throw const FormatException(
          'Telegram command descriptions require 1–256 characters without control characters.',
        );
      }
    }
  }
}

Iterable<Json> inlineKeyboardTargets(dynamic keyboard) sync* {
  for (final row in keyboard as List) {
    for (final button in row as List) {
      yield (button as Json)['webApp'] as Json;
    }
  }
}

Iterable<Json> webAppTargets({
  Json? telegram,
  Iterable<Json> actionConfigs = const [],
}) sync* {
  final menu = telegram?['menuButton'] as Json?;
  if (menu?['webApp'] is Json) yield menu!['webApp'] as Json;
  for (final config in actionConfigs) {
    if (config['inlineKeyboard'] != null) {
      yield* inlineKeyboardTargets(config['inlineKeyboard']);
    }
    for (final keyboard in [
      config['keyboard'],
      (config['list'] as Json?)?['keyboard'],
    ]) {
      for (final row in keyboard as List? ?? const []) {
        for (final button in row as List) {
          if (button is Json && button['webApp'] is Json) {
            yield button['webApp'] as Json;
          }
        }
      }
    }
  }
}

String resolveWebAppTarget(
  Json target,
  Map<String, String> fields, {
  Json? event,
}) {
  final value = fields[target['originField']] ?? '';
  final origin = parseConfiguredOrigin(value, requireHttps: true);
  if (origin == null) {
    throw const RuntimeFailure(
      'The Mini App link needs a valid HTTPS origin in the plugin parameters.',
      code: 'configuration.invalid_public_origin',
      permanent: true,
    );
  }
  var path = target['path'] as String;
  if (target['argumentPath'] != null && event != null) {
    final argument = valueAt(event, target['argumentPath'] as String);
    if (argument is! String || !validPathArgument(argument)) {
      throw const RuntimeFailure('A URL path argument is invalid.');
    }
    path = path.replaceFirst('{argument}', argument);
  }
  final resolved = Uri.parse(origin.origin).resolve(path);
  if (resolved.origin != origin.origin) {
    throw const RuntimeFailure(
      'The Mini App link must stay on its configured origin.',
      code: 'configuration.invalid_public_origin',
      permanent: true,
    );
  }
  return resolved.toString();
}

Json resolveInlineKeyboard(dynamic keyboard, Map<String, String> fields) => {
  'inline_keyboard': [
    for (final row in keyboard as List)
      [
        for (final rawButton in row as List)
          {
            'text': (rawButton as Json)['text'],
            'web_app': {
              'url': resolveWebAppTarget(rawButton['webApp'] as Json, fields),
            },
          },
      ],
  ],
};
