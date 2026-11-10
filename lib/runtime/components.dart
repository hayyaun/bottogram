import 'dart:async';
import 'dart:collection';
import 'ports.dart';
import 'http_request.dart';
import 'telegram_config.dart';

class HttpPollTrigger implements AutomationTrigger {
  HttpPollTrigger(this.config, RuntimeContext context)
    : request = HttpRequest(config['request'] as Json, context);
  final Json config;
  final HttpRequest request;
  @override
  Duration get interval => Duration(seconds: config['intervalSeconds'] as int);
  @override
  bool get baseline => config['initialSync'] == 'baseline';
  @override
  Future<TriggerBatch> next(String? cursor) async {
    final pagination = config['pagination'] as Json;
    final response = config['response'] as Json;
    final body = await request.fetch(
      query: {
        if (cursor != null)
          pagination['cursorQueryParameter'] as String: cursor,
      },
    );
    final items = valueAt(body, response['itemsPath'] as String);
    final checkpoint = valueAt(body, response['checkpointPath'] as String);
    final hasMore = valueAt(body, pagination['hasMorePath'] as String);
    final next = valueAt(body, pagination['nextPagePath'] as String);
    if (items is! List ||
        items.length > 100 ||
        checkpoint is! String ||
        checkpoint.isEmpty ||
        checkpoint.length > 4096 ||
        hasMore is! bool ||
        (hasMore &&
            (next is! String ||
                next.isEmpty ||
                next.length > 4096 ||
                next == cursor))) {
      throw const RuntimeFailure(
        'The polling response does not match the plugin contract.',
        permanent: true,
      );
    }
    final events = <Json>[];
    for (final item in items) {
      final id = valueAt(item, response['itemIdPath'] as String);
      if (item is! Json ||
          (id is! String && id is! int) ||
          id.toString().isEmpty ||
          id.toString().length > 256) {
        throw const RuntimeFailure(
          'A polling event has no stable ID.',
          permanent: true,
        );
      }
      events.add({...item, 'id': id.toString()});
    }
    return TriggerBatch(
      events,
      checkpoint: checkpoint,
      nextCursor: hasMore ? next as String : null,
    );
  }

  @override
  void close() {}
}

class TelegramCommandTrigger implements AutomationTrigger {
  TelegramCommandTrigger(Json config, RuntimeContext context) {
    final commands = config['commands'] as List? ?? [config['command']];
    for (final command in commands) {
      context.telegram.command(command as String, (event) {
        if (_closed) return;
        final chatTypes = config['chatTypes'] as List?;
        if (chatTypes != null && !chatTypes.contains(event['chatType'])) return;
        if (config['arguments'] == 'ignore') {
          event = {...event}..remove('arguments');
        }
        if (config['arguments'] == 'page') {
          final args = List<String>.from(event['arguments'] as List? ?? []);
          final page = args.isEmpty ? 1 : int.tryParse(args.first);
          if (args.length > 1 || page == null || page < 1 || page > 10000) {
            unawaited(
              context.telegram
                  .send(
                    event['chatId'].toString(),
                    'Use /${config['command']} or /${config['command']} 2 for the next page.',
                  )
                  .catchError((Object _) {}),
            );
            return;
          }
          event = {...event, 'page': page};
        }
        if (_waiting != null) {
          _waiting!.complete(TriggerBatch([event]));
          _waiting = null;
        } else if (_events.length < 32) {
          _events.add(event);
        } else {
          unawaited(
            context.telegram
                .send(
                  event['chatId'].toString(),
                  'The bot is busy. Please try this command again shortly.',
                )
                .catchError((Object _) {}),
          );
        }
      });
    }
  }
  final Queue<Json> _events = Queue();
  Completer<TriggerBatch>? _waiting;
  bool _closed = false;
  @override
  Duration get interval => Duration.zero;
  @override
  bool get baseline => false;
  @override
  Future<TriggerBatch> next(String? cursor) {
    if (_events.isNotEmpty) {
      return Future.value(TriggerBatch([_events.removeFirst()]));
    }
    if (_closed) return Future.error(const RuntimeFailure('Bot stopped.'));
    _waiting = Completer<TriggerBatch>();
    return _waiting!.future;
  }

  @override
  void close() {
    _closed = true;
    _events.clear();
    _waiting?.completeError(const RuntimeFailure('Bot stopped.'));
    _waiting = null;
  }
}

class HttpGetAction implements AutomationAction {
  HttpGetAction(this.config, RuntimeContext context)
    : request = HttpRequest(config['request'] as Json, context);
  final Json config;
  final HttpRequest request;
  @override
  Future<Json> execute(Json event) async {
    final pagination = config['pagination'] as Json?;
    final page = event['page'] as int? ?? 1;
    return {
      ...event,
      'page': page,
      'nextPage': page + 1,
      'results': {
        ...(event['results'] as Json? ?? {}),
        config['resultKey'] as String: await request.fetch(
          query: {
            if (pagination != null) 'limit': pagination['pageSize'].toString(),
            if (pagination != null)
              'offset': ((page - 1) * (pagination['pageSize'] as int))
                  .toString(),
          },
        ),
      },
    };
  }
}

class TelegramMessageAction implements AutomationAction {
  TelegramMessageAction(this.config, this.context, {required this.adminOnly});
  final Json config;
  final RuntimeContext context;
  final bool adminOnly;
  @override
  Future<Json> execute(Json event) async {
    final chatId = adminOnly ? context.adminId : event['chatId']?.toString();
    if (chatId == null) {
      throw const RuntimeFailure(
        'The event has no reply destination.',
        permanent: true,
      );
    }
    var text = render(config['text'] as String, event);
    final list = config['list'] as Json?;
    if (list != null) {
      final items = valueAt(event, list['itemsPath'] as String);
      if (items is! List || items.length > 100) {
        throw const RuntimeFailure(
          'The catalog response is invalid.',
          permanent: true,
        );
      }
      text += items.isEmpty
          ? '\n${list['emptyText']}'
          : '\n${items.map((item) => render(list['itemText'] as String, event, item: item)).join('\n')}';
    }
    // A list is split into acknowledged actions at the runner boundary by the
    // package author. Avoid silently truncating products or retrying partial sends.
    if (text.isEmpty || text.length > 4096) {
      throw const RuntimeFailure(
        'The reply exceeds Telegram’s 4096-character limit. Use a smaller catalog page.',
        permanent: true,
      );
    }
    Json? replyMarkup;
    if (config['inlineKeyboard'] != null) {
      if (event['chatType'] != 'private') {
        throw const RuntimeFailure(
          'Mini App replies require a private chat.',
          permanent: true,
        );
      }
      replyMarkup = resolveInlineKeyboard(
        config['inlineKeyboard'],
        context.fields,
      );
    }
    await context.telegram.send(chatId, text, replyMarkup: replyMarkup);
    return event;
  }
}
