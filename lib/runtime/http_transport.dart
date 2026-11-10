import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'ports.dart';
import 'http_headers.dart' show validHttpHeaderValue;

void _validateOutgoingHeaders(Map<String, String> headers) {
  final names = headers.keys.map((name) => name.toLowerCase()).toSet();
  if (headers.length > 32 ||
      names.length != headers.length ||
      headers.entries.any(
        (entry) =>
            entry.key.length > 128 ||
            !RegExp(r"^[!#$%&'*+.^_`|~0-9a-zA-Z-]+$").hasMatch(entry.key) ||
            !validHttpHeaderValue(entry.value) ||
            {
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
            }.contains(entry.key.toLowerCase()),
      )) {
    throw const RuntimeFailure(
      'Invalid or reserved HTTP header.',
      code: 'http.invalid_headers',
      permanent: true,
    );
  }
}

RuntimeFailure _statusFailure(HttpClientResponse response) {
  final status = response.statusCode;
  final retry = int.tryParse(response.headers.value('retry-after') ?? '');
  final code = switch (status) {
    401 => 'http.unauthorized',
    403 => 'http.forbidden',
    408 => 'http.timeout',
    429 => 'http.rate_limited',
    _ => 'http.request_failed',
  };
  return RuntimeFailure(
    'HTTP request failed (status $status).',
    code: code,
    permanent: status >= 300 && status < 500 && !{408, 429}.contains(status),
    retryAfter: retry == null ? null : Duration(seconds: retry.clamp(1, 3600)),
  );
}

/// Each bot owns its client: Stop cancels its requests without affecting others.
class BoundedJsonTransport implements JsonTransport {
  BoundedJsonTransport({HttpClient? client}) : _client = client ?? HttpClient();
  final HttpClient _client;
  bool _closed = false;

  /// Shared transport for the user-facing builder. Responses and requests are
  /// bounded, redirects are not followed and writes are never auto-retried.
  Future<Json> request(
    String method,
    Uri url,
    Map<String, String> headers, {
    dynamic body,
  }) async {
    if (_closed) throw const RuntimeFailure('Bot stopped.');
    if (!{'GET', 'POST', 'PUT', 'PATCH', 'DELETE'}.contains(method) ||
        !{'http', 'https'}.contains(url.scheme) ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasFragment) {
      throw const RuntimeFailure(
        'Invalid HTTP method or API URL.',
        code: 'http.request_failed',
        permanent: true,
      );
    }
    _validateOutgoingHeaders(headers);
    final payload = body == null ? null : utf8.encode(jsonEncode(body));
    if (payload != null && (payload.length > 65536 || method == 'GET')) {
      throw const RuntimeFailure(
        'JSON request bodies are limited to 64 KiB and are not supported for GET.',
        code: 'http.request_failed',
        permanent: true,
      );
    }
    HttpClientRequest? outgoing;
    try {
      return await (() async {
        outgoing = await _client.openUrl(method, url);
        outgoing!.followRedirects = false;
        outgoing!.headers.set('Accept', 'application/json');
        headers.forEach((key, value) => outgoing!.headers.set(key, value));
        if (payload != null) {
          outgoing!.headers.contentType = ContentType.json;
          outgoing!.add(payload);
        }
        final response = await outgoing!.close();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw _statusFailure(response);
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 1024 * 1024) {
            throw const RuntimeFailure(
              'API response exceeds 1 MiB.',
              code: 'http.invalid_response',
              permanent: true,
            );
          }
          bytes.add(chunk);
        }
        final data = bytes.takeBytes();
        return {
          'status': response.statusCode,
          'body': data.isEmpty ? null : jsonDecode(utf8.decode(data)),
        };
      })().timeout(const Duration(seconds: 22));
    } on RuntimeFailure {
      outgoing?.abort();
      rethrow;
    } on FormatException {
      outgoing?.abort();
      throw const RuntimeFailure(
        'The API returned invalid JSON.',
        code: 'http.invalid_response',
        permanent: true,
      );
    } on TimeoutException {
      outgoing?.abort();
      throw const RuntimeFailure(
        'The HTTP request timed out.',
        code: 'http.timeout',
      );
    } catch (_) {
      outgoing?.abort();
      throw const RuntimeFailure(
        'The HTTP endpoint could not be reached.',
        code: 'http.request_failed',
      );
    }
  }

  @override
  Future<Json> get(Uri url, Map<String, String> headers) async {
    if (_closed) throw const RuntimeFailure('Bot stopped.');
    _validateOutgoingHeaders(headers);
    HttpClientRequest? request;
    try {
      return await (() async {
        request = await _client.getUrl(url);
        request!.followRedirects = false;
        request!.headers.set('Accept', 'application/json');
        headers.forEach((key, value) => request!.headers.set(key, value));
        final response = await request!.close();
        if (response.statusCode != 200) {
          throw _statusFailure(response);
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 1024 * 1024) {
            throw const RuntimeFailure(
              'API response exceeds 1 MiB.',
              code: 'http.invalid_response',
              permanent: true,
            );
          }
          bytes.add(chunk);
        }
        final decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
        if (decoded is! Json) throw const FormatException();
        return decoded;
      })().timeout(const Duration(seconds: 22));
    } on RuntimeFailure {
      request?.abort();
      rethrow;
    } on FormatException {
      throw const RuntimeFailure(
        'The API returned invalid JSON.',
        code: 'http.invalid_response',
        permanent: true,
      );
    } on TimeoutException {
      request?.abort();
      throw const RuntimeFailure(
        'The HTTP request timed out.',
        code: 'http.timeout',
      );
    } catch (_) {
      request?.abort();
      throw const RuntimeFailure(
        'The HTTP endpoint could not be reached.',
        code: 'http.request_failed',
      );
    }
  }

  @override
  void close() {
    _closed = true;
    _client.close(force: true);
  }
}
