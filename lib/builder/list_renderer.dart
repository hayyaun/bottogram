import 'dart:convert';
import 'engine.dart';
import 'values.dart';

/// Formats bounded lists without evaluating code or executing nested actions.
abstract final class BuilderListRenderer {
  static BuilderJson render(BuilderStep step, BuilderJson values) {
    final config = step.config;
    final items = BuilderValues.resolve(config['items'] ?? '', values);
    if (items is! List || items.length > 50) {
      throw const BuilderFailure(
        'Render list requires an array of at most 50 items. Use pagination for larger lists.',
      );
    }
    final rows = <List<Map<String, dynamic>>>[];
    final parts = <String>[];
    final layout = config['richLayout'];
    final itemBlocks = <Map<String, dynamic>>[];
    final pictures = <String>[];
    final columns = layout is Map ? layout['columns'] as Map? : null;
    final cells = <List<dynamic>>[if (columns != null) columns.keys.toList()];
    for (final (index, item) in items.indexed) {
      final local = <String, dynamic>{
        ...values,
        'item': item,
        'index': index + 1,
      };
      parts.add(BuilderValues.text(step.text, local));
      if (columns != null) {
        cells.add([
          for (final source in columns.values)
            BuilderValues.text(source.toString(), local),
        ]);
      }
      final blocks = layout is Map ? layout['rowBlocks'] : null;
      if (blocks is List) {
        itemBlocks.addAll(
          (BuilderValues.resolve(blocks, local) as List)
              .cast<Map<String, dynamic>>(),
        );
      }
      final hosts = layout is Map ? layout['photoHosts'] : null;
      if (layout is Map && item is Map && hosts is List) {
        final source = item[layout['photoField']];
        final uri = source is String ? Uri.tryParse(source) : null;
        if (uri != null &&
            uri.scheme == 'https' &&
            uri.userInfo.isEmpty &&
            hosts.contains(uri.host) &&
            pictures.length < 5) {
          pictures.add(uri.toString());
        }
      }
      final buttons = BuilderValues.json(
        config['buttons']?.toString() ?? '[]',
        local,
      );
      if (buttons is! List || buttons.length > 8) {
        throw const BuilderFailure(
          'Each list item may have at most eight buttons.',
        );
      }
      if (buttons.isNotEmpty) rows.add(buttons.map(_button).toList());
    }
    final footer = BuilderValues.json(
      config['footerButtons']?.toString() ?? '[]',
      values,
    );
    if (footer is! List || footer.length > 8) {
      throw const BuilderFailure('Use at most eight footer button rows.');
    }
    for (final row in footer) {
      if (row is! List || row.isEmpty || row.length > 8) {
        throw const BuilderFailure(
          'Each footer row needs one to eight buttons.',
        );
      }
      rows.add(row.map(_button).toList());
    }
    String text(String key, [String fallback = '']) =>
        BuilderValues.text(config[key]?.toString() ?? fallback, values);
    final body = items.isEmpty
        ? text('emptyText', 'No results yet.')
        : parts.join(text('separator', '\n'));
    final result = '${text('header')}$body${text('footer')}';
    if (result.length > 4096 || utf8.encode(jsonEncode(rows)).length > 65536) {
      throw const BuilderFailure(
        'Rendered content is too large. Use a smaller page.',
      );
    }
    final header = text('header').trim().split('\n');
    final footerText = text('footer').trim();
    final richButtons = layout is Map && layout['buttonsInMessage'] == true;
    return {
      if (layout is Map)
        'rich': [
          if (header.first.isNotEmpty)
            {'type': 'heading', 'text': header.first},
          if (header.length > 1)
            {'type': 'paragraph', 'text': header.skip(1).join('\n')},
          if (items.isEmpty)
            {'type': 'paragraph', 'text': body}
          else if (columns != null)
            {'type': 'table', 'rows': cells}
          else if (itemBlocks.isNotEmpty)
            ...itemBlocks
          else
            {'type': 'list', 'items': parts},
          if (pictures.length == 1) {'type': 'photo', 'url': pictures.single},
          if (pictures.length > 1) {'type': 'collage', 'urls': pictures},
          if (footerText.isNotEmpty) {'type': 'footer', 'text': footerText},
          if (richButtons)
            for (final row in rows) {'type': 'buttons', 'buttons': row},
        ],
      'ok': true,
      'text': result,
      'count': items.length,
      'keyboard': {'inline_keyboard': richButtons ? [] : rows},
    };
  }

  static Map<String, dynamic> _button(dynamic input) {
    if (input is! Map ||
        input['text'] is! String ||
        (input['text'] as String).isEmpty) {
      throw const BuilderFailure('A rendered button needs a text label.');
    }
    final data = input['callback_data'], url = input['url'];
    if ((data == null) == (url == null) ||
        input.keys.any((k) => !{'text', 'callback_data', 'url'}.contains(k))) {
      throw const BuilderFailure(
        'A rendered button needs either callback data or an HTTP(S) URL.',
      );
    }
    if (data != null &&
        (data is! String ||
            utf8.encode(data).isEmpty ||
            utf8.encode(data).length > 64)) {
      throw const BuilderFailure(
        'Button callback data must contain 1–64 UTF-8 bytes.',
      );
    }
    if (url != null) {
      final uri = url is String ? Uri.tryParse(url) : null;
      if (uri == null ||
          !{'http', 'https'}.contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const BuilderFailure(
          'Button URLs require HTTP(S) and a hostname.',
        );
      }
    }
    return Map<String, dynamic>.from(input);
  }
}
