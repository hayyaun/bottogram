import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'ports.dart';

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
        permanent: true,
      );
    }
    if (headers.length > 32 ||
        headers.entries.any(
          (e) =>
              !RegExp(r'^[!#$%&\x27*+.^_`|~0-9a-zA-Z-]+$').hasMatch(e.key) ||
              e.value.length > 8192 ||
              e.value.contains('\r') ||
              e.value.contains('\n') ||
              {
                'host',
                'content-length',
                'transfer-encoding',
                'connection',
              }.contains(e.key.toLowerCase()),
        )) {
      throw const RuntimeFailure(
        'Invalid or reserved API header.',
        permanent: true,
      );
    }
    final payload = body == null ? null : utf8.encode(jsonEncode(body));
    if (payload != null && (payload.length > 65536 || method == 'GET')) {
      throw const RuntimeFailure(
        'JSON request bodies are limited to 64 KiB and are not supported for GET.',
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
          throw RuntimeFailure(
            'API request failed (HTTP ${response.statusCode}).',
            permanent:
                response.statusCode < 500 &&
                !{408, 429}.contains(response.statusCode),
          );
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 1024 * 1024) {
            throw const RuntimeFailure(
              'API response exceeds 1 MiB.',
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
        permanent: true,
      );
    } catch (_) {
      outgoing?.abort();
      throw const RuntimeFailure(
        'The API request timed out or could not connect.',
      );
    }
  }

  @override
  Future<Json> get(Uri url, Map<String, String> headers) async {
    if (_closed) throw const RuntimeFailure('Bot stopped.');
    HttpClientRequest? request;
    try {
      return await (() async {
        request = await _client.getUrl(url);
        request!.followRedirects = false;
        headers.forEach((key, value) => request!.headers.set(key, value));
        request!.headers.set('Accept', 'application/json');
        final response = await request!.close();
        if (response.statusCode != 200) {
          final retry = int.tryParse(
            response.headers.value('retry-after') ?? '',
          );
          throw RuntimeFailure(
            response.statusCode == 401
                ? 'The API rejected this key (HTTP 401). Check the key and registered storefront.'
                : response.statusCode == 403
                ? 'API access was denied (HTTP 403). Check the key permissions and registered storefront.'
                : 'API request failed (HTTP ${response.statusCode}).',
            permanent:
                response.statusCode >= 300 &&
                response.statusCode < 500 &&
                !{408, 429}.contains(response.statusCode),
            retryAfter:
                retry == null ? null : Duration(seconds: retry.clamp(1, 3600)),
          );
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 1024 * 1024) {
            throw const RuntimeFailure(
              'API response exceeds 1 MiB.',
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
        permanent: true,
      );
    } catch (_) {
      request?.abort();
      throw const RuntimeFailure('The API could not be reached. Retrying.');
    }
  }

  @override
  void close() {
    _closed = true;
    _client.close(force: true);
  }
}
