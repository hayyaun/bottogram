import 'ports.dart';

/// Presentation never changes the execution/retry policy of a RuntimeFailure.
class FailurePresentation {
  const FailurePresentation({
    required this.code,
    required this.title,
    required this.message,
    this.help,
    this.action,
    this.hostNotice,
  });

  final String code;
  final String title;
  final String message;
  final String? help;
  final String? action;
  final String? hostNotice;
}

final _resourceId = RegExp(r'^[a-zA-Z][a-zA-Z0-9_.-]{0,63}$');
final _failureCode = RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$');

String _text(dynamic value, String field, int limit) {
  if (value is! String || value.trim().isEmpty || value.length > limit) {
    throw FormatException('Invalid plugin error $field.');
  }
  if (value.contains('{{') || value.contains('}}') || value.contains(r'${')) {
    throw const FormatException(
      'Plugin error text does not support interpolation.',
    );
  }
  return value;
}

Json parseErrorMessages(dynamic raw) {
  if (raw == null) return const {};
  if (raw is! Json || raw.length > 64) {
    throw const FormatException(
      'errorMessages must contain at most 64 resources.',
    );
  }
  final result = <String, dynamic>{};
  for (final entry in raw.entries) {
    if (!_resourceId.hasMatch(entry.key) || entry.value is! Json) {
      throw const FormatException('Invalid plugin error resource.');
    }
    final value = entry.value as Json;
    if (value.keys.any(
      (key) => !{'title', 'message', 'help', 'action'}.contains(key),
    )) {
      throw const FormatException(
        'Unsupported plugin error presentation property.',
      );
    }
    final action = value['action'];
    if (action != null && !{'editPluginParameters', 'retry'}.contains(action)) {
      throw const FormatException('Unsupported plugin error action.');
    }
    result[entry.key] = Map<String, dynamic>.unmodifiable({
      'title': _text(value['title'], 'title', 100),
      'message': _text(value['message'], 'message', 2000),
      if (value['help'] != null) 'help': _text(value['help'], 'help', 2000),
      if (action != null) 'action': action,
    });
  }
  return Map<String, dynamic>.unmodifiable(result);
}

Map<String, String> validateErrorMap(dynamic raw) {
  if (raw == null) return const {};
  if (raw is! Json || raw.length > 64) {
    throw const FormatException('errorMap must contain at most 64 mappings.');
  }
  final result = <String, String>{};
  for (final entry in raw.entries) {
    if (!_failureCode.hasMatch(entry.key) ||
        entry.value is! String ||
        !_resourceId.hasMatch(entry.value as String)) {
      throw const FormatException('Invalid plugin error mapping.');
    }
    result[entry.key] = entry.value as String;
  }
  return Map<String, String>.unmodifiable(result);
}

FailurePresentation renderFailure(
  RuntimeFailure error,
  Json catalog,
  Map<String, String> mapping,
) {
  final notice = error.code == 'telegram.delivery_unconfirmed'
      ? 'Telegram may already have delivered this message. Retrying can send it again.'
      : null;
  final resource = catalog[mapping[error.code]];
  if (resource is Json) {
    return FailurePresentation(
      code: error.code,
      title: resource['title'] as String,
      message: resource['message'] as String,
      help: resource['help'] as String?,
      action: resource['action'] as String?,
      hostNotice: notice,
    );
  }
  return FailurePresentation(
    code: error.code,
    title: 'Automation issue',
    message: error.message,
    hostNotice: notice,
  );
}
