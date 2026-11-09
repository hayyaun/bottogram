import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'ports.dart';
import 'registry.dart';

/// Acknowledges each action before advancing the source checkpoint. Network IO
/// never occupies a global persistence queue. Stop drains any in-flight send.
class AutomationRunner {
  AutomationRunner({
    required this.definition,
    required this.context,
    required this.store,
    required this.key,
    required this.onStatus,
    AutomationRegistry? registry,
  }) : registry = registry ?? AutomationRegistry.standard;
  final AutomationDefinition definition;
  final RuntimeContext context;
  final ProgressStore store;
  final String key;
  final void Function(String? error) onStatus;
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
    final trigger =
        _trigger = registry.triggers[definition.trigger.type]!.create(
          definition.trigger.config,
          context,
        );
    final actions =
        definition.actions
            .map((a) => registry.actions[a.type]!.create(a.config, context))
            .toList();
    var failures = 0;
    try {
      final state = await store.read(key);
      while (!_stopped) {
        try {
          if (state['pending'] == null) {
            final batch = await trigger.next(
              (state['pageCursor'] ?? state['checkpoint']) as String?,
            );
            if (_stopped) break;
            final horizon = state['cycleCheckpoint'] as String?;
            if (horizon != null && batch.checkpoint != horizon) {
              throw const RuntimeFailure(
                'The API changed its checkpoint during pagination.',
                permanent: true,
              );
            }
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
                permanent: true,
              );
            }
            await store.write(key, state);
          }
          final pending = Map<String, dynamic>.from(state['pending'] as Map);
          final events =
              (pending['events'] as List)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
          final recent = List<String>.from(state['recent'] as List? ?? []);
          final durable = pending['durableDeduplication'] == true;
          final baseline = trigger.baseline && state['initialized'] != true;
          while ((pending['index'] as int) < events.length && !_stopped) {
            final index = pending['index'] as int;
            var event = events[index];
            final receiptKey =
                '$key:delivered:${sha256.convert(utf8.encode(event['id'] as String))}';
            final seen =
                durable
                    ? (await store.read(receiptKey))['complete'] == true
                    : recent.contains(event['id']);
            if (!baseline && !seen) {
              while ((pending['action'] as int) < actions.length && !_stopped) {
                final action = pending['action'] as int;
                event = await actions[action].execute(event);
                events[index] = event;
                pending['events'] = events;
                pending['action'] = action + 1;
                state['pending'] = pending;
                await store.write(key, state);
              }
              if (_stopped) break;
            }
            if (durable) {
              if (!seen) await store.write(receiptKey, {'complete': true});
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
          state.remove('pending');
          if (pending['nextCursor'] != null) {
            state['pageCursor'] = pending['nextCursor'];
            state['cycleCheckpoint'] = pending['checkpoint'];
          } else {
            state['checkpoint'] = pending['checkpoint'];
            state['initialized'] = true;
            state.remove('pageCursor');
            state.remove('cycleCheckpoint');
          }
          await store.write(key, state);
          failures = 0;
          onStatus(null);
          // Bound work even for an API that returns endlessly changing pages.
          await _delay(
            state['pageCursor'] == null
                ? trigger.interval
                : Duration(milliseconds: pending['pageDelayMs'] as int? ?? 100),
          );
        } on RuntimeFailure catch (error) {
          if (_stopped) break;
          onStatus(error.message);
          if (error.permanent) break;
          failures++;
          await _delay(
            error.retryAfter ??
                Duration(seconds: (1 << failures.clamp(1, 8)).clamp(2, 300)),
          );
        } catch (_) {
          if (!_stopped) {
            onStatus(
              'Automation progress could not be saved. Stop and restart this bot.',
            );
          }
          break;
        }
      }
    } catch (_) {
      if (!_stopped) {
        onStatus(
          'Automation progress could not be loaded. Stop and restart this bot.',
        );
      }
    } finally {
      trigger.close();
    }
  }
}
