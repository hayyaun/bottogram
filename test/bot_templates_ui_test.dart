import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:bottogram/builder/values.dart';
import 'package:bottogram/pages/store.dart';
import 'package:bottogram/templates/catalog.dart';
import 'package:bottogram/templates/model.dart';
import 'package:bottogram/templates/setup_page.dart';
import 'package:bottogram/ui/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    Widget page, {
    double width = 390,
    double scale = 1,
    Brightness brightness = Brightness.light,
    GlobalKey? boundary,
  }) async {
    if (Platform.environment['CAPTURE_TEMPLATE_UI'] == '1') {
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
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: brightness == Brightness.dark
            ? BottogramDesign.darkTheme
            : BottogramDesign.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(key: boundary, child: page),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<void> capture(
    WidgetTester tester,
    GlobalKey boundary,
    String name,
  ) async {
    if (Platform.environment['CAPTURE_TEMPLATE_UI'] != '1') return;
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(
        'build/verification/templates-ui',
      ).create(recursive: true);
      await File(
        'build/verification/templates-ui/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final width in [390.0, 1280.0]) {
    testWidgets('catalog fits $width and opens the actual template setup', (
      tester,
    ) async {
      final boundary = GlobalKey();
      await open(
        tester,
        const Scaffold(body: StorePage()),
        width: width,
        boundary: boundary,
      );
      expect(find.text('Quiz with scores'), findsOneWidget);
      expect(find.text('Event registration'), findsOneWidget);
      expect(find.text('Use template'), findsNWidgets(7));
      await capture(tester, boundary, 'catalog-$width');
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Use template').first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(TemplateSetupPage), findsOneWidget);
      expect(find.text('Template settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'sample editing is copied into the created action chain and original samples stay intact',
    (tester) async {
      BotTemplateDraft? created;
      final template = BotTemplates.all.first;
      await open(
        tester,
        TemplateSetupPage(
          template: template,
          onCreate: (name, token, admin, draft) async {
            created = draft;
          },
        ),
        width: 900,
      );
      await tester.enterText(field('Telegram bot token'), '123:fixture_only');
      await tester.enterText(field('Admin Telegram ID'), '99');
      final question = find.text('How many sides does a triangle have?');
      await tester.ensureVisible(question);
      await tester.tap(question);
      await tester.pumpAndSettle();
      await tester.enterText(field('Question'), 'My edited question');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('My edited question'), findsOneWidget);
      final submit = find.widgetWithText(
        FilledButton,
        'Create bot from template',
      );
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(created, isNotNull);
      final seed = created!.events.first.acts.firstWhere(
        (a) => a.config['output'] == 'seed_quiz_questions',
      );
      expect(
        jsonDecode(seed.config['parameters'] as String),
        contains('My edited question'),
      );
      expect(
        template.sampleRows().first['question'],
        'How many sides does a triangle have?',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'creation errors keep the draft and large-text dark layout has no overflow',
    (tester) async {
      final boundary = GlobalKey();
      await open(
        tester,
        TemplateSetupPage(
          template: BotTemplates.all[1],
          onCreate: (_, _, _, _) async => throw const BuilderFailure(
            'This bot token is already in your list.',
          ),
        ),
        width: 390,
        scale: 1.4,
        brightness: Brightness.dark,
        boundary: boundary,
      );
      await capture(tester, boundary, 'crypto-setup-dark');
      await tester.ensureVisible(field('Telegram bot token'));
      await tester.enterText(field('Telegram bot token'), '123:fixture_only');
      await tester.enterText(field('Admin Telegram ID'), '99');
      final submit = find.widgetWithText(
        FilledButton,
        'Create bot from template',
      );
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(
        find.text('This bot token is already in your list.'),
        findsOneWidget,
      );
      expect(
        (tester.widget(field('Telegram bot token')) as TextField)
            .controller!
            .text,
        '123:fixture_only',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
