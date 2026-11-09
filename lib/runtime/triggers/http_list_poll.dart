import '../http_request.dart';
import '../ports.dart';

/// Polls a current-state list. Its continuation is a local offset, never an API
/// cursor or a consistent-snapshot guarantee. The runner owns delivery receipts.
class HttpListPollTrigger implements AutomationTrigger {
  HttpListPollTrigger(this.config, RuntimeContext context)
    : request = HttpRequest(config['request'] as Json, context),
      lookup =
          config['lookup'] == null
              ? null
              : HttpRequest(config['lookup']['request'] as Json, context);
  final Json config;
  final HttpRequest request;
  final HttpRequest? lookup;
  Map<String, String>? _parameters;
  @override
  Duration get interval => Duration(seconds: config['intervalSeconds'] as int);
  @override
  bool get baseline => config['initialSync'] == 'baseline';

  @override
  Future<TriggerBatch> next(String? cursor) async {
    final pagination = config['pagination'] as Json;
    final size = pagination['pageSize'] as int;
    final offset = cursor == null ? 0 : int.tryParse(cursor);
    if (offset == null || offset < 0 || offset % size != 0) {
      throw const RuntimeFailure(
        'Stored list scan progress is invalid.',
        permanent: true,
      );
    }
    if (offset ~/ size >= (pagination['maxPages'] as int)) {
      throw const RuntimeFailure(
        'Order history exceeds this plugin’s scan limit. Contact the plugin author.',
        permanent: true,
      );
    }
    if (_parameters == null) {
      final bindings = <String, String>{};
      if (lookup != null) {
        final body = await lookup!.fetch();
        for (final entry in (config['lookup']['bindings'] as Json).entries) {
          final value = valueAt(body, entry.value as String);
          if (value is! String ||
              !RegExp(r'^[a-zA-Z0-9_-]{1,256}$').hasMatch(value)) {
            throw const RuntimeFailure(
              'The API lookup returned an invalid resource ID.',
              permanent: true,
            );
          }
          bindings[entry.key] = value;
        }
      }
      _parameters = bindings;
    }
    final body = await request.fetch(
      query: {
        pagination['limitQueryParameter'] as String: size.toString(),
        pagination['offsetQueryParameter'] as String: offset.toString(),
      },
      pathParameters: _parameters!,
    );
    final response = config['response'] as Json;
    final items = valueAt(body, response['itemsPath'] as String);
    if (items is! List || items.length > size) {
      throw const RuntimeFailure(
        'The list response does not match the plugin contract.',
        permanent: true,
      );
    }
    final filter = config['filter'] as Json?;
    final events = <Json>[];
    for (final item in items) {
      final id = valueAt(item, response['itemIdPath'] as String);
      if (item is! Json ||
          (id is! String && id is! int) ||
          id.toString().isEmpty ||
          id.toString().length > 256) {
        throw const RuntimeFailure(
          'A list item has no stable ID.',
          permanent: true,
        );
      }
      if (filter != null) {
        final value = valueAt(item, filter['path'] as String);
        if (value == null) {
          throw const RuntimeFailure(
            'A list item is missing its filter field.',
            permanent: true,
          );
        }
        if (value != filter['equals']) continue;
      }
      events.add({...item, 'id': id.toString()});
    }
    return TriggerBatch(
      events,
      nextCursor: items.length == size ? (offset + size).toString() : null,
      pageDelay: Duration(seconds: pagination['pageDelaySeconds'] as int),
      durableDeduplication: true,
    );
  }

  @override
  void close() {}
}
