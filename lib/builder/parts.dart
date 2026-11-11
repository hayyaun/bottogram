import 'dart:convert';
import 'dart:math';

import '../units/virt_act.dart';
import 'values.dart';

/// Named list layouts and keyboard rows stored alongside the action library.
class BuilderParts {
  BuilderParts([Map? data])
    : lists = _entries(data?['lists']),
      rows = _entries(data?['rows']);

  static const listDefaults = <String, String>{
    'header': '',
    'separator': '\n',
    'emptyText': 'No results yet.',
    'footer': '',
    'buttons': '[]',
    'footerButtons': '[]',
    'itemData': '',
  };
  static final listFields = {...listDefaults.keys, 'richLayout'};
  static const inline = 'inline_keyboard';
  static const reply = 'keyboard';
  final Map<String, Map<String, dynamic>> lists, rows;

  static Map<String, Map<String, dynamic>> _entries(Object? raw) => {
    if (raw is Map)
      for (final entry in raw.entries)
        entry.key as String: Map<String, dynamic>.from(entry.value as Map),
  };

  static String newId() {
    final random = Random.secure();
    return base64Url.encode(List.generate(12, (_) => random.nextInt(256)));
  }

  bool get isEmpty => lists.isEmpty && rows.isEmpty;
  Map<String, dynamic> toJson() => {'lists': lists, 'rows': rows};

  static Map<String, dynamic> list(String label, VirtAct act) => {
    'label': label,
    'text': act.text,
    'config': {
      for (final key in listFields)
        if (act.config.containsKey(key)) key: act.config[key],
    },
  };

  static bool sameList(
    Map<String, dynamic> first,
    Map<String, dynamic> second,
  ) {
    Map<String, dynamic> normalized(Map<String, dynamic> definition) {
      final config = Map<String, dynamic>.from(definition['config'] as Map);
      return {
        'label': definition['label'],
        'text': definition['text'],
        'config': {
          for (final entry in listDefaults.entries)
            entry.key: config[entry.key] ?? entry.value,
          if (config.containsKey('richLayout'))
            'richLayout': config['richLayout'],
        },
      };
    }

    return jsonEncode(normalized(first)) == jsonEncode(normalized(second));
  }

  static Map<String, dynamic> row(String label, String kind, List buttons) {
    if (!{inline, reply}.contains(kind) ||
        buttons.isEmpty ||
        buttons.length > 8 ||
        buttons.any(
          (button) =>
              button is! Map ||
              button['text'] is! String ||
              (button['text'] as String).trim().isEmpty ||
              (kind == inline &&
                  (button['callback_data'] is String) ==
                      (button['url'] is String)),
        )) {
      throw const BuilderFailure(
        'A row needs one to eight buttons with labels and valid actions.',
      );
    }
    return {'label': label, 'kind': kind, 'buttons': buttons};
  }

  List resolveRow(Object? raw, String kind) {
    if (raw is List) return raw;
    if (raw is Map && raw.length == 1 && raw['ref'] is String) {
      final row = rows[raw['ref']];
      if (row != null && row['kind'] == kind) return row['buttons'] as List;
    }
    throw const BuilderFailure(
      'A linked button row is missing or has the wrong keyboard type.',
    );
  }

  /// Keep the item source, output name, and execution controls at each placement.
  VirtAct expandList(VirtAct action) {
    final id = action.config['sharedList'];
    if (id == null) return action;
    final list = lists[id];
    if (action.type != VirtActType.renderList || list == null) {
      throw const BuilderFailure('The linked list could not be loaded.');
    }
    return VirtAct(type: action.type, text: list['text'] as String)
      ..rmu = action.rmu
      ..config = {
        ...Map.of(action.config)
          ..removeWhere((key, _) => listFields.contains(key)),
        ...Map<String, dynamic>.from(list['config'] as Map),
      };
  }

  VirtAct resolve(VirtAct placement) {
    final action = expandList(placement);
    final config = Map.of(action.config)..remove('sharedList');
    if (action.type == VirtActType.renderList) {
      final itemRow = _decode(config['buttons']);
      if (itemRow is Map && itemRow.containsKey('ref')) {
        config['buttons'] = jsonEncode(resolveRow(itemRow, inline));
      }
      final footer = _decode(config['footerButtons']);
      if (footer is List && footer.any((row) => row is Map)) {
        config['footerButtons'] = jsonEncode([
          for (final row in footer) resolveRow(row, inline),
        ]);
      }
    }
    var markup = action.rmu;
    final keyboard = config['keyboard'];
    if (keyboard is Map) {
      for (final kind in [inline, reply]) {
        final rows = keyboard[kind];
        if (rows is! List || rows.isEmpty) continue;
        final manual = markup?.hydrate().toJson();
        if (manual != null && manual[kind] is! List) {
          throw const BuilderFailure(
            'Use the same keyboard type for local and linked rows.',
          );
        }
        config['keyboard'] = {
          ...?manual,
          ...keyboard,
          kind: [
            if (manual != null) ...(manual[kind] as List),
            for (final row in rows) resolveRow(row, kind),
          ],
        };
        markup = null;
        break;
      }
    }
    return VirtAct(type: action.type, text: action.text)
      ..config = config
      ..rmu = markup;
  }

  static Object? _decode(Object? raw) {
    if (raw is! String || raw.isEmpty) return raw;
    try {
      return jsonDecode(raw);
    } on FormatException {
      // Let the renderer report its usual field error.
      return null;
    }
  }
}
