import 'dart:io';

import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/runtime/coordinator.dart';
import 'package:bottogram/store/app_preferences.dart';
import 'package:bottogram/store/bots.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'automation_runtime_test.dart' show MemoryProgress, until;
import 'plugins_test.dart' show MemoryVault, TestContext;
import 'runtime_lifecycle_test.dart' show RuntimeBot, TestLease;

class RuntimeBotAdapter extends TypeAdapter<RuntimeBot> {
  @override
  int get typeId => 122;
  @override
  RuntimeBot read(BinaryReader reader) =>
      RuntimeBot(reader.readString(), reader.readString());
  @override
  void write(BinaryWriter writer, RuntimeBot bot) {
    writer.writeString(bot.name);
    writer.writeString(bot.token);
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'cold foreground launch restores enabled bots and remembers explicit stops',
    () async {
      final directory = await Directory.systemTemp.createTemp('bot-resume-');
      final preferences = BotRunPreferences();
      if (!Hive.isAdapterRegistered(122)) {
        Hive.registerAdapter(RuntimeBotAdapter());
      }
      final lease = TestLease();

      Future<BotsCubit> reopen() async {
        Hive.init(directory.path);
        final plugins = PluginRepository(
          vault: MemoryVault(),
          bundledAssets: [],
        );
        addTearDown(plugins.dispose);
        final runtime = BotRuntime(lease, plugins, progress: MemoryProgress());
        final store = BotsCubit(
          TestContext(),
          plugins: plugins,
          runtime: runtime,
          runPreferences: preferences,
        );
        await store.ready;
        return store;
      }

      void foreground() {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }

      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      var bots = await reopen();
      try {
        final first = RuntimeBot('Enabled', '1:first');
        final stopped = RuntimeBot('Stopped', '2:second');
        bots.add(first);
        bots.add(stopped);
        await until(() => bots.state.length == 2);

        lease.fail = true;
        await expectLater(bots.toggle(first), throwsStateError);
        expect(await preferences.read(), isEmpty);
        lease.fail = false;
        await bots.toggle(first);
        await bots.toggle(stopped);
        await bots.toggle(stopped);
        expect((await preferences.read()).length, 1);
        expect(lease.totals.last, 2);
        expect(lease.counts.last, 1);

        // Losing the Android service is different from pressing Stop bots.
        await bots.runtime.stopAll();
        expect((await preferences.read()).length, 1);
        await bots.close();
        await Hive.close();

        bots = await reopen();
        final restored = bots.state.first as RuntimeBot;
        final stillStopped = bots.state.last as RuntimeBot;
        expect(restored.starts, 0);
        expect(restored.resumeOnLaunch, isTrue);
        expect(stillStopped.resumeOnLaunch, isFalse);
        foreground();
        await until(() => restored.active);
        expect(stillStopped.starts, 0);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await Future<void>.delayed(Duration.zero);
        expect(restored.starts, 1);

        await bots.stopAll();
        expect(await preferences.read(), isEmpty);
        expect(bots.runtime.activeCount, 0);
        await bots.close();
        await Hive.close();

        bots = await reopen();
        await Future<void>.delayed(Duration.zero);
        expect(
          bots.state.every((bot) => !bot.active && !bot.resumeOnLaunch),
          isTrue,
        );
      } finally {
        if (!bots.isClosed) await bots.close();
        await Hive.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
