import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'http_request.dart';
import 'ports.dart';
import 'registry.dart';
import 'telegram_config.dart';
import 'telegram_destinations.dart';
import 'widget_thumbnails.dart';

const presentationAction = 'telegram.present.v1';
const statusAction = 'telegram.status.v1';

void _template(dynamic value, int max) {
  final template = AutomationRegistry.string(value, max);
  final rest = template.replaceAll(
    RegExp(r'\{\{(event|item)\.[a-zA-Z0-9_.]+\}\}'),
    '',
  );
  if (rest.contains('{{') || rest.contains('}}')) AutomationRegistry.invalid();
}

void _binding(dynamic raw) {
  final binding = AutomationRegistry.object(raw);
  AutomationRegistry.keys(binding, {'text', 'maxLength'});
  _template(binding['text'], 1000);
  final max = binding['maxLength'];
  if (max is! int || max < 1 || max > 1024) AutomationRegistry.invalid();
}

void _data(dynamic raw) {
  final data = AutomationRegistry.object(raw);
  if (data.length > 12) AutomationRegistry.invalid();
  for (final entry in data.entries) {
    AutomationRegistry.identifier(entry.key);
    _binding(entry.value);
  }
}

void _buttons(dynamic raw, {required bool channel}) {
  if (raw is! List || raw.isEmpty || raw.length > 8) {
    AutomationRegistry.invalid();
  }
  for (final row in raw) {
    if (row is! List || row.isEmpty || row.length > 4) {
      AutomationRegistry.invalid();
    }
    for (final button in row.map(AutomationRegistry.object)) {
      AutomationRegistry.keys(button, {
        'text',
        'when',
        'unless',
        'callback',
        'url',
        'deepLink',
        'webApp',
      });
      _template(button['text'], 150);
      if (button['when'] != null) AutomationRegistry.path(button['when']);
      if (button['unless'] != null) AutomationRegistry.path(button['unless']);
      final types = [
        'callback',
        'url',
        'deepLink',
        'webApp',
      ].where(button.containsKey).toList();
      if (types.length != 1 ||
          channel && {'callback', 'webApp'}.contains(types.single)) {
        AutomationRegistry.invalid();
      }
      switch (types.single) {
        case 'callback':
        case 'deepLink':
          _template(button[types.single], 150);
        case 'url':
          final url = Uri.tryParse(
            AutomationRegistry.string(button['url'], 2048),
          );
          if (url == null ||
              url.scheme != 'https' ||
              url.host.isEmpty ||
              url.userInfo.isNotEmpty) {
            AutomationRegistry.invalid();
          }
        case 'webApp':
          validateWebAppTarget(button['webApp'], allowArgument: true);
      }
    }
  }
}

Iterable<Json> presentationPhotos(Json config) sync* {
  if (config['photo'] case final Json photo) yield photo;
  if (config['widget']?['thumbnails']?['photo'] case final Json photo) {
    yield photo;
  }
}

Iterable<Json> presentationLookupRequests(Json config) sync* {
  if (config['list']?['lookup']?['request'] case final Json request) {
    yield request;
  }
}

void _validatePhoto(Json photo) {
  AutomationRegistry.keys(photo, {
    'originField',
    'path',
    'argumentPath',
    'itemsPath',
    'itemIdPath',
  });
  validateWebAppTarget({
    'originField': photo['originField'],
    'path': photo['path'],
    'argumentPath': photo['argumentPath'],
  }, allowArgument: true);
  if (photo['argumentPath'] != 'media') AutomationRegistry.invalid();
  AutomationRegistry.path(photo['itemsPath']);
  AutomationRegistry.path(photo['itemIdPath']);
}

void validatePresentation(Json config) {
  AutomationRegistry.keys(config, {
    'lines',
    'keyboard',
    'list',
    'widget',
    'photo',
    'channelField',
  });
  final lines = config['lines'];
  if (lines is! List || lines.isEmpty || lines.length > 12) {
    AutomationRegistry.invalid();
  }
  for (final line in lines.map(AutomationRegistry.object)) {
    AutomationRegistry.keys(line, {'text', 'maxLength', 'when', 'unless'});
    _binding({'text': line['text'], 'maxLength': line['maxLength']});
    if (line['when'] != null) AutomationRegistry.path(line['when']);
    if (line['unless'] != null) AutomationRegistry.path(line['unless']);
  }
  final channel = config['channelField'] != null;
  if (channel) {
    AutomationRegistry.identifier(config['channelField']);
    if (config['widget'] != null || config['list'] != null) {
      AutomationRegistry.invalid();
    }
  }
  if (config['keyboard'] != null) {
    _buttons(config['keyboard'], channel: channel);
  }
  if (config['widget'] != null) {
    final widget = AutomationRegistry.object(config['widget']);
    AutomationRegistry.keys(widget, {
      'html',
      'data',
      'editOnWidget',
      'thumbnails',
    });
    final html = AutomationRegistry.string(widget['html'], 32768);
    if (!widgetHtmlFits(html) ||
        widget['editOnWidget'] != null && widget['editOnWidget'] is! bool ||
        config['photo'] != null) {
      AutomationRegistry.invalid();
    }
    if (widget['thumbnails'] != null) {
      final thumbs = AutomationRegistry.object(widget['thumbnails']);
      AutomationRegistry.keys(thumbs, {'photo', 'allowWebp'});
      if (config['list'] == null ||
          thumbs['allowWebp'] != null && thumbs['allowWebp'] is! bool ||
          widget['editOnWidget'] == true ||
          html.split(widgetRowsSlot).length != 2) {
        AutomationRegistry.invalid();
      }
      _validatePhoto(AutomationRegistry.object(thumbs['photo']));
    }
    _data(widget['data']);
  }
  if (config['list'] != null) {
    final list = AutomationRegistry.object(config['list']);
    AutomationRegistry.keys(list, {
      'itemsPath',
      'data',
      'keyboard',
      'emptyText',
      'lookup',
    });
    AutomationRegistry.path(list['itemsPath']);
    AutomationRegistry.string(list['emptyText'], 200);
    _data(list['data']);
    if (list['lookup'] != null) {
      final lookup = AutomationRegistry.object(list['lookup']);
      AutomationRegistry.keys(lookup, {
        'request',
        'parameter',
        'itemIdPath',
        'minimum',
      });
      AutomationRegistry.object(lookup['request']);
      AutomationRegistry.identifier(lookup['parameter']);
      AutomationRegistry.path(lookup['itemIdPath']);
      if (lookup['minimum'] != null) {
        final minimum = AutomationRegistry.object(lookup['minimum']);
        AutomationRegistry.keys(minimum, {'itemsPath', 'valuePath'});
        AutomationRegistry.path(minimum['itemsPath']);
        AutomationRegistry.path(minimum['valuePath']);
      }
    }
    _buttons(list['keyboard'], channel: false);
  }
  if (config['photo'] != null) {
    _validatePhoto(AutomationRegistry.object(config['photo']));
  }
}

void validateTelegramStatus(Json config) {
  AutomationRegistry.keys(config, {
    'channelField',
    'setting',
    'channelLabels',
    'settingLabels',
    'photo',
  });
  if (config['photo'] != null &&
      (config['photo'] is! bool || config['channelField'] == null)) {
    AutomationRegistry.invalid();
  }
  if (config['channelField'] == null && config['setting'] == null) {
    AutomationRegistry.invalid();
  }
  if (config['channelField'] != null) {
    AutomationRegistry.identifier(config['channelField']);
    final labels = AutomationRegistry.object(config['channelLabels']);
    AutomationRegistry.keys(labels, {'unset', 'ready', 'denied'});
    for (final key in ['unset', 'ready', 'denied']) {
      AutomationRegistry.string(labels[key], 300);
    }
  } else if (config['channelLabels'] != null) {
    AutomationRegistry.invalid();
  }
  if (config['setting'] != null) {
    AutomationRegistry.identifier(config['setting']);
    final labels = AutomationRegistry.object(config['settingLabels']);
    AutomationRegistry.keys(labels, {'on', 'off'});
    AutomationRegistry.string(labels['on'], 300);
    AutomationRegistry.string(labels['off'], 300);
  } else if (config['settingLabels'] != null) {
    AutomationRegistry.invalid();
  }
}

class TelegramStatusAction implements AutomationAction {
  TelegramStatusAction(this.config, this.context);
  final Json config;
  final RuntimeContext context;

  @override
  Future<Json> execute(Json event) async {
    final field = config['channelField'] as String?;
    final labels = config['channelLabels'] as Json?;
    final destinations =
        parseTelegramDestinations(context.fields[field] ?? '') ?? const [];
    final checked = await Future.wait(
      destinations.map(
        (id) => context.interactions.canPost(
          id,
          chatTypes: context.destinationChatTypes[field] ?? const {'channel'},
          photo: config['photo'] == true,
        ),
      ),
    );
    final summary = checked.isEmpty
        ? 'unset'
        : checked.every((allowed) => allowed)
        ? 'ready'
        : 'denied';
    final on = context.settings[config['setting']] == true;
    return {
      ...event,
      'status': {
        'channel': labels?[summary],
        if (destinations.isNotEmpty)
          'destinations': [
            for (final (index, id) in destinations.indexed)
              '$id · ${labels![checked[index] ? 'ready' : 'denied']}',
          ].join('\n'),
        'setting': config['settingLabels']?[on ? 'on' : 'off'],
      },
    };
  }
}

String _truncate(String text, int length) =>
    String.fromCharCodes(text.runes.take(length));

bool _has(Json event, String path, {Object? item}) {
  final value = item != null && path.startsWith('item.')
      ? valueAt(item, path.substring(5))
      : valueAt(event, path);
  return value != null && value != false && value.toString().trim().isNotEmpty;
}

String _render(Json binding, Json event, {Object? item}) => _truncate(
  render(binding['text'] as String, event, item: item).trim(),
  binding['maxLength'] as int,
);

class TelegramPresentationAction implements AutomationAction {
  TelegramPresentationAction(this.config, this.context);
  final Json config;
  final RuntimeContext context;

  @override
  Future<Json> execute(Json event) async {
    final channelField = config['channelField'] as String?;
    final chat = channelField == null
        ? event['chatId'] as String
        : event['destinationChatId'] as String;
    final lines = [
      for (final line in (config['lines'] as List).cast<Json>())
        if ((line['when'] == null || _has(event, line['when'] as String)) &&
            (line['unless'] == null || !_has(event, line['unless'] as String)))
          _render(line, event),
    ];
    final list = config['list'] as Json?;
    var items = list == null
        ? const []
        : (valueAt(event, list['itemsPath'] as String) as List)
              .take(maxWidgetRows)
              .toList();
    if (list?['lookup'] case final Json lookup) {
      items = await _lookupItems(lookup, items);
    }
    if (list != null && items.isEmpty) lines.add(list['emptyText'] as String);
    final text = lines.where((line) => line.isNotEmpty).join('\n\n');
    final rows = _keyboard(config['keyboard'], event);
    final widget = config['widget'] as Json?;
    if (widget != null) {
      final data = _project(widget['data'] as Json, event);
      final thumbnails = widget['thumbnails'] as Json?;
      final projected = [
        if (list != null)
          for (final item in items)
            _project(list['data'] as Json, event, item: item),
      ];
      if (list != null && thumbnails == null) data['items'] = projected;
      if (utf8.encode(jsonEncode(data)).length <= 1024) {
        final template = widget['html'] as String;
        final content = thumbnails == null
            ? (html: template, data: data)
            : await embedWidgetRows(
                template,
                data,
                projected,
                await _loadThumbnails(thumbnails, items),
                allowWebp: thumbnails['allowWebp'] == true,
              );
        if (content != null) {
          await context.interactions.widget(
            {
              ...event,
              'editWidget': widget['editOnWidget'] == true,
              'replaceWidget': thumbnails != null,
            },
            content.html,
            content.data,
            _truncate(text, 1024),
            _markup(rows),
          );
          return event;
        }
      }
      // Large input uses the same text and inline actions without a widget.
    }
    if (list != null) {
      rows.insertAll(0, [
        for (final item in items)
          ..._keyboard(list['keyboard'], event, item: item),
      ]);
    }
    final photo = config['photo'] as Json?;
    if (photo != null) {
      final bytes = await _photo(photo, event);
      if (bytes != null) {
        await context.interactions.photo(
          chat,
          bytes,
          _truncate(text, 1024),
          _markup(rows),
        );
        return event;
      }
      if (channelField != null) throw const DeferDelivery(missingPhoto: true);
    }
    await context.telegram.send(
      chat,
      _truncate(text, 4096),
      replyMarkup: _markup(rows),
    );
    return event;
  }

  Future<List<dynamic>> _lookupItems(Json lookup, List<dynamic> items) {
    final request = HttpRequest(lookup['request'] as Json, context);
    return Future.wait(
      items.map((item) async {
        if (item is! Json) return item;
        final id = valueAt(item, lookup['itemIdPath'] as String);
        if (id is! String || !validPathArgument(id)) return item;
        try {
          final detail = await request
              .fetch(pathParameters: {lookup['parameter'] as String: id})
              .timeout(const Duration(seconds: 4));
          final minimum = lookup['minimum'] as Json?;
          final price = minimum == null ? null : minimumValue(detail, minimum);
          return {
            ...item,
            'detail': {...detail, if (price != null) 'minimum': price},
          };
        } on RuntimeFailure {
          return item;
        } on TimeoutException {
          return item;
        }
      }),
    );
  }

  Future<List<Uint8List?>> _loadThumbnails(Json config, List<dynamic> items) {
    final photo = config['photo'] as Json;
    return Future.wait(
      items.map((item) async {
        if (item is! Json) return null;
        try {
          return await _photo(
            photo,
            item,
            firstOnly: true,
          ).timeout(const Duration(seconds: 4), onTimeout: () => null);
        } on RuntimeFailure {
          return null;
        }
      }),
    );
  }

  Future<Uint8List?> _photo(
    Json photo,
    Json event, {
    bool firstOnly = false,
  }) async {
    final transport = context.http;
    final items = valueAt(event, photo['itemsPath'] as String);
    if (transport is! PhotoTransport || items is! List) return null;
    for (final item in firstOnly ? items.take(1) : items) {
      final id = valueAt(item, photo['itemIdPath'] as String);
      if (id is! String || !validPathArgument(id)) continue;
      final url = resolveWebAppTarget(
        photo,
        context.fields,
        event: {'media': id},
      );
      final bytes = await (transport as PhotoTransport).jpeg(Uri.parse(url));
      if (bytes != null) return bytes;
    }
    return null;
  }

  Json _project(Json bindings, Json event, {Object? item}) => {
    for (final entry in bindings.entries)
      entry.key: _render(entry.value as Json, event, item: item),
  };

  List<List<Json>> _keyboard(dynamic raw, Json event, {Object? item}) {
    final rows = <List<Json>>[];
    for (final row in raw as List? ?? const []) {
      final buttons = <Json>[];
      for (final button in (row as List).cast<Json>()) {
        if ((button['when'] != null &&
                !_has(event, button['when'] as String, item: item)) ||
            (button['unless'] != null &&
                _has(event, button['unless'] as String, item: item))) {
          continue;
        }
        final label = _truncate(
          render(button['text'], event, item: item).trim(),
          64,
        );
        if (label.isEmpty) continue;
        if (button['webApp'] != null) {
          buttons.add({
            'text': label,
            'web_app': {
              'url': resolveWebAppTarget(
                button['webApp'] as Json,
                context.fields,
                event: event,
              ),
            },
          });
        } else if (button['callback'] != null) {
          final data = render(button['callback'], event, item: item);
          if (data.isEmpty || utf8.encode(data).length > 64) continue;
          buttons.add({'text': label, 'callback_data': data});
        } else {
          final link = button['deepLink'] == null
              ? button['url'] as String
              : _deepLink(render(button['deepLink'], event, item: item));
          buttons.add({'text': label, 'url': link});
        }
      }
      if (buttons.isNotEmpty) rows.add(buttons);
    }
    return rows;
  }

  String _deepLink(String payload) {
    final username = context.interactions.username;
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(payload) ||
        !RegExp(r'^[a-zA-Z0-9_]{1,32}$').hasMatch(username)) {
      throw const RuntimeFailure('Invalid Telegram deep-link payload.');
    }
    return Uri.https('t.me', '/$username', {'start': payload}).toString();
  }

  Json? _markup(List<List<Json>> rows) =>
      rows.isEmpty ? null : {'inline_keyboard': rows};
}
