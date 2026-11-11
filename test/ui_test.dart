import 'dart:io';
import 'dart:ui' as ui;

import 'package:bottogram/background/controller.dart';
import 'package:bottogram/background/guide.dart';
import 'package:bottogram/dialogs/share_dialog.dart';
import 'package:bottogram/inbox/conversation_page.dart';
import 'package:bottogram/inbox/models.dart';
import 'package:bottogram/inbox/settings_page.dart';
import 'package:bottogram/inbox/users_page.dart';
import 'package:bottogram/pages/act.dart';
import 'package:bottogram/pages/bot.dart';
import 'package:bottogram/pages/create_bot.dart';
import 'package:bottogram/pages/event.dart';
import 'package:bottogram/pages/home.dart';
import 'package:bottogram/pages/settings.dart';
import 'package:bottogram/pages/store.dart';
import 'package:bottogram/pages/templates.dart';
import 'package:bottogram/plugins/plugins_page.dart';
import 'package:bottogram/plugins/bot_setup.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/store/rmus.dart';
import 'package:bottogram/ui/design.dart';
import 'package:bottogram/units/virt_act.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/units/virt_event.dart';
import 'package:bottogram/units/virt_rmu.dart';
import 'package:bottogram/widgets/bot_card.dart';
import 'package:bottogram/widgets/rmu_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'background_test.dart' show FakeBackground;
import 'inbox_repository_test.dart' show MemorySource;
import 'plugins_test.dart' show MemoryCatalog, definition, package;
import 'widget_test.dart' show WidgetInbox;

/// Rendering fixtures stay in memory and never use the user's Hive directory.
class PreviewBots extends Cubit<List<VirtBot>> implements BotsCubit {
  PreviewBots(super.initialState);
  @override
  Future<void> get ready async {}
  @override
  String? lastError;
  int importCalls = 0;
  bool failImport = false;
  @override
  Future<void> import() async {
    importCalls++;
    lastError = failImport
        ? 'The bot configuration could not be imported.'
        : null;
  }

  @override
  void update() => emit(List.of(state));
  @override
  Future<void> saveBot(VirtBot bot) async => emit(List.of(state));
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}

class PreviewTemplates extends Cubit<List<VirtRMU>> implements RMUsCubit {
  PreviewTemplates(super.initialState);
  @override
  Future<void> get ready async {}
  @override
  String? lastError;
  @override
  Future<void> add(VirtRMU value) async => emit([...state, value]);
  @override
  Future<void> remove(VirtRMU value) async =>
      emit(state.where((item) => item != value).toList());
  @override
  void update() => emit(List.of(state));
  @override
  Future<void> reset() async => emit([]);
}

void main() {
  late MemoryCatalog catalog;
  late PreviewBots bots;
  late PreviewTemplates templates;
  late WidgetInbox inbox;
  late VirtBot manual;
  late VirtBot pluginBot;
  late VirtEvent event;
  final boundary = GlobalKey();
  final captureEnabled = Platform.environment['CAPTURE_PLUGIN_UI'] == '1';

  setUp(() {
    catalog = MemoryCatalog()..entries.add(package());
    manual = VirtBot(
      'Shop assistant',
      '123456:fixture_only',
      addSamples: false,
    );
    event = VirtEvent(type: VirtEventType.command, query: 'start')
      ..acts.add(
        VirtAct(type: VirtActType.reply, text: 'Hello! How can we help?'),
      );
    manual.events.add(event);
    pluginBot =
        VirtBot('Inshopa sales', '789012:fixture_only', addSamples: false)
          ..setup = BotSetup(
            instanceId: 'fixture',
            tokenFingerprint: 'fixture',
            adminIds: ['123456789'],
            pluginKey: catalog.entries.first.storageKey,
            pluginName: 'Inshopa',
            secretFields: const ['apiKey'],
          );
    bots = PreviewBots([manual, pluginBot]);
    templates = PreviewTemplates([
      VirtRMUKeyboard()
        ..name = 'Customer support'
        ..items = ['Browse products', null, 'Contact us'],
    ]);
    inbox = WidgetInbox();
    inbox.known[0] = const KnownUser(
      id: 26,
      name: 'مریم احمدی',
      username: 'maryam',
      lastInteraction: 1794000000,
    );
    inbox.retained
      ..clear()
      ..addAll(const [
        CachedMessage(
          id: 1,
          chatId: 26,
          date: 1794000000,
          outgoing: false,
          text: 'سلام سفارش من چه زمانی ارسال میشه؟',
        ),
        CachedMessage(
          id: 2,
          chatId: 26,
          date: 1794000060,
          outgoing: true,
          text:
              'Hello! Your order is being prepared. We will send the tracking number here.',
        ),
        CachedMessage(
          id: 3,
          chatId: 26,
          date: 1794000120,
          outgoing: false,
          text: 'Order details',
          attachment: InboxAttachment(
            fileId: 'fixture',
            kind: 'document',
            name: 'order-details.pdf',
            size: 24000,
          ),
        ),
      ]);
  });
  tearDown(() async {
    catalog.dispose();
    await bots.close();
    await templates.close();
    await inbox.notifications.close();
  });

  Future<void> loadFonts(WidgetTester tester) async {
    await tester.runAsync(() async {
      final sdk = Platform.environment['FLUTTER_ROOT']!;
      for (final entry in {
        'Host Grotesk': 'assets/fonts/HostGrotesk.ttf',
        'Noto Sans Arabic': 'assets/fonts/NotoSansArabic.ttf',
        'MaterialIcons':
            '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      }.entries) {
        final loader = FontLoader(entry.key)
          ..addFont(
            Future.value(
              ByteData.sublistView(await File(entry.value).readAsBytes()),
            ),
          );
        await loader.load();
      }
    });
  }

  Future<void> pumpPage(
    WidgetTester tester,
    Widget page, {
    Size size = const Size(390, 844),
    double scale = 1,
    bool keyboard = false,
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    await tester.pumpWidget(const SizedBox());
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard ? 300 : 0);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<BotsCubit>.value(value: bots),
          BlocProvider<RMUsCubit>.value(value: templates),
        ],
        child: ChangeNotifierProvider<PluginRepository>.value(
          value: catalog,
          child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              theme: BottogramDesign.theme,
              darkTheme: BottogramDesign.darkTheme,
              themeMode: themeMode,
              debugShowCheckedModeBanner: false,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: page,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!captureEnabled) return;
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/verification/ui').create(recursive: true);
      await File(
        'build/verification/ui/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  void cleanup(WidgetTester tester) => addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewInsets();
  });

  test('keyboard template copies do not share buttons or callback values', () {
    final keyboard = VirtRMUKeyboard()..items = ['Original', null];
    final copy = keyboard.copy('Copy') as VirtRMUKeyboard;
    copy.items[0] = 'Changed';
    expect(keyboard.items, ['Original', null]);
    final inline = VirtRMUInlineKeyboard()
      ..items = [KeyValue('Original', 'original'), null];
    final inlineCopy = inline.copy('Copy') as VirtRMUInlineKeyboard;
    inlineCopy.items.first!.value = 'changed';
    inlineCopy.items.add(KeyValue('New', 'new'));
    expect(inline.items.first!.value, 'original');
    expect(inline.items.length, 2);
  });

  testWidgets(
    'keyboard starts at None and choosing a template attaches an independent copy',
    (tester) async {
      cleanup(tester);
      final action = event.acts.first;
      await pumpPage(
        tester,
        Scaffold(
          body: SingleChildScrollView(child: RMUEditor(act: action)),
        ),
      );
      expect(find.text('None'), findsOneWidget);
      await tester.tap(find.text('Choose template'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Customer support'));
      await tester.pumpAndSettle();
      expect(action.rmu, isA<VirtRMUKeyboard>());
      expect(identical(action.rmu, templates.state.first), isFalse);
      (action.rmu as VirtRMUKeyboard).items.add('New');
      expect((templates.state.first as VirtRMUKeyboard).items, [
        'Browse products',
        null,
        'Contact us',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'event dialog updates its selected type and keeps inline queries available',
    (tester) async {
      cleanup(tester);
      await pumpPage(tester, BotPage(bot: manual));
      await tester.ensureVisible(find.text('Add event'));
      await tester.tap(find.text('Add event'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Command').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inline query').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Query'),
        'catalog',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add event'));
      await tester.pumpAndSettle();
      expect(manual.events.last.type, VirtEventType.inlineQuery);
      expect(manual.events.last.query, 'catalog');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mobile headers scroll away and final items clear floating navigation',
    (tester) async {
      cleanup(tester);
      addTearDown(() {
        tester.view.resetPadding();
        tester.view.resetViewPadding();
      });
      await loadFonts(tester);
      bots.state.addAll([
        for (var i = 0; i < 4; i++)
          VirtBot('Preview bot $i', '$i:fixture_only', addSamples: false),
      ]);
      catalog.entries.addAll([
        for (var i = 0; i < 3; i++)
          package({
            ...definition(),
            'id': 'org.example.preview$i',
            'name': 'Preview integration $i',
          }),
      ]);
      for (final variant in [
        (size: const Size(390, 844), scale: 1.0, inset: 0.0),
        (size: const Size(360, 800), scale: 1.6, inset: 34.0),
        (size: const Size(844, 390), scale: 1.0, inset: 0.0),
      ]) {
        tester.view.padding = FakeViewPadding(bottom: variant.inset);
        tester.view.viewPadding = FakeViewPadding(bottom: variant.inset);
        await pumpPage(
          tester,
          const HomePage(title: 'Bottogram'),
          size: variant.size,
          scale: variant.scale,
        );
        final bar = find.byType(BackdropFilter);
        final barRect = tester.getRect(bar);
        final list = find.byType(CustomScrollView);
        expect(tester.getRect(list).bottom, greaterThan(barRect.bottom));
        expect(
          barRect.bottom,
          lessThanOrEqualTo(variant.size.height - variant.inset),
        );
        await tester.drag(list, const Offset(0, -240));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.text('Bottogram', skipOffstage: false)).bottom,
          lessThan(0),
        );
        expect(tester.getRect(bar), barRect);
        if (variant.size.width == 390) {
          await capture(tester, 'bots-floating-scroll');
        }
        final scroll = tester.state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        );
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byType(BotCard).last).bottom,
          lessThan(barRect.top),
        );
        await tester.tap(find.byTooltip('Plugins'));
        await tester.pumpAndSettle();
        final plugins = find.byType(SingleChildScrollView);
        expect(tester.getRect(plugins).bottom, greaterThan(barRect.bottom));
        await tester.drag(plugins, const Offset(0, -240));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.text('Bottogram', skipOffstage: false)).bottom,
          lessThan(0),
        );
        final pluginScroll = tester.state<ScrollableState>(
          find.descendant(of: plugins, matching: find.byType(Scrollable)).first,
        );
        pluginScroll.position.jumpTo(pluginScroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byType(BPanel).last).bottom,
          lessThan(tester.getRect(bar).top),
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('Store and Settings fit mobile navigation and desktop rail', (
    tester,
  ) async {
    cleanup(tester);
    await loadFonts(tester);
    for (final variant in [
      (size: const Size(320, 700), scale: 1.0),
      (size: const Size(390, 844), scale: 1.0),
      (size: const Size(360, 800), scale: 1.6),
      (size: const Size(1440, 960), scale: 1.0),
    ]) {
      await pumpPage(
        tester,
        const HomePage(title: 'Bottogram'),
        size: variant.size,
        scale: variant.scale,
      );
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/icon/foreground.png'),
          boundary.currentContext!,
        ),
      );
      await tester.pumpAndSettle();
      final mobile = variant.size.width < 1000;
      Finder tab(String label) =>
          mobile ? find.byTooltip(label) : find.widgetWithText(ListTile, label);
      if (mobile) {
        final controls = [
          'Bots',
          'Store',
          'Create bot',
          'Plugins',
          'Settings',
        ].map(find.byTooltip).toList();
        for (var i = 0; i < controls.length; i++) {
          expect(tester.getSize(controls[i]).width, greaterThanOrEqualTo(48));
          expect(tester.getSize(controls[i]).height, greaterThanOrEqualTo(48));
          if (i > 0) {
            expect(
              tester.getCenter(controls[i]).dx,
              greaterThan(tester.getCenter(controls[i - 1]).dx),
            );
          }
        }
        expect(
          tester.getCenter(find.byTooltip('Create bot')).dx,
          closeTo(variant.size.width / 2, 1),
        );
        expect(
          tester.getSize(find.byType(BackdropFilter)).height,
          closeTo(64, 1),
        );
      }
      await tester.tap(tab('Store'));
      await tester.pumpAndSettle();
      expect(find.byType(StorePage), findsOneWidget);
      if (mobile) {
        expect(
          tester.getRect(find.text('Bottogram')).top,
          greaterThanOrEqualTo(0),
        );
      }
      expect(find.text('Bot templates'), findsOneWidget);
      expect(find.text('Quiz with scores'), findsOneWidget);
      expect(find.byType(BotCard), findsNothing);
      if (variant.size.width == 390) await capture(tester, 'store-phone');
      await tester.tap(tab('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.text('Data & storage'), findsOneWidget);
      expect(find.text('Running'), findsOneWidget);
      if (variant.size.width == 390) await capture(tester, 'settings-phone');
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(SettingsPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      if (mobile) {
        expect(
          tester.getRect(find.text('Open-source licenses')).bottom,
          lessThan(tester.getRect(find.byType(BackdropFilter)).top),
        );
      }
      if (variant.size.width == 390) {
        await capture(tester, 'settings-phone-bottom');
      }
      await tester.tap(tab('Plugins'));
      await tester.pumpAndSettle();
      expect(find.byType(PluginsPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'Settings opens existing data, background, about and license tools',
    (tester) async {
      cleanup(tester);
      final background = BackgroundController(FakeBackground());
      await background.ready;
      addTearDown(background.dispose);
      await pumpPage(
        tester,
        ChangeNotifierProvider<BackgroundController>.value(
          value: background,
          child: const HomePage(title: 'Bottogram'),
        ),
      );
      final warning = find.byTooltip('Battery optimization can interrupt your bots.');
      expect(warning, findsOneWidget);
      expect(find.byTooltip('Import bots'), findsOneWidget);
      await tester.tap(warning);
      await tester.pumpAndSettle();
      expect(find.text('Keep bots running'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Import bots'));
      await tester.tap(find.text('Import bots'));
      await tester.pumpAndSettle();
      expect(find.text('Scan QR code'), findsOneWidget);
      await tester.tap(find.text('Backup file'));
      await tester.pumpAndSettle();
      expect(bots.importCalls, 1);
      bots.failImport = true;
      await tester.tap(find.text('Import bots'));
      await tester.pumpAndSettle();
      expect(find.text('Scan QR code'), findsOneWidget);
      await tester.tap(find.text('Backup file'));
      await tester.pumpAndSettle();
      expect(
        find.text('The bot configuration could not be imported.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Export bot configurations'));
      await tester.tap(find.text('Export bot configurations'));
      await tester.pumpAndSettle();
      expect(find.byType(ShareDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Inbox & cache'));
      await tester.tap(find.text('Inbox & cache'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a bot'), findsOneWidget);
      expect(find.text('Shop assistant'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Keep bots running'));
      await tester.tap(find.text('Keep bots running'));
      await tester.pumpAndSettle();
      expect(find.byType(BackgroundGuide), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('About Bottogram'));
      await tester.tap(find.text('About Bottogram'));
      await tester.pumpAndSettle();
      expect(find.byType(AboutDialog), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Open-source licenses'));
      await tester.tap(find.text('Open-source licenses'));
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dark palette renders bot cards, plugins, dialogs and conversations',
    (tester) async {
      cleanup(tester);
      await loadFonts(tester);
      for (final preview in <String, Widget>{
        'bots-dark': const HomePage(title: 'Bottogram'),
        'plugins-dark': PluginsPage(repository: catalog),
        'create-dark': CreateBotPage(bots: bots, plugins: catalog),
        'conversation-dark': InboxConversationPage(
          repository: inbox,
          user: inbox.known[0],
          source: MemorySource(1),
          send: (_) async {},
        ),
      }.entries) {
        await pumpPage(tester, preview.value, themeMode: ThemeMode.dark);
        expect(
          Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
          Brightness.dark,
        );
        if (preview.key == 'bots-dark') {
          await tester.runAsync(
            () => precacheImage(
              const AssetImage('assets/icon/foreground.png'),
              boundary.currentContext!,
            ),
          );
          await tester.pumpAndSettle();
        }
        await capture(tester, preview.key);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'rendered phone screens retain scrolling, keyboard space and large text',
    (tester) async {
      cleanup(tester);
      await loadFonts(tester);
      await pumpPage(tester, const HomePage(title: 'Bottogram'));
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/icon/foreground.png'),
          boundary.currentContext!,
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, 'bots-phone');
      await pumpPage(
        tester,
        const HomePage(title: 'Bottogram'),
        size: const Size(1440, 960),
      );
      await capture(tester, 'bots-desktop');
      await pumpPage(
        tester,
        const HomePage(title: 'Bottogram'),
        size: const Size(360, 800),
        scale: 1.6,
      );
      await capture(tester, 'bots-large-text');
      await pumpPage(tester, PluginsPage(repository: catalog));
      await capture(tester, 'plugins-phone');
      await pumpPage(tester, CreateBotPage(bots: bots, plugins: catalog));
      await capture(tester, 'create-phone');
      await tester.ensureVisible(find.text('Manual'));
      await tester.tap(find.text('Manual'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inshopa · 0.2.0').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Inshopa API key'));
      await tester.pumpAndSettle();
      await capture(tester, 'create-inshopa-phone');
      final secretField = tester.widget<TextField>(
        find.descendant(
          of: find.widgetWithText(TextFormField, 'Inshopa API key'),
          matching: find.byType(TextField),
        ),
      );
      expect(secretField.obscureText, isTrue);
      await pumpPage(tester, BotPage(bot: manual));
      await capture(tester, 'bot-phone');
      await pumpPage(tester, BotPage(bot: pluginBot));
      await capture(tester, 'plugin-bot-phone');
      await tester.ensureVisible(find.byType(Switch));
      await tester.pumpAndSettle();
      await capture(tester, 'plugin-settings-phone');
      await pumpPage(tester, EventPage(ev: event, bot: manual));
      await capture(tester, 'event-phone');
      event.acts.first.rmu = VirtRMUInlineKeyboard()
        ..items = [
          for (var i = 0; i < 7; i++) KeyValue('Button $i', 'value_$i'),
        ];
      await pumpPage(
        tester,
        ActPage(act: event.acts.first, ev: event, bot: manual),
      );
      await tester.ensureVisible(find.text('Inline keyboard'));
      await tester.pumpAndSettle();
      await capture(tester, 'keyboard-phone');
      await pumpPage(tester, const TemplatesPage(selectMode: true));
      await capture(tester, 'templates-phone');
      await pumpPage(tester, InboxUsersPage(bot: manual, repository: inbox));
      await capture(tester, 'inbox-phone');
      await pumpPage(
        tester,
        InboxConversationPage(
          repository: inbox,
          user: inbox.known.first,
          source: MemorySource(1),
          send: (_) async {},
        ),
      );
      await capture(tester, 'conversation-phone');
      await pumpPage(
        tester,
        InboxConversationPage(
          repository: inbox,
          user: inbox.known.first,
          source: MemorySource(1),
          send: (_) async {},
        ),
        size: const Size(320, 640),
        keyboard: true,
      );
      await tester.enterText(
        find.byType(TextField),
        'A reply with the keyboard open',
      );
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(find.byTooltip('Send reply')).dy,
        lessThanOrEqualTo(340),
      );
      await capture(tester, 'conversation-keyboard');
      await pumpPage(tester, InboxSettingsPage(repository: inbox));
      await capture(tester, 'storage-phone');
      await pumpPage(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const ShareDialog(),
              ),
              child: const Text('Open share'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open share'));
      await tester.pumpAndSettle();
      await capture(tester, 'share-phone');
      expect(tester.takeException(), isNull);
      await pumpPage(
        tester,
        InboxUsersPage(bot: manual, repository: inbox),
        size: const Size(320, 640),
        scale: 2,
      );
      final firstUser = find.ancestor(
        of: find.text('مریم احمدی'),
        matching: find.byType(BPanel),
      );
      await tester.ensureVisible(firstUser);
      await tester.pumpAndSettle();
      expect(
        tester.getBottomRight(firstUser).dy,
        lessThan(tester.getTopLeft(find.text('Page 1 of 2 · 26 users')).dy),
      );
      await capture(tester, 'inbox-large-text');
    },
  );
}
