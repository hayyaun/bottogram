import 'dart:convert';

/// A configuration error is safe to show: it describes a field, never its value.
class BuilderFailure implements Exception {
  const BuilderFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract final class BuilderValues {
  static final reference = RegExp(r'\{\{\s*([a-zA-Z_][a-zA-Z0-9_.]*)\s*\}\}');
  static final name = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]{0,47}$');

  static dynamic lookup(Map<String, dynamic> values, String path) {
    dynamic current = values;
    for (final part in path.split('.')) {
      if (current is Map && current.containsKey(part)) {
        current = current[part];
      } else if (current is List && int.tryParse(part) != null) {
        final index = int.parse(part);
        if (index < 0 || index >= current.length) {
          throw BuilderFailure('Missing value: $path.');
        }
        current = current[index];
      } else {
        throw BuilderFailure('Missing value: $path.');
      }
    }
    if (current == null) throw BuilderFailure('Missing value: $path.');
    return current;
  }

  /// A complete reference preserves JSON types for API payloads and variables.
  static dynamic resolve(dynamic input, Map<String, dynamic> values) {
    if (input is Map) {
      return input.map(
        (key, value) => MapEntry(key.toString(), resolve(value, values)),
      );
    }
    if (input is List) return input.map((v) => resolve(v, values)).toList();
    if (input is! String) return input;
    final match = reference.firstMatch(input);
    if (match != null && match.start == 0 && match.end == input.length) {
      return lookup(values, match[1]!);
    }
    return text(input, values);
  }

  static String scalar(dynamic value) {
    if (value is! String && value is! num && value is! bool) {
      throw const BuilderFailure(
        'A text field requires a string, number or boolean. Select a specific result field.',
      );
    }
    return value.toString();
  }

  static dynamic stringFields(dynamic input, Map<String, dynamic> values) {
    if (input is String) return text(input, values);
    if (input is List) {
      return input.map((v) => stringFields(v, values)).toList();
    }
    if (input is Map) {
      return input.map((k, v) => MapEntry(k, stringFields(v, values)));
    }
    return input;
  }

  static String text(
    String input,
    Map<String, dynamic> values, {
    bool markdown = false,
  }) {
    final result = input.replaceAllMapped(reference, (match) {
      final value = scalar(lookup(values, match[1]!));
      if (!markdown) return value;
      // MarkdownV2 has different escaping rules inside code and link targets.
      // Scan authored syntax only: substituted values cannot open new entities.
      final before = input.substring(0, match.start);
      final context = _markdownContext(before);
      return escapeMarkdown(value, code: context == 1, link: context == 2);
    });
    if (result.contains('{{') || result.contains('}}')) {
      // Check authored input, not substituted content (which may contain braces).
      final rest = input.replaceAll(reference, '');
      if (rest.contains('{{') || rest.contains('}}')) {
        throw const BuilderFailure(
          'Invalid variable reference. Use {{event.text}}, {{user.score}} or {{steps.name.body.field}}.',
        );
      }
    }
    return result;
  }

  static int _markdownContext(String source) {
    var code = 0, link = false;
    for (var i = 0; i < source.length; i++) {
      if (source[i] == '\\') {
        i++;
        continue;
      }
      if (source.startsWith('```', i)) {
        code = code == 3 ? 0 : (code == 0 ? 3 : code);
        i += 2;
      } else if (source[i] == '`' && code != 3) {
        code = code == 1 ? 0 : 1;
      } else if (code == 0 && source.startsWith('](', i)) {
        link = true;
        i++;
      } else if (code == 0 && source[i] == ')') {
        link = false;
      }
    }
    return code != 0 ? 1 : (link ? 2 : 0);
  }

  static String escapeMarkdown(
    String value, {
    bool code = false,
    bool link = false,
  }) {
    final specials = code
        ? r'\`'
        : link
        ? r'\)'
        : r'\_*[]()~`>#+-=|{}.!';
    return value.split('').map((c) => specials.contains(c) ? '\\$c' : c).join();
  }

  static bool matches(Map condition, Map<String, dynamic> values) =>
      _matches(condition, values, 0);

  static bool _matches(Map condition, Map<String, dynamic> values, int depth) {
    if (condition.containsKey('all')) {
      final all = condition['all'];
      if (depth >= 3 ||
          all is! List ||
          all.isEmpty ||
          all.length > 8 ||
          all.any((part) => part is! Map)) {
        throw const BuilderFailure('Invalid group of action conditions.');
      }
      return all.every((part) => _matches(part as Map, values, depth + 1));
    }
    var left = resolve(condition['left'] ?? '', values);
    var right = resolve(condition['right'] ?? '', values);
    if (left is num && right is String) right = num.tryParse(right) ?? right;
    if (right is num && left is String) left = num.tryParse(left) ?? left;
    if (left is bool && right is String && {'true', 'false'}.contains(right)) {
      right = right == 'true';
    }
    if (right is bool && left is String && {'true', 'false'}.contains(left)) {
      left = left == 'true';
    }
    return switch (condition['operator'] ?? 'equals') {
      'equals' => left == right,
      'notEquals' => left != right,
      'contains' => scalar(left).contains(scalar(right)),
      'greater' => number(left) > number(right),
      'less' => number(left) < number(right),
      _ => throw const BuilderFailure('Unknown condition operator.'),
    };
  }

  static num number(dynamic value) {
    final number = value is num ? value : num.tryParse(value.toString());
    if (number == null || !number.isFinite) {
      throw const BuilderFailure(
        'A numeric operation requires a finite number.',
      );
    }
    return number;
  }

  static dynamic json(String source, Map<String, dynamic> values) =>
      resolve(decodeJson(source), values);

  static dynamic decodeJson(String source) {
    try {
      return jsonDecode(source);
    } on FormatException {
      throw const BuilderFailure(
        'Invalid JSON. Put variable references inside JSON strings.',
      );
    }
  }
}
