import 'values.dart';

/// Literal matching only: creator input never becomes executable regular expressions.
abstract final class BuilderEventMatch {
  static List<String> splitInput(String input, Object? separator) =>
      separator is String && separator.isNotEmpty
      ? input.split(separator)
      : [input];

  static String? remainder(String input, String query, String mode) {
    return switch (mode) {
      'exact' => input == query ? '' : null,
      'prefix' =>
        query.isNotEmpty && input.startsWith(query)
            ? input.substring(query.length)
            : null,
      'any' => input.isNotEmpty && !input.startsWith('/') ? input : null,
      _ => throw const BuilderFailure('Unknown event matching mode.'),
    };
  }
}
