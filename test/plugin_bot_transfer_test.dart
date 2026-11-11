import 'dart:io';
import 'dart:typed_data';

import 'package:bottogram/plugins/bot_qr.dart';
import 'package:bottogram/plugins/bot_transfer.dart';
import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:image/image.dart' as image;
import 'package:qr_flutter/qr_flutter.dart';

import 'plugins_test.dart' show MemoryVault, TestContext;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Inshopa QR scan recreates bot inputs with secure keys on another installation',
    () async {
      final senderDirectory = await Directory.systemTemp.createTemp(
        'bot-qr-send-',
      );
      final receiverDirectory = await Directory.systemTemp.createTemp(
        'bot-qr-receive-',
      );
      addTearDown(() async {
        await Hive.close();
        await senderDirectory.delete(recursive: true);
        await receiverDirectory.delete(recursive: true);
      });

      final source = await File(
        'examples/plugins/inshopa.storefront.0.8.8.bottogram-plugin.json',
      ).readAsBytes();
      final plugin = PluginManifest.parse(source);
      const name = 'Example shop';
      const token = '123:telegram-fixture';
      const secret = 'inshopa-fixture';
      const parameters = {
        'storefrontUrl': 'https://example.test',
        'telegramChannelId': '-100123, -100456',
        'apiKey': secret,
      };
      const preferences = {'notifyNewSuccessfulPurchases': false};

      Hive.init(senderDirectory.path);
      final sender = PluginRepository(
        vault: MemoryVault(),
        bundledAssets: const [],
      );
      await sender.install(plugin);
      final original = await sender.prepare(
        token: token,
        adminIds: '123,456',
        plugin: plugin,
        parameters: parameters,
        settings: preferences,
      );
      await sender.attach(1, original);
      final transfer = await sender.exportBot(1, name: name, token: token);
      final link = transfer.toLink();
      expect(Uri.parse(link).scheme, 'bottogram');
      final qr = QrImage(
        QrCode.fromData(data: link, errorCorrectLevel: QrErrorCorrectLevel.M),
      );
      final scanned = decodeBotQrImage(image.encodePng(_render(qr)));
      expect(scanned, link);
      final decoded = PluginBotTransfer.fromLink(scanned!);
      expect(decoded.parameters, parameters);

      await sender.vault.delete(original.secretKey('apiKey'));
      await expectLater(
        sender.exportBot(1, name: name, token: token),
        throwsA(isA<PluginException>()),
      );
      sender.dispose();
      await Hive.close();

      Hive.init(receiverDirectory.path);
      if (!Hive.isAdapterRegistered(10)) Hive.registerAdapter(VirtBotAdapter());
      final receiver = PluginRepository(
        vault: MemoryVault(),
        bundledAssets: const [],
      );
      final bots = BotsCubit(TestContext(), plugins: receiver);
      try {
        await bots.ready;
        final wrongBuild = PluginManifest.parse(
          Uint8List.fromList([...source, 32]),
        );
        await receiver.install(wrongBuild);
        await expectLater(
          bots.importPluginBot(decoded),
          throwsA(
            isA<PluginException>().having(
              (e) => e.message,
              'message',
              contains('exact plugin package'),
            ),
          ),
        );
        expect(bots.state, isEmpty);
        await receiver.uninstall(wrongBuild.storageKey);
        await receiver.install(plugin);

        await bots.importPluginBot(decoded);
        final bot = bots.state.single;
        final restored = bot.setup!;
        expect(bot.active, isFalse);
        expect(bot.name, name);
        expect(bot.token, token);
        expect(restored.instanceId, isNot(original.instanceId));
        expect(restored.adminIds, ['123', '456']);
        expect(restored.values, original.values);
        expect(restored.settings, preferences);
        expect(restored.secretFields, ['apiKey']);
        expect(await receiver.vault.read(restored.secretKey('apiKey')), secret);
        expect(restored.toMap().toString(), isNot(contains(secret)));
        await expectLater(
          bots.importPluginBot(decoded),
          throwsA(isA<PluginException>()),
        );
        expect(bots.state, hasLength(1));
      } finally {
        await bots.close();
        receiver.dispose();
      }
    },
  );

  test(
    'corrupt and unrelated QR payloads are rejected without exposing their contents',
    () {
      for (final link in [
        'https://example.test',
        'bottogram://import/plugin-bot/v1#private-marker',
      ]) {
        expect(
          () => PluginBotTransfer.fromLink(link),
          throwsA(
            isA<PluginException>().having(
              (e) => e.message,
              'message',
              isNot(contains('private-marker')),
            ),
          ),
        );
      }
    },
  );
}

image.Image _render(QrImage qr) {
  const scale = 5;
  const quiet = 4;
  final side = (qr.moduleCount + 2 * quiet) * scale;
  final pixels = image.Image(width: side, height: side);
  image.fill(pixels, color: image.ColorRgb8(255, 255, 255));
  for (var row = 0; row < qr.moduleCount; row++) {
    for (var col = 0; col < qr.moduleCount; col++) {
      if (!qr.isDark(row, col)) continue;
      final x = (col + quiet) * scale;
      final y = (row + quiet) * scale;
      image.fillRect(
        pixels,
        x1: x,
        y1: y,
        x2: x + scale - 1,
        y2: y + scale - 1,
        color: image.ColorRgb8(0, 0, 0),
      );
    }
  }
  return pixels;
}
