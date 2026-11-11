enum PluginSettingType { string, boolean, integer, number, choice }

class PluginSettingChoice {
  const PluginSettingChoice(this.value, this.label);
  final String value;
  final String label;
}

/// Editable, nonsecret preferences. Credentials belong in setupFields.
class PluginSetting {
  const PluginSetting({
    required this.key,
    required this.label,
    required this.type,
    required this.defaultValue,
    this.helpText,
    this.min,
    this.max,
    this.minLength = 0,
    this.maxLength = 4096,
    this.choices = const [],
  });

  final String key;
  final String label;
  final PluginSettingType type;
  final Object defaultValue;
  final String? helpText;
  final num? min;
  final num? max;
  final int minLength;
  final int maxLength;
  final List<PluginSettingChoice> choices;

  String? validate(Object? value) {
    switch (type) {
      case PluginSettingType.boolean:
        return value is bool ? null : 'Choose enabled or disabled.';
      case PluginSettingType.string:
        if (value is! String) return 'Enter text.';
        if (value.length < minLength) return 'Minimum length: $minLength.';
        if (value.length > maxLength) return 'Maximum length: $maxLength.';
        return null;
      case PluginSettingType.choice:
        return value is String && choices.any((c) => c.value == value)
            ? null
            : 'Choose one of the available options.';
      case PluginSettingType.integer:
      case PluginSettingType.number:
        if (value is! num ||
            !value.isFinite ||
            (type == PluginSettingType.integer && value is! int)) {
          return type == PluginSettingType.integer
              ? 'Enter a whole number.'
              : 'Enter a finite number.';
        }
        if (min != null && value < min!) return 'Minimum: $min.';
        if (max != null && value > max!) return 'Maximum: $max.';
        return null;
    }
  }

  Object? parseInput(String value) => switch (type) {
    PluginSettingType.integer => int.tryParse(value.trim()),
    PluginSettingType.number => num.tryParse(value.trim()),
    _ => value,
  };

  static PluginSetting parse(dynamic raw, Set<String> usedKeys) {
    Never invalid(String message) => throw FormatException(message);
    if (raw is! Map<String, dynamic>) invalid('Invalid plugin setting.');
    final data = raw;
    const allowed = {
      'key',
      'label',
      'type',
      'default',
      'helpText',
      'min',
      'max',
      'minLength',
      'maxLength',
      'options',
    };
    if (data.keys.any((key) => !allowed.contains(key))) {
      invalid('Unsupported plugin setting property.');
    }
    String text(dynamic value, int limit) {
      if (value is! String || value.trim().isEmpty || value.length > limit) {
        invalid('Invalid plugin setting text.');
      }
      return value.trim();
    }

    final key = text(data['key'], 64);
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(key) ||
        {
          'name',
          'token',
          'botToken',
          'adminTelegramUserId',
          'adminIds',
        }.contains(key) ||
        !usedKeys.add(key)) {
      invalid('Setting keys must be unique and distinct from creation fields.');
    }
    final type = switch (data['type']) {
      'string' => PluginSettingType.string,
      'boolean' => PluginSettingType.boolean,
      'integer' => PluginSettingType.integer,
      'number' => PluginSettingType.number,
      'enum' => PluginSettingType.choice,
      _ => null,
    };
    if (type == null ||
        !data.containsKey('default') ||
        data['default'] == null) {
      invalid('Every setting needs a supported type and typed default.');
    }
    final numeric =
        type == PluginSettingType.integer || type == PluginSettingType.number;
    final min = data['min'];
    final max = data['max'];
    if ((min != null && (min is! num || !min.isFinite)) ||
        (max != null && (max is! num || !max.isFinite)) ||
        (!numeric && (min != null || max != null)) ||
        (min is num && max is num && min > max) ||
        (type == PluginSettingType.integer &&
            ((min != null && min is! int) || (max != null && max is! int)))) {
      invalid('Invalid setting numeric bounds.');
    }
    final minLength = data['minLength'] ?? 0;
    final maxLength = data['maxLength'] ?? 4096;
    if (minLength is! int ||
        maxLength is! int ||
        minLength < 0 ||
        maxLength > 4096 ||
        minLength > maxLength ||
        (type != PluginSettingType.string &&
            (data.containsKey('minLength') || data.containsKey('maxLength')))) {
      invalid('Invalid setting text bounds.');
    }
    final choices = <PluginSettingChoice>[];
    if (type == PluginSettingType.choice) {
      final options = data['options'];
      if (options is! List || options.isEmpty || options.length > 32) {
        invalid('Enum settings need 1–32 options.');
      }
      final seen = <String>{};
      for (final option in options) {
        if (option is! Map<String, dynamic> ||
            option.keys.any((key) => !{'value', 'label'}.contains(key))) {
          invalid('Invalid setting option.');
        }
        final value = text(option['value'], 100);
        if (!seen.add(value)) invalid('Setting options must be unique.');
        choices.add(PluginSettingChoice(value, text(option['label'], 100)));
      }
    } else if (data.containsKey('options')) {
      invalid('Only enum settings accept options.');
    }
    final setting = PluginSetting(
      key: key,
      label: text(data['label'], 100),
      type: type,
      defaultValue: data['default'] as Object,
      helpText: data['helpText'] == null ? null : text(data['helpText'], 300),
      min: min as num?,
      max: max as num?,
      minLength: minLength,
      maxLength: maxLength,
      choices: List.unmodifiable(choices),
    );
    if (setting.validate(setting.defaultValue) != null) {
      invalid(
        'A setting default does not satisfy its declared type or bounds.',
      );
    }
    return setting;
  }
}
