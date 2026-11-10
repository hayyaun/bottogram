import 'dart:convert';
import 'dart:io';
import 'package:bottogram/builder/database.dart';
import 'package:bottogram/builder/storage_snapshot.dart';
import 'package:bottogram/builder/store.dart';
import 'package:bottogram/builder/values.dart';
import 'package:bottogram/units/virt_act.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/units/virt_event.dart';
import 'package:bottogram/units/virt_rmu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'plugins_test.dart' show MemoryVault;

class LegacyActionAdapter extends VirtActAdapter {
  @override
  int get typeId => 30;

  @override
  void write(BinaryWriter writer, VirtAct value) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(value.type)
      ..writeByte(1)
      ..write(value.text)
      ..writeByte(2)
      ..write(value.rmu);
  }
}

class LegacyEventAdapter extends VirtEventAdapter {
  @override
  int get typeId => 20;

  @override
  void write(BinaryWriter writer, VirtEvent value) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(value.type)
      ..writeByte(1)
      ..write(value.query)
      ..writeByte(2)
      ..write(value.acts);
  }
}

// Frozen pre-builder enum wire values, independent of the current enum order.
class LegacyActionTypeAdapter extends VirtActTypeAdapter {
  @override
  int get typeId => 31;

  @override
  VirtActType read(BinaryReader reader) => switch (reader.readByte()) {
    0 => VirtActType.reply,
    1 => VirtActType.dice,
    _ => throw StateError('Unknown legacy action'),
  };

  @override
  void write(BinaryWriter writer, VirtActType value) {
    writer.writeByte(switch (value) {
      VirtActType.reply => 0,
      VirtActType.dice => 1,
      _ => throw StateError('Not a legacy action'),
    });
  }
}

class LegacyEventTypeAdapter extends VirtEventTypeAdapter {
  @override
  int get typeId => 21;

  @override
  VirtEventType read(BinaryReader reader) => switch (reader.readByte()) {
    0 => VirtEventType.command,
    1 => VirtEventType.text,
    2 => VirtEventType.callbackQuery,
    3 => VirtEventType.inlineQuery,
    _ => throw StateError('Unknown legacy event'),
  };

  @override
  void write(BinaryWriter writer, VirtEventType value) {
    writer.writeByte(switch (value) {
      VirtEventType.command => 0,
      VirtEventType.text => 1,
      VirtEventType.callbackQuery => 2,
      VirtEventType.inlineQuery => 3,
      _ => throw StateError('Not a legacy event'),
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late BuilderStore store;
  final id = builderBotId('fixture');
  setUp(() async {
    root = await Directory.systemTemp.createTemp('bottogram-state-');
    Hive.init(root.path);
    store = BuilderStore(
      vault: MemoryVault(),
      data: BotDatabases(root: '${root.path}/data'),
    );
    await store.ready;
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(VirtBotAdapter());
    }
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(VirtActAdapter());
      Hive.registerAdapter(VirtActTypeAdapter());
      Hive.registerAdapter(VirtEventAdapter());
      Hive.registerAdapter(VirtEventTypeAdapter());
      Hive.registerAdapter(VirtRMUKeyboardAdapter());
      Hive.registerAdapter(VirtRMUInlineKeyboardAdapter());
      Hive.registerAdapter(KeyValueAdapter());
    }
  });
  tearDown(() async {
    await store.close();
    await Hive.close();
    await root.delete(recursive: true);
  });
  test(
    'old actions and events load unchanged; new settings round trip',
    () async {
      Hive.registerAdapter(LegacyActionAdapter(), override: true);
      Hive.registerAdapter(LegacyEventAdapter(), override: true);
      var box = await Hive.openBox<VirtEvent>('legacy');
      await box.put(
        'event',
        VirtEvent(type: VirtEventType.command, query: 'start')
          ..acts.add(VirtAct(type: VirtActType.reply, text: 'Hello!')),
      );
      await box.close();
      Hive.registerAdapter(VirtActAdapter(), override: true);
      Hive.registerAdapter(VirtEventAdapter(), override: true);
      box = await Hive.openBox<VirtEvent>('legacy');
      final event = box.get('event')!;
      expect(event.config, isEmpty);
      expect(event.acts.single.config, isEmpty);
      expect(event.acts.single.text, 'Hello!');
      event.config = {'intervalSeconds': 60};
      event.acts.add(
        VirtAct(type: VirtActType.http, text: '')
          ..config = {'url': 'https://example.com', 'output': 'lookup'},
      );
      await box.put('event', event);
      await box.close();
      box = await Hive.openBox<VirtEvent>('legacy');
      expect(box.get('event')!.acts.last.config['output'], 'lookup');
      expect(box.get('event')!.config['intervalSeconds'], 60);
    },
  );
  test(
    'nested legacy bots retain keyboard cells and enum wire values after editing',
    () async {
      Hive.registerAdapter(LegacyActionAdapter(), override: true);
      Hive.registerAdapter(LegacyEventAdapter(), override: true);
      Hive.registerAdapter(LegacyActionTypeAdapter(), override: true);
      Hive.registerAdapter(LegacyEventTypeAdapter(), override: true);
      final keyboard = VirtRMUKeyboard()
        ..name = null
        ..items = ['Yes', null, 'No', null];
      final inline = VirtRMUInlineKeyboard()
        ..name = 'Inline tools'
        ..items = [
          KeyValue('Open', 'https://example.com'),
          null,
          KeyValue('Choose', 'pick'),
        ];
      final legacyTypes = [
        VirtEventType.command,
        VirtEventType.text,
        VirtEventType.callbackQuery,
        VirtEventType.inlineQuery,
      ];
      final bot = VirtBot('Nested bot', '1:nested-fixture', addSamples: false)
        ..events = [
          for (var index = 0; index < legacyTypes.length; index++)
            VirtEvent(type: legacyTypes[index], query: 'query-$index')
              ..acts = [
                VirtAct(type: VirtActType.reply, text: 'Reply $index')
                  ..rmu = switch (index) {
                    0 => keyboard,
                    1 => inline,
                    _ => null,
                  },
                VirtAct(type: VirtActType.dice, text: ''),
              ],
        ];
      var box = await Hive.openBox<VirtBot>('nested');
      await box.put('bot', bot);
      await box.close();

      Hive.registerAdapter(VirtActAdapter(), override: true);
      Hive.registerAdapter(VirtEventAdapter(), override: true);
      Hive.registerAdapter(VirtActTypeAdapter(), override: true);
      Hive.registerAdapter(VirtEventTypeAdapter(), override: true);
      box = await Hive.openBox<VirtBot>('nested');
      var loaded = box.get('bot')!;
      expect(loaded.name, 'Nested bot');
      expect(loaded.token, '1:nested-fixture');
      expect(loaded.events.map((event) => event.type), legacyTypes);
      for (var index = 0; index < legacyTypes.length; index++) {
        final event = loaded.events[index];
        expect(event.query, 'query-$index');
        expect(event.config, isEmpty);
        expect(event.acts.map((action) => action.type), [
          VirtActType.reply,
          VirtActType.dice,
        ]);
        expect(event.acts.first.text, 'Reply $index');
        expect(event.acts.first.config, isEmpty);
        expect(event.acts.last.rmu, isNull);
      }
      final loadedKeyboard = loaded.events[0].acts.first.rmu as VirtRMUKeyboard;
      expect(loadedKeyboard.name, isNull);
      expect(loadedKeyboard.items, ['Yes', null, 'No', null]);
      final loadedInline =
          loaded.events[1].acts.first.rmu as VirtRMUInlineKeyboard;
      expect(loadedInline.name, 'Inline tools');
      expect(loadedInline.items, hasLength(3));
      expect(loadedInline.items[0]!.key, 'Open');
      expect(loadedInline.items[0]!.value, 'https://example.com');
      expect(loadedInline.items[1], isNull);
      expect(loadedInline.items[2]!.key, 'Choose');
      expect(loadedInline.items[2]!.value, 'pick');

      loaded.name = 'Edited bot';
      loaded.events[0].acts.first.config = {'parseMode': 'MarkdownV2'};
      await box.put('bot', loaded);
      await box.close();

      // A legacy reader must still understand values rewritten by this app.
      Hive.registerAdapter(LegacyActionTypeAdapter(), override: true);
      Hive.registerAdapter(LegacyEventTypeAdapter(), override: true);
      box = await Hive.openBox<VirtBot>('nested');
      loaded = box.get('bot')!;
      expect(loaded.name, 'Edited bot');
      expect(loaded.events.map((event) => event.type), legacyTypes);
      expect(loaded.events.last.acts.last.type, VirtActType.dice);
      await box.close();

      Hive.registerAdapter(VirtActTypeAdapter(), override: true);
      Hive.registerAdapter(VirtEventTypeAdapter(), override: true);
      box = await Hive.openBox<VirtBot>('nested');
      loaded = box.get('bot')!;
      loaded.events.add(
        VirtEvent(type: VirtEventType.polling, query: '')
          ..config = {'intervalSeconds': 60}
          ..acts = [
            VirtAct(type: VirtActType.sql, text: '')
              ..config = {'statement': 'SELECT 1', 'output': 'query'},
          ],
      );
      await box.put('bot', loaded);
      await box.close();

      box = await Hive.openBox<VirtBot>('nested');
      loaded = box.get('bot')!;
      expect(loaded.events.take(4).map((event) => event.type), legacyTypes);
      expect(loaded.events[0].acts.first.config['parseMode'], 'MarkdownV2');
      expect(loaded.events.last.type, VirtEventType.polling);
      expect(loaded.events.last.config['intervalSeconds'], 60);
      expect(loaded.events.last.acts.single.type, VirtActType.sql);
      expect(loaded.events.last.acts.single.config['output'], 'query');
    },
  );
  test(
    'defaults do not allocate rows and changed values survive restart with scope isolation',
    () async {
      await store.addDefinition(
        id,
        const VariableDefinition('score', 'user', 'number', 0),
      );
      await store.addDefinition(
        id,
        const VariableDefinition('total', 'bot', 'number', 0),
      );
      expect((await store.read(id, '1'))['user'], {'score': 0});
      expect(await store.data.read(id, 'user', '1'), isEmpty);
      await store.change(id, '1', 'user', 'score', 5, increment: true);
      await store.change(id, '2', 'user', 'score', 9);
      await store.change(id, null, 'bot', 'total', 2);
      await store.close();
      store = BuilderStore(
        vault: MemoryVault(),
        data: BotDatabases(root: '${root.path}/data'),
      );
      expect((await store.read(id, '1'))['user'], {'score': 5});
      expect((await store.read(id, '2'))['user'], {'score': 9});
      expect((await store.read(id, '1'))['bot'], {'total': 2});
      await store.change(id, '1', 'user', 'score', 0);
      expect(await store.data.read(id, 'user', '1'), isEmpty);
      await expectLater(
        store.change(id, null, 'user', 'score', 1),
        throwsA(isA<BuilderFailure>()),
      );
      await expectLater(
        store.change(id, '1', 'user', 'missing', 1),
        throwsA(isA<BuilderFailure>()),
      );
    },
  );
  test(
    'credentials have references in Hive but secret bytes only enter the vault',
    () async {
      await store.saveCredential(id, 'service', 'private-key-fixture');
      expect(await store.credentials(id), ['service']);
      expect(await store.secret(id, 'service'), 'private-key-fixture');
      final raw = await File(
        '${root.path}/builder_definitions_v1.hive',
      ).readAsBytes();
      expect(
        utf8.decode(raw, allowMalformed: true),
        isNot(contains('private-key-fixture')),
      );
    },
  );
  test(
    'pre-builder snapshot is verified once and never overwritten by later writes',
    () async {
      final box = await Hive.openBox<String>('snapshotfixture');
      await box.put('old', 'before');
      await ensureBuilderSnapshot(box);
      final manifest =
          jsonDecode(
                await File(
                  '${root.path}/builder_upgrade_backup/completed.json',
                ).readAsString(),
              )
              as Map;
      final snapshot = File(manifest['path'] as String);
      final original = await snapshot.readAsBytes();
      await box.put('new', 'after');
      await ensureBuilderSnapshot(box);
      expect(await snapshot.readAsBytes(), original);
    },
  );
}
