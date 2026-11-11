import 'dart:io';
import 'package:bottogram/builder/store.dart';
import 'package:bottogram/builder/values.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/templates/catalog.dart';
import 'package:bottogram/units/virt_act.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/units/virt_event.dart';
import 'package:bottogram/units/virt_rmu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'plugins_test.dart' show MemoryVault, TestContext;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late PluginRepository plugins;
  late BotsCubit bots;
  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'bottogram-template-creation-',
    );
    Hive.init(root.path);
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(VirtBotAdapter());
      Hive.registerAdapter(VirtEventAdapter());
      Hive.registerAdapter(VirtEventTypeAdapter());
      Hive.registerAdapter(VirtActAdapter());
      Hive.registerAdapter(VirtActTypeAdapter());
      Hive.registerAdapter(VirtRMUKeyboardAdapter());
      Hive.registerAdapter(VirtRMUInlineKeyboardAdapter());
      Hive.registerAdapter(KeyValueAdapter());
    }
    plugins = PluginRepository(vault: MemoryVault(), bundledAssets: const []);
    await plugins.ready;
    bots = BotsCubit(TestContext(), plugins: plugins);
    await bots.ready;
  });
  tearDown(() async {
    await bots.close();
    plugins.dispose();
    await BuilderStore.shared.close();
    await Hive.close();
    await root.delete(recursive: true);
  });
  test(
    'template events and variables persist without publishing a running bot',
    () async {
      final template = BotTemplates.all.first;
      final draft = BotTemplates.create(
        template,
        template.defaults(),
        template.sampleRows(),
        '99',
      );
      await bots.create(
        name: 'My quiz',
        token: '123:fixture',
        adminIds: '99, 98',
        template: draft,
      );
      expect(bots.state.single.active, isFalse);
      expect(bots.state.single.setup!.usesPlugin, isFalse);
      final originalSetup = bots.state.single.setup!;
      expect(originalSetup.adminIds, ['99', '98']);
      await bots.updateAdmins(bots.state.single, '98\n97');
      expect(bots.state.single.setup!.instanceId, originalSetup.instanceId);
      expect(
        bots.state.single.events.first.acts.any(
          (a) => a.type == VirtActType.renderList,
        ),
        isTrue,
      );
      expect(
        (await BuilderStore.shared.definitions(
          builderBotId('123:fixture'),
        )).map((definition) => definition.name),
        ['initialized', 'textQuiz'],
      );
      await expectLater(
        bots.create(
          name: 'Duplicate',
          token: '123:fixture',
          adminIds: '99',
          template: draft,
        ),
        throwsException,
      );
      await bots.close();
      await Hive.box<VirtBot>(BotsCubit.boxName).close();
      await BuilderStore.shared.close();
      bots = BotsCubit(TestContext(), plugins: plugins);
      await bots.ready;
      expect(bots.state.single.name, 'My quiz');
      expect(bots.state.single.setup!.adminIds, ['98', '97']);
      expect(bots.state.single.events.length, draft.events.length);
      expect(
        (await BuilderStore.shared.definitions(
          builderBotId('123:fixture'),
        )).map((definition) => definition.name),
        ['initialized', 'textQuiz'],
      );
      await bots.remove(bots.state.single);
      expect(
        await BuilderStore.shared.definitions(builderBotId('123:fixture')),
        isEmpty,
      );
    },
  );
  test(
    'orphaned bot data is preserved and never replaced by a template',
    () async {
      final id = builderBotId('456:fixture');
      await BuilderStore.shared.ready;
      await BuilderStore.shared.data.query(
        id,
        'CREATE TABLE existing_notes(note TEXT NOT NULL)',
        [],
      );
      await BuilderStore.shared.data.query(
        id,
        'INSERT INTO existing_notes VALUES(?)',
        ['Keep me'],
      );
      final template = BotTemplates.all[2];
      await expectLater(
        bots.create(
          name: 'Tasks',
          token: '456:fixture',
          adminIds: '99',
          template: BotTemplates.create(
            template,
            template.defaults(),
            template.sampleRows(),
            '99',
          ),
        ),
        throwsA(isA<BuilderFailure>()),
      );
      expect(bots.state, isEmpty);
      expect(
        (await BuilderStore.shared.data.query(
          id,
          'SELECT note FROM existing_notes',
          [],
        ))['rows'],
        [
          {'note': 'Keep me'},
        ],
      );
    },
  );
}
