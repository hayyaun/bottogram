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

void validateWebAppTarget(dynamic raw) {
  final target = _object(raw);
  _keys(target, {'originField', 'path'});
  final field = target['originField'];
  final path = target['path'];
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
  _keys(config, {'menuButton'});
  final menu = _object(config['menuButton']);
  _keys(menu, {'text', 'webApp'});
  _label(menu['text']);
  validateWebAppTarget(menu['webApp']);
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
  if (telegram != null) {
    yield (telegram['menuButton'] as Json)['webApp'] as Json;
  }
  for (final config in actionConfigs) {
    if (config['inlineKeyboard'] != null) {
      yield* inlineKeyboardTargets(config['inlineKeyboard']);
    }
  }
}

String resolveWebAppTarget(Json target, Map<String, String> fields) {
  final value = fields[target['originField']] ?? '';
  final origin = parseConfiguredOrigin(value, requireHttps: true);
  if (origin == null) {
    throw const RuntimeFailure(
      'The Mini App link needs a valid HTTPS origin in the plugin parameters.',
      code: 'configuration.invalid_public_origin',
      permanent: true,
    );
  }
  final resolved = Uri.parse(origin.origin).resolve(target['path'] as String);
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
