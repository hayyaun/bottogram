import 'dart:async';

typedef Json = Map<String, dynamic>;

class RuntimeFailure implements Exception {
  const RuntimeFailure(
    this.message, {
    this.permanent = false,
    this.retryAfter,
    this.code = 'runtime.failure',
  });
  final String message;
  final String code;
  final bool permanent;
  final Duration? retryAfter;
  @override
  String toString() => message;
}

abstract interface class ExecutionLease {
  Future<void> startService(int count);
  Future<void> updateService(int count);
  Future<void> stopService();
}

abstract interface class ProgressStore {
  Future<Json> read(String key);
  Future<void> write(String key, Json value);
  Future<void> removeInstance(String instanceId);
}

abstract interface class JsonTransport {
  Future<Json> get(Uri url, Map<String, String> headers);
  void close();
}

abstract interface class TelegramPort {
  /// One shared Telegram session installs every command before it starts.
  void command(String command, void Function(Json event) receive);
  Future<void> send(String chatId, String text, {Json? replyMarkup});
}

class RuntimeContext {
  RuntimeContext({
    required this.http,
    required this.telegram,
    required this.secret,
    required this.fields,
    required this.adminId,
  });
  final JsonTransport http;
  final TelegramPort telegram;
  final Future<String?> Function(String field) secret;
  final Map<String, String> fields;
  final String adminId;
}

class TriggerBatch {
  const TriggerBatch(
    this.events, {
    this.checkpoint,
    this.nextCursor,
    this.pageDelay = const Duration(milliseconds: 100),
    this.durableDeduplication = false,
  });
  final List<Json> events;
  final String? checkpoint;
  final String? nextCursor;
  final Duration pageDelay;
  final bool durableDeduplication;
}

abstract interface class AutomationTrigger {
  Duration get interval;
  bool get baseline;
  Future<TriggerBatch> next(String? cursor);
  void close();
}

abstract interface class AutomationAction {
  Future<Json> execute(Json event);
}

dynamic valueAt(dynamic value, String path) {
  for (final part in path.split('.')) {
    if (value is! Map || !value.containsKey(part)) return null;
    value = value[part];
  }
  return value;
}

String render(String template, Json event, {dynamic item}) => template
    .replaceAllMapped(RegExp(r'\{\{(event|item)\.([a-zA-Z0-9_.]+)\}\}'), (m) {
      final value = valueAt(m[1] == 'event' ? event : item, m[2]!);
      if (value == null) return '';
      if (value is! String && value is! num && value is! bool) {
        throw const RuntimeFailure(
          'The message template requires a scalar value.',
          code: 'message.invalid_template',
          permanent: true,
        );
      }
      return value.toString();
    });
