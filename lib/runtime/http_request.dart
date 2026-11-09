import 'ports.dart';

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
        pathSegments:
            url.pathSegments.map((segment) {
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
    final headers = <String, String>{
      ...Map<String, String>.from(config['headers'] ?? {}),
    };
    final storefront = config['storefrontUrlField'] as String?;
    if (storefront != null) {
      final address = Uri.tryParse(context.fields[storefront] ?? '');
      if (address == null ||
          !{'http', 'https'}.contains(address.scheme) ||
          address.host.isEmpty ||
          address.userInfo.isNotEmpty ||
          address.hasQuery ||
          address.hasFragment ||
          (address.path.isNotEmpty && address.path != '/')) {
        throw const RuntimeFailure(
          'Enter the registered storefront origin, including its scheme, in plugin setup.',
          permanent: true,
        );
      }
      headers['Origin'] = address.origin;
      headers['X-Storefront-Host'] = address.authority;
    }
    final auth = config['authentication'] as Json?;
    if (auth != null) {
      final String? value;
      try {
        value = await context.secret(auth['secretField'] as String);
      } catch (_) {
        throw const RuntimeFailure(
          'The saved API key could not be read. Unlock the device and restart this bot.',
          permanent: true,
        );
      }
      if (value == null ||
          value.isEmpty ||
          value.contains('\r') ||
          value.contains('\n')) {
        throw const RuntimeFailure(
          'The saved API key is unavailable. Recreate this bot with its key.',
          permanent: true,
        );
      }
      headers['Authorization'] = 'Bearer $value';
    }
    return context.http.get(
      url.replace(queryParameters: {...url.queryParameters, ...query}),
      headers,
    );
  }
}
