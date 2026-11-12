import 'package:bottogram/l10n/generated/app_localizations.dart';
import 'package:bottogram/pages/home.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/runtime/ports.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/ui/design.dart';
import 'package:bottogram/updates/app_updates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'plugin_authoring_link_test.dart' show GuideLauncher;
import 'plugins_test.dart' show MemoryCatalog;
import 'ui_test.dart' show PreviewBots;

class _ReleaseTransport implements JsonTransport {
  Json release = {
    'tag_name': 'v1.10.0',
    'draft': false,
    'prerelease': false,
    'html_url': 'https://example.test/wrong-release',
  };
  bool offline = false;
  final requests = <Uri>[];

  @override
  Future<Json> get(Uri url, Map<String, String> headers) async {
    requests.add(url);
    if (offline) throw StateError('offline');
    return release;
  }

  @override
  void close() {}
}

void main() {
  test('ignores prereleases, drafts and invalid tags', () async {
    final transport = _ReleaseTransport();
    final updates = AppUpdates(
      transport: transport,
      readVersion: () async => '1.9.0+22',
    );
    addTearDown(updates.dispose);

    for (final release in [
      {...transport.release, 'tag_name': 'v2.0.0-rc.1'},
      {...transport.release, 'prerelease': true},
      {...transport.release, 'draft': true},
      {...transport.release, 'tag_name': 'v2.0.0/../../other'},
    ]) {
      transport.release = release;
      await updates.check();
      expect(updates.available, isNull);
      expect(updates.feedback, isNull);
    }
  });

  testWidgets(
    'startup and manual checks share the release on Home and Settings',
    (tester) async {
      final transport = _ReleaseTransport();
      final updates = AppUpdates(
        transport: transport,
        readVersion: () async => '1.9.0+22',
      );
      final catalog = MemoryCatalog();
      final bots = PreviewBots([]);
      final previousLauncher = UrlLauncherPlatform.instance;
      final launcher = GuideLauncher();
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() async {
        UrlLauncherPlatform.instance = previousLauncher;
        catalog.dispose();
        await bots.close();
      });
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            BlocProvider<BotsCubit>.value(value: bots),
            ChangeNotifierProvider<PluginRepository>.value(value: catalog),
            ChangeNotifierProvider(create: (_) => updates..start()),
          ],
          child: MaterialApp(
            theme: BottogramDesign.theme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.4)),
              child: child!,
            ),
            home: const HomePage(title: 'Bottogram'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final notice = find.text('Bottogram 1.10.0 is available');
      final download = find.text('Download update');
      final check = find.text('Check for updates');
      expect(notice, findsOneWidget);
      expect(transport.requests, [
        Uri.parse(
          'https://api.github.com/repos/hayyaun/bottogram/releases/latest',
        ),
      ]);
      await tester.tap(download);
      await tester.pumpAndSettle();
      expect(launcher.calls, [
        (
          'https://github.com/hayyaun/bottogram/releases/tag/v1.10.0',
          PreferredLaunchMode.externalApplication,
        ),
      ]);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(check);
      await tester.pumpAndSettle();
      expect(find.text('Version 1.9.0'), findsOneWidget);
      expect(notice, findsOneWidget);

      transport.release['tag_name'] = 'v1.9.0';
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(find.text('Bottogram is up to date.'), findsOneWidget);
      expect(notice, findsNothing);

      transport.offline = true;
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(
        find.text('Couldn’t check for updates. Try again in a moment.'),
        findsOneWidget,
      );

      transport.offline = false;
      transport.release['tag_name'] = 'v1.10.0';
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(notice, findsOneWidget);
      await tester.tap(find.byTooltip('Bots'));
      await tester.pumpAndSettle();
      expect(notice, findsOneWidget);
      expect(transport.requests.length, 4);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
    },
  );
}
