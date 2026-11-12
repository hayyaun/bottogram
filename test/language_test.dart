import 'dart:async';
import 'dart:io';

import 'package:bottogram/main.dart';
import 'package:bottogram/pages/home.dart';
import 'package:bottogram/pages/settings.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/store/app_preferences.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/ui/language_preferences.dart';
import 'package:bottogram/ui/theme_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bottogram_language_');
    Hive.init(directory.path);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'language survives reopening and clearing the choice restores device mode',
    () async {
      final box = await Hive.openBox<String>(appPreferencesBoxName);
      await box.put('theme_mode', 'dark');
      var preferences = LanguagePreferences(box: box);
      await preferences.ready;
      expect(preferences.language, AppLanguage.system);

      await preferences.setLanguage(AppLanguage.persian);
      preferences.dispose();
      await box.close();
      preferences = LanguagePreferences();
      await preferences.ready;
      expect(preferences.language, AppLanguage.persian);
      expect(Hive.box<String>(appPreferencesBoxName).get('theme_mode'), 'dark');

      await preferences.setLanguage(AppLanguage.system);
      preferences.dispose();
      await Hive.box<String>(appPreferencesBoxName).close();
      preferences = LanguagePreferences();
      await preferences.ready;
      expect(preferences.language, AppLanguage.system);
      preferences.dispose();
    },
  );

  testWidgets(
    'language picker switches the app and mirrors navigation on mobile and desktop',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.localesTestValue = const [Locale('fa', 'IR')];
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      late LanguagePreferences language;
      await tester.runAsync(() async {
        language = LanguagePreferences();
        await language.ready;
        final theme = ThemePreferences();
        await theme.ready;
        await tester.pumpWidget(MyApp(preferences: theme, language: language));
        final home = tester.element(find.byType(HomePage));
        await home.read<PluginRepository>().ready;
        await home.read<BotsCubit>().ready;
      });
      await tester.pumpAndSettle();

      final home = tester.element(find.byType(HomePage));
      expect(language.language, AppLanguage.system);
      expect(Localizations.localeOf(home), const Locale('fa'));
      expect(Directionality.of(home), TextDirection.rtl);

      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('تنظیمات'));
        await tester.pump();
        await tester.element(find.byType(SettingsPage)).read<BotsCubit>().ready;
        await tester
            .element(find.byType(SettingsPage))
            .read<PluginRepository>()
            .ready;
      });
      await tester.pumpAndSettle();

      Future<void> select(String label, AppLanguage choice) async {
        await tester.runAsync(() async {
          final saved = Completer<void>();
          void changed() {
            if (!language.saving &&
                (language.language == choice || language.saveFailed)) {
              if (!saved.isCompleted) saved.complete();
            }
          }

          language.addListener(changed);
          try {
            await tester.tap(find.widgetWithText(ChoiceChip, label));
            await saved.future.timeout(const Duration(seconds: 5));
          } finally {
            language.removeListener(changed);
          }
          expect(language.language, choice);
        });
        await tester.pumpAndSettle();
      }

      await select('English', AppLanguage.english);
      expect(find.text('Language'), findsOneWidget);
      expect(
        tester.getCenter(find.byTooltip('Bots')).dx,
        lessThan(tester.getCenter(find.byTooltip('Settings')).dx),
      );

      await select('فارسی', AppLanguage.persian);
      final settingsPage = tester.element(find.byType(SettingsPage));
      expect(Localizations.localeOf(settingsPage), const Locale('fa'));
      expect(Directionality.of(settingsPage), TextDirection.rtl);
      expect(find.text('زبان'), findsOneWidget);
      final persianBots = find.byTooltip('ربات‌ها');
      final persianSettings = find.byTooltip('تنظیمات');
      expect(
        tester.getCenter(persianBots).dx,
        greaterThan(tester.getCenter(persianSettings).dx),
      );

      tester.view.physicalSize = const Size(1200, 900);
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.byType(SettingsPage)).dx, lessThan(600));

      await select('English', AppLanguage.english);
      expect(
        Directionality.of(tester.element(find.byType(SettingsPage))),
        TextDirection.ltr,
      );
      expect(tester.getCenter(find.byType(SettingsPage)).dx, greaterThan(600));

      await select('Device language', AppLanguage.system);
      expect(find.text('زبان'), findsOneWidget);

      tester.platformDispatcher.localesTestValue = const [Locale('fr', 'FR')];
      await tester.pumpAndSettle();
      expect(find.text('Language'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
