import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/runtime/automation_runner.dart';
import 'package:bottogram/runtime/ports.dart';
import 'package:bottogram/runtime/http_transport.dart';
import 'package:bottogram/runtime/progress_store.dart';
import 'package:bottogram/runtime/registry.dart';
import 'package:bottogram/runtime/triggers/http_list_poll.dart';
import 'automation_runtime_test.dart'
    show
        MemoryProgress,
        FakeTelegram,
        FakeHttp,
        QueueTrigger,
        FunctionAction,
        until;

Json salesPackage() =>
    jsonDecode(
          File(
            'examples/plugins/inshopa.sales.bottogram-plugin.json',
          ).readAsStringSync(),
        )
        as Json;
PluginManifest parse(Json package) =>
    PluginManifest.parse(Uint8List.fromList(utf8.encode(jsonEncode(package))));
Json salesConfig() =>
    salesPackage()['automations'][1]['trigger']['config'] as Json;
RuntimeContext context(
  FakeHttp http,
  FakeTelegram telegram, {
  String admin = '123',
}) => RuntimeContext(
  http: http,
  telegram: telegram,
  secret: (_) async => 'test-secret',
  fields: {'storefrontUrl': 'https://shop.example.test'},
  adminId: admin,
);
Json order(String id, String status) => {
  'id': id,
  'status': status,
  'shop_id': 'shop-1',
  'shop_name': 'Test shop',
  'total_irr': 250000,
  'currency': 'IRR',
  'created_at': '2026-01-01T00:00:00Z',
};

class ReceiptFailureStore extends MemoryProgress {
  bool fail = true;
  @override
  Future<void> write(String key, Json value) async {
    if (fail && key.contains(':delivered:')) {
      throw StateError('Disk unavailable');
    }
    await super.write(key, value);
  }
}

void main() {
  test(
    'actual HTTP transport resolves and filters the order-list contract with the registered headers',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      var denied = false;
      server.listen((request) async {
        requests++;
        expect(request.headers.value('authorization'), 'Bearer test-secret');
        expect(request.headers.value('x-storefront-host'), 'shop.example.test');
        expect(request.headers.value('origin'), 'https://shop.example.test');
        request.response.headers.contentType = ContentType.json;
        if (denied) {
          request.response.statusCode = 403;
          request.response.write(
            jsonEncode({
              'error': {'code': 'CLIENT_SCOPE_DENIED'},
            }),
          );
        } else if (request.uri.path == '/v1/storefront') {
          request.response.write(jsonEncode({'id': 'shop-1'}));
        } else {
          expect(request.uri.path, '/v1/shops/shop-1/orders');
          expect(request.uri.queryParameters, {'limit': '100', 'offset': '0'});
          request.response.write(
            jsonEncode({
              'orders': [
                order('pending', 'pending_payment'),
                order('paid', 'paid'),
              ],
            }),
          );
        }
        await request.response.close();
      });
      final transport = BoundedJsonTransport();
      try {
        final data = salesPackage();
        final config = data['automations'][1]['trigger']['config'];
        final origin = 'http://127.0.0.1:${server.port}';
        config['lookup']['request']['url'] = '$origin/v1/storefront';
        config['request']['url'] = '$origin/v1/shops/{shopId}/orders';
        final definition = parse(data).automations[1];
        final ctx = RuntimeContext(
          http: transport,
          telegram: FakeTelegram(),
          secret: (_) async => 'test-secret',
          fields: {'storefrontUrl': 'https://shop.example.test'},
          adminId: '123',
        );
        final batch = await HttpListPollTrigger(
          definition.trigger.config,
          ctx,
        ).next(null);
        expect(batch.events.map((e) => e['id']), ['paid']);
        expect(requests, 2);
        denied = true;
        await expectLater(
          HttpListPollTrigger(definition.trigger.config, ctx).next(null),
          throwsA(
            isA<RuntimeFailure>()
                .having((e) => e.permanent, 'permanent', true)
                .having((e) => e.code, 'code', 'http.forbidden'),
          ),
        );
      } finally {
        transport.close();
        await server.close(force: true);
      }
    },
  );
  test(
    'delivery receipts survive Hive reopening and are isolated and deleted by bot instance',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bottogram-order-receipts-',
      );
      Hive.init(directory.path);
      try {
        final original = HiveProgressStore();
        await original.write('A:digest:orders:delivered:hash', {
          'complete': true,
        });
        await original.write('B:digest:orders:delivered:hash', {
          'complete': true,
        });
        await Hive.close();
        final reopened = HiveProgressStore();
        expect(
          (await reopened.read('A:digest:orders:delivered:hash'))['complete'],
          isTrue,
        );
        await reopened.removeInstance('A');
        expect(await reopened.read('A:digest:orders:delivered:hash'), isEmpty);
        expect(
          (await reopened.read('B:digest:orders:delivered:hash'))['complete'],
          isTrue,
        );
      } finally {
        await Hive.close();
        await directory.delete(recursive: true);
      }
    },
  );
  test('secure-key read failures stop before making any API request', () async {
    final http = FakeHttp();
    final ctx = RuntimeContext(
      http: http,
      telegram: FakeTelegram(),
      secret: (_) async => throw StateError('Vault unavailable'),
      fields: {'storefrontUrl': 'https://shop.example.test'},
      adminId: '123',
    );
    await expectLater(
      HttpListPollTrigger(salesConfig(), ctx).next(null),
      throwsA(
        isA<RuntimeFailure>().having((e) => e.permanent, 'permanent', true),
      ),
    );
    expect(http.requests, isEmpty);
  });
  test(
    'new package composes paid-order polling and public products with shared inputs',
    () {
      final package = parse(salesPackage());
      expect(package.automations.map((a) => a.id), ['products', 'paid-orders']);
      expect(package.fields.map((f) => f.key), ['apiKey', 'storefrontUrl']);
      expect(package.settingValues({})['notifyNewSuccessfulPurchases'], isTrue);
      expect(
        AutomationRegistry.standard
            .requestsFor(package.automations[1].trigger)
            .length,
        2,
      );
      final local = parse(
        jsonDecode(
              File(
                'examples/plugins/inshopa.sales.local.bottogram-plugin.json',
              ).readAsStringSync(),
            )
            as Json,
      );
      expect(local.id, 'bottogram-plugin-inshopa-local');
      expect(
        AutomationRegistry.standard
            .requestsFor(local.automations[1].trigger)
            .every(
              (r) => (r['url'] as String).startsWith('http://127.0.0.1:8080/'),
            ),
        isTrue,
      );
    },
  );
  test(
    'schemas validate lookup secrets and constrain resource bindings to path segments',
    () {
      for (final mutate in <void Function(Json)>[
        (c) =>
            c['lookup']['request']['authentication']['secretField'] = 'missing',
        (c) => c['request']['url'] = 'https://{shopId}.example.test/orders',
        (c) => c['request']['url'] =
            'https://api.inshopa.ir/v1/orders?shop={shopId}',
        (c) => c['request']['url'] =
            'https://api.inshopa.ir/v1/shops/{unknown}/orders',
        (c) => c['request']['url'] =
            'https://api.inshopa.ir/v1/shops/prefix-{shopId}/orders',
        (c) => c['lookup']['bindings']['unused'] = 'id',
        (c) => c['pagination']['pageSize'] = 101,
        (c) => c['pagination']['pageDelaySeconds'] = 0,
        (c) => c['pagination']['maxPages'] = 0,
        (c) => c['filter']['equals'] = {'unsupported': 'object'},
      ]) {
        final data = salesPackage();
        mutate(data['automations'][1]['trigger']['config'] as Json);
        expect(() => parse(data), throwsA(isA<PluginException>()));
      }
    },
  );
  test(
    'lookup identifies the shop; raw page size controls pagination before paid filtering',
    () async {
      final http = FakeHttp()
        ..responses.addAll([
          {'id': 'shop-1'},
          {
            'orders': [
              order('unpaid', 'pending_payment'),
              order('paid', 'paid'),
            ],
          },
          {
            'orders': [order('older', 'paid')],
          },
        ]);
      final config = salesConfig();
      config['pagination']['pageSize'] = 2;
      final trigger = HttpListPollTrigger(
        config,
        context(http, FakeTelegram()),
      );
      final first = await trigger.next(null);
      expect(first.events.map((e) => e['id']), ['paid']);
      expect(first.nextCursor, '2');
      expect(first.checkpoint, isNull);
      expect(first.durableDeduplication, isTrue);
      expect(first.pageDelay, const Duration(seconds: 2));
      final last = await trigger.next(first.nextCursor);
      expect(last.nextCursor, isNull);
      expect(last.events.single['id'], 'older');
      expect(http.requests.map((r) => r.$1.path), [
        '/v1/storefront',
        '/v1/shops/shop-1/orders',
        '/v1/shops/shop-1/orders',
      ]);
      expect(http.requests.last.$1.queryParameters, {
        'limit': '2',
        'offset': '2',
      });
      expect(
        http.requests.every(
          (r) =>
              r.$2['Authorization'] == 'Bearer test-secret' &&
              r.$2['X-Storefront-Host'] == 'shop.example.test',
        ),
        isTrue,
      );
      expect(
        http.requests.every((r) => !r.$1.toString().contains('test-secret')),
        isTrue,
      );
    },
  );
  test(
    'lookup rejects malformed IDs without requesting a substituted resource',
    () async {
      for (final id in ['../admin', 'other/shop', 'https://evil.test', '']) {
        final http = FakeHttp()..responses.add({'id': id});
        final trigger = HttpListPollTrigger(
          salesConfig(),
          context(http, FakeTelegram()),
        );
        await expectLater(trigger.next(null), throwsA(isA<RuntimeFailure>()));
        expect(http.requests.length, 1);
      }
    },
  );
  test(
    'list shape, item IDs, missing status and page limit fail explicitly',
    () async {
      for (final response in <Json>[
        {'orders': {}},
        {
          'orders': [
            {'status': 'paid'},
          ],
        },
        {
          'orders': [
            {'id': '1'},
          ],
        },
      ]) {
        final http = FakeHttp()
          ..responses.addAll([
            {'id': 'shop-1'},
            response,
          ]);
        await expectLater(
          HttpListPollTrigger(
            salesConfig(),
            context(http, FakeTelegram()),
          ).next(null),
          throwsA(isA<RuntimeFailure>()),
        );
      }
      final http = FakeHttp();
      final config = salesConfig();
      config['pagination']['maxPages'] = 1;
      await expectLater(
        HttpListPollTrigger(config, context(http, FakeTelegram())).next('100'),
        throwsA(isA<RuntimeFailure>()),
      );
      expect(http.requests, isEmpty);
    },
  );
  test(
    'real list pipeline baselines history, notices delayed payment, and persists once per order across restart',
    () async {
      final http = FakeHttp();
      final telegram = FakeTelegram();
      final store = MemoryProgress();
      final raw = salesPackage();
      final config = raw['automations'][1]['trigger']['config'];
      config['pagination']['pageSize'] = 2;
      config['pagination']['pageDelaySeconds'] = 1;
      final definition = parse(raw).automations[1];
      final ctx = context(http, telegram);
      Future<void> scan(List<Json> responses) async {
        http.responses.addAll([
          {'id': 'shop-1'},
          ...responses,
        ]);
        final done = Completer<void>();
        final runner = AutomationRunner(
          definition: definition,
          context: ctx,
          store: store,
          key: 'instance:digest:paid-orders',
          onStatus: (error) {
            if (error != null && !done.isCompleted) {
              done.completeError(StateError(error));
            }
            if (error == null &&
                store.values['instance:digest:paid-orders']?['initialized'] ==
                    true &&
                store.values['instance:digest:paid-orders']?['pageCursor'] ==
                    null &&
                !done.isCompleted) {
              done.complete();
            }
          },
        );
        unawaited(runner.start());
        try {
          await done.future.timeout(const Duration(seconds: 6));
        } finally {
          await runner.stop();
        }
      }

      await scan([
        {
          'orders': [
            order('historic', 'paid'),
            order('late', 'pending_payment'),
          ],
        },
        {'orders': []},
      ]);
      expect(telegram.messages, isEmpty);
      await scan([
        {
          'orders': [order('new', 'paid'), order('historic', 'paid')],
        },
        {
          'orders': [order('late', 'paid')],
        },
      ]);
      expect(telegram.messages.length, 2);
      expect(telegram.messages.every((m) => m.$1 == '123'), isTrue);
      expect(telegram.messages.first.$2, contains('Order: new'));
      expect(telegram.messages.last.$2, contains('Order: late'));
      await scan([
        {
          'orders': [order('new', 'paid'), order('historic', 'paid')],
        },
        {
          'orders': [order('late', 'paid')],
        },
      ]);
      expect(telegram.messages.length, 2);
      expect(jsonEncode(store.values), isNot(contains('test-secret')));
    },
  );
  test(
    'history larger than the recent-ID cache never replays after restart',
    () async {
      final store = MemoryProgress();
      var sends = 0;
      final items = List<Json>.generate(2501, (i) => {'id': 'order-$i'});
      final registry = AutomationRegistry(
        triggers: {
          'list': ComponentRegistration(
            (_) {},
            (_, __) => QueueTrigger([
              TriggerBatch(items, durableDeduplication: true),
            ], baseline: true),
          ),
        },
        actions: {
          'send': ComponentRegistration(
            (_) {},
            (_, __) => FunctionAction((e) async {
              sends++;
              return e;
            }),
          ),
        },
      );
      final definition = AutomationDefinition(
        'orders',
        const ComponentDefinition('list', {}),
        [const ComponentDefinition('send', {}, id: 'send')],
        null,
      );
      Future<void> scan() async {
        final done = Completer<void>();
        final runner = AutomationRunner(
          definition: definition,
          context: context(FakeHttp(), FakeTelegram()),
          store: store,
          key: 'A:digest:orders',
          registry: registry,
          onStatus: (error) {
            if (error != null && !done.isCompleted) {
              done.completeError(StateError(error));
            }
            if (error == null && !done.isCompleted) done.complete();
          },
        );
        unawaited(runner.start());
        try {
          await done.future.timeout(const Duration(seconds: 6));
        } finally {
          await runner.stop();
        }
      }

      await scan();
      expect(sends, 0);
      expect(
        store.values.keys.where((k) => k.contains(':delivered:')).length,
        2501,
      );
      await scan();
      expect(sends, 0);
      await store.removeInstance('A');
      expect(store.values, isEmpty);
    },
  );
  test(
    'receipt storage failure resumes an acknowledged send without repeating it',
    () async {
      final store = ReceiptFailureStore();
      var sends = 0;
      final registry = AutomationRegistry(
        triggers: {
          'list': ComponentRegistration(
            (_) {},
            (_, __) => QueueTrigger([
              const TriggerBatch([
                {'id': 'order'},
              ], durableDeduplication: true),
            ]),
          ),
        },
        actions: {
          'send': ComponentRegistration(
            (_) {},
            (_, __) => FunctionAction((e) async {
              sends++;
              return e;
            }),
          ),
        },
      );
      final definition = AutomationDefinition(
        'orders',
        const ComponentDefinition('list', {}),
        [const ComponentDefinition('send', {}, id: 'send')],
        null,
      );
      AutomationRunner create(void Function(String?) status) =>
          AutomationRunner(
            definition: definition,
            context: context(FakeHttp(), FakeTelegram()),
            store: store,
            key: 'A:digest:orders',
            registry: registry,
            onStatus: status,
          );
      await create((_) {}).start();
      expect(sends, 1);
      expect(store.values['A:digest:orders']?['pending']['action'], 1);
      store.fail = false;
      final done = Completer<void>();
      final restarted = create((error) {
        if (error == null && !done.isCompleted) done.complete();
      });
      unawaited(restarted.start());
      await done.future.timeout(const Duration(seconds: 3));
      await restarted.stop();
      expect(sends, 1);
      expect(
        store.values.keys.where((k) => k.contains(':delivered:')).length,
        1,
      );
    },
  );
  test(
    'Stop during page pacing retains continuation and makes no further request',
    () async {
      final http = FakeHttp()
        ..responses.addAll([
          {'id': 'shop-1'},
          {
            'orders': [order('old', 'paid')],
          },
        ]);
      final config = salesConfig();
      config['pagination']['pageSize'] = 1;
      final registry = AutomationRegistry(
        triggers: {
          'list': ComponentRegistration(
            (_) {},
            (_, ctx) => HttpListPollTrigger(config, ctx),
          ),
        },
        actions: {
          'send': ComponentRegistration(
            (_) {},
            (_, __) => FunctionAction((e) async => e),
          ),
        },
      );
      final store = MemoryProgress();
      final runner = AutomationRunner(
        definition: AutomationDefinition(
          'orders',
          const ComponentDefinition('list', {}),
          [const ComponentDefinition('send', {}, id: 'send')],
          null,
        ),
        context: context(http, FakeTelegram()),
        store: store,
        key: 'A',
        registry: registry,
        onStatus: (_) {},
      );
      unawaited(runner.start());
      await until(() => store.values['A']?['pageCursor'] == '1');
      await runner.stop();
      expect(http.requests.length, 2);
      expect(store.values['A']?['pageCursor'], '1');
    },
  );
}
