import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bottogram/runtime/automation_runner.dart';
import 'package:bottogram/runtime/ports.dart';
import 'package:bottogram/runtime/registry.dart';
import 'automation_runtime_test.dart'
    show MemoryProgress, FakeHttp, FakeTelegram, QueueTrigger, FunctionAction;

class _LongIntervalTrigger extends QueueTrigger {
  _LongIntervalTrigger()
    : super([
        const TriggerBatch([
          {'id': 'one'},
        ]),
      ]);
  @override
  Duration get interval => const Duration(minutes: 1);
}

void main() {
  testWidgets('Stop releases the pending polling timer', (tester) async {
    final store = MemoryProgress();
    final registry = AutomationRegistry(
      triggers: {
        'poll': ComponentRegistration(
          (_) {},
          (_, __) => _LongIntervalTrigger(),
        ),
      },
      actions: {
        'send': ComponentRegistration(
          (_) {},
          (_, __) => FunctionAction((event) async => event),
        ),
      },
    );
    final runner = AutomationRunner(
      definition: AutomationDefinition(
        'test',
        const ComponentDefinition('poll', {}),
        [const ComponentDefinition('send', {}, id: 'send')],
        null,
      ),
      context: RuntimeContext(
        http: FakeHttp(),
        telegram: FakeTelegram(),
        secret: (_) async => null,
        fields: {},
        adminIds: ['1'],
      ),
      store: store,
      key: 'timer-probe',
      registry: registry,
      onStatus: (_) {},
    );
    unawaited(runner.start());
    await tester.pump();
    expect(store.values['timer-probe']?['initialized'], isTrue);
    await runner.stop();
    await tester.pump();
    // Widget-test teardown rejects any timer left alive by the stopped runner.
  });
}
