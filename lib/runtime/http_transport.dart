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
