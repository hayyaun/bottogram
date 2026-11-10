import 'dart:io';

import 'package:bottogram/plugins/capability_review.dart';
import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/plugins/update_section.dart';
import 'package:bottogram/runtime/progress_store.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/ui/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

import 'automation_runtime_test.dart' show until;
import 'plugin_upgrade_test.dart'
    show
        QueueBot,
        QueueBotAdapter,
        QueueRuntime,
        definition,
        manifest,
        nextDefinition;
import 'plugins_test.dart' show MemoryVault, TestContext;

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
    await repository.install(target);
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
      adminId: '123',
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

  Widget app() => MultiProvider(
    providers: [
      ChangeNotifierProvider<PluginRepository>.value(value: repository),
      BlocProvider<BotsCubit>.value(value: bots),
    ],
    child: MaterialApp(
      theme: BottogramDesign.theme,
      home: Scaffold(
        body: SingleChildScrollView(
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
        expect(find.text('Queue for next Start'), findsNothing);
        expect(
          find.textContaining('It will not start the bot.'),
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
        expect(fixture.bots.pendingUpgradeFor(fixture.bot), isNull);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(fixture.close);
      }
    },
  );

  testWidgets(
    'running bot review queues a session-only selection and allows cancellation',
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
        expect(find.text('Queue for next Start'), findsOneWidget);
        expect(find.text('Apply update'), findsNothing);
        expect(
          find.textContaining('This bot will keep running.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('kept only for this app session'),
          findsOneWidget,
        );
        await tapAndWaitForIo(
          tester,
          find.text('Queue for next Start'),
          () => fixture.bots.pendingUpgradeFor(fixture.bot) != null,
        );
        expect(fixture.bot.active, isTrue);
        expect(fixture.runtime.stops, 0);
        expect(fixture.bot.setup!.pluginDigest, fixture.old.digest);
        expect(find.textContaining('Version 1.1.0 is queued'), findsOneWidget);
        await tester.tap(find.text('Cancel queued update'));
        await tester.pumpAndSettle();
        expect(fixture.bots.pendingUpgradeFor(fixture.bot), isNull);
        expect(fixture.bot.active, isTrue);
        expect(fixture.bot.setup!.pluginDigest, fixture.old.digest);
        expect(fixture.runtime.stops, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(fixture.close);
      }
    },
  );

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
        expect(fixture.bots.pendingUpgradeFor(fixture.bot), isNull);
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
