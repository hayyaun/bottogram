import 'dart:io';
import 'dart:math';

import 'package:bottogram/plugins/secret_vault.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'macOS Keychain saves, replaces and deletes a disposable secret',
    (tester) async {
      // Exercise the real platform plugin without starting the application,
      // opening Hive, or reading any saved bot configuration.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: Text('Keychain storage test'))),
        ),
      );
      final random = Random.secure();
      final suffix = List.generate(
        32,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final key = 'bottogram.integration.keychain.$suffix';
      final writer = PlatformSecretVault();
      expect(
        await writer.read(key),
        isNull,
        reason: 'The disposable test key must not already exist.',
      );

      // Register cleanup only after proving absence. Never delete or enumerate
      // existing items, even if the first write fails after reaching Keychain.
      addTearDown(() async {
        await writer.delete(key);
        expect(await writer.read(key), isNull);
      });

      const initial = 'Disposable Keychain integration value';
      const replacement = 'Replacement Keychain integration value';
      await writer.write(key, initial);
      expect(await PlatformSecretVault().read(key), initial);
      await writer.write(key, replacement);
      expect(await PlatformSecretVault().read(key), replacement);
      await writer.delete(key);
      expect(await PlatformSecretVault().read(key), isNull);
      await writer.delete(key);
      expect(await PlatformSecretVault().read(key), isNull);

      binding.reportData = {
        'secretVault': {
          'platform': Platform.operatingSystem,
          'writeRead': true,
          'replaceRead': true,
          'deleteRead': true,
          'repeatedDelete': true,
        },
      };
      debugPrint('KEYCHAIN_NATIVE_PASS write/read replace/read delete/read');
    },
    skip: !Platform.isMacOS,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
