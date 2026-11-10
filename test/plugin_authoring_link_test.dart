import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/plugins/plugins_page.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/ui/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class GuideCatalog extends PluginRepository {
  GuideCatalog() : super(bundledAssets: const []);

  @override
  Future<void> get ready async {}

  @override
  List<PluginManifest> get installed => const [];
}

class GuideLauncher extends UrlLauncherPlatform {
  final calls = <(String, PreferredLaunchMode)>[];
  bool result = true;
  Object? error;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    calls.add((url, options.mode));
    if (error != null) throw error!;
    return result;
  }
}

void main() {
  late UrlLauncherPlatform previousLauncher;
  late GuideLauncher launcher;
  late GuideCatalog catalog;

  setUp(() {
    previousLauncher = UrlLauncherPlatform.instance;
    launcher = GuideLauncher();
    UrlLauncherPlatform.instance = launcher;
    catalog = GuideCatalog();
  });

  tearDown(() {
    UrlLauncherPlatform.instance = previousLauncher;
    catalog.dispose();
  });

  Future<void> showPage(WidgetTester tester, double width) async {
    await tester.binding.setSurfaceSize(Size(width, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: BottogramDesign.theme,
        home: PluginsPage(repository: catalog),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [390.0, 1100.0]) {
    testWidgets('authoring link opens the GitHub guide at $width px', (
      tester,
    ) async {
      await showPage(tester, width);
      final link = find.widgetWithText(TextButton, 'آموزش ساخت پلاگین');
      expect(link, findsOneWidget);
      expect(
        tester.getBottomLeft(link).dy,
        lessThan(tester.getTopLeft(find.byType(BNotice)).dy),
      );
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(launcher.calls, [
        (
          'https://github.com/hayyaun/bottogram/blob/main/docs/PLUGIN_AUTHORING.md',
          PreferredLaunchMode.externalApplication,
        ),
      ]);
      expect(find.text('Your next integration'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final throwsPlatformError in [false, true]) {
    testWidgets('guide launch failure stays in the page ($throwsPlatformError)', (
      tester,
    ) async {
      launcher.result = false;
      if (throwsPlatformError) {
        launcher.error = StateError('private-platform-diagnostic');
      }
      await showPage(tester, 390);
      await tester.tap(find.widgetWithText(TextButton, 'آموزش ساخت پلاگین'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The plugin guide could not be opened. Check your browser and try again.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('private-platform-diagnostic'), findsNothing);
      expect(find.text('Your next integration'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
