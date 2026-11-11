import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:bottogram/background/platform.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'one Dart runtime survives Activity close while foreground service owns execution',
    (tester) async {
      final platform = AndroidBackgroundPlatform();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Background execution test')),
        ),
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      await platform.startService(0, 3);
      await platform.updateService(1, 3);
      expect((await platform.readState()).serviceRunning, isTrue);
      var ticks = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => ticks++,
      );
      try {
        await SystemNavigator.pop();
        debugPrint('BACKGROUND_PROBE_START pid=$pid');
        await Future<void>.delayed(const Duration(seconds: 45));
        expect(ticks, greaterThan(80));
        debugPrint('BACKGROUND_PROBE_END ticks=$ticks');
        expect((await platform.readState()).serviceRunning, isTrue);
        // Outside adb verification can inspect service, Activity and wake lock
        // during this interval. No debug-only production bridge is introduced.
        await platform.stopService();
        expect((await platform.readState()).serviceRunning, isFalse);
      } finally {
        timer.cancel();
        await platform.stopService();
        platform.dispose();
      }
    },
  );
}
