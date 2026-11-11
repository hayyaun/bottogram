import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:televerse/televerse.dart';
import 'support/telegram_updates.dart';
import 'package:televerse/telegram.dart' show Update;
import 'package:bottogram/plugins/bot_setup.dart';
import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/runtime/coordinator.dart';
import 'package:bottogram/runtime/progress_store.dart';
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
  late final bot = Bot.local('99:test-token', 'http://127.0.0.1:${server.port}')
    ..onError((error) => errors.add(error));

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
      } else if (method == 'setChatMenuButton' || method == 'setMyCommands') {
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
      bot.dispatch(
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

class MemoryNamespaces extends MemoryProgress
    implements NamespaceProgressStore {
  @override
  Future<void> copyNamespace(String source, String destination) async {
    for (final entry in values.entries.toList()) {
      if (entry.key == source || entry.key.startsWith('$source:')) {
        values['$destination${entry.key.substring(source.length)}'] =
            jsonDecode(jsonEncode(entry.value)) as Map<String, dynamic>;
      }
    }
  }
}

class PluginHarness {
  PluginHarness(
    this.api,
    this.manifest,
    this.catalog,
    this.bot,
    this.runtime,
    this.http,
    this.progress,
  );
  final TelegramFixture api;
  final PluginManifest manifest;
  final MemoryCatalog catalog;
  final PresentationBot bot;
  final BotRuntime runtime;
  final FakeHttp http;
  final MemoryNamespaces progress;

  static Future<PluginHarness> create({
    String package = 'inshopa.storefront',
    bool notify = false,
    bool failMenu = false,
    String origin = 'https://shop.example.test',
    String apiOrigin = 'http://registered-shop.localhost',
  }) async {
    final api = await TelegramFixture.open()
      ..failMenu = failMenu;
    final manifest = shipped(package);
    final catalog = MemoryCatalog()..entries.add(manifest);
    final bot = PresentationBot(api.bot)
      ..setup = BotSetup(
        instanceId: 'original-instance',
        tokenFingerprint: BotSetup.fingerprint('99:test-token'),
        adminTelegramUserId: '123',
        pluginKey: manifest.storageKey,
        pluginDigest: manifest.digest,
        pluginName: manifest.name,
        values: {
          'storefrontUrl': origin,
          if (manifest.fields.any((field) => field.key == 'apiOrigin'))
            'apiOrigin': apiOrigin,
        },
        secretFields: const ['apiKey'],
        settings: {'notifyNewSuccessfulPurchases': notify},
      );
    await catalog.vault.write(bot.setup!.secretKey('apiKey'), 'seller-key');
    final http = FakeHttp();
    final progress = MemoryNamespaces();
    final runtime = BotRuntime(
      TestLease(),
      catalog,
      progress: progress,
      httpClientFactory: () => http,
    );
    return PluginHarness(api, manifest, catalog, bot, runtime, http, progress);
  }

  Future<void> command(String name, {String suffix = ''}) async {
    final before = api.messages.length;
    await api.command(name, suffix: suffix);
    await until(() => api.messages.length == before + 1);
  }

  Future<void> close() async {
    await runtime.close();
    catalog.dispose();
    await api.close();
  }
}

void main() {
  for (final package in ['inshopa.storefront', 'inshopa.storefront.local']) {
    test(
      '$package JSON drives every buyer command and direct Mini App destination through the real SDK',
      () async {
        final h = await PluginHarness.create(package: package);
        try {
          await h.runtime.start(h.bot);
          for (final command in [
            'start',
            'menu',
            'shop',
            'products',
            'store',
            'orders',
            'myorders',
            'help',
            'guide',
            'support',
          ]) {
            await h.command(command, suffix: command == 'products' ? ' 2' : '');
            final reply = h.api.messages.last;
            final rows =
                (reply['reply_markup'] as Map)['inline_keyboard'] as List;
            final buttons = rows
                .expand((row) => (row as List).cast<Map>())
                .toList();
            final orderFirst = {
              'orders',
              'myorders',
              'support',
            }.contains(command);
            expect(
              buttons.map((b) => b['text']),
              orderFirst
                  ? ['سفارش های من', 'ورود به فروشگاه']
                  : ['ورود به فروشگاه', 'سفارش های من'],
            );
            expect(buttons[orderFirst ? 0 : 1]['web_app'], {
              'url': 'https://shop.example.test/orders',
            });
            expect(buttons[orderFirst ? 1 : 0]['web_app'], {
              'url': 'https://shop.example.test/',
            });
            expect(rows.every((row) => (row as List).length == 1), isTrue);
            expect(reply['text'], matches(RegExp(r'^[\u0600-\u06ff]')));
            expect(jsonEncode(reply), isNot(contains('seller-key')));
            expect(
              buttons.every(
                (b) =>
                    !b.containsKey('callback_data') &&
                    !b.containsKey('login_url'),
              ),
              isTrue,
            );
          }
          await until(
            () => h.api.calls.any((c) => c.$1 == 'setChatMenuButton'),
          );
          final menu =
              h.api.calls
                      .firstWhere((c) => c.$1 == 'setChatMenuButton')
                      .$2['menu_button']
                  as Map;
          expect(menu['text'], 'ورود به فروشگاه');
          expect(menu['web_app'], {'url': 'https://shop.example.test/'});
          await until(() => h.api.calls.any((c) => c.$1 == 'setMyCommands'));
          final registered = h.api.calls
              .firstWhere((c) => c.$1 == 'setMyCommands')
              .$2;
          expect(registered['commands'], h.manifest.telegram!['commands']);
          expect(registered['scope'], {'type': 'all_private_chats'});
          expect(registered['language_code'] ?? '', isEmpty);
          final before = h.api.messages.length;
          await h.api.command('shop', chat: -100);
          await h.api.bot.dispatch(
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
          expect(h.api.messages.length, before);
          expect(h.http.requests, isEmpty);
          expect(h.bot.active, isTrue);
        } finally {
          await h.close();
        }
      },
    );
  }

  test(
    'old pinned package executes its own catalog declaration without host overrides',
    () async {
      final h = await PluginHarness.create(package: 'inshopa.sales');
      h.http.responses.add({
        'products': [
          {'title': 'Original catalog'},
        ],
      });
      try {
        await h.runtime.start(h.bot);
        await h.command('products');
        expect(h.api.messages.last['text'], contains('Original catalog'));
        expect(h.api.messages.last.containsKey('reply_markup'), isFalse);
        expect(h.http.requests.single.$1.path, '/v1/storefront/products');
        expect(h.api.calls.any((c) => c.$1 == 'setChatMenuButton'), isFalse);
        expect(h.api.calls.any((c) => c.$1 == 'setMyCommands'), isFalse);
        final before = h.api.messages.length;
        await h.api.command('shop');
        expect(h.api.messages.length, before);
      } finally {
        await h.close();
      }
    },
  );

  for (final acknowledged in [false, true]) {
    test(
      'prepared seller namespace resumes copied progress ($acknowledged) without rebaselining or replaying receipts',
      () async {
        final h = await PluginHarness.create(
          notify: true,
          failMenu: true,
          origin: acknowledged
              ? 'shop.example.test'
              : 'https://shop.example.test',
        );
        final setup = h.bot.setup!;
        expect(h.manifest.fields.map((field) => field.key), [
          'apiKey',
          'storefrontUrl',
        ]);
        expect(setup.values.containsKey('apiOrigin'), isFalse);
        final snapshot = jsonEncode(setup.toMap());
        final oldKey =
            '${setup.instanceId}:${shipped('inshopa.sales').digest}:paid-orders';
        final key = '${setup.instanceId}:${h.manifest.digest}:paid-orders';
        String receipt(String prefix, String id) =>
            '$prefix:delivered:${sha256.convert(utf8.encode(id))}';
        h.progress.values[oldKey] = {
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
        h.progress.values[receipt(oldKey, 'old')] = {'complete': true};
        final oldSnapshot = jsonEncode(h.progress.values);
        await h.progress.copyNamespace(oldKey, key);
        h.http.responses.addAll([
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
        try {
          await h.runtime.start(h.bot);
          await until(
            () => h.progress.values[receipt(key, 'new')]?['complete'] == true,
          );
          expect(h.bot.active, isTrue);
          expect(jsonEncode(h.bot.setup!.toMap()), snapshot);
          expect(
            await h.catalog.vault.read(setup.secretKey('apiKey')),
            'seller-key',
          );
          expect(h.progress.values[receipt(key, 'old')], {'complete': true});
          expect(h.progress.values[receipt(key, 'queued')], {'complete': true});
          expect(h.progress.values[key]?['initialized'], isTrue);
          expect(
            jsonEncode({
              for (final e in h.progress.values.entries)
                if (e.key == oldKey || e.key.startsWith('$oldKey:'))
                  e.key: e.value,
            }),
            oldSnapshot,
          );
          final alerts = h.api.messages
              .where((m) => m['chat_id'].toString() == '123')
              .toList();
          expect(alerts.length, acknowledged ? 1 : 2);
          expect(
            alerts.where(
              (m) => (m['text'] as String).contains('شماره سفارش: new'),
            ),
            hasLength(1),
          );
          expect(
            alerts.any(
              (m) => (m['text'] as String).contains('شماره سفارش: old'),
            ),
            isFalse,
          );
          expect(
            alerts.every(
              (m) => (m['text'] as String).contains('مبلغ سفارش: 1 ریال'),
            ),
            isTrue,
          );
          await h.command('shop');
          final buyerReply = h.api.messages.last;
          final buyerRows =
              (buyerReply['reply_markup'] as Map)['inline_keyboard'] as List;
          expect((buyerRows.first as List).first['web_app'], {
            'url': 'https://shop.example.test/',
          });
          await h.runtime.start(h.bot);
          expect(h.http.requests.map((r) => r.$1.path), [
            '/v1/storefront',
            '/v1/shops/shop-1/orders',
          ]);
          expect(
            h.http.requests.every(
              (request) =>
                  request.$2['Origin'] == 'https://shop.example.test' &&
                  request.$2['X-Storefront-Host'] == 'shop.example.test',
            ),
            isTrue,
          );
          expect(h.runtime.errorFor(h.bot), contains('menu'));
          expect(h.api.errors, isEmpty);
        } finally {
          await h.close();
        }
      },
    );
  }

  test(
    'local example keeps seller origin independent of invalid Telegram website origin',
    () async {
      final h = await PluginHarness.create(
        package: 'inshopa.storefront.local',
        notify: true,
        origin: 'http://localhost:3000',
      );
      expect(h.manifest.fields.map((field) => field.key), [
        'apiKey',
        'apiOrigin',
        'storefrontUrl',
      ]);
      final key = '${h.bot.setup!.instanceId}:${h.manifest.digest}:paid-orders';
      h.progress.values[key] = {'initialized': true};
      h.http.responses.addAll([
        {'id': 'shop-1'},
        {
          'orders': [
            {
              'id': 'paid',
              'status': 'paid',
              'shop_name': 'Shop',
              'total_irr': 1,
              'currency': 'IRR',
            },
          ],
        },
      ]);
      try {
        await h.runtime.start(h.bot);
        await h.api.command('shop');
        await until(
          () => h.api.messages.any((m) => m['chat_id'].toString() == '123'),
        );
        expect(h.bot.active, isTrue);
        expect(
          h.api.messages.where((m) => m['chat_id'].toString() == '42'),
          isEmpty,
        );
        expect(
          jsonEncode(h.api.calls.map((c) => c.$2).toList()),
          isNot(contains('seller-key')),
        );
        expect(h.http.requests, hasLength(2));
        expect(
          h.http.requests.every(
            (request) =>
                request.$2['Origin'] == 'http://registered-shop.localhost' &&
                request.$2['X-Storefront-Host'] == 'registered-shop.localhost',
          ),
          isTrue,
        );
      } finally {
        await h.close();
      }
    },
  );

  test('failed buyer delivery does not stop the bot', () async {
    final failed = await PluginHarness.create();
    try {
      failed.api.failMessages = true;
      await failed.runtime.start(failed.bot);
      await failed.api.command('shop');
      await until(() => failed.runtime.errorFor(failed.bot) != null);
      expect(failed.bot.active, isTrue);
      expect(failed.api.errors, isEmpty);
    } finally {
      await failed.close();
    }
  });
}
