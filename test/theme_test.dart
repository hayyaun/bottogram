import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bottogram/main.dart';
import 'package:bottogram/pages/home.dart';
import 'package:bottogram/pages/settings.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/ui/theme_preferences.dart';
import 'package:bottogram/units/virt_act.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/units/virt_event.dart';
import 'package:bottogram/units/virt_rmu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bottogram_theme_');
    Hive.init(directory.path);
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
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'theme defaults to system and saved choices survive reopening',
    () async {
      var preferences = ThemePreferences();
      await preferences.ready;
      expect(preferences.mode, ThemeMode.system);
      for (final mode in [ThemeMode.dark, ThemeMode.light, ThemeMode.system]) {
        await preferences.setMode(mode);
        preferences.dispose();
        await Hive.box<String>(ThemePreferences.boxName).close();
        preferences = ThemePreferences();
        await preferences.ready;
        expect(preferences.mode, mode);
      }
      preferences.dispose();
    },
  );

  test(
    'unknown saved values use system and failed writes retain the last choice',
    () async {
      final box = await Hive.openBox<String>(ThemePreferences.boxName);
      await box.put(ThemePreferences.themeKey, 'future-theme');
      final preferences = ThemePreferences(box: box);
      await preferences.ready;
      expect(preferences.mode, ThemeMode.system);
      await preferences.setMode(ThemeMode.dark);
      await box.close();
      await preferences.setMode(ThemeMode.light);
      expect(preferences.mode, ThemeMode.dark);
      expect(preferences.error, isNotNull);
      expect(preferences.saving, isFalse);
      preferences.dispose();
    },
  );

  testWidgets(
    'Settings controls the app theme and System follows live platform changes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      late ThemePreferences preferences;
      late Box<String> box;
      final boundary = GlobalKey();
      final capture = Platform.environment['CAPTURE_PLUGIN_UI'] == '1';
      await tester.runAsync(() async {
        preferences = ThemePreferences();
        await preferences.ready;
        box = Hive.box<String>(ThemePreferences.boxName);
        if (capture) {
          for (final font
              in {
                'Host Grotesk': 'assets/fonts/HostGrotesk.ttf',
                'Noto Sans Arabic': 'assets/fonts/NotoSansArabic.ttf',
                'MaterialIcons':
                    '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              }.entries) {
            final loader = FontLoader(font.key)..addFont(
              Future.value(
                ByteData.sublistView(await File(font.value).readAsBytes()),
              ),
            );
            await loader.load();
          }
        }
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MyApp(preferences: preferences),
          ),
        );
        final home = tester.element(find.byType(HomePage));
        await home.read<PluginRepository>().ready;
        await home.read<BotsCubit>().ready;
      });
      await tester.pumpAndSettle();
      Brightness brightness() =>
          Theme.of(tester.element(find.byType(HomePage))).brightness;
      expect(brightness(), Brightness.dark);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Settings'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'System'))
            .selected,
        isTrue,
      );

      Future<void> choose(String label, ThemeMode mode) async {
        await tester.runAsync(() async {
          final saved = Completer<void>();
          void changed() {
            if (!preferences.saving &&
                preferences.mode == mode &&
                !saved.isCompleted) {
              saved.complete();
            }
          }

          preferences.addListener(changed);
          try {
            await tester.tap(find.widgetWithText(ChoiceChip, label));
            await saved.future;
          } finally {
            preferences.removeListener(changed);
          }
        });
        await tester.pumpAndSettle();
        expect(preferences.mode, mode);
        expect(box.get(ThemePreferences.themeKey), mode.name);
        final overlay =
            tester
                .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
                  find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
                )
                .value;
        expect(
          overlay.statusBarIconBrightness,
          brightness() == Brightness.dark ? Brightness.light : Brightness.dark,
        );
        expect(
          overlay.systemNavigationBarIconBrightness,
          overlay.statusBarIconBrightness,
        );
      }

      void expectReadableChips() {
        for (final label in ['System', 'Light', 'Dark']) {
          final chip = find.widgetWithText(ChoiceChip, label);
          final richText = tester.widget<RichText>(
            find.descendant(
              of: chip,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is RichText && widget.text.toPlainText() == label,
              ),
            ),
          );
          final foreground = richText.text.style!.color!;
          final ink = tester.widget<Ink>(
            find.descendant(of: chip, matching: find.byType(Ink)).first,
          );
          final background = (ink.decoration! as ShapeDecoration).color!;
          final a = foreground.computeLuminance();
          final b = background.computeLuminance();
          final contrast = ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
          expect(
            contrast,
            greaterThanOrEqualTo(4.5),
            reason:
                '$label label in ${brightness().name} mode must be readable',
          );
        }
      }

      await choose('Light', ThemeMode.light);
      expect(brightness(), Brightness.light);
      expectReadableChips();
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      await choose('Dark', ThemeMode.dark);
      expect(brightness(), Brightness.dark);
      expectReadableChips();
      if (capture) {
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/icon/foreground.png'),
            boundary.currentContext!,
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await render.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/verification/ui').create(recursive: true);
          await File(
            'build/verification/ui/settings-dark.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await choose('System', ThemeMode.system);
      expect(brightness(), Brightness.light);
      expectReadableChips();
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.dark);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
