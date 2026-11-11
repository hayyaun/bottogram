import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bottogram/runtime/automation_runner.dart';
import 'package:bottogram/runtime/failure_presentation.dart';
import 'package:bottogram/runtime/ports.dart';
import 'package:bottogram/runtime/registry.dart';

import 'automation_runtime_test.dart'
    show
        MemoryProgress,
        FakeHttp,
        FakeTelegram,
        QueueTrigger,
        FunctionAction,
        until;

Json messages([String copy = 'Reconnect the event service.']) =>
    parseErrorMessages({
      'eventConnection': {
        'title': 'Event service unavailable',
        'message': copy,
        'help': 'Check the saved service credentials.',
        'action': 'editPluginParameters',
      },
      'deliveryPending': {
        'title': 'Delivery pending',
        'message': 'The event pass is still waiting to be delivered.',
        'action': 'retry',
      },
    });

RuntimeContext context() => RuntimeContext(
  http: FakeHttp(),
  telegram: FakeTelegram(),
  secret: (_) async => null,
  fields: const {},
  adminIds: ['999'],
);

class FailingTrigger implements AutomationTrigger {
  FailingTrigger(this.error);
  final Object error;
  int calls = 0;
  @override
  Duration get interval => Duration.zero;
  @override
  bool get baseline => false;
  @override
  Future<TriggerBatch> next(String? cursor) async {
    calls++;
    throw error;
  }

  @override
  void close() {}
}

void main() {
  test(
    'reusable error resources are literal presentation, not retry or execution policy',
    () {
      final catalog = messages();
      final map = validateErrorMap({
        'http.unauthorized': 'eventConnection',
        'http.forbidden': 'eventConnection',
      });
      for (final code in ['http.unauthorized', 'http.forbidden']) {
        final failure = RuntimeFailure(
          'Host fallback',
          code: code,
          permanent: true,
        );
        final view = renderFailure(failure, catalog, map);
        expect(view.code, code);
        expect(view.message, 'Reconnect the event service.');
        expect(view.title, 'Event service unavailable');
        expect(view.help, 'Check the saved service credentials.');
        expect(view.action, 'editPluginParameters');
        expect(failure.permanent, isTrue);
      }
      final fallback = renderFailure(
        const RuntimeFailure(
          'A sanitized host message.',
          code: 'runtime.unexpected',
        ),
        catalog,
        map,
      );
      expect(fallback.title, 'Automation issue');
      expect(fallback.message, 'A sanitized host message.');
      expect(fallback.action, isNull);
      final ambiguous = renderFailure(
        const RuntimeFailure(
          'Telegram delivery is unconfirmed.',
          code: 'telegram.delivery_unconfirmed',
        ),
        catalog,
        {'telegram.delivery_unconfirmed': 'deliveryPending'},
      );
      expect(
        ambiguous.message,
        'The event pass is still waiting to be delivered.',
      );
      expect(
        ambiguous.hostNotice,
        'Telegram may already have delivered this message. Retrying can send it again.',
      );
      expect(
        () => parseErrorMessages({
          'custom': {
            'title': 'Title',
            'message': 'Message',
            'hostNotice': 'Delivery succeeded',
          },
        }),
        throwsFormatException,
      );
      for (final field in [
        'permanent',
        'retryAfter',
        'severity',
        'url',
        'script',
      ]) {
        expect(
          () => parseErrorMessages({
            'custom': {'title': 'Title', 'message': 'Message', field: true},
          }),
          throwsFormatException,
        );
      }
      for (final text in ['{{secrets.apiKey}}', r'${response.body}', '  ']) {
        expect(
          () => parseErrorMessages({
            'custom': {'title': 'Title', 'message': text},
          }),
          throwsFormatException,
        );
      }
      expect(
        () => parseErrorMessages({
          'custom': {
            'title': 'Title',
            'message': 'Message',
            'action': 'openArbitraryUrl',
          },
        }),
        throwsFormatException,
      );
      expect(
        () => validateErrorMap({'bad code': 'custom'}),
        throwsFormatException,
      );
    },
  );

  test(
    'trigger mapping is component-local and a permanent failure is never retried by presentation',
    () async {
      final trigger = FailingTrigger(
        const RuntimeFailure(
          'Request denied.',
          code: 'http.forbidden',
          permanent: true,
        ),
      );
      final progress = MemoryProgress();
      final views = <FailurePresentation?>[];
      final definition = AutomationDefinition(
        'events',
        const ComponentDefinition(
          'test.trigger',
          {},
          errorMap: {'http.forbidden': 'eventConnection'},
        ),
        [
          const ComponentDefinition(
            'test.action',
            {},
            id: 'delivery',
            errorMap: {'http.forbidden': 'deliveryPending'},
          ),
        ],
        null,
      );
      var actionCalls = 0;
      final runner = AutomationRunner(
        definition: definition,
        context: context(),
        store: progress,
        key: 'events',
        errorMessages: messages(),
        onStatus: (_) {},
        onFailure: views.add,
        registry: AutomationRegistry(
          triggers: {
            'test.trigger': ComponentRegistration((_) {}, (_, __) => trigger),
          },
          actions: {
            'test.action': ComponentRegistration(
              (_) {},
              (_, __) => FunctionAction((event) async {
                actionCalls++;
                return event;
              }),
            ),
          },
        ),
      );
      await runner.start();
      expect(trigger.calls, 1);
      expect(actionCalls, 0);
      expect(views.single!.message, 'Reconnect the event service.');
      expect(progress.values, isEmpty);
      await runner.stop();
    },
  );

  test(
    'checkpoint mismatch uses trigger mapping without advancing saved progress',
    () async {
      final source = QueueTrigger([
        const TriggerBatch([
          {'id': 'pass-2'},
        ], checkpoint: 'changed-horizon'),
      ]);
      final progress = MemoryProgress();
      await progress.write('events', {
        'checkpoint': 'previous-cycle',
        'pageCursor': 'page-2',
        'cycleCheckpoint': 'original-horizon',
        'initialized': true,
        'recent': ['pass-1'],
      });
      final saved = jsonEncode(progress.values);
      final views = <FailurePresentation?>[];
      var actionCalls = 0;
      final runner = AutomationRunner(
        definition: AutomationDefinition(
          'events',
          const ComponentDefinition(
            'test.trigger',
            {},
            errorMap: {'poll.invalid_response': 'eventConnection'},
          ),
          [
            const ComponentDefinition(
              'test.action',
              {},
              id: 'delivery',
              errorMap: {'poll.invalid_response': 'deliveryPending'},
            ),
          ],
          null,
        ),
        context: context(),
        store: progress,
        key: 'events',
        errorMessages: messages(),
        onStatus: (_) {},
        onFailure: views.add,
        registry: AutomationRegistry(
          triggers: {
            'test.trigger': ComponentRegistration((_) {}, (_, __) => source),
          },
          actions: {
            'test.action': ComponentRegistration(
              (_) {},
              (_, __) => FunctionAction((event) async {
                actionCalls++;
                return event;
              }),
            ),
          },
        ),
      );

      await runner.start();
      expect(source.cursors, ['page-2']);
      expect(views.single!.code, 'poll.invalid_response');
      expect(views.single!.message, 'Reconnect the event service.');
      expect(actionCalls, 0);
      expect(jsonEncode(progress.values), saved);
      await runner.stop();
    },
  );

  test(
    'action presentation does not change retry timing, pending position, or acknowledgement semantics',
    () async {
      final source = QueueTrigger([
        const TriggerBatch([
          {'id': 'pass-1'},
        ], durableDeduplication: true),
      ]);
      final progress = MemoryProgress();
      final views = <FailurePresentation?>[];
      final snapshots = <String>[];
      var calls = 0;
      final definition = AutomationDefinition(
        'events',
        const ComponentDefinition(
          'test.trigger',
          {},
          errorMap: {'http.rate_limited': 'eventConnection'},
        ),
        [
          const ComponentDefinition(
            'test.action',
            {},
            id: 'delivery',
            errorMap: {'http.rate_limited': 'deliveryPending'},
          ),
        ],
        null,
      );
      final runner = AutomationRunner(
        definition: definition,
        context: context(),
        store: progress,
        key: 'events',
        errorMessages: messages(),
        onStatus: (_) {},
        onFailure: (view) {
          views.add(view);
          if (view != null) snapshots.add(jsonEncode(progress.values));
        },
        registry: AutomationRegistry(
          triggers: {
            'test.trigger': ComponentRegistration((_) {}, (_, __) => source),
          },
          actions: {
            'test.action': ComponentRegistration(
              (_) {},
              (_, __) => FunctionAction((event) async {
                if (++calls == 1) {
                  throw const RuntimeFailure(
                    'Wait before trying again.',
                    code: 'http.rate_limited',
                    retryAfter: Duration(milliseconds: 1),
                  );
                }
                return event;
              }),
            ),
          },
        ),
      );
      unawaited(runner.start());
      await until(
        () => progress.values.entries.any(
          (e) => e.key.contains(':delivered:') && e.value['complete'] == true,
        ),
      );
      expect(calls, 2);
      expect(
        views.whereType<FailurePresentation>().single.message,
        'The event pass is still waiting to be delivered.',
      );
      expect(views.last, isNull);
      final failedState =
          (jsonDecode(snapshots.single) as Map)['events']['pending'];
      expect(failedState['action'], 0);
      expect(failedState['index'], 0);
      expect(snapshots.single, isNot(contains('Delivery pending')));
      expect(snapshots.single, isNot(contains('deliveryPending')));
      await runner.stop();
    },
  );

  test(
    'changing error wording across recovery does not rewrite queued work or reveal unexpected exceptions',
    () async {
      final progress = MemoryProgress();
      final definition = AutomationDefinition(
        'events',
        const ComponentDefinition('test.trigger', {}),
        [
          const ComponentDefinition(
            'test.action',
            {},
            id: 'delivery',
            errorMap: {'http.forbidden': 'eventConnection'},
          ),
        ],
        null,
      );
      Future<FailurePresentation> failOnce(
        Json catalog,
        QueueTrigger source,
      ) async {
        FailurePresentation? view;
        final runner = AutomationRunner(
          definition: definition,
          context: context(),
          store: progress,
          key: 'events',
          errorMessages: catalog,
          onStatus: (_) {},
          onFailure: (value) => view = value,
          registry: AutomationRegistry(
            triggers: {
              'test.trigger': ComponentRegistration((_) {}, (_, __) => source),
            },
            actions: {
              'test.action': ComponentRegistration(
                (_) {},
                (_, __) => FunctionAction((_) async {
                  throw const RuntimeFailure(
                    'Request denied.',
                    code: 'http.forbidden',
                    permanent: true,
                  );
                }),
              ),
            },
          ),
        );
        await runner.start();
        await runner.stop();
        return view!;
      }

      expect(
        (await failOnce(
          messages('Original guidance.'),
          QueueTrigger([
            const TriggerBatch([
              {'id': 'pass-1'},
            ]),
          ]),
        )).message,
        'Original guidance.',
      );
      final persisted = jsonEncode(progress.values);
      expect(
        (await failOnce(
          messages('Updated guidance.'),
          QueueTrigger([]),
        )).message,
        'Updated guidance.',
      );
      expect(jsonEncode(progress.values), persisted);

      final views = <FailurePresentation?>[];
      final unsafe = FailingTrigger(
        StateError('raw-secret-token-and-response-body'),
      );
      final runner = AutomationRunner(
        definition: definition,
        context: context(),
        store: MemoryProgress(),
        key: 'unhandled',
        onStatus: (_) {},
        onFailure: views.add,
        registry: AutomationRegistry(
          triggers: {
            'test.trigger': ComponentRegistration((_) {}, (_, __) => unsafe),
          },
          actions: {
            'test.action': ComponentRegistration(
              (_) {},
              (_, __) => FunctionAction((e) async => e),
            ),
          },
        ),
      );
      await runner.start();
      expect(views.single!.code, 'runtime.unexpected');
      expect(views.single!.message, isNot(contains('raw-secret')));
      await runner.stop();
    },
  );
}
