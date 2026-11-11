import 'dart:async';
import 'package:televerse/televerse.dart';
import 'package:televerse/telegram.dart';
import '../units/virt_event.dart';
import '../units/virt_act.dart';
import 'engine.dart';
import 'store.dart';
import 'telegram.dart';
import 'event_match.dart';

class BuilderSession {
  BuilderSession(String token, RawAPI api, {BuilderStore? store}) {
    final repository = store ?? BuilderStore.shared;
    final id = builderBotId(token);
    telegram = BuilderTelegramPort(api);
    engine = BuilderEngine(
      botId: id,
      telegram: telegram,
      variables: repository.variables(id),
      secret: (name) => repository.secret(id, name),
    );
  }
  late final BuilderEngine engine;
  late final BuilderTelegramPort telegram;
  final List<Timer> _timers = [];
  bool _closed = false;
  static List<BuilderStep> steps(VirtEvent event) => event.acts
      .map(
        (act) => BuilderStep(act.type.name, act.text, {
          ...act.config,
          if (act.rmu != null) 'keyboard': act.rmu!.hydrate().toJson(),
        }),
      )
      .toList();
  Future<void> receive(VirtEvent event, Context context) async {
    final message = context.message ?? context.callbackQuery?.message;
    final from = context.from;
    final text = message is Message
        ? message.text ?? message.caption ?? ''
        : '';
    final commandText = text.startsWith('/')
        ? text.split(RegExp(r'\s+')).skip(1).toList()
        : <String>[];
    final input = event.config.containsKey('match')
        ? BuilderEventMatch.remainder(
                event.type == VirtEventType.callbackQuery
                    ? context.callbackQuery?.data ?? ''
                    : event.type == VirtEventType.inlineQuery
                    ? context.inlineQuery?.query ?? ''
                    : text,
                event.query,
                event.config['match'].toString(),
              ) ??
              ''
        : text;
    await engine.run('${event.type.name}:${event.query}', {
      'type': event.type.name,
      'updateId': context.update.updateId,
      'text': text,
      'query': context.inlineQuery?.query ?? event.query,
      'arguments': commandText,
      'userId': from?.id,
      'firstName': from?.firstName ?? '',
      'lastName': from?.lastName ?? '',
      'username': from?.username ?? '',
      'chatId': message?.chat.id,
      'messageId': message?.messageId,
      'callbackId': context.callbackQuery?.id,
      'callbackData': context.callbackQuery?.data,
      'input': input,
      'inputParts': BuilderEventMatch.splitInput(
        input,
        event.config['inputSeparator'],
      ),
      'argumentsText': commandText.isEmpty
          ? ''
          : text.substring(text.indexOf(RegExp(r'\s+'))).trim(),
      'inlineMessageId': context.callbackQuery?.inlineMessageId,
      'inlineQueryId': context.inlineQuery?.id,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    }, steps(event));
    final callback = context.callbackQuery;
    if (!_closed &&
        callback != null &&
        event.acts.any((a) => a.type == VirtActType.callbackAnswer) &&
        !telegram.takeCallbackAnswer(callback.id)) {
      try {
        await context.answerCallbackQuery();
      } catch (_) {
        /* An expired click has already been reported by its action. */
      }
    }
  }

  void startPolling(Iterable<VirtEvent> events) {
    for (final event in events.where((e) => e.type == VirtEventType.polling)) {
      final seconds = event.config['intervalSeconds'];
      if (seconds is! int || seconds < 30 || seconds > 86400) {
        throw const FormatException(
          'Polling intervals must be between 30 and 86400 seconds.',
        );
      }
      var busy = false;
      Future<void> tick() async {
        if (_closed || busy) return;
        busy = true;
        try {
          await engine.run('polling:${event.query}', {
            'type': 'polling',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          }, steps(event));
        } finally {
          busy = false;
        }
      }

      _timers.add(
        Timer.periodic(Duration(seconds: seconds), (_) => unawaited(tick())),
      );
      unawaited(tick());
    }
  }

  Future<void> close() async {
    _closed = true;
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    await engine.close();
  }
}
