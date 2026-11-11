import 'dart:async';
import 'dart:collection';
import 'dart:convert';
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
        code: 'poll.invalid_response',
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
          code: 'poll.invalid_response',
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

class TelegramCommandTrigger extends TelegramEventTrigger {
  TelegramCommandTrigger(Json config, RuntimeContext context) {
    final commands = config['commands'] as List? ?? [config['command']];
    for (final command in commands) {
      context.telegram.command(command as String, (event) {
        if (isClosed) return;
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
        if (!enqueue(event)) {
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
}

class TelegramEventTrigger implements AutomationTrigger {
  bool get isClosed => _closed;

  bool enqueue(Json event) {
    if (_closed) return false;
    if (_waiting != null) {
      _waiting!.complete(TriggerBatch([event]));
      _waiting = null;
    } else if (_events.length < 32) {
      _events.add(event);
    } else {
      return false;
    }
    return true;
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
  HttpGetAction(this.config, this.context)
    : request = HttpRequest(config['request'] as Json, context),
      cacheKey = config['useLastResponse'] == true
          ? jsonEncode([config['request'], config['minimum']])
          : null;
  final Json config;
  final RuntimeContext context;
  final HttpRequest request;
  final String? cacheKey;

  @override
  Future<Json> execute(Json event) async {
    final pagination = config['pagination'] as Json?;
    final size = pagination?['pageSize'] as int? ?? 0;
    final lookahead = pagination?['itemsPath'] is String;
    final page = event['page'] as int? ?? 1;
    final query = <String, String>{
      if (pagination != null) ...{
        'limit': (size + (lookahead ? 1 : 0)).toString(),
        'offset': ((page - 1) * size).toString(),
      },
    };
    final bindings = config['bindings'] as Json? ?? const {};
    try {
      var result = await request.fetch(
        query: query,
        pathParameters: {
          for (final binding in bindings.entries)
            binding.key:
                valueAt(event, binding.value as String)?.toString() ?? '',
        },
      );
      if (lookahead) {
        final items = valueAt(result, pagination!['itemsPath'] as String);
        if (items is! List || items.length > size + 1) {
          throw const RuntimeFailure(
            'The list response does not match the plugin contract.',
            code: 'http.invalid_response',
          );
        }
        result = {
          'items': items.take(size).toList(),
          'page': page,
          if (page > 1) 'previous': page - 1,
          if (items.length > size && page < 9999) 'next': page + 1,
        };
      }
      final minimum = config['minimum'] as Json?;
      if (minimum != null) {
        final items = valueAt(result, minimum['itemsPath'] as String);
        if (items is List) {
          final amounts = items
              .map((item) => valueAt(item, minimum['valuePath'] as String))
              .whereType<num>()
              .where((value) => value.isFinite && value >= 0);
          if (amounts.isNotEmpty) {
            result = {
              ...result,
              'minimum': amounts.reduce((a, b) => a < b ? a : b),
            };
          }
        }
      }
      if (cacheKey != null) {
        final cache = context.lastResponses;
        cache.remove(cacheKey);
        if (cache.length >= 8) cache.remove(cache.keys.first);
        cache[cacheKey!] = result;
      }
      return _withResult(event, page, result);
    } on RuntimeFailure catch (error) {
      if (config['deferOnNotFound'] == true && error.httpStatus == 404) {
        throw const DeferDelivery();
      }
      if (cacheKey == null) rethrow;
      return _withResult(event, page, context.lastResponses[cacheKey] ?? {});
    }
  }

  Json _withResult(Json event, int page, Json result) => {
    ...event,
    'page': page,
    'nextPage': page + 1,
    'results': {
      ...(event['results'] as Json? ?? {}),
      config['resultKey'] as String: result,
    },
  };
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
        code: 'message.no_destination',
        permanent: true,
      );
    }
    var text = render(config['text'] as String, event);
    final list = config['list'] as Json?;
    if (list != null) {
      final items = valueAt(event, list['itemsPath'] as String);
      if (items is! List || items.length > 100) {
        throw const RuntimeFailure(
          'The list response is invalid.',
          code: 'message.invalid_list',
          permanent: true,
        );
      }
      text += items.isEmpty
          ? '\n${list['emptyText']}'
          : '\n${items.map((item) => render(list['itemText'] as String, event, item: item)).join('\n')}';
    }
    // A list is split into acknowledged actions at the runner boundary by the
    // package author. Avoid silently truncating items or retrying partial sends.
    if (text.isEmpty || text.length > 4096) {
      throw const RuntimeFailure(
        'The reply exceeds Telegram’s 4096-character limit. Send fewer items per message.',
        code: 'message.too_long',
        permanent: true,
      );
    }
    Json? replyMarkup;
    if (config['inlineKeyboard'] != null) {
      if (event['chatType'] != 'private') {
        throw const RuntimeFailure(
          'Mini App replies require a private chat.',
          code: 'telegram.invalid_chat_type',
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
