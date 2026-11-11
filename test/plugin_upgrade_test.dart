import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:bottogram/plugins/bot_setup.dart';
import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/plugins/upgrade.dart';
import 'package:bottogram/runtime/ports.dart';
import 'package:bottogram/runtime/progress_store.dart';
import 'package:bottogram/runtime/coordinator.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_bot.dart';

import 'plugins_test.dart' show MemoryVault, TestContext;
import 'automation_runtime_test.dart' show until;
import 'runtime_lifecycle_test.dart' show TestLease;

class QueueBot extends VirtBot {
  QueueBot(super.name, super.token) : super(addSamples: false);
  bool running = false;
  @override
  bool get active => running;
}

class QueueBotAdapter extends TypeAdapter<QueueBot> {
  @override
  int get typeId => 121;
  @override
  QueueBot read(BinaryReader reader) =>
      QueueBot(reader.readString(), reader.readString());
  @override
  void write(BinaryWriter writer, QueueBot obj) {
    writer.writeString(obj.name);
    writer.writeString(obj.token);
  }
}

class FailableProgress extends HiveProgressStore {
  bool fail = false;
  int copies = 0;
  @override
  Future<void> copyNamespace(String source, String destination) async {
    copies++;
    if (fail) throw StateError('Injected staging failure');
    await super.copyNamespace(source, destination);
  }
}

class QueueRuntime extends BotRuntime {
  QueueRuntime(PluginRepository plugins, NamespaceProgressStore progress)
    : super(TestLease(), plugins, progress: progress);
  int starts = 0;
  bool failStart = false;
  int stops = 0;
  Completer<void>? stopDrain;
  bool waitingForDrain = false;
  @override
  Future<void> start(VirtBot bot) async {
    starts++;
    if (failStart) throw StateError('Injected start failure');
    (bot as QueueBot).running = true;
  }

  @override
  Future<void> stop(VirtBot bot) async {
    if (stopDrain != null) {
      waitingForDrain = true;
      await stopDrain!.future;
      stopDrain = null;
      waitingForDrain = false;
    }
    if (bot.active) {
      stops++;
    }
    (bot as QueueBot).running = false;
  }
}

Map<String, dynamic> definition({String version = '1.0.0'}) => {
  'manifestVersion': 2,
  'hostApiMajor': 2,
  'id': 'example.integration',
  'name': 'Example integration',
  'version': version,
  'executionStatus': 'live',
  'requiresBotFields': ['adminTelegramUserId'],
  'setupFields': [
    {
      'key': 'credential',
      'label': 'API credential',
      'type': 'secret',
      'required': true,
    },
    {
      'key': 'publicOrigin',
      'label': 'Public origin',
      'type': 'text',
      'required': true,
    },
  ],
  'settings': [
    {
      'key': 'notify',
      'type': 'boolean',
      'label': 'Notifications',
      'default': true,
    },
  ],
  'automations': [
    {
      'id': 'navigation',
      'trigger': {
        'type': 'telegram.command.v1',
        'config': {'command': 'directory'},
      },
      'actions': [
        {
          'id': 'reply',
          'type': 'telegram.reply.v1',
          'config': {'text': 'Directory'},
        },
      ],
    },
    {
      'id': 'monitor',
      'enabledBySetting': 'notify',
      'trigger': {
        'type': 'http.poll.v1',
        'config': {
          'intervalSeconds': 60,
          'initialSync': 'baseline',
          'request': {
            'method': 'GET',
            'url': 'https://api.example.test/events',
            'headers': {
              'Origin': {'field': 'publicOrigin', 'transform': 'url.origin'},
              'X-Storefront-Host': {
                'field': 'publicOrigin',
                'transform': 'url.authority',
              },
            },
            'authentication': {'type': 'bearer', 'secretField': 'credential'},
          },
          'response': {
            'itemsPath': 'events',
            'itemIdPath': 'id',
            'checkpointPath': 'checkpoint',
          },
          'pagination': {
            'cursorQueryParameter': 'cursor',
            'nextPagePath': 'next',
            'hasMorePath': 'hasMore',
          },
        },
      },
      'actions': [
        {
          'id': 'notify',
          'type': 'telegram.notify-admin.v1',
          'config': {'text': 'Event {{event.id}}'},
        },
      ],
    },
  ],
};

PluginManifest manifest(Map<String, dynamic> value) =>
    PluginManifest.parse(utf8.encode(jsonEncode(value)));

Map<String, dynamic> nextDefinition() {
  final value = definition(version: '1.1.0');
  value['automations'][0]['trigger']['config']['command'] = 'open';
  value['automations'][0]['actions'][0]['config']['text'] =
      'Open the integration';
  value['setupFields'][0]['helpText'] =
      'Updated help does not change execution context.';
  return value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PluginRepository repository;
  late MemoryVault vault;
  late PluginManifest old;
  late BotSetup setup;
  const token = '99:upgrade-test';

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bottogram-upgrades-');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(121)) Hive.registerAdapter(QueueBotAdapter());
    vault = MemoryVault();
    repository = PluginRepository(vault: vault, bundledAssets: const []);
    await repository.ready;
    old = manifest(definition());
    await repository.install(old);
    setup = await repository.prepare(
      token: token,
      adminIds: '123',
      plugin: old,
      parameters: {
        'credential': 'test-secret',
        'publicOrigin': 'https://public.example.test',
      },
    );
    setup = setup.withSettings({'notify': false});
    await repository.attach(1, setup);
  });

  tearDown(() async {
    repository.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'generic review compares object structure and preserves unchanged background definitions',
    () async {
      final data = nextDefinition();
      final request = Map<String, dynamic>.from(
        data['automations'][1]['trigger']['config']['request'] as Map,
      );
      data['automations'][1]['trigger']['config']['request'] = Map.fromEntries(
        request.entries.toList().reversed,
      );
      final target = manifest(data);
      await repository.install(target);
      final plan = await repository.reviewUpgrade(1, token, target);
      expect(plan.preservedAutomationIds, ['monitor']);
      expect(plan.replacedAutomationIds, ['navigation']);
      expect(plan.addedAutomationIds, isEmpty);
      expect(plan.removedAutomationIds, isEmpty);
      expect(comparePluginVersions('1.10.0', '1.9.9'), greaterThan(0));
      expect(
        comparePluginVersions('99999999999999999999.0.0', '1.0.0'),
        greaterThan(0),
      );
      expect((await repository.setupFor(1, token))!.pluginDigest, old.digest);
    },
  );

  test(
    'state-preserving update rejects altered setup semantics, settings defaults and background behavior',
    () {
      final changedField = nextDefinition();
      changedField['setupFields'][1]['default'] = 'https://other.example.test';
      final changedSetting = nextDefinition();
      changedSetting['settings'][0]['default'] = false;
      final changedPoll = nextDefinition();
      changedPoll['automations'][1]['trigger']['config']['intervalSeconds'] =
          120;
      final removedPoll = nextDefinition();
      removedPoll['automations'].removeLast();
      for (final value in [
        changedField,
        changedSetting,
        changedPoll,
        removedPoll,
      ]) {
        expect(
          () => PluginUpgradePlan.review(old, manifest(value), setup),
          throwsA(isA<PluginException>()),
        );
      }
      final otherId = nextDefinition()..['id'] = 'another.integration';
      expect(
        () => PluginUpgradePlan.review(old, manifest(otherId), setup),
        throwsA(isA<PluginException>()),
      );
      expect(
        () => PluginUpgradePlan.review(old, old, setup),
        throwsA(isA<PluginException>()),
      );
    },
  );

  test(
    'upgrade retains saved setup, secure references and all progress after reopening Hive',
    () async {
      final target = manifest(nextDefinition());
      await repository.install(target);
      final progress = HiveProgressStore();
      final from = '${setup.instanceId}:${old.digest}:monitor';
      final to = '${setup.instanceId}:${target.digest}:monitor';
      final state = <String, dynamic>{
        'initialized': true,
        'checkpoint': 'earlier',
        'pageCursor': 'next-page',
        'cycleCheckpoint': 'current',
        'pending': {
          'events': [
            {'id': 'queued'},
          ],
          'index': 0,
          'action': 1,
          'checkpoint': 'current',
          'nextCursor': 'later',
        },
      };
      await progress.write(from, state);
      await progress.write('$from:delivered:first', {'complete': true});
      await progress.write('$from:delivered:second', {'complete': true});
      await progress.write('other:${old.digest}:monitor:delivered:other', {
        'complete': true,
      });
      final updated = await repository.upgrade(
        1,
        token,
        target,
        copyNamespace: progress.copyNamespace,
      );
      expect(updated.instanceId, setup.instanceId);
      expect(updated.tokenFingerprint, setup.tokenFingerprint);
      expect(updated.adminIds, setup.adminIds);
      expect(updated.values, setup.values);
      expect(updated.secretFields, setup.secretFields);
      expect(updated.settings, {'notify': false});
      expect(updated.toMap().keys, setup.toMap().keys);
      expect(await vault.read(setup.secretKey('credential')), 'test-secret');
      expect(
        repository.installed.map((p) => p.storageKey),
        containsAll([old.storageKey, target.storageKey]),
      );
      expect(await progress.read(from), state);
      expect(await progress.read(to), state);
      repository.dispose();
      await Hive.close();
      repository = PluginRepository(vault: vault, bundledAssets: const []);
      await repository.ready;
      final reopened = HiveProgressStore();
      expect(
        (await repository.setupFor(1, token))!.pluginDigest,
        target.digest,
      );
      expect(await reopened.read(to), state);
      expect(await reopened.read('$to:delivered:first'), {'complete': true});
      expect(await reopened.read('$to:delivered:second'), {'complete': true});
      expect(
        await reopened.read('other:${old.digest}:monitor:delivered:other'),
        {'complete': true},
      );
    },
  );

  test(
    'interrupted progress staging leaves the old pin intact and retry rebuilds destination from current source',
    () async {
      final target = manifest(nextDefinition());
      await repository.install(target);
      final progress = HiveProgressStore();
      final from = '${setup.instanceId}:${old.digest}:monitor';
      final to = '${setup.instanceId}:${target.digest}:monitor';
      await progress.write(from, {'initialized': true, 'checkpoint': 'before'});
      await progress.write('$from:delivered:old', {'complete': true});
      await expectLater(
        repository.upgrade(
          1,
          token,
          target,
          copyNamespace: (source, destination) async {
            await progress.copyNamespace(source, destination);
            throw StateError('Injected interruption before publishing pin');
          },
        ),
        throwsStateError,
      );
      expect((await repository.setupFor(1, token))!.toMap(), setup.toMap());
      await progress.write(from, {'initialized': true, 'checkpoint': 'after'});
      await progress.write('$from:delivered:new', {'complete': true});
      await progress.write('$to:delivered:unpublished', {'complete': true});
      await repository.upgrade(
        1,
        token,
        target,
        copyNamespace: progress.copyNamespace,
      );
      expect(await progress.read(to), {
        'initialized': true,
        'checkpoint': 'after',
      });
      expect(await progress.read('$to:delivered:new'), {'complete': true});
      expect(await progress.read('$to:delivered:unpublished'), isEmpty);
      expect(await progress.read('$from:delivered:old'), {'complete': true});
    },
  );

  test(
    'namespace copying cannot cross a bot or automation and leaves sibling prefixes intact',
    () async {
      final progress = HiveProgressStore();
      await progress.write('same:old:monitor', {'initialized': true});
      await progress.write('same:new:monitor-extra', {'keep': true});
      for (final destination in [
        'other:new:monitor',
        'same:new:different',
        'same:old:monitor',
      ]) {
        await expectLater(
          progress.copyNamespace('same:old:monitor', destination),
          throwsA(isA<RuntimeFailure>()),
        );
      }
      await progress.copyNamespace('same:old:monitor', 'same:new:monitor');
      expect(await progress.read('same:new:monitor'), {'initialized': true});
      expect(await progress.read('same:new:monitor-extra'), {'keep': true});
      expect(await progress.read('same:old:monitor'), {'initialized': true});
    },
  );

  test(
    'an invalid public origin prevents only the reviewed update and never rewrites the old origin',
    () async {
      final data = nextDefinition();
      data['telegram'] = {
        'menuButton': {
          'text': 'Open',
          'webApp': {'originField': 'publicOrigin', 'path': '/account'},
        },
      };
      final target = manifest(data);
      await repository.install(target);
      final invalid = BotSetup(
        instanceId: setup.instanceId,
        tokenFingerprint: setup.tokenFingerprint,
        adminIds: setup.adminIds,
        pluginKey: setup.pluginKey,
        pluginDigest: setup.pluginDigest,
        pluginName: setup.pluginName,
        values: {'publicOrigin': 'http://localhost:3000'},
        secretFields: setup.secretFields,
        settings: setup.settings,
      );
      await repository.attach(1, invalid);
      await expectLater(
        repository.reviewUpgrade(1, token, target),
        throwsA(
          isA<PluginException>().having(
            (e) => e.message,
            'message',
            contains('HTTPS'),
          ),
        ),
      );
      expect((await repository.setupFor(1, token))!.toMap(), invalid.toMap());
      expect(await vault.read(setup.secretKey('credential')), 'test-secret');
    },
  );

  test(
    'active updates drain old work, restore the previous version on failure, and restart on success',
    () async {
      // BotsCubit reconciliation operates on real setup records and bot keys.
      // This test-only adapter supplies controllable running state without any
      // network session or real credentials.
      final progress = FailableProgress();
      final runtime = QueueRuntime(repository, progress);
      final bots = BotsCubit(
        TestContext(),
        plugins: repository,
        runtime: runtime,
      );
      await bots.ready;
      final bot = QueueBot('Existing bot', token)..running = true;
      final peer = QueueBot('Unrelated bot', '100:peer')..running = true;
      bots.add(bot);
      bots.add(peer);
      await until(() => bots.state.length == 2);
      final attached = await repository.prepare(
        token: token,
        adminIds: '123',
        plugin: old,
        parameters: {
          'credential': 'test-secret',
          'publicOrigin': 'https://public.example.test',
        },
      );
      bot.setup = attached;
      await repository.attach(bot.key, attached);
      final target = manifest(nextDefinition());
      await repository.install(target);
      final from = '${attached.instanceId}:${old.digest}:monitor';
      final to = '${attached.instanceId}:${target.digest}:monitor';
      await progress.write(from, {'initialized': true, 'pageCursor': 'resume'});
      try {
        progress.fail = true;
        runtime.stopDrain = Completer<void>();
        final updating = bots.upgradePlugin(bot, target);
        final failure = expectLater(updating, throwsA(isA<PluginException>()));
        await until(() => runtime.waitingForDrain);
        expect(progress.copies, 0);
        expect(runtime.starts, 0);
        expect(peer.active, isTrue);
        // A final old-session acknowledgement arrives while cleanup drains.
        final drainedState = {
          'initialized': true,
          'pageCursor': 'drained',
          'pending': {'action': 1},
        };
        await progress.write(from, drainedState);
        runtime.stopDrain!.complete();
        await failure;
        expect(bot.active, isTrue);
        expect(runtime.starts, 1);
        expect(
          (await repository.setupFor(bot.key, token))!.pluginDigest,
          old.digest,
        );
        expect(await progress.read(from), drainedState);
        expect(await progress.read(to), isEmpty);

        progress.fail = false;
        await bots.upgradePlugin(bot, target);
        expect(bot.active, isTrue);
        expect(peer.active, isTrue);
        expect(runtime.stops, 2);
        expect(runtime.starts, 2);
        expect(bot.setup!.pluginDigest, target.digest);
        expect(await progress.read(to), drainedState);

        final later = nextDefinition()..['version'] = '1.2.0';
        final next = manifest(later);
        await repository.install(next);
        runtime.failStart = true;
        await expectLater(
          bots.upgradePlugin(bot, next),
          throwsA(
            isA<PluginException>().having(
              (error) => error.message,
              'message',
              contains('Plugin update saved'),
            ),
          ),
        );
        expect(bot.active, isFalse);
        expect(peer.active, isTrue);
        expect(
          (await repository.setupFor(bot.key, token))!.pluginDigest,
          next.digest,
        );
      } finally {
        await bots.close();
      }
    },
  );
}
