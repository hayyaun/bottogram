import 'origin.dart';
import 'ports.dart';

const _transportHeaders = {
  'host',
  'content-length',
  'transfer-encoding',
  'connection',
  'proxy-connection',
  'keep-alive',
  'te',
  'trailer',
  'upgrade',
  'expect',
};

const _sessionHeaders = {
  'cookie',
  'cookie2',
  'set-cookie',
  'set-cookie2',
  'proxy-authorization',
  'proxy-authenticate',
};

bool _validName(dynamic value) =>
    value is String &&
    value.isNotEmpty &&
    value.length <= 128 &&
    RegExp(r"^[!#$%&'*+.^_`|~0-9a-zA-Z-]+$").hasMatch(value);

bool validHttpHeaderValue(String value) =>
    value.length <= 8192 && !RegExp(r'[^\x09\x20-\x7e]').hasMatch(value);

bool _validField(dynamic value) =>
    value is String && RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,63}$').hasMatch(value);

Never _invalid() =>
    throw const FormatException('Invalid HTTP header configuration.');

/// Public header values are literals or references to declared non-secret fields.
/// Credential values are configured separately and read only from secure storage.
void validateHttpHeaders(Json request) {
  final rawHeaders = request['headers'];
  if (rawHeaders != null && rawHeaders is! Json) _invalid();
  final headers = rawHeaders as Json? ?? const <String, dynamic>{};
  if (headers.length > 32) _invalid();
  final names = <String>{};
  for (final entry in headers.entries) {
    final name = entry.key.toLowerCase();
    if (!_validName(entry.key) ||
        !names.add(name) ||
        _transportHeaders.contains(name) ||
        _sessionHeaders.contains(name) ||
        name == 'authorization') {
      _invalid();
    }
    final value = entry.value;
    if (value is String) {
      if (!validHttpHeaderValue(value)) _invalid();
    } else if (value is Json) {
      if (value.keys.any((key) => !{'field', 'transform'}.contains(key)) ||
          !_validField(value['field']) ||
          !{
            'value',
            'url.origin',
            'url.authority',
          }.contains(value['transform'])) {
        _invalid();
      }
    } else {
      _invalid();
    }
  }
  final rawAuthentication = request['authentication'];
  if (rawAuthentication == null) return;
  if (rawAuthentication is! Json) _invalid();
  final authentication = rawAuthentication;
  if (authentication.keys.any(
        (key) => !{'type', 'header', 'secretField'}.contains(key),
      ) ||
      !_validField(authentication['secretField'])) {
    _invalid();
  }
  final String name;
  switch (authentication['type']) {
    case 'bearer':
      if (authentication.containsKey('header')) _invalid();
      name = 'authorization';
    case 'header':
      if (!_validName(authentication['header'])) _invalid();
      name = (authentication['header'] as String).toLowerCase();
    default:
      _invalid();
  }
  if (_transportHeaders.contains(name) ||
      _sessionHeaders.contains(name) ||
      !names.add(name) ||
      names.length > 32) {
    _invalid();
  }
}

Iterable<({String field, String transform})> headerFieldBindings(
  Json request,
) sync* {
  final headers = request['headers'] as Json? ?? const <String, dynamic>{};
  for (final value in headers.values) {
    if (value is Json) {
      yield (
        field: value['field'] as String,
        transform: value['transform'] as String,
      );
    }
  }
}

Uri _origin(String value) {
  final address = parseConfiguredOrigin(value);
  if (address == null) {
    throw const RuntimeFailure(
      'A header URL binding requires a valid HTTP or HTTPS origin in the plugin parameters.',
      code: 'http.invalid_origin',
      permanent: true,
    );
  }
  return address;
}

Future<Map<String, String>> resolveHttpHeaders(
  Json request,
  RuntimeContext context,
) async {
  try {
    validateHttpHeaders(request);
  } on FormatException {
    throw const RuntimeFailure(
      'The HTTP header configuration is invalid.',
      code: 'http.invalid_headers',
      permanent: true,
    );
  }
  final headers = <String, String>{};
  final rawHeaders = request['headers'] as Json? ?? const <String, dynamic>{};
  for (final entry in rawHeaders.entries) {
    final binding = entry.value;
    final String value;
    if (binding is String) {
      value = binding;
    } else {
      final field = context.fields[(binding as Json)['field']];
      if (field == null) {
        throw const RuntimeFailure(
          'A public header field is unavailable in the plugin parameters.',
          code: 'http.invalid_headers',
          permanent: true,
        );
      }
      value = switch (binding['transform']) {
        'value' => field,
        'url.origin' => _origin(field).origin,
        'url.authority' => _origin(field).authority,
        _ => throw const RuntimeFailure(
          'The HTTP header binding is invalid.',
          code: 'http.invalid_headers',
          permanent: true,
        ),
      };
    }
    if (!validHttpHeaderValue(value)) {
      throw const RuntimeFailure(
        'A configured HTTP header value is invalid.',
        code: 'http.invalid_headers',
        permanent: true,
      );
    }
    headers[entry.key] = value;
  }
  final authentication = request['authentication'] as Json?;
  if (authentication != null) {
    final String? secret;
    try {
      secret = await context.secret(authentication['secretField'] as String);
    } catch (_) {
      throw const RuntimeFailure(
        'The saved credential could not be read. Unlock secure storage and try again.',
        code: 'http.credentials_unavailable',
        permanent: true,
      );
    }
    if (secret == null || secret.isEmpty || !validHttpHeaderValue(secret)) {
      throw const RuntimeFailure(
        'The saved credential is unavailable or invalid. Check the plugin parameters.',
        code: 'http.credentials_unavailable',
        permanent: true,
      );
    }
    final bearer = authentication['type'] == 'bearer';
    final value = bearer ? 'Bearer $secret' : secret;
    if (!validHttpHeaderValue(value)) {
      throw const RuntimeFailure(
        'The saved credential exceeds the HTTP header limit.',
        code: 'http.credentials_unavailable',
        permanent: true,
      );
    }
    headers[bearer ? 'Authorization' : authentication['header'] as String] =
        value;
  }
  return headers;
}
