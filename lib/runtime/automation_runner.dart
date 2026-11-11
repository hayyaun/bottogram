import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'ports.dart';
import 'registry.dart';
import 'failure_presentation.dart';
import 'telegram_interaction.dart';

/// Acknowledges each action before advancing the source checkpoint. Network IO
/// never occupies a global persistence queue. Stop drains any in-flight send.
class AutomationRunner {
  AutomationRunner({
    required this.definition,
    required this.context,
    required this.store,
    required this.key,
    required this.onStatus,
    this.errorMessages,
    this.channelId,
    this.onFailure,
    AutomationRegistry? registry,
  }) : registry = registry ?? AutomationRegistry.standard;
  final AutomationDefinition definition;
  final RuntimeContext context;
  final ProgressStore store;
  final String key;
  final void Function(String? error) onStatus;
  final Json? errorMessages;
  final String? channelId;

  Set<String> get _chatTypes =>
      context.destinationChatTypes[definition.destinationField] ??
      const {'channel'};
  final void Function(FailurePresentation? failure)? onFailure;
  final AutomationRegistry registry;
  AutomationTrigger? _trigger;
  bool _stopped = false;
  Timer? _delayTimer;
  Completer<void>? _delayDone;
  Future<void>? _running;
  Future<void> start() => _running ??= _loop();
  Future<void> stop() async {
    _stopped = true;
    _delayTimer?.cancel();
    _delayTimer = null;
    _delayDone?.complete();
    _delayDone = null;
    _trigger?.close();
    await _running;
  }

  Future<void> _delay(Duration duration) {
    if (_stopped) return Future.value();
    final done = _delayDone = Completer<void>();
    _delayTimer = Timer(duration, () {
      _delayTimer = null;
      _delayDone = null;
      done.complete();
    });
    return done.future;
  }

  Future<void> _loop() async {
    late AutomationTrigger trigger;
    final actions = <AutomationAction>[];
    Map<String, String> initializationMapping = definition.trigger.errorMap;
    try {
      trigger = _trigger = registry.triggers[definition.trigger.type]!.create(
        definition.trigger.config,
        context,
      );
      for (final component in definition.actions) {
        initializationMapping = component.errorMap;
        actions.add(
          registry.actions[component.type]!.create(component.config, context),
        );
      }
    } on RuntimeFailure catch (error) {
      _report(error, initializationMapping);
      _trigger?.close();
      return;
    } catch (_) {
      _report(
        const RuntimeFailure(
          'The automation could not be initialized.',
          code: 'runtime.initialization_failed',
          permanent: true,
        ),
      );
      _trigger?.close();
      return;
    }
    if (definition.trigger.type == interactionTrigger) {
      try {
        while (!_stopped) {
          final TriggerBatch batch;
          try {
            batch = await trigger.next(null);
          } on RuntimeFailure {
            if (_stopped) break;
            rethrow;
          }
          for (var event in batch.events) {
            try {
              for (final action in actions) {
                if (_stopped) break;
                event = await action.execute(event);
              }
            } catch (_) {
              if (_stopped) break;
              try {
                await context.telegram.send(
                  event['chatId'] as String,
                  definition.trigger.config['failureText'] as String,
                );
              } catch (_) {
                // A later interaction can still succeed.
              }
            }
          }
        }
      } finally {
        trigger.close();
      }
      return;
    }
    var failures = 0;
    var channelChecked = false;
    try {
      final state = await store.read(key);
      while (!_stopped) {
        Map<String, String> failureMapping = const {};
        var executingComponent = false;
        try {
          if (channelId != null && !channelChecked) {
            failureMapping = definition.actions.last.errorMap;
            executingComponent = true;
            if (!await context.interactions.canPost(
              channelId!,
              chatTypes: _chatTypes,
              photo: definition.actions.last.config['photo'] != null,
            )) {
              throw const RuntimeFailure(
                'The bot cannot post to the configured Telegram chat.',
                code: 'telegram.channel_unavailable',
                retryAfter: Duration(seconds: 60),
              );
            }
            channelChecked = true;
          }
          if (state['pending'] == null) {
            failureMapping = definition.trigger.errorMap;
            executingComponent = true;
            final batch = await trigger.next(
              (state['pageCursor'] ?? state['checkpoint']) as String?,
            );
            if (_stopped) break;
            final horizon = state['cycleCheckpoint'] as String?;
            if (horizon != null && batch.checkpoint != horizon) {
              throw const RuntimeFailure(
                'The API changed its checkpoint during pagination.',
                code: 'poll.invalid_response',
                permanent: true,
              );
            }
            failureMapping = const {};
            executingComponent = false;
            state['pending'] = {
              'events': batch.events,
              'index': 0,
              'action': 0,
              'checkpoint': batch.checkpoint,
              'nextCursor': batch.nextCursor,
              'pageDelayMs': batch.pageDelay.inMilliseconds,
              'durableDeduplication': batch.durableDeduplication,
            };
            if (utf8.encode(jsonEncode(state)).length > 2 * 1024 * 1024) {
              throw const RuntimeFailure(
                'Automation progress exceeds its size limit.',
                code: 'progress.limit_exceeded',
                permanent: true,
              );
            }
            await store.write(key, state);
          }
          final pending = Map<String, dynamic>.from(state['pending'] as Map);
          final events = (pending['events'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final recent = List<String>.from(state['recent'] as List? ?? []);
          final durable = pending['durableDeduplication'] == true;
          final baseline = trigger.baseline && state['initialized'] != true;
          var deferred = false;
          while ((pending['index'] as int) < events.length && !_stopped) {
            final index = pending['index'] as int;
            var event = channelId == null
                ? events[index]
                : {...events[index], 'destinationChatId': channelId};
            final receiptKey =
                '$key:delivered:${sha256.convert(utf8.encode(event['id'] as String))}';
            final seen = durable
                ? (await store.read(receiptKey))['complete'] == true
                : recent.contains(event['id']);
            if (!baseline && !seen) {
              while ((pending['action'] as int) < actions.length && !_stopped) {
                final action = pending['action'] as int;
                failureMapping = definition.actions[action].errorMap;
                executingComponent = true;
                try {
                  event = await actions[action].execute(event);
                } on DeferDelivery catch (defer) {
                  if (channelId == null || !durable) rethrow;
                  deferred = deferred || defer.missingPhoto;
                  pending['index'] = index + 1;
                  pending['action'] = 0;
                  state['pending'] = pending;
                  break;
                }
                failureMapping = const {};
                executingComponent = false;
                pending['action'] = action + 1;
                if (channelId == null) {
                  events[index] = event;
                  pending['events'] = events;
                  state['pending'] = pending;
                  await store.write(key, state);
                } else if (action == actions.length - 1) {
                  // A confirmed channel delivery is recorded even when Stop
                  // was pressed while the Telegram request was in flight.
                  await store.write(receiptKey, {'complete': true});
                }
              }
              if (_stopped) break;
            }
            if (pending['index'] != index) continue;
            if (durable) {
              if (!seen && (channelId == null || baseline)) {
                await store.write(receiptKey, {'complete': true});
              }
            } else {
              recent.add(event['id'] as String);
              if (recent.length > 2000) {
                recent.removeRange(0, recent.length - 2000);
              }
            }
            pending['index'] = index + 1;
            pending['action'] = 0;
            state['recent'] = recent;
            state['pending'] = pending;
            // Durable receipts make replaying already completed items harmless;
            // avoid rewriting a whole history page for every baseline/seen item.
            if (!durable) await store.write(key, state);
          }
          if (_stopped) break;
          if (deferred) state['deferredDelivery'] = true;
          final scanDeferred = state['deferredDelivery'] == true;
          state.remove('pending');
          if (pending['nextCursor'] != null) {
            state['pageCursor'] = pending['nextCursor'];
            state['cycleCheckpoint'] = pending['checkpoint'];
          } else {
            state['checkpoint'] = pending['checkpoint'];
            state['initialized'] = true;
            channelChecked = false;
            state.remove('deferredDelivery');
            state.remove('pageCursor');
            state.remove('cycleCheckpoint');
          }
          await store.write(key, state);
          failures = 0;
          if (scanDeferred) {
            _report(
              const RuntimeFailure(
                'An item is waiting for usable media and will be checked again.',
                code: 'telegram.photo_unavailable',
              ),
              definition.actions.last.errorMap,
            );
          } else if (channelId == null || state['pageCursor'] == null) {
            onStatus(null);
            onFailure?.call(null);
          }
          // Bound work even for an API that returns endlessly changing pages.
          await _delay(
            state['pageCursor'] == null
                ? trigger.interval
                : Duration(milliseconds: pending['pageDelayMs'] as int? ?? 100),
          );
        } on RuntimeFailure catch (error) {
          if (_stopped) break;
          _report(error, failureMapping);
          channelChecked = false;
          if (channelId != null && state['pending'] is Json) {
            (state['pending'] as Json)['action'] = 0;
          }
          if (error.permanent) break;
          failures++;
          await _delay(
            error.retryAfter ??
                Duration(seconds: (1 << failures.clamp(1, 8)).clamp(2, 300)),
          );
        } catch (_) {
          if (!_stopped) {
            _report(
              executingComponent
                  ? const RuntimeFailure(
                      'An automation operation failed unexpectedly. Stop and restart this bot.',
                      code: 'runtime.unexpected',
                      permanent: true,
                    )
                  : const RuntimeFailure(
                      'Automation progress could not be saved. Stop and restart this bot.',
                      code: 'progress.save_failed',
                      permanent: true,
                    ),
              failureMapping,
            );
          }
          break;
        }
      }
    } catch (_) {
      if (!_stopped) {
        _report(
          const RuntimeFailure(
            'Automation progress could not be loaded. Stop and restart this bot.',
            code: 'progress.load_failed',
            permanent: true,
          ),
        );
      }
    } finally {
      trigger.close();
    }
  }

  void _report(RuntimeFailure error, [Map<String, String> mapping = const {}]) {
    final presentation = renderFailure(
      error,
      errorMessages ?? const {},
      mapping,
      destination: channelId,
    );
    onStatus(presentation.message);
    onFailure?.call(presentation);
  }
}
