import 'dart:io';

import 'package:bottogram/pages/bot.dart';
import 'package:bottogram/plugins/bot_setup.dart';
import 'package:bottogram/plugins/bot_transfer.dart';
import 'package:bottogram/plugins/capability_review.dart';
import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/plugins/update_section.dart';
import 'package:bottogram/runtime/progress_store.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/ui/design.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/widgets/bot_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'automation_runtime_test.dart' show until;
import 'plugin_upgrade_test.dart'
    show
        QueueBot,
        QueueBotAdapter,
        QueueRuntime,
        definition,
        manifest,
        nextDefinition;
import 'plugins_test.dart' show MemoryCatalog, MemoryVault, TestContext;

Map<String, dynamic> eventUpdate() {
  final value = nextDefinition();
  value['name'] = 'Event tickets';
  value['description'] = 'Open the event portal and your passes.';
  value['telegram'] = {
    'menuButton': {
      'text': 'Open event',
      'webApp': {'originField': 'publicOrigin', 'path': '/events'},
    },
  };
  value['automations'][0] = {
    'id': 'navigation',
    'trigger': {
      'type': 'telegram.command.v2',
      'config': {
        'commands': ['tickets', 'passes'],
        'chatTypes': ['private'],
        'arguments': 'ignore',
      },
    },
    'actions': [
      {
        'id': 'reply',
        'type': 'telegram.reply.v2',
        'config': {
          'text': 'Your event passes',
          'inlineKeyboard': [
            [
              {
                'text': 'My passes',
                'webApp': {'originField': 'publicOrigin', 'path': '/tickets'},
              },
            ],
          ],
        },
      },
    ],
  };
  return value;
}

class UpdateUiFixture {
  UpdateUiFixture(
    this.directory,
    this.repository,
    this.bots,
    this.runtime,
    this.bot,
    this.old,
    this.target,
  );
  final Directory directory;
  final PluginRepository repository;
  final BotsCubit bots;
  final QueueRuntime runtime;
  final QueueBot bot;
  final PluginManifest old;
  final PluginManifest target;

  static Future<UpdateUiFixture> create({
    bool active = false,
    String origin = 'https://events.example.test',
    bool installTarget = true,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'bottogram-plugin-update-ui-',
    );
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(121)) Hive.registerAdapter(QueueBotAdapter());
    final repository = PluginRepository(
      vault: MemoryVault(),
      bundledAssets: const [],
    );
    await repository.ready;
    final old = manifest(definition());
    final target = manifest(eventUpdate());
    await repository.install(old);
    if (installTarget) await repository.install(target);
    final runtime = QueueRuntime(repository, HiveProgressStore());
    final bots = BotsCubit(
      TestContext(),
      plugins: repository,
      runtime: runtime,
    );
    await bots.ready;
    final bot = QueueBot('Existing event bot', '99:ui-test')..running = active;
    bots.add(bot);
    await until(() => bots.state.length == 1);
    final setup = await repository.prepare(
      token: bot.token,
      adminIds: '123',
      plugin: old,
      parameters: {'credential': 'test-key', 'publicOrigin': origin},
    );
    bot.setup = setup;
    await repository.attach(bot.key, setup);
    return UpdateUiFixture(
      directory,
      repository,
      bots,
      runtime,
      bot,
      old,
      target,
    );
  }

  Widget app({bool card = false}) => MultiProvider(
    providers: [
      ChangeNotifierProvider<PluginRepository>.value(value: repository),
      BlocProvider<BotsCubit>.value(value: bots),
    ],
    child: MaterialApp(
      theme: BottogramDesign.theme,
      home: Scaffold(
        body: card
            ? Center(
                child: SizedBox(
                  width: 316,
                  height: 248,
                  child: BotCard(bot: bot),
                ),
              )
            : SingleChildScrollView(
                child: PluginUpdateSection(bot: bot, plugin: old),
              ),
      ),
    ),
  );

  Future<void> close() async {
    await bots.close();
    repository.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  }
}

Future<void> tapAndWaitForIo(
  WidgetTester tester,
  Finder target,
  bool Function() ready,
) async {
  await tester.runAsync(() async {
    await tester.tap(target);
    for (var attempt = 0; attempt < 1000; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      await tester.pump();
      if (ready()) return;
    }
    fail('The plugin update UI did not finish its isolated operation.');
  });
  await tester.pumpAndSettle();
}

class QrShareBots extends Cubit<List<VirtBot>> implements BotsCubit {
  QrShareBots(VirtBot bot, this.transfer) : super([bot]);

  final PluginBotTransfer transfer;
  int exports = 0;

  @override
  Future<PluginBotTransfer> exportPluginBot(VirtBot bot) async {
    exports++;
    return transfer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}

void main() {
  testWidgets(
    'capability review renders arbitrary commands, destinations and menu declarations',
    (tester) async {
      final target = manifest(eventUpdate());
      Widget review({Map<String, String>? fields}) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PluginCapabilityReview(plugin: target, fields: fields),
          ),
        ),
      );
      await tester.pumpWidget(review());
      expect(find.text('/tickets · /passes · private chats'), findsOneWidget);
      expect(find.text('Menu button: Open event'), findsOneWidget);
      expect(
        find.text('Mini App: Public origin → /events (HTTPS)'),
        findsOneWidget,
      );
      expect(
        find.text('Mini App: Public origin → /tickets (HTTPS)'),
        findsOneWidget,
      );
      expect(find.text('GET https://api.example.test/events'), findsOneWidget);
      expect(find.textContaining('Inshopa'), findsNothing);
      expect(find.text('Open shop'), findsNothing);
      expect(find.text('My orders'), findsNothing);

      await tester.pumpWidget(
        review(fields: {'publicOrigin': 'https://events.example.test:8443'}),
      );
      expect(
        find.text(
          'Mini App: Public origin → https://events.example.test:8443/events',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Mini App: Public origin → https://events.example.test:8443/tickets',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(
        review(
          fields: {'publicOrigin': 'http://user:private-marker@localhost:3000'},
        ),
      );
      expect(find.textContaining('private-marker'), findsNothing);
      expect(
        find.text('Mini App: Public origin → /tickets (HTTPS)'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stopped bot review applies only after confirmation and does not start it',
    (tester) async {
      final fixture = (await tester.runAsync(() => UpdateUiFixture.create()))!;
      try {
        await tester.pumpWidget(fixture.app());
        await tapAndWaitForIo(
          tester,
          find.text('Review update'),
          () => find.byType(AlertDialog).evaluate().isNotEmpty,
        );
        expect(find.text('Apply update'), findsOneWidget);
        expect(find.text('Apply and restart'), findsNothing);
        expect(
          find.textContaining('The bot will stay stopped'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Progress retained: monitor.'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Mini App: Public origin → https://events.example.test/tickets',
          ),
          findsOneWidget,
        );
        expect(fixture.bot.setup!.pluginDigest, fixture.old.digest);
        await tapAndWaitForIo(
          tester,
          find.text('Cancel'),
          () => find.text('Review update').evaluate().isNotEmpty,
        );
        expect(fixture.bot.setup!.pluginDigest, fixture.old.digest);

        await tapAndWaitForIo(
          tester,
          find.text('Review update'),
          () => find.byType(AlertDialog).evaluate().isNotEmpty,
        );
        final identity = fixture.bot.setup!.instanceId;
        await tapAndWaitForIo(
          tester,
          find.text('Apply update'),
          () => fixture.bot.setup!.pluginDigest == fixture.target.digest,
        );
        expect(fixture.bot.active, isFalse);
        expect(fixture.runtime.starts, 0);
        expect(fixture.bot.setup!.instanceId, identity);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(fixture.close);
      }
    },
  );

  testWidgets(
    'the bot card reacts to a compatible install and leads to the reviewed update',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 610);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fixture = (await tester.runAsync(
        () => UpdateUiFixture.create(installTarget: false),
      ))!;
      try {
        final incompatible = eventUpdate();
        incompatible['version'] = '1.2.0';
        (incompatible['setupFields'] as List).add({
          'key': 'newField',
          'label': 'New required field',
          'type': 'text',
          'required': true,
        });
        await tester.runAsync(
          () => fixture.repository.install(manifest(incompatible)),
        );
        await tester.pumpWidget(fixture.app(card: true));
        expect(find.text('Update available'), findsNothing);

        await tester.runAsync(() => fixture.repository.install(fixture.target));
        await tester.pumpAndSettle();
        expect(find.text('Update available'), findsOneWidget);
        await tester.tap(find.text('Update available'));
        await tester.pumpAndSettle();
        expect(find.byType(BotPage), findsOneWidget);
        expect(find.text('Review update').hitTestable(), findsOneWidget);
        await tapAndWaitForIo(
          tester,
          find.text('Review update'),
          () => find.byType(AlertDialog).evaluate().isNotEmpty,
        );
        expect(find.text('Version 1.0.0 → 1.1.0'), findsOneWidget);
        final id = fixture.bot.setup!.instanceId;
        await tapAndWaitForIo(
          tester,
          find.text('Apply update'),
          () => fixture.bot.setup!.pluginDigest == fixture.target.digest,
        );
        expect(fixture.bot.setup!.instanceId, id);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('Update available'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(fixture.close);
      }
    },
  );

  testWidgets(
    'confirming an active update immediately applies it and restarts the bot',
    (tester) async {
      final fixture = (await tester.runAsync(
        () => UpdateUiFixture.create(active: true),
      ))!;
      try {
        await tester.pumpWidget(fixture.app());
        await tapAndWaitForIo(
          tester,
          find.text('Review update'),
          () => find.byType(AlertDialog).evaluate().isNotEmpty,
        );
        expect(find.textContaining('then start again'), findsOneWidget);
        expect(fixture.bot.setup!.pluginDigest, fixture.old.digest);
        expect(fixture.runtime.stops, 0);
        await tapAndWaitForIo(
          tester,
          find.text('Apply and restart'),
          () =>
              fixture.bot.setup!.pluginDigest == fixture.target.digest &&
              fixture.bot.active,
        );
        expect(fixture.runtime.stops, 1);
        expect(fixture.runtime.starts, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(fixture.close);
      }
    },
  );

  testWidgets('bot settings reveal the private QR only after two approvals', (
    tester,
  ) async {
    final plugin = manifest(definition());
    final repository = MemoryCatalog()..entries.add(plugin);
    final bot = VirtBot('Example bot', '1:fixture', addSamples: false)
      ..setup = BotSetup(
        instanceId: 'fixture',
        tokenFingerprint: BotSetup.fingerprint('1:fixture'),
        adminIds: const ['123'],
        pluginKey: plugin.storageKey,
        pluginDigest: plugin.digest,
        pluginName: plugin.name,
      );
    final bots = QrShareBots(
      bot,
      PluginBotTransfer(
        name: bot.name,
        token: bot.token,
        adminIds: bot.setup!.adminIds,
        pluginKey: plugin.storageKey,
        pluginDigest: plugin.digest,
        parameters: const {'credential': 'test-key'},
        settings: const {},
      ),
    );
    addTearDown(bots.close);
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PluginRepository>.value(value: repository),
          BlocProvider<BotsCubit>.value(value: bots),
        ],
        child: MaterialApp(home: BotPage(bot: bot)),
      ),
    );
    await tester.tap(find.text('Share as QR code'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Do not share this code'), findsOneWidget);
    expect(bots.exports, 0);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Reveal the private QR code?'), findsOneWidget);
    expect(bots.exports, 0);
    expect(find.byType(QrImageView), findsNothing);
    await tester.tap(find.text('Show QR code'));
    await tester.pumpAndSettle();
    expect(bots.exports, 1);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Private bot QR code'), findsOneWidget);
    expect(find.textContaining('test-key'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unsupported HTTP origin shows a sanitized review error and leaves the running bot pinned',
    (tester) async {
      const origin = 'http://user:private-marker@localhost:3000';
      final fixture = (await tester.runAsync(
        () => UpdateUiFixture.create(active: true, origin: origin),
      ))!;
      try {
        await tester.pumpWidget(fixture.app());
        final before = fixture.bot.setup!.toMap();
        await tapAndWaitForIo(
          tester,
          find.text('Review update'),
          () => find
              .textContaining('The saved public URL cannot')
              .evaluate()
              .isNotEmpty,
        );
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.textContaining('valid HTTPS origin'), findsOneWidget);
        expect(find.textContaining('private-marker'), findsNothing);
        expect(fixture.bot.setup!.toMap(), before);
        expect(fixture.bot.active, isTrue);
        expect(fixture.runtime.stops, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(fixture.close);
      }
    },
  );
}
