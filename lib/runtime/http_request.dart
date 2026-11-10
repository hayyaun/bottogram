import 'ports.dart';
import 'http_headers.dart';

class HttpRequest {
  HttpRequest(this.config, this.context);
  final Json config;
  final RuntimeContext context;

  Future<Json> fetch({
    Map<String, String> query = const {},
    Map<String, String> pathParameters = const {},
  }) async {
    var url = Uri.parse(config['url'] as String);
    if (pathParameters.isNotEmpty) {
      url = url.replace(
        pathSegments: url.pathSegments.map((segment) {
          final match = RegExp(
            r'^\{([a-zA-Z][a-zA-Z0-9_]*)\}$',
          ).firstMatch(segment);
          if (match == null) return segment;
          final value = pathParameters[match[1]];
          if (value == null ||
              !RegExp(r'^[a-zA-Z0-9_-]{1,256}$').hasMatch(value)) {
            throw const RuntimeFailure(
              'The API lookup returned an invalid resource ID.',
              permanent: true,
            );
          }
          return value;
        }).toList(),
      );
    }
    final headers = await resolveHttpHeaders(config, context);
    return context.http.get(
      url.replace(queryParameters: {...url.queryParameters, ...query}),
      headers,
    );
  }
}
