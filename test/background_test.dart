import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bottogram/background/controller.dart';
import 'package:bottogram/background/guide.dart';
import 'package:bottogram/background/platform.dart';
import 'package:bottogram/ui/design.dart';

class FakeBackground extends BackgroundPlatform {
  BackgroundSnapshot state = const BackgroundSnapshot(
    supported: true,
    batteryExempt: false,
    backgroundRestricted: false,
    notificationsEnabled: true,
  );
  int reads = 0;
  bool fail = false;
  @override
  bool get supported => true;
  @override
  Future<BackgroundSnapshot> readState() async {
    reads++;
    if (fail) throw StateError('unavailable');
    return state;
  }

  @override
  Future<bool> openBatterySettings() async => true;
  @override
  Future<bool> openAppSettings() async => true;
  @override
  Future<void> requestNotifications() async {}
  @override
  Future<void> startService(int count) async {}
  @override
  Future<void> updateService(int count) async {}
  @override
  Future<void> stopService() async {}
}

void main() {
  testWidgets(
    'guide once per opening; skip leaves warning across navigation; settings do not loop',
    (tester) async {
      final platform = FakeBackground();
      final controller = BackgroundController(platform);
      await controller.ready;
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: BottogramDesign.theme,
          builder:
              (context, child) => BackgroundSetupHost(
                controller: controller,
                navigatorKey: navigator,
                child: child!,
              ),
          home: const Scaffold(body: Text('Home')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Keep bots running'), findsOneWidget);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Keep bots running'), findsNothing);
      expect(find.text('Read instructions'), findsOneWidget);
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Other page')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Read instructions'), findsOneWidget);
      await controller.openSettings(battery: true);
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(controller.opening, 1);
      expect(find.text('Keep bots running'), findsNothing);
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(controller.opening, 2);
      expect(find.text('Keep bots running'), findsOneWidget);
      platform.state = const BackgroundSnapshot(
        supported: true,
        batteryExempt: true,
        backgroundRestricted: false,
        notificationsEnabled: true,
      );
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(find.text('Read instructions'), findsNothing);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Keep bots running'), findsNothing);
      platform.fail = true;
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(controller.snapshot.ready, isFalse);
      expect(find.text('Read instructions'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
  testWidgets(
    'guide supports small RTL screen, large text and truthful separate states',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final platform =
          FakeBackground()
            ..state = const BackgroundSnapshot(
              supported: true,
              batteryExempt: true,
              backgroundRestricted: false,
              notificationsEnabled: false,
            );
      final controller = BackgroundController(platform);
      await controller.ready;
      await tester.pumpWidget(
        MaterialApp(
          theme: BottogramDesign.theme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 640),
              textScaler: TextScaler.linear(1.8),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: BackgroundGuide(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Battery optimization · Ready'), findsOneWidget);
      expect(find.text('Notifications · Needs setup'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Skip for this opening'), 300);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
