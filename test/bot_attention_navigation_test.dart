import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bottogram/inbox/repository.dart';
import 'package:bottogram/inbox/users_page.dart';
import 'package:bottogram/pages/bot.dart';
import 'package:bottogram/plugins/bot_setup.dart';
import 'package:bottogram/plugins/failure_notice.dart';
import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/runtime/coordinator.dart';
import 'package:bottogram/runtime/failure_presentation.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/ui/design.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/widgets/bot_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'plugins_test.dart' show MemoryCatalog;
import 'widget_test.dart' show WidgetInbox;

class AttentionRuntime extends Fake implements BotRuntime {
  FailurePresentation? presentation = const FailurePresentation(
    code: 'http.invalid_origin',
    title: 'Automation issue',
    message: 'The configured website origin is invalid.',
  );

  @override
  List<FailurePresentation> failuresFor(VirtBot bot) => [
    if (presentation case final FailurePresentation failure) failure,
  ];
}

class AttentionBots extends Cubit<List<VirtBot>> implements BotsCubit {
  AttentionBots(super.initialState);

  @override
  final AttentionRuntime runtime = AttentionRuntime();

  @override
  PluginManifest? pendingUpgradeFor(VirtBot bot) => null;

  @override
  void update() => emit(List.of(state));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}

class AttentionBot extends VirtBot {
  AttentionBot(this.fixtureInbox)
    : super('Navigation fixture', '123456:fixture_only', addSamples: false);

  final InboxRepository fixtureInbox;

  @override
  Future<InboxRepository> get inbox async => fixtureInbox;
}

void main() {
  late MemoryCatalog catalog;
  late AttentionBots bots;
  late AttentionBot bot;
  late WidgetInbox inbox;
  final captureEnabled = Platform.environment['CAPTURE_ATTENTION_UI'] == '1';
  final boundary = GlobalKey();

  setUp(() {
    final manifest = PluginManifest.parse(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'manifestVersion': 2,
            'hostApiMajor': 2,
            'id': 'example.navigation-fixture',
            'name': 'Navigation fixture plugin',
            'version': '1.0.0',
            'executionStatus': 'live',
            'setupFields': [
              for (var i = 0; i < 6; i++)
                {
                  'key': 'detail$i',
                  'label': 'Connection detail $i',
                  'type': 'text',
                  'required': true,
                },
            ],
            'automations': [
              {
                'id': 'hello',
                'trigger': {
                  'type': 'telegram.command.v2',
                  'config': {
                    'commands': ['hello'],
                    'chatTypes': ['private'],
                    'arguments': 'ignore',
                  },
                },
                'actions': [
                  {
                    'id': 'reply',
                    'type': 'telegram.reply.v1',
                    'config': {'text': 'Hello'},
                  },
                ],
              },
            ],
          }),
        ),
      ),
    );
    catalog = MemoryCatalog()..entries.add(manifest);
    inbox = WidgetInbox();
    bot = AttentionBot(inbox)
      ..setup = BotSetup(
        instanceId: 'navigation-fixture',
        tokenFingerprint: 'fixture',
        adminIds: ['123456789'],
        pluginKey: manifest.storageKey,
        pluginDigest: manifest.digest,
        pluginName: manifest.name,
        values: {for (var i = 0; i < 6; i++) 'detail$i': 'Fixture value $i'},
      )
      ..runtimeError = 'The configured website origin is invalid.';
    bots = AttentionBots([bot]);
  });

  tearDown(() async {
    catalog.dispose();
    await bots.close();
    await inbox.notifications.close();
  });

  Future<void> showCard(
    WidgetTester tester, {
    bool disableAnimations = false,
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 600);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    if (captureEnabled) {
      await tester.runAsync(() async {
        final sdk = Platform.environment['FLUTTER_ROOT']!;
        for (final font in {
          'Host Grotesk': 'assets/fonts/HostGrotesk.ttf',
          'Noto Sans Arabic': 'assets/fonts/NotoSansArabic.ttf',
          'MaterialIcons':
              '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        }.entries) {
          final loader = FontLoader(font.key)
            ..addFont(
              Future.value(
                ByteData.sublistView(await File(font.value).readAsBytes()),
              ),
            );
          await loader.load();
        }
      });
    }
    await tester.pumpWidget(
      BlocProvider<BotsCubit>.value(
        value: bots,
        child: ChangeNotifierProvider<PluginRepository>.value(
          value: catalog,
          child: MaterialApp(
            theme: BottogramDesign.theme,
            darkTheme: BottogramDesign.darkTheme,
            themeMode: themeMode,
            debugShowCheckedModeBanner: false,
            builder: (context, child) => RepaintBoundary(
              key: boundary,
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: disableAnimations),
                child: child!,
              ),
            ),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 340,
                  height: 280,
                  child: BotCard(bot: bot),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
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

  ScrollPosition pagePosition(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(BotPage),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  void expectVisible(WidgetTester tester, Finder error) {
    final rectangle = tester.getRect(error);
    expect(rectangle.top, greaterThanOrEqualTo(kToolbarHeight));
    expect(rectangle.bottom, lessThanOrEqualTo(600));
    expect(error.hitTestable(), findsOneWidget);
  }

  for (final variant in [
    (name: 'light', reducedMotion: false, themeMode: ThemeMode.light),
    (name: 'reduced-motion', reducedMotion: true, themeMode: ThemeMode.light),
    (name: 'dark', reducedMotion: false, themeMode: ThemeMode.dark),
  ]) {
    testWidgets(
      'attention badge opens and reveals runtime error (${variant.name})',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await showCard(
            tester,
            disableAnimations: variant.reducedMotion,
            themeMode: variant.themeMode,
          );
          final badge = find.widgetWithText(TextButton, 'Needs attention');
          expect(tester.getSize(badge).height, greaterThanOrEqualTo(48));
          expect(
            tester
                .getSemantics(badge)
                .getSemanticsData()
                .flagsCollection
                .isButton,
            isTrue,
          );
          await tester.tap(badge);
          await tester.pumpAndSettle();
          expect(find.byType(BotPage), findsOneWidget);
          expect(find.byType(InboxUsersPage), findsNothing);
          expect(pagePosition(tester).pixels, greaterThan(0));
          expectVisible(tester, find.byType(PluginFailureNotice));
          expect(tester.takeException(), isNull);
          if (variant.name != 'reduced-motion') {
            await capture(tester, 'attention-error-${variant.name}');
          }
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets('oversized error reveals its title and beginning', (
    tester,
  ) async {
    bots.runtime.presentation = FailurePresentation(
      code: 'http.invalid_origin',
      title: 'Automation issue',
      message: List.filled(
        30,
        'A detailed explanation of the failed operation.',
      ).join(' '),
    );
    await showCard(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Needs attention'));
    await tester.pumpAndSettle();
    final panel = tester.getRect(find.byType(PluginFailureNotice));
    expect(panel.top, greaterThanOrEqualTo(kToolbarHeight));
    expect(panel.bottom, greaterThan(600));
    expect(find.text('Automation issue').hitTestable(), findsOneWidget);
    expect(pagePosition(tester).pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('attention badge can be activated with the keyboard', (
    tester,
  ) async {
    await showCard(tester);
    Focus.of(tester.element(find.text('Needs attention'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expectVisible(tester, find.byType(PluginFailureNotice));
  });

  testWidgets('settings gear retains its ordinary initial position', (
    tester,
  ) async {
    await showCard(tester);
    await tester.tap(find.byTooltip('Bot settings'));
    await tester.pumpAndSettle();
    expect(find.byType(BotPage), findsOneWidget);
    expect(pagePosition(tester).pixels, 0);
    expect(find.text('Plugin configuration').hitTestable(), findsOneWidget);
  });

  testWidgets('card body still opens the users and inbox page', (tester) async {
    await showCard(tester);
    await tester.tap(find.text('Navigation fixture'));
    await tester.pumpAndSettle();
    expect(find.byType(InboxUsersPage), findsOneWidget);
    expect(find.byType(BotPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('setup error is preferred when both error types exist', (
    tester,
  ) async {
    bot.setupError = 'The saved setup needs to be repaired.';
    await showCard(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Needs attention'));
    await tester.pumpAndSettle();
    expectVisible(tester, find.text(bot.setupError!));
    expect(tester.takeException(), isNull);
  });

  testWidgets('error clearing during navigation leaves the settings usable', (
    tester,
  ) async {
    await showCard(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Needs attention'));
    bot.runtimeError = null;
    bots.runtime.presentation = null;
    await tester.pumpAndSettle();
    expect(find.byType(BotPage), findsOneWidget);
    expect(find.byType(PluginFailureNotice), findsNothing);
    expect(pagePosition(tester).pixels, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual bot runtime error is also visible from its badge', (
    tester,
  ) async {
    bot.setup = null;
    await showCard(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Needs attention'));
    await tester.pumpAndSettle();
    expectVisible(tester, find.text(bot.runtimeError!));
    expect(tester.takeException(), isNull);
  });
}
