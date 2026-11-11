import 'dart:async';
import 'dart:typed_data';

typedef Json = Map<String, dynamic>;

class RuntimeFailure implements Exception {
  const RuntimeFailure(
    this.message, {
    this.permanent = false,
    this.retryAfter,
    this.code = 'runtime.failure',
    this.httpStatus,
  });
  final String message;
  final String code;
  final int? httpStatus;
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

/// Optional Telegram operations used by interactive and channel automations.
abstract interface class TelegramInteractions {
  String get username;
  void interaction(String kind, void Function(Json event) receive);
  Future<bool> canPost(
    String chatId, {
    Set<String> chatTypes = const {'channel'},
    bool photo = true,
  });
  Future<void> photo(
    String chatId,
    Uint8List bytes,
    String caption,
    Json? keyboard,
  );
  Future<void> widget(
    Json event,
    String html,
    Json data,
    String caption,
    Json? keyboard,
  );
}

abstract interface class PhotoTransport {
  Future<Uint8List?> jpeg(Uri url);
}

/// Defer an item before delivery. A full list scan can retry it next time.
class DeferDelivery implements Exception {
  const DeferDelivery({this.missingPhoto = false});
  final bool missingPhoto;
}

class RuntimeContext {
  RuntimeContext({
    required this.http,
    required this.telegram,
    required this.secret,
    required this.fields,
    required this.adminId,
    this.settings = const {},
    this.destinationChatTypes = const {},
  });
  final JsonTransport http;
  final TelegramPort telegram;
  final Future<String?> Function(String field) secret;
  final Map<String, String> fields;
  final String adminId;
  final Map<String, Object> settings;
  final Map<String, Set<String>> destinationChatTypes;
  final lastResponses = <String, Json>{};

  TelegramInteractions get interactions => telegram as TelegramInteractions;
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

num? minimumValue(Json result, Json config) {
  final items = valueAt(result, config['itemsPath'] as String);
  if (items is! List) return null;
  final amounts = items
      .map((item) => valueAt(item, config['valuePath'] as String))
      .whereType<num>()
      .where((value) => value.isFinite && value >= 0);
  return amounts.isEmpty ? null : amounts.reduce((a, b) => a < b ? a : b);
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
