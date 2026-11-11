import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bottogram/plugins/bot_setup.dart';
import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/runtime/automation_runner.dart';
import 'package:bottogram/runtime/ports.dart';
import 'package:bottogram/runtime/progress_store.dart';
import 'package:bottogram/runtime/telegram_port.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'automation_runtime_test.dart'
    show FakeHttp, FakeTelegram, MemoryProgress, until;
import 'plugins_test.dart' show MemoryVault;
import 'storefront_presentation_test.dart' show PluginHarness, shipped;

const package = 'inshopa.storefront.0.8.1';
const productId = 'e6af6af3-a42d-4a71-87d5-aac75e232183';
const nextId = '11111111-1111-1111-1111-111111111111';
const otherId = '22222222-2222-2222-2222-222222222222';

class TransientHttp extends FakeHttp {
  bool failNext = false;

  @override
  Future<Json> get(Uri url, Map<String, String> headers) async {
    if (failNext) {
      failNext = false;
      throw const RuntimeFailure('Temporary test failure.');
    }
    return super.get(url, headers);
  }
}

class ChannelFixture extends FakeTelegram implements TelegramInteractions {
  bool allowed = true;
  Completer<void>? photoGate;
  final posts = <(String, String, Json?)>[];
  @override
  String get username => 'shop_bot';
  @override
  Future<bool> canPost(
    String chatId, {
    Set<String> chatTypes = const {'channel'},
    bool photo = true,
  }) async => allowed;
  @override
  void interaction(String kind, void Function(Json event) receive) {}
  @override
  Future<void> photo(
    String chatId,
    Uint8List bytes,
    String caption,
    Json? keyboard,
  ) async {
    posts.add((chatId, caption, keyboard));
    await photoGate?.future;
  }

  @override
  Future<void> widget(
    Json event,
    String html,
    Json data,
    String caption,
    Json? keyboard,
  ) async => throw StateError('Unexpected widget');
}

class FanOutHttp extends FakeHttp implements PhotoTransport {
  @override
  Future<Json> get(Uri url, Map<String, String> headers) async {
    if (url.path.endsWith('/products')) {
      return {
        'products': [
          {'id': productId},
        ],
      };
    }
    return {
      'product': {'title': 'New product'},
      'variants': [],
      'images': [
        {'id': productId},
      ],
    };
  }

  @override
  Future<Uint8List?> jpeg(Uri url) async =>
      Uint8List.fromList([255, 216, 255, 217]);
}

class CatalogFixture implements JsonTransport, PhotoTransport {
  List<String> ids = [productId];
  final availablePhotos = <String>{};
  final mediaRequests = <Uri>[];
  @override
  Future<Json> get(Uri url, Map<String, String> headers) async {
    expect(headers['Origin'], 'https://shop.example.test');
    if (url.path.endsWith('/products')) {
      return {
        'products': [
          for (final id in ids) {'id': id},
        ],
      };
    }
    final id = url.pathSegments.last;
    return {
      'product': {'title': 'New item $id'},
      'variants': [
        {'price_irr': 120000},
      ],
      'images': [
        {'id': id},
      ],
    };
  }

  @override
  Future<Uint8List?> jpeg(Uri url) async {
    mediaRequests.add(url);
    return availablePhotos.contains(url.pathSegments.last)
        ? Uint8List.fromList([255, 216, 255, 217])
        : null;
  }

  @override
  void close() {}
}

void main() {
  test(
    'private welcome and menus route buyer and seller commands and paginate one widget',
    () async {
      final http = TransientHttp();
      final h = await PluginHarness.create(package: package, transport: http);
      addTearDown(h.close);
      h.http.responses.add({
        'name': 'حامی‌کامپ',
        'description': 'فروشگاه قطعات کامپیوتر',
      });
      await h.runtime.start(h.bot);
      await until(
        () => h.api.calls.where((c) => c.$1 == 'setMyCommands').length == 2,
      );
      final lists = h.api.calls
          .where((c) => c.$1 == 'setMyCommands')
          .map((c) => c.$2)
          .toList();
      expect(lists[0]['scope'], {'type': 'all_private_chats'});
      expect(lists[1]['scope']['chat_id'].toString(), '123');
      expect((lists[0]['commands'] as List).map((c) => c['command']), [
        'start',
        'shop',
        'products',
        'orders',
        'support',
        'help',
      ]);
      expect((lists[1]['commands'] as List).map((c) => c['command']), [
        'start',
        'shop',
        'products',
        'orders',
        'support',
        'help',
        'seller',
        'channel',
      ]);
      expect(
        h.api.calls
            .singleWhere((c) => c.$1 == 'setChatMenuButton')
            .$2['menu_button'],
        {'type': 'commands'},
      );

      await h.api.command('start');
      await until(() => h.api.calls.any((c) => c.$1 == 'sendWidget'));
      final welcome = h.api.calls.lastWhere((c) => c.$1 == 'sendWidget').$2;
      expect(jsonDecode(welcome['chat_data'])['shop'], 'حامی‌کامپ');
      expect(jsonDecode(welcome['chat_data'])['name'], 'Buyer');
      expect(
        welcome['reply_markup']['inline_keyboard'][0][0]['text'],
        'مشاهده محصولات',
      );

      final before = h.api.messages.length;
      await h.api.command('seller', chat: 123); // chat ID alone is insufficient
      expect(h.api.messages.length, before);
      http.failNext = true;
      await h.api.command('start', chat: 123, sender: 123);
      await until(() => h.api.messages.length == before + 1);
      expect(h.api.messages.last['text'], contains('مدیریت فروشگاه حامی‌کامپ'));
      expect(h.api.messages.last['text'], contains('خاموش'));

      h.http.responses.add({
        'products': [
          for (var i = 0; i < 6; i++) {'id': productId, 'title': 'Product $i'},
        ],
      });
      await h.api.command('shop');
      await until(
        () => h.api.calls.where((c) => c.$1 == 'sendWidget').length == 2,
      );
      final catalog = jsonDecode(
        h.api.calls.lastWhere((c) => c.$1 == 'sendWidget').$2['chat_data'],
      );
      expect(catalog['items'], hasLength(5));
      expect(catalog['next'], '2');
      expect(h.http.requests.last.$1.queryParameters, {
        'limit': '6',
        'offset': '0',
      });

      h.http.responses.add({
        'products': [
          {'id': productId, 'title': 'Last product'},
        ],
      });
      await h.api.widgetTap('catalog:2');
      await until(
        () => h.api.calls.any((c) => c.$1 == 'editMessageWidgetData'),
      );
      final edit = h.api.calls
          .singleWhere((c) => c.$1 == 'editMessageWidgetData')
          .$2;
      expect(edit['message_id'], 200);
      expect(jsonDecode(edit['chat_data'])['previous'], '1');
      expect(jsonDecode(edit['chat_data'])['next'], '');
      expect(h.http.requests.last.$1.queryParameters, {
        'limit': '6',
        'offset': '5',
      });

      h.http.responses.add({
        'products': [
          {'id': productId, 'title': 'Last product'},
        ],
      });
      await h.command('products', suffix: ' 2');
      expect(
        h
            .api
            .messages
            .last['reply_markup']['inline_keyboard'][0][0]['callback_data'],
        'product:$productId',
      );

      h.http.responses.add({
        'product': {'title': 'Last product', 'description': 'Details'},
        'variants': [
          {'price_irr': 10000},
          {'price_irr': 9000},
        ],
        'images': [],
      });
      await h.command('start', suffix: ' p_$productId');
      expect(h.api.messages.last['text'], contains('9000 ریال'));
      expect(
        h
            .api
            .messages
            .last['reply_markup']['inline_keyboard'][0][0]['web_app']['url'],
        'https://shop.example.test/products/$productId',
      );
      expect(
        h.http.requests.last.$1.path,
        '/v1/storefront/products/$productId',
      );
    },
  );

  test(
    'first welcome keeps navigation available if the shop profile is unreachable',
    () async {
      final http = TransientHttp()..failNext = true;
      final h = await PluginHarness.create(package: package, transport: http);
      addTearDown(h.close);
      await h.runtime.start(h.bot);
      await h.api.command('start');
      await until(() => h.api.calls.any((call) => call.$1 == 'sendWidget'));
      final welcome = h.api.calls
          .singleWhere((call) => call.$1 == 'sendWidget')
          .$2;
      expect(welcome['caption'], contains('به فروشگاه خوش اومدی'));
      final buttons = welcome['reply_markup']['inline_keyboard'];
      expect(buttons[0][0]['callback_data'], 'catalog');
      expect(
        buttons[1][0]['web_app']['url'],
        'https://shop.example.test/orders',
      );
    },
  );

  test(
    'channel scans quietly, retries missing media, and isolates receipt history by destination',
    () async {
      final manifest = shipped(package);
      final definition = manifest.automations.singleWhere(
        (a) => a.destinationField != null,
      );
      final http = CatalogFixture();
      final telegram = ChannelFixture();
      final progress = MemoryProgress();

      AutomationRunner channelRunner(
        String channel,
        void Function(String?) onStatus,
      ) => AutomationRunner(
        definition: definition,
        store: progress,
        key: 'instance:digest:automation:channel:$channel',
        channelId: channel,
        onStatus: onStatus,
        context: RuntimeContext(
          http: http,
          telegram: telegram,
          secret: (_) async => 'fixture',
          fields: {
            'storefrontUrl': 'https://shop.example.test',
            'telegramChannelId': channel,
          },
          adminId: '123',
        ),
      );

      Future<void> scan(String channel, {bool denied = false}) async {
        final statuses = <String?>[];
        final runner = channelRunner(channel, statuses.add);
        unawaited(runner.start());
        try {
          await until(() => statuses.isNotEmpty);
          if (denied) expect(statuses.last, contains('cannot post'));
        } finally {
          await runner.stop();
        }
      }

      telegram.allowed = false;
      await scan('-1001', denied: true);
      expect(progress.values, isEmpty);
      telegram.allowed = true;
      await scan('-1001');
      expect(telegram.posts, isEmpty);
      expect(http.mediaRequests, isEmpty);
      http.ids = [productId, nextId, otherId];
      http.availablePhotos.add(otherId);
      await scan('-1001');
      expect(
        telegram.posts.single.$3!['inline_keyboard'][0][0]['url'],
        'https://t.me/shop_bot?start=p_$otherId',
      );
      expect(
        http.mediaRequests.last.toString(),
        'https://shop.example.test/api/v1/media/$otherId',
      );
      http.availablePhotos.add(nextId);
      await scan('-1001');
      expect(telegram.posts, hasLength(2));
      await scan('-1001');
      expect(telegram.posts, hasLength(2));
      await scan('-1002');
      expect(telegram.posts, hasLength(2));
      await scan('-1001');
      expect(telegram.posts, hasLength(2));

      const newestId = '33333333-3333-3333-3333-333333333333';
      http.ids.add(newestId);
      http.availablePhotos.add(newestId);
      telegram.photoGate = Completer<void>();
      final runner = channelRunner('-1001', (_) {});
      unawaited(runner.start());
      await until(() => telegram.posts.length == 3);
      final stopping = runner.stop();
      telegram.photoGate!.complete();
      await stopping;
      await scan('-1001');
      expect(telegram.posts, hasLength(3));
    },
  );

  test(
    'reviewed upgrade and channel edit preserve seller progress, settings and key references',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'storefront-upgrade-',
      );
      Hive.init(directory.path);
      final repository = PluginRepository(
        vault: MemoryVault(),
        bundledAssets: [],
      );
      addTearDown(() async {
        repository.dispose();
        await Hive.close();
        await directory.delete(recursive: true);
      });
      final next = shipped(package);
      final older = jsonDecode(next.source) as Json..['version'] = '0.8.0';
      final previous = PluginManifest.parse(utf8.encode(jsonEncode(older)));
      await repository.install(previous);
      await repository.install(next);
      const token = '99:fixture';
      final setup = await repository.prepare(
        token: token,
        adminId: '123',
        plugin: previous,
        parameters: {
          'storefrontUrl': 'https://shop.example.test',
          'apiKey': 'fixture',
        },
      );
      await repository.attach(1, setup);
      await repository.updateSettings(1, token, {
        'notifyNewSuccessfulPurchases': false,
      });
      final progress = HiveProgressStore();
      final from = '${setup.instanceId}:${previous.digest}:paid-orders';
      final to = '${setup.instanceId}:${next.digest}:paid-orders';
      await progress.write(from, {'initialized': true, 'pageCursor': '100'});
      await progress.write('$from:delivered:sample', {'complete': true});
      final plan = await repository.reviewUpgrade(1, token, next);
      expect(plan.preservedAutomationIds, contains('paid-orders'));
      final updated = await repository.upgrade(
        1,
        token,
        next,
        copyNamespace: progress.copyNamespace,
      );
      final channel = await repository.updateParameters(
        1,
        token,
        adminId: '123',
        parameters: {'telegramChannelId': '-100123'},
      );
      expect(channel.instanceId, setup.instanceId);
      expect(channel.secretKey('apiKey'), setup.secretKey('apiKey'));
      expect(channel.values['telegramChannelId'], '-100123');
      expect(channel.values['storefrontUrl'], 'https://shop.example.test');
      expect(channel.pluginDigest, updated.pluginDigest);
      expect(channel.settings['notifyNewSuccessfulPurchases'], false);
      expect(await progress.read(to), {
        'initialized': true,
        'pageCursor': '100',
      });
      expect(await progress.read('$to:delivered:sample'), {'complete': true});
    },
  );

  test(
    'command synchronization retires a previously managed admin scope',
    () async {
      final h = await PluginHarness.create(package: package);
      addTearDown(h.close);
      final setup = h.bot.setup!;
      final key = '@telegram:${setup.tokenFingerprint}:commands';
      await h.progress.write(key, {
        'admins': ['123'],
      });
      h.bot.setup = BotSetup.fromMap({
        ...setup.toMap(),
        'adminTelegramUserId': '777',
      });
      await h.runtime.start(h.bot);
      await until(
        () => h.api.calls.any((call) => call.$1 == 'deleteMyCommands'),
      );
      final deleted = h.api.calls
          .singleWhere((call) => call.$1 == 'deleteMyCommands')
          .$2;
      expect(deleted['scope']['chat_id'].toString(), '123');
      final published = h.api.calls
          .lastWhere((call) => call.$1 == 'setMyCommands')
          .$2;
      expect(published['scope']['chat_id'].toString(), '777');
      await h.runtime.stop(h.bot);
      expect(await h.progress.read(key), {
        'admins': ['777'],
      });
    },
  );

  test(
    'Telegram port checks channel permission and uploads a photo with a deep link',
    () async {
      final h = await PluginHarness.create(package: package);
      addTearDown(h.close);
      await h.api.bot.initialize();
      final telegram = BotTelegramPort(h.api.bot);
      h.api.canPost = false;
      expect(await telegram.canPost('-100123'), false);
      h.api.canPost = true;
      expect(await telegram.canPost('-100123'), true);
      final keyboard = {
        'inline_keyboard': [
          [
            {'text': 'Open', 'url': 'https://t.me/shop_bot?start=p_$productId'},
          ],
        ],
      };
      await telegram.photo(
        '-100123',
        Uint8List.fromList([255, 216, 255, 217]),
        'محصول تازه',
        keyboard,
      );
      final post = h.api.calls.singleWhere((call) => call.$1 == 'sendPhoto').$2;
      expect(post['uploaded_photo'], true);
      expect(post['chat_id'].toString(), '-100123');
      expect(post['caption'], 'محصول تازه');
      expect(jsonDecode(post['reply_markup']), keyboard);
    },
  );

  test(
    'selected channels and groups receive separate deliveries despite denied destinations',
    () async {
      final h = await PluginHarness.create(
        package: package,
        transport: FanOutHttp(),
      );
      addTearDown(h.close);
      h.api.groupPhotoPermissions.addAll({-1002: true, -1003: false});
      h.api.deniedChannels.add(-1004);
      final setup = h.bot.setup!;
      h.bot.setup = setup.copyWith(
        values: {
          ...setup.values,
          'telegramChannelId': '-1001, -1002\n-1003، -1004\n-1001',
        },
      );
      final field = h.manifest.fields.singleWhere(
        (field) => field.key == 'telegramChannelId',
      );
      expect(field.validate(h.bot.setup!.values[field.key]!), isNull);
      expect(field.validate('-1001, @unresolved_channel'), isNotNull);
      final namespace =
          '${setup.instanceId}:${h.manifest.digest}:new-published-products';
      for (final destination in ['-1001', '-1002', '-1003', '-1004']) {
        await h.progress.write('$namespace:channel:$destination', {
          'initialized': true,
        });
      }
      await h.runtime.start(h.bot);
      await until(
        () =>
            h.api.calls.where((call) => call.$1 == 'sendPhoto').length == 2 &&
            h.runtime.failuresFor(h.bot).length == 2 &&
            h.progress.values.keys
                    .where((key) => key.contains(':delivered:'))
                    .length ==
                2,
      );
      final posts = h.api.calls
          .where((call) => call.$1 == 'sendPhoto')
          .map((call) => call.$2);
      expect(
        posts.map((post) => post['chat_id']),
        unorderedEquals(['-1001', '-1002']),
      );
      expect(
        posts.every(
          (post) =>
              post['reply_markup'].toString().contains('start=p_$productId'),
        ),
        true,
      );
      expect(
        h.runtime.failuresFor(h.bot).map((failure) => failure.destination),
        unorderedEquals(['-1003', '-1004']),
      );
    },
  );

  test('manifest rejects a destination with unrestricted field semantics', () {
    final source = shipped(package).source;
    final json = jsonDecode(source) as Json;
    (json['setupFields'] as List).last['chatTypes'] = ['private'];
    expect(
      () => PluginManifest.parse(utf8.encode(jsonEncode(json))),
      throwsA(isA<PluginException>()),
    );
  });
}
