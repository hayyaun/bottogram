import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/plugins/parameters_form.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/runtime/coordinator.dart';
import 'package:bottogram/runtime/ports.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'automation_runtime_test.dart' show until;
import 'plugin_upgrade_test.dart' show QueueBot, QueueBotAdapter, definition;
import 'plugins_test.dart' show MemoryVault, TestContext;
import 'runtime_lifecycle_test.dart' show TestLease;

class ParameterProgress implements ProgressStore {
  final records = <String, Json>{};
  final removed = <String>[];

  @override
  Future<Json> read(String key) async => records[key] ?? {};

  @override
  Future<void> write(String key, Json value) async => records[key] = value;

  @override
  Future<void> removeInstance(String instanceId) async {
    removed.add(instanceId);
    records.removeWhere((key, _) => key.startsWith('$instanceId:'));
  }
}

class ParameterRuntime extends BotRuntime {
  ParameterRuntime(PluginRepository plugins, ParameterProgress progress)
    : super(TestLease(), plugins, progress: progress);

  int starts = 0;
  int stops = 0;
  Completer<void>? drain;
  final stopEntered = Completer<void>();
  bool failStop = false;

  @override
  Future<void> start(VirtBot bot) async {
    starts++;
    (bot as QueueBot).running = true;
  }

  @override
  Future<void> stop(VirtBot bot) async {
    stops++;
    if (!stopEntered.isCompleted) stopEntered.complete();
    await drain?.future;
    if (failStop) throw StateError('Session did not drain');
    (bot as QueueBot).running = false;
    bot.runtimeError = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late MemoryVault vault;
  late PluginRepository repository;
  late ParameterProgress progress;
  late ParameterRuntime runtime;
  late BotsCubit bots;
  late QueueBot bot;
  late PluginManifest plugin;
  const token = '199:parameter-test';
  const origin = 'https://original.example.test';
  const changedOrigin = 'https://changed.example.test';

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bottogram-parameters-');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(121)) Hive.registerAdapter(QueueBotAdapter());
    vault = MemoryVault();
    repository = PluginRepository(vault: vault, bundledAssets: const []);
    await repository.ready;
    // This live manifest binds a URL field and a secure credential to an HTTP
    // request. The fake runtime below never executes it or contacts a service.
    plugin = PluginManifest.parse(utf8.encode(jsonEncode(definition())));
    await repository.install(plugin);
    progress = ParameterProgress();
    runtime = ParameterRuntime(repository, progress);
    bots = BotsCubit(TestContext(), plugins: repository, runtime: runtime);
    await bots.ready;
    bot = QueueBot('Parameter test', token);
    bots.add(bot);
    await until(() => bots.state.contains(bot));
    bot.setup = await repository.prepare(
      token: token,
      adminId: '123',
      plugin: plugin,
      parameters: {'credential': 'original-test-key', 'publicOrigin': origin},
    );
    await repository.attach(bot.key, bot.setup!);
    bot.setup = await repository.updateSettings(bot.key, token, {
      'notify': false,
    });
  });

  tearDown(() async {
    await bots.close();
    repository.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'changed URL preserves a blank credential and notification preference, drains the old session, and clears stale failure without starting',
    () async {
      final previous = bot.setup!;
      final oldProgress = '${previous.instanceId}:${plugin.digest}:monitor';
      await progress.write(oldProgress, {'checkpoint': 'saved'});
      bot.runtimeError = 'http.forbidden';
      final drain = runtime.drain = Completer<void>();

      final saving = bots.updatePluginParameters(
        bot,
        adminId: '123',
        parameters: {'credential': '', 'publicOrigin': changedOrigin},
      );
      try {
        await until(() => runtime.stopEntered.isCompleted);
        expect(bot.runtimeError, 'http.forbidden');
        expect(progress.records[oldProgress], {'checkpoint': 'saved'});
        expect(progress.removed, isEmpty);
        expect(runtime.starts, 0);
      } finally {
        drain.complete();
      }
      await saving;

      final changed = bot.setup!;
      expect(changed.instanceId, isNot(previous.instanceId));
      expect(changed.values['publicOrigin'], changedOrigin);
      expect(changed.settings['notify'], isFalse);
      expect(changed.adminTelegramUserId, '123');
      expect(
        await vault.read(changed.secretKey('credential')),
        'original-test-key',
      );
      expect(await vault.read(previous.secretKey('credential')), isNull);
      expect(bot.runtimeError, isNull);
      expect(bot.active, isFalse);
      expect(runtime.stops, 1);
      expect(runtime.starts, 0);
      expect(progress.removed, [previous.instanceId]);
      expect(progress.records, isEmpty);
      expect(
        (await repository.setupFor(bot.key, token))!.instanceId,
        changed.instanceId,
      );

      await bots.updatePluginParameters(
        bot,
        adminId: '123',
        parameters: {
          'credential': 'replacement-test-key',
          'publicOrigin': changedOrigin,
        },
      );
      expect(
        await vault.read(bot.setup!.secretKey('credential')),
        'replacement-test-key',
      );
      expect(await vault.read(changed.secretKey('credential')), isNull);
      expect(vault.values.length, 1);
      expect(bot.setup!.settings['notify'], isFalse);
      expect(bot.active, isFalse);
      expect(runtime.starts, 0);
    },
  );

  test(
    'failed and unchanged saves keep the stopped bot failure and configuration',
    () async {
      final previous = bot.setup!;
      bot.runtimeError = 'http.forbidden';
      vault.failWrite = true;
      await expectLater(
        bots.updatePluginParameters(
          bot,
          adminId: '123',
          parameters: {
            'credential': 'replacement-test-key',
            'publicOrigin': changedOrigin,
          },
        ),
        throwsA(isA<PluginException>()),
      );
      expect(bot.setup!.instanceId, previous.instanceId);
      expect(bot.setup!.values['publicOrigin'], origin);
      expect(
        await vault.read(previous.secretKey('credential')),
        'original-test-key',
      );
      expect(bot.setup!.settings['notify'], isFalse);
      expect(bot.runtimeError, 'http.forbidden');
      expect(runtime.stops, 0);
      expect(runtime.starts, 0);
      expect(progress.removed, isEmpty);

      vault.failWrite = false;
      await bots.updatePluginParameters(
        bot,
        adminId: '123',
        parameters: {'credential': '', 'publicOrigin': origin},
      );
      expect(bot.setup!.instanceId, previous.instanceId);
      expect(bot.runtimeError, 'http.forbidden');
      expect(runtime.stops, 0);
      expect(runtime.starts, 0);
      expect(progress.removed, isEmpty);
    },
  );

  test(
    'changed parameters preserve the existing running-bot restart intent',
    () async {
      bot.running = true;
      await bots.updatePluginParameters(
        bot,
        adminId: '123',
        parameters: {'credential': '', 'publicOrigin': changedOrigin},
      );
      expect(runtime.stops, 1);
      expect(runtime.starts, 1);
      expect(bot.active, isTrue);
      expect(bot.setup!.values['publicOrigin'], changedOrigin);
      expect(bot.setup!.settings['notify'], isFalse);
      expect(
        await vault.read(bot.setup!.secretKey('credential')),
        'original-test-key',
      );
    },
  );

  test(
    'a failed residual-session drain reports the committed save and retains its progress',
    () async {
      final previous = bot.setup!;
      final oldProgress = '${previous.instanceId}:${plugin.digest}:monitor';
      await progress.write(oldProgress, {'checkpoint': 'saved'});
      bot.runtimeError = 'http.forbidden';
      runtime.failStop = true;
      await expectLater(
        bots.updatePluginParameters(
          bot,
          adminId: '123',
          parameters: {'credential': '', 'publicOrigin': changedOrigin},
        ),
        throwsA(
          isA<PluginException>().having(
            (error) => error.message,
            'message',
            startsWith('Parameters saved.'),
          ),
        ),
      );
      expect(bot.setup!.values['publicOrigin'], changedOrigin);
      expect(bot.setup!.settings['notify'], isFalse);
      expect(bot.runtimeError, 'http.forbidden');
      expect(progress.records[oldProgress], {'checkpoint': 'saved'});
      expect(progress.removed, isEmpty);
      expect(bot.active, isFalse);
      expect(runtime.starts, 0);
    },
  );

  testWidgets(
    'saved credentials have a visible status while URL edits submit a blank secret',
    (tester) async {
      Map<String, String>? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PluginParametersForm(
                plugin: plugin,
                setup: bot.setup!,
                onSave: (adminId, values) async => submitted = values,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Saved securely'), findsOneWidget);
      expect(find.text('original-test-key'), findsNothing);
      final credential = find.widgetWithText(TextFormField, 'API credential');
      expect(
        tester.widget<TextFormField>(credential).controller!.text,
        isEmpty,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Public origin'),
        changedOrigin,
      );
      await tester.ensureVisible(find.text('Save parameters'));
      await tester.tap(find.text('Save parameters'));
      await tester.pumpAndSettle();
      expect(submitted, {'credential': '', 'publicOrigin': changedOrigin});
      expect(find.text('Saved securely'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(credential).controller!.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
