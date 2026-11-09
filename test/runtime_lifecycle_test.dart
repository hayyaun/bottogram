import 'package:flutter_test/flutter_test.dart';
import 'package:televerse/televerse.dart';
import 'package:bottogram/runtime/coordinator.dart';
import 'package:bottogram/runtime/ports.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'automation_runtime_test.dart' show MemoryProgress;
import 'plugins_test.dart' show MemoryCatalog;

class TestLease implements ExecutionLease {
  final counts = <int>[];
  bool fail = false;
  @override
  Future<void> startService(int count) async {
    if (fail) throw StateError('Service unavailable');
    counts.add(count);
  }

  @override
  Future<void> updateService(int count) async {
    counts.add(count);
  }

  @override
  Future<void> stopService() async {
    counts.add(0);
  }
}

class InitializedBot extends Fake implements Bot<Context> {
  int initializations = 0;
  @override
  Future<void> init() async {
    initializations++;
  }
}

class RuntimeBot extends VirtBot {
  RuntimeBot() : super('Test', '1:testing', addSamples: false) {
    bot = InitializedBot();
  }
  bool running = false;
  int starts = 0;
  @override
  bool get active => running;
  @override
  Future<void> start({bool pluginRuntime = false}) async {
    starts++;
    running = true;
    onRunningChanged?.call();
  }

  @override
  Future<void> stop() async {
    running = false;
    onRunningChanged?.call();
  }
}

void main() {
  test(
    'one lifecycle owner serializes duplicate Starts and aggregates two bot leases',
    () async {
      final lease = TestLease();
      final catalog = MemoryCatalog();
      final runtime = BotRuntime(lease, catalog, progress: MemoryProgress());
      final first = RuntimeBot(), second = RuntimeBot();
      await Future.wait([
        runtime.start(first),
        runtime.start(first),
        runtime.start(second),
      ]);
      expect(first.starts, 1);
      expect(second.starts, 1);
      expect((first.bot as InitializedBot).initializations, 1);
      expect(runtime.activeCount, 2);
      expect(lease.counts.last, 2);
      await runtime.stop(first);
      expect(runtime.activeCount, 1);
      expect(lease.counts.last, 1);
      await runtime.stopAll();
      expect(runtime.activeCount, 0);
      expect(lease.counts.last, 0);
      await runtime.close();
      catalog.dispose();
    },
  );
  test(
    'foreground service failure prevents Telegram startup and releases the lease',
    () async {
      final lease = TestLease()..fail = true;
      final catalog = MemoryCatalog();
      final runtime = BotRuntime(lease, catalog, progress: MemoryProgress());
      final bot = RuntimeBot();
      await expectLater(runtime.start(bot), throwsStateError);
      expect(bot.starts, 0);
      expect((bot.bot as InitializedBot).initializations, 0);
      expect(runtime.activeCount, 0);
      expect(lease.counts.last, 0);
      await runtime.close();
      catalog.dispose();
    },
  );
}
