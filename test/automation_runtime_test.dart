import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/runtime/automation_runner.dart';
import 'package:bottogram/runtime/components.dart';
import 'package:bottogram/runtime/http_transport.dart';
import 'package:bottogram/runtime/ports.dart';
import 'package:bottogram/runtime/registry.dart';

class MemoryProgress implements ProgressStore {
  final values = <String, Json>{};
  @override
  Future<Json> read(String key) async =>
      jsonDecode(jsonEncode(values[key] ?? {})) as Json;
  @override
  Future<void> write(String key, Json value) async {
    values[key] = jsonDecode(jsonEncode(value)) as Json;
  }

  @override
  Future<void> removeInstance(String id) async =>
      values.removeWhere((k, v) => k.startsWith('$id:'));
}

class FakeHttp implements JsonTransport {
  final requests = <(Uri, Map<String, String>)>[];
  final responses = <Json>[];
  @override
  Future<Json> get(Uri url, Map<String, String> headers) async {
    requests.add((url, headers));
    return responses.removeAt(0);
  }

  @override
  void close() {}
}

class FakeTelegram implements TelegramPort {
  final commands = <String, void Function(Json)>{};
  final messages = <(String, String)>[];
  @override
  void command(String command, void Function(Json) receive) {
    commands[command] = receive;
  }

  @override
  Future<void> send(String chat, String text, {Json? replyMarkup}) async {
    messages.add((chat, text));
  }
}

class QueueTrigger implements AutomationTrigger {
  QueueTrigger(this.batches, {this.baseline = false});
  final List<TriggerBatch> batches;
  final cursors = <String?>[];
  final _cancel = Completer<TriggerBatch>();
  @override
  final bool baseline;
  @override
  Duration get interval => Duration.zero;
  @override
  Future<TriggerBatch> next(String? cursor) {
    cursors.add(cursor);
    return batches.isEmpty ? _cancel.future : Future.value(batches.removeAt(0));
  }

  @override
  void close() {
    if (!_cancel.isCompleted) _cancel.complete(const TriggerBatch([]));
  }
}

class FunctionAction implements AutomationAction {
  FunctionAction(this.run);
  final Future<Json> Function(Json) run;
  @override
  Future<Json> execute(Json event) => run(event);
}

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 2000; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Condition did not become true.');
}

Json productDefinition() => {
  'manifestVersion': 2,
  'hostApiMajor': 2,
  'id': 'test.catalog',
  'name': 'Catalog',
  'version': '1.0.0',
  'executionStatus': 'live',
  'requiresBotFields': ['adminTelegramUserId'],
  'setupFields': [
    {'key': 'apiKey', 'label': 'API key', 'type': 'secret', 'required': true},
    {
      'key': 'storefrontUrl',
      'label': 'Shop URL',
      'type': 'text',
      'required': true,
    },
  ],
  'automations': [
    {
      'id': 'products',
      'trigger': {
        'type': 'telegram.command.v1',
        'config': {'command': 'products', 'arguments': 'page'},
      },
      'actions': [
        {
          'id': 'catalog',
          'type': 'http.get-json.v1',
          'config': {
            'request': {
              'method': 'GET',
              'url': 'https://api.example.test/v1/storefront/products',
              'storefrontUrlField': 'storefrontUrl',
              'authentication': {'type': 'bearer', 'secretField': 'apiKey'},
            },
            'resultKey': 'catalog',
            'pagination': {'pageSize': 10},
          },
        },
        {
          'id': 'reply',
          'type': 'telegram.reply.v1',
          'config': {
            'text': 'Products · page {{event.page}}',
            'list': {
              'itemsPath': 'results.catalog.products',
              'itemText': '{{item.title}}',
              'emptyText': 'No products.',
            },
          },
        },
      ],
    },
  ],
};
PluginManifest parse(Json value) =>
    PluginManifest.parse(Uint8List.fromList(utf8.encode(jsonEncode(value))));

void main() {
  test(
    'v2 validates schemas, credentials and unknown types while preserving v1',
    () {
      expect(parse(productDefinition()).executable, isTrue);
      for (final mutate in <void Function(Json)>[
        (d) => d['automations'][0]['trigger']['type'] = 'download.code',
        (d) => d['automations'][0]['actions'][0]['config']['request']['url'] =
            'http://unsafe.test',
        (d) =>
            d['automations'][0]['actions'][0]['config']['request']['authentication']['secretField'] =
                'missing',
        (d) => d['automations'][0]['actions'][1]['config']['chatId'] =
            'someone-else',
        (d) => d['automations'][0]['actions'][1]['config']['text'] =
            '{{secrets.apiKey}}',
        (d) => d['automations'][0]['actions'].add(
          d['automations'][0]['actions'][1],
        ),
      ]) {
        final d = productDefinition();
        mutate(d);
        expect(() => parse(d), throwsA(isA<PluginException>()));
      }
    },
  );
  test(
    'products command replies to a non-admin and uses key, host and pagination',
    () async {
      final http = FakeHttp()
        ..responses.add({
          'products': [
            {'title': 'Product A'},
            {'title': 'Product B'},
          ],
        });
      final telegram = FakeTelegram();
      final progress = MemoryProgress();
      final context = RuntimeContext(
        http: http,
        telegram: telegram,
        secret: (_) async => 'secret-key',
        fields: {'storefrontUrl': 'https://shop.example.test'},
        adminId: '999',
      );
      final runner = AutomationRunner(
        definition: parse(productDefinition()).automations.single,
        context: context,
        store: progress,
        key: 'bot:catalog:products',
        onStatus: (_) {},
      );
      unawaited(runner.start());
      await until(() => telegram.commands.isNotEmpty);
      telegram.commands['products']!({
        'id': '42',
        'chatId': '123',
        'arguments': ['2'],
      });
      await until(() => telegram.messages.isNotEmpty);
      expect(telegram.messages.single, (
        '123',
        'Products · page 2\nProduct A\nProduct B',
      ));
      expect(http.requests.single.$1.queryParameters, {
        'limit': '10',
        'offset': '10',
      });
      expect(
        http.requests.single.$2,
        containsPair('Authorization', 'Bearer secret-key'),
      );
      expect(
        http.requests.single.$2,
        containsPair('Origin', 'https://shop.example.test'),
      );
      expect(
        http.requests.single.$2,
        containsPair('X-Storefront-Host', 'shop.example.test'),
      );
      await runner.stop();
      expect(jsonEncode(progress.values), isNot(contains('secret-key')));
    },
  );
  test(
    'first sync baselines history and later pages commit only after all actions',
    () async {
      final store = MemoryProgress();
      final telegram = FakeTelegram();
      final http = FakeHttp();
      final source = QueueTrigger([
        const TriggerBatch([
          {'id': 'old'},
        ], checkpoint: 'baseline'),
      ], baseline: true);
      final definition = AutomationDefinition(
        'sales',
        const ComponentDefinition('test.trigger', {}),
        [const ComponentDefinition('test.send', {}, id: 'send')],
        null,
      );
      final registry = AutomationRegistry(
        triggers: {
          'test.trigger': ComponentRegistration((_) {}, (_, __) => source),
        },
        actions: {
          'test.send': ComponentRegistration(
            (_) {},
            (_, __) => FunctionAction((e) async {
              await telegram.send('999', e['id']);
              return e;
            }),
          ),
        },
      );
      final context = RuntimeContext(
        http: http,
        telegram: telegram,
        secret: (_) async => null,
        fields: {},
        adminId: '999',
      );
      final runner = AutomationRunner(
        definition: definition,
        context: context,
        store: store,
        key: 'A',
        onStatus: (_) {},
        registry: registry,
      );
      unawaited(runner.start());
      await until(() => store.values['A']?['checkpoint'] == 'baseline');
      expect(telegram.messages, isEmpty);
      await runner.stop();
      final nextSource = QueueTrigger([
        const TriggerBatch(
          [
            {'id': 'new1'},
          ],
          checkpoint: 'horizon',
          nextCursor: 'page2',
        ),
        const TriggerBatch([
          {'id': 'new1'},
          {'id': 'new2'},
        ], checkpoint: 'horizon'),
      ], baseline: true);
      registry.triggers['test.trigger'] = ComponentRegistration(
        (_) {},
        (_, __) => nextSource,
      );
      final next = AutomationRunner(
        definition: definition,
        context: context,
        store: store,
        key: 'A',
        onStatus: (_) {},
        registry: registry,
      );
      unawaited(next.start());
      await until(() => store.values['A']?['checkpoint'] == 'horizon');
      expect(telegram.messages, [('999', 'new1'), ('999', 'new2')]);
      expect(nextSource.cursors.take(2), ['baseline', 'page2']);
      await next.stop();
    },
  );
  test(
    'restart resumes the failed action without repeating a confirmed action',
    () async {
      final store = MemoryProgress();
      var first = 0;
      var second = 0;
      var failSecond = true;
      final context = RuntimeContext(
        http: FakeHttp(),
        telegram: FakeTelegram(),
        secret: (_) async => null,
        fields: {},
        adminId: '9',
      );
      final definition =
          AutomationDefinition('a', const ComponentDefinition('t', {}), [
            const ComponentDefinition('first', {}, id: 'first'),
            const ComponentDefinition('second', {}, id: 'second'),
          ], null);
      final registry = AutomationRegistry(
        triggers: {
          't': ComponentRegistration(
            (_) {},
            (_, __) => QueueTrigger([
              const TriggerBatch([
                {'id': 'order'},
              ], checkpoint: 'C'),
            ]),
          ),
        },
        actions: {
          'first': ComponentRegistration(
            (_) {},
            (_, __) => FunctionAction((e) async {
              first++;
              return {...e, 'result': 'saved'};
            }),
          ),
          'second': ComponentRegistration(
            (_) {},
            (_, __) => FunctionAction((e) async {
              second++;
              expect(e['result'], 'saved');
              if (failSecond) {
                throw const RuntimeFailure('Denied', permanent: true);
              }
              return e;
            }),
          ),
        },
      );
      AutomationRunner create() => AutomationRunner(
        definition: definition,
        context: context,
        store: store,
        key: 'bot:digest:a',
        onStatus: (_) {},
        registry: registry,
      );
      final runner = create();
      await runner.start();
      expect(first, 1);
      expect(second, 1);
      expect(store.values['bot:digest:a']?['checkpoint'], isNull);
      failSecond = false;
      final restarted = create();
      unawaited(restarted.start());
      await until(() => store.values['bot:digest:a']?['checkpoint'] == 'C');
      expect(first, 1);
      expect(second, 2);
      await restarted.stop();
    },
  );
  test(
    'Stop waits for an in-flight action acknowledgement and prevents following actions',
    () async {
      final store = MemoryProgress();
      final entered = Completer<void>();
      final sent = Completer<void>();
      var second = 0;
      final context = RuntimeContext(
        http: FakeHttp(),
        telegram: FakeTelegram(),
        secret: (_) async => null,
        fields: {},
        adminId: '9',
      );
      final registry = AutomationRegistry(
        triggers: {
          't': ComponentRegistration(
            (_) {},
            (_, __) => QueueTrigger([
              const TriggerBatch([
                {'id': 'e'},
              ], checkpoint: 'C'),
            ]),
          ),
        },
        actions: {
          'first': ComponentRegistration(
            (_) {},
            (_, __) => FunctionAction((e) async {
              entered.complete();
              await sent.future;
              return e;
            }),
          ),
          'second': ComponentRegistration(
            (_) {},
            (_, __) => FunctionAction((e) async {
              second++;
              return e;
            }),
          ),
        },
      );
      final runner = AutomationRunner(
        definition:
            AutomationDefinition('a', const ComponentDefinition('t', {}), [
              const ComponentDefinition('first', {}, id: 'first'),
              const ComponentDefinition('second', {}, id: 'second'),
            ], null),
        context: context,
        store: store,
        key: 'A',
        onStatus: (_) {},
        registry: registry,
      );
      unawaited(runner.start());
      await entered.future;
      var stopped = false;
      final stopping = runner.stop().then((_) => stopped = true);
      await Future<void>.delayed(Duration.zero);
      expect(stopped, isFalse);
      sent.complete();
      await stopping;
      expect(second, 0);
      expect(store.values['A']?['pending']['action'], 1);
      expect(store.values['A']?['checkpoint'], isNull);
    },
  );
  test('polling rejects malformed pagination and unstable IDs', () async {
    final http = FakeHttp()
      ..responses.add({
        'orders': [
          {'id': 'e'},
        ],
        'checkpoint': 'C',
        'next_cursor': null,
        'has_more': true,
      });
    final context = RuntimeContext(
      http: http,
      telegram: FakeTelegram(),
      secret: (_) async => null,
      fields: {},
      adminId: '9',
    );
    final trigger = HttpPollTrigger({
      'intervalSeconds': 60,
      'initialSync': 'baseline',
      'request': {'method': 'GET', 'url': 'https://api.example.test/sales'},
      'response': {
        'itemsPath': 'orders',
        'itemIdPath': 'id',
        'checkpointPath': 'checkpoint',
      },
      'pagination': {
        'cursorQueryParameter': 'cursor',
        'nextPagePath': 'next_cursor',
        'hasMorePath': 'has_more',
      },
    }, context);
    await expectLater(trigger.next(null), throwsA(isA<RuntimeFailure>()));
  });
  test(
    'transport refuses redirects rather than forwarding its API key',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      server.listen((r) {
        requests++;
        r.response.statusCode = 302;
        r.response.headers.set('location', '/elsewhere');
        unawaited(r.response.close());
      });
      final transport = BoundedJsonTransport();
      await expectLater(
        transport.get(Uri.parse('http://127.0.0.1:${server.port}/catalog'), {
          'Authorization': 'Bearer test',
        }),
        throwsA(isA<RuntimeFailure>()),
      );
      expect(requests, 1);
      transport.close();
      await server.close(force: true);
    },
  );
}
