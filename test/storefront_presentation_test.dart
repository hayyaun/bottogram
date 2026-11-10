import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:televerse/televerse.dart';
import 'package:televerse/telegram.dart' show Update;
import 'package:bottogram/plugins/bot_setup.dart';
import 'package:bottogram/plugins/bundled_presentations.dart';
import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/runtime/coordinator.dart';
import 'package:bottogram/runtime/storefront_presentation.dart';
import 'package:bottogram/units/virt_bot.dart';

import 'automation_runtime_test.dart' show FakeHttp, MemoryProgress, until;
import 'plugins_test.dart' show MemoryCatalog;
import 'runtime_lifecycle_test.dart' show TestLease;

PluginManifest shipped(String filename) => PluginManifest.parse(
  File('examples/plugins/$filename.bottogram-plugin.json').readAsBytesSync(),
);

class TelegramFixture {
  TelegramFixture(this.server);
  final HttpServer server;
  final calls = <(String, Map<String, dynamic>)>[];
  final errors = <Object>[];
  bool failMenu = false;
  bool failMessages = false;
  late final bot = Bot.local(
    '99:test-token',
    baseURL: 'http://127.0.0.1:${server.port}',
  )..onError((error) => errors.add(error));

  static Future<TelegramFixture> open() async {
    final fixture = TelegramFixture(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    fixture.server.listen((request) async {
      final method = request.uri.pathSegments.last;
      final text = await utf8.decoder.bind(request).join();
      final body = text.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(text) as Map<String, dynamic>;
      fixture.calls.add((method, body));
      dynamic result;
      final denied =
          (method == 'setChatMenuButton' && fixture.failMenu) ||
          (method == 'sendMessage' && fixture.failMessages);
      if (method == 'getMe') {
        result = {
          'id': 99,
          'is_bot': true,
          'first_name': 'Shop bot',
          'username': 'shop_bot',
        };
      } else if (method == 'setChatMenuButton') {
        result = true;
      } else if (method == 'sendMessage') {
        final chat = int.parse(body['chat_id'].toString());
        result = {
          'message_id': fixture.calls.length,
          'date': 1700000000,
          'chat': {'id': chat, 'type': chat < 0 ? 'group' : 'private'},
          'text': body['text'],
        };
      } else {
        throw StateError('Unexpected Telegram method: $method');
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(
          denied
              ? {
                  'ok': false,
                  'error_code': 403,
                  'description': 'Test delivery denied',
                }
              : {'ok': true, 'result': result},
        ),
      );
      await request.response.close();
    });
    return fixture;
  }

  Iterable<Map<String, dynamic>> get messages =>
      calls.where((call) => call.$1 == 'sendMessage').map((call) => call.$2);

  Future<void> command(String command, {int chat = 42, String suffix = ''}) =>
      bot.handleUpdate(
        Update.fromJson({
          'update_id': calls.length + 1,
          'message': {
            'message_id': calls.length + 1,
            'date': 1700000000,
            'chat': {'id': chat, 'type': chat < 0 ? 'group' : 'private'},
            'from': {'id': 42, 'is_bot': false, 'first_name': 'Buyer'},
            'text': '/$command$suffix',
            'entities': [
              {
                'offset': 0,
                'length': command.length + 1,
                'type': 'bot_command',
              },
            ],
          },
        }),
      );

  Future<void> close() async {
    bot.api.closeClient();
    await server.close(force: true);
  }
}

class PresentationBot extends VirtBot {
  PresentationBot(Bot session)
    : super('Existing shop', '99:test-token', addSamples: false) {
    bot = session;
  }
  bool running = false;
  @override
  bool get active => running;
  @override
  Future<void> start({bool pluginRuntime = false}) async {
    running = true;
    onRunningChanged?.call();
  }

  @override
  Future<void> stop() async {
    running = false;
    onRunningChanged?.call();
  }
}

void main() {
  const presentation = StorefrontPresentation(
    originField: 'storefrontUrl',
    replacedAutomationIds: {'products'},
  );

  test('only exact shipped live packages receive the host presentation', () {
    for (final name in [
      'inshopa.sales',
      'inshopa.sales.local',
      'inshopa.catalog',
      'inshopa.catalog.local',
    ]) {
      final manifest = shipped(name);
      final binding = bundledPresentationFor(manifest)!;
      final remaining = binding.automationsFor(manifest).toList();
      expect(remaining.any((a) => a.id == 'products'), isFalse);
      expect(
        remaining.map((a) => a.id),
        name.contains('sales') ? ['paid-orders'] : isEmpty,
      );
      if (remaining.isNotEmpty) {
        expect(remaining.single, same(manifest.automations.last));
      }
      final custom = PluginManifest.parse(utf8.encode('${manifest.source}\n'));
      expect(bundledPresentationFor(custom), isNull);
    }
    expect(bundledPresentationFor(shipped('inshopa')), isNull);
  });

  test(
    'launch URLs accept only an HTTPS origin and never strip credentials into a usable link',
    () {
      expect(
        presentation.origin({
          'storefrontUrl': 'https://shop.example.test/',
        }).toString(),
        'https://shop.example.test',
      );
      expect(
        presentation.origin({
          'storefrontUrl': 'https://custom.example.test:8443',
        }).toString(),
        'https://custom.example.test:8443',
      );
      for (final address in [
        '',
        'http://127.0.0.1:3000',
        '//shop.example.test',
        'https://user:secret@shop.example.test',
        'https://shop.example.test?token=secret',
        'https://shop.example.test#secret',
        'https://shop.example.test/login',
        ' https://shop.example.test',
        'https://shop.example.test\\@other.test',
      ]) {
        expect(
          presentation.origin({'storefrontUrl': address}),
          isNull,
          reason: address,
        );
      }
    },
  );

  test(
    'real SDK sends direct Mini App buttons for each command and ignores buyer payloads',
    () async {
      final api = await TelegramFixture.open();
      try {
        await api.bot.init();
        presentation.register(api.bot, {
          'storefrontUrl': 'https://shop.example.test',
          'apiKey': 'never-send-this',
        });
        for (final command in StorefrontPresentation.commands) {
          await api.command(command, suffix: command == 'products' ? ' 2' : '');
          final reply = api.messages.last;
          final rows =
              (reply['reply_markup'] as Map)['inline_keyboard'] as List;
          final buttons = (rows.single as List).cast<Map>();
          expect(
            buttons.map((b) => b['text']),
            command == 'orders' ? ['My orders'] : ['Open shop', 'My orders'],
          );
          expect(buttons.last['web_app'], {
            'url': 'https://shop.example.test/orders',
          });
          if (command != 'orders') {
            expect(buttons.first['web_app'], {
              'url': 'https://shop.example.test',
            });
          }
          expect(jsonEncode(reply), isNot(contains('never-send-this')));
          expect(
            buttons.every(
              (b) =>
                  !b.containsKey('callback_data') &&
                  !b.containsKey('login_url') &&
                  !b.containsKey('url'),
            ),
            isTrue,
          );
        }
        final before = api.messages.length;
        await api.bot.handleUpdate(
          Update.fromJson({
            'update_id': 200,
            'message': {
              'message_id': 200,
              'date': 1700000000,
              'chat': {'id': 42, 'type': 'private'},
              'from': {'id': 42, 'is_bot': false, 'first_name': 'Buyer'},
              'web_app_data': {
                'button_text': 'Unexpected data',
                'data': 'not-an-auth-channel',
              },
            },
          }),
        );
        expect(api.messages.length, before);
        await api.command('shop', chat: -100);
        expect(api.messages.last.containsKey('reply_markup'), isFalse);
        expect(api.messages.last['text'], contains('private chat'));
        expect(
          await presentation.synchronizeMenu(api.bot, {
            'storefrontUrl': 'https://shop.example.test',
          }),
          isTrue,
        );
        final menu = api.calls.last.$2['menu_button'] as Map;
        expect(menu['type'], 'web_app');
        expect(menu['web_app'], {'url': 'https://shop.example.test'});
        api.failMenu = true;
        expect(
          await presentation.synchronizeMenu(api.bot, {
            'storefrontUrl': 'https://shop.example.test',
          }),
          isFalse,
        );
        api.failMessages = true;
        await api.command('shop');
        expect(api.errors, isEmpty);
      } finally {
        await api.close();
      }
    },
  );

  for (final acknowledged in [false, true]) {
    test(
      'coordinator preserves pinned setup, baseline, pending action ($acknowledged) and seller receipts',
      () async {
        final api = await TelegramFixture.open()
          ..failMenu = true;
        final catalog = MemoryCatalog();
        final manifest = shipped('inshopa.sales');
        catalog.entries.add(manifest);
        final bot = PresentationBot(api.bot);
        final setup = bot.setup = BotSetup(
          instanceId: 'original-instance',
          tokenFingerprint: BotSetup.fingerprint(bot.token),
          adminTelegramUserId: '123',
          pluginKey: manifest.storageKey,
          pluginDigest: manifest.digest,
          pluginName: manifest.name,
          values: {'storefrontUrl': 'https://shop.example.test'},
          secretFields: const ['apiKey'],
          settings: const {'notifyNewSuccessfulPurchases': true},
        );
        await catalog.vault.write(setup.secretKey('apiKey'), 'seller-key');
        final savedSetup = jsonEncode(setup.toMap());
        final progress = MemoryProgress();
        final key = '${setup.instanceId}:${manifest.digest}:paid-orders';
        String receipt(String id) =>
            '$key:delivered:${sha256.convert(utf8.encode(id))}';
        progress.values[key] = {
          'initialized': true,
          'pending': {
            'events': [
              {
                'id': 'queued',
                'shop_name': 'Shop',
                'total_irr': 1,
                'currency': 'IRR',
              },
            ],
            'index': 0,
            'action': acknowledged ? 1 : 0,
            'checkpoint': null,
            'nextCursor': '100',
            'pageDelayMs': 0,
            'durableDeduplication': true,
          },
        };
        progress.values[receipt('old')] = {'complete': true};
        final http = FakeHttp()
          ..responses.addAll([
            {'id': 'shop-1'},
            {
              'orders': [
                {'id': 'old', 'status': 'paid'},
                {
                  'id': 'new',
                  'status': 'paid',
                  'shop_name': 'Shop',
                  'total_irr': 1,
                  'currency': 'IRR',
                },
              ],
            },
          ]);
        final runtime = BotRuntime(
          TestLease(),
          catalog,
          progress: progress,
          httpClientFactory: () => http,
        );
        try {
          await runtime.start(bot);
          await until(
            () => progress.values[receipt('new')]?['complete'] == true,
          );
          expect(bot.active, isTrue);
          expect(bot.setup, same(setup));
          expect(jsonEncode(bot.setup!.toMap()), savedSetup);
          expect(
            await catalog.vault.read(setup.secretKey('apiKey')),
            'seller-key',
          );
          expect(progress.values[receipt('old')], {'complete': true});
          expect(progress.values[receipt('queued')], {'complete': true});
          expect(progress.values[key]?['initialized'], isTrue);
          final alerts = api.messages
              .where((m) => m['chat_id'].toString() == '123')
              .toList();
          expect(alerts.length, acknowledged ? 1 : 2);
          expect(
            alerts.where((m) => (m['text'] as String).contains('Order: new')),
            hasLength(1),
          );
          expect(
            alerts.any((m) => (m['text'] as String).contains('Order: old')),
            isFalse,
          );
          await api.command('start');
          await api.command('products', suffix: ' 2');
          await runtime.start(bot);
          expect(bot.active, isTrue);
          expect(api.messages.last['reply_markup'], isNotNull);
          expect(http.requests.map((r) => r.$1.path), [
            '/v1/storefront',
            '/v1/shops/shop-1/orders',
          ]);
          expect(runtime.errorFor(bot), isNull);
          expect(progress.values.keys.every((k) => k.startsWith(key)), isTrue);
        } finally {
          await runtime.close();
          catalog.dispose();
          await api.close();
        }
      },
    );
  }

  test(
    'disabled alerts stay disabled and invalid HTTPS setup cannot interrupt the bot or expose its value',
    () async {
      final api = await TelegramFixture.open();
      final catalog = MemoryCatalog();
      final manifest = shipped('inshopa.sales');
      catalog.entries.add(manifest);
      final bot = PresentationBot(api.bot)
        ..setup = BotSetup(
          instanceId: 'disabled',
          tokenFingerprint: BotSetup.fingerprint('99:test-token'),
          adminTelegramUserId: '123',
          pluginKey: manifest.storageKey,
          pluginDigest: manifest.digest,
          values: {'storefrontUrl': 'http://user:secret@localhost:3000'},
          settings: const {'notifyNewSuccessfulPurchases': false},
        );
      final progress = MemoryProgress();
      final http = FakeHttp();
      final runtime = BotRuntime(
        TestLease(),
        catalog,
        progress: progress,
        httpClientFactory: () => http,
      );
      try {
        await runtime.start(bot);
        await api.command('shop');
        expect(bot.active, isTrue);
        expect(api.messages.last['text'], contains('HTTPS'));
        expect(
          jsonEncode(api.calls.map((call) => call.$2).toList()),
          isNot(contains('secret')),
        );
        expect(api.messages.last.containsKey('reply_markup'), isFalse);
        expect(api.calls.any((c) => c.$1 == 'setChatMenuButton'), isFalse);
        expect(http.requests, isEmpty);
        expect(progress.values, isEmpty);
      } finally {
        await runtime.close();
        catalog.dispose();
        await api.close();
      }
    },
  );
}
