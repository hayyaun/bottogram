import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:bottogram/builder/console.dart';
import 'package:bottogram/builder/engine.dart';
import 'package:bottogram/runtime/http_transport.dart';
import 'package:bottogram/runtime/ports.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryBuilderVariables implements BuilderVariables {
  final values = <String, dynamic>{'score': 0};
  @override
  Future<BuilderJson> read(String? userId) async => {
    'user': Map<String, dynamic>.of(values),
    'bot': <String, dynamic>{},
  };
  @override
  Future<dynamic> change(
    String? userId,
    String scope,
    String name,
    dynamic value, {
    bool increment = false,
  }) async {
    return values[name] =
        increment ? (values[name] as num) + (value as num) : value;
  }
}

class RecordingTelegram implements BuilderTelegram {
  final calls = <(String, BuilderJson)>[];
  Completer<void>? blocked;
  @override
  Future<BuilderJson> execute(String kind, BuilderJson arguments) async {
    calls.add((kind, arguments));
    if (blocked != null) await blocked!.future;
    return {'messageId': 100 + calls.length, 'chatId': 42};
  }
}

void main() {
  late HttpServer server;
  late BuilderEngine engine;
  late RecordingTelegram telegram;
  late BuilderConsole console;
  late MemoryBuilderVariables variables;
  final requests = <Map<String, dynamic>>[];
  setUp(() async {
    requests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add({
        'uri': request.uri,
        'method': request.method,
        'body': await utf8.decoder.bind(request).join(),
        'auth': request.headers.value('authorization'),
      });
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/fail') {
        request.response.statusCode = 401;
        request.response.write('{"secret":"do-not-log"}');
      } else if (request.uri.path == '/invalid') {
        request.response.write('not json');
      } else if (request.uri.path == '/large') {
        request.response.write(jsonEncode({'x': 'a' * (1024 * 1024)}));
      } else if (request.uri.path == '/redirect') {
        request.response.statusCode = 302;
        request.response.headers.set('location', '/leaked');
      } else {
        request.response.write('{"price":25,"name":"A_[B]."}');
      }
      await request.response.close();
    });
    telegram = RecordingTelegram();
    console = BuilderConsole();
    variables = MemoryBuilderVariables();
    engine = BuilderEngine(
      botId: 'fixture',
      telegram: telegram,
      variables: variables,
      console: console,
      secret: (name) async => 'credential-value',
    );
  });
  tearDown(() async {
    await engine.close();
    await server.close(force: true);
    console.dispose();
  });
  String url(String path) => 'http://127.0.0.1:${server.port}$path';

  test(
    'API output binds into another typed API request, variable and Markdown reply',
    () async {
      await engine.run(
        '/price',
        {'userId': 1, 'chatId': 42},
        [
          BuilderStep('http', '', {
            'output': 'lookup',
            'url': url('/price'),
            'credential': 'key',
          }),
          BuilderStep('http', '', {
            'output': 'save',
            'method': 'POST',
            'url': url('/save'),
            'body': '{"price":"{{steps.lookup.body.price}}"}',
          }),
          const BuilderStep(
            'incrementVariable',
            '{{steps.lookup.body.price}}',
            {'output': 'score', 'variable': 'score', 'scope': 'user'},
          ),
          const BuilderStep(
            'reply',
            '*{{steps.lookup.body.name}}*: {{user.score}}',
            {'output': 'reply', 'format': 'MarkdownV2'},
          ),
          const BuilderStep('editText', 'Done', {
            'output': 'edit',
            'messageId': '{{steps.reply.messageId}}',
          }),
        ],
      );
      expect(requests.length, 2);
      expect(requests.first['auth'], 'Bearer credential-value');
      expect(jsonDecode(requests.last['body'] as String), {'price': 25});
      expect(variables.values['score'], 25);
      expect(telegram.calls.first.$2['text'], r'*A\_\[B\]\.*: 25');
      expect(telegram.calls.last.$2['messageId'], '101');
      expect(console.entries('fixture').first.status, 'completed');
      expect(
        console.entries('fixture').map((e) => e.message).join(),
        isNot(contains('credential-value')),
      );
    },
  );
  test(
    'missing references stop execution with the step and missing path',
    () async {
      await engine.run('hi', {}, [
        const BuilderStep('reply', '{{steps.missing.body.price}}', {
          'output': 'answer',
        }),
        const BuilderStep('reply', 'must not send', {}),
      ]);
      expect(telegram.calls, isEmpty);
      expect(
        console
            .entries('fixture')
            .any(
              (e) =>
                  e.step == 'answer' &&
                  e.message.contains('steps.missing.body.price'),
            ),
        true,
      );
    },
  );
  test(
    'API failure stops by default; explicit continue makes a structured error available',
    () async {
      await engine.run('hi', {}, [
        BuilderStep('http', '', {
          'output': 'api',
          'url': url('/fail'),
          'onError': 'continue',
        }),
        const BuilderStep('reply', '{{steps.api.ok}}', {}),
      ]);
      expect(telegram.calls.single.$2['text'], 'false');
      final messages = console.entries('fixture').map((e) => e.message).join();
      expect(messages, contains('HTTP 401'));
      expect(messages, isNot(contains('do-not-log')));
    },
  );
  test('variables and writes serialize across concurrent events', () async {
    await Future.wait(
      List.generate(
        12,
        (_) => engine.run(
          'score',
          {'userId': 1},
          [
            const BuilderStep('incrementVariable', '1', {'variable': 'score'}),
          ],
        ),
      ),
    );
    expect(variables.values['score'], 12);
  });
  test('invalid output names fail before any side effects', () async {
    await engine.run('hi', {}, [
      const BuilderStep('reply', 'one', {'output': 'duplicate'}),
      const BuilderStep('reply', 'two', {'output': 'duplicate'}),
    ]);
    expect(telegram.calls, isEmpty);
  });
  test(
    'bound URL values cannot change the host or inject another query parameter',
    () async {
      await engine.run(
        'hi',
        {'text': 'x&admin=true'},
        [
          BuilderStep('http', '', {'url': url('/query?q={{event.text}}')}),
        ],
      );
      final uri = requests.single['uri'] as Uri;
      expect(uri.queryParameters, {'q': 'x&admin=true'});
    },
  );
  test('stop cancels a wait and prevents all subsequent actions', () async {
    final run = engine.run('hi', {}, [
      const BuilderStep('wait', '60', {}),
      const BuilderStep('reply', 'must not send', {}),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await engine.close().timeout(const Duration(seconds: 1));
    await run;
    expect(telegram.calls, isEmpty);
  });
  test(
    'transport bounds responses, rejects invalid JSON and does not follow redirects',
    () async {
      final transport = BoundedJsonTransport();
      try {
        for (final path in ['/large', '/invalid', '/redirect']) {
          await expectLater(
            transport.request('GET', Uri.parse(url(path)), {}),
            throwsA(isA<RuntimeFailure>()),
          );
        }
        expect(requests.any((r) => (r['uri'] as Uri).path == '/leaked'), false);
      } finally {
        transport.close();
      }
    },
  );
  test('console stays bounded per bot and globally', () {
    for (var i = 0; i < 240; i++) {
      console.add(
        'fixture',
        ExecutionEntry(
          time: DateTime.now(),
          run: i,
          event: 'hi',
          step: 'a',
          status: 'success',
          message: 'Done',
        ),
      );
    }
    expect(console.entries('fixture').length, 200);
    expect(console.entries('fixture').last.run, 40);
  });
}
