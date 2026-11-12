import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bottogram/runtime/progress_store.dart';
import 'package:bottogram/server/config.dart';
import 'package:bottogram/server/worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bottogram-server-');
    file = File(p.join(directory.path, 'bot.json'));
    await File(
      'examples/headless/config/hello.bottogram-plugin.json',
    ).copy(p.join(directory.path, 'hello.json'));
    await File(p.join(directory.path, 'token')).writeAsString('99:fixture\n');
    await file.writeAsString(
      jsonEncode({'plugin': 'hello.json', 'tokenFile': 'token'}),
    );
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'configuration resolves file paths and rejects inline secrets',
    () async {
      final config = await ServerBotConfig.load(file);
      expect(config.token, '99:fixture');
      expect(config.manifest.storageKey, 'bottogram.hello@1.0.0');
      expect(config.setup.adminIds, isEmpty);
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final manifestFile = File(p.join(directory.path, 'hello.json'));
      final manifest =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      manifest['setupFields'] = [
        {
          'key': 'apiKey',
          'label': 'API key',
          'type': 'secret',
          'required': true,
        },
      ];
      await manifestFile.writeAsString(jsonEncode(manifest));
      json['fields'] = {'apiKey': 'inline-fixture-secret'};
      await file.writeAsString(jsonEncode(json));
      await expectLater(
        ServerBotConfig.load(file),
        throwsA(
          isA<ServerConfigException>().having(
            (error) => error.message,
            'safe message',
            'fields may contain only declared non-secret plugin fields.',
          ),
        ),
      );

      json.remove('fields');
      json['secretFiles'] = {'apiKey': 'api_key'};
      await File(
        p.join(directory.path, 'api_key'),
      ).writeAsString('secret-from-file\n');
      await file.writeAsString(jsonEncode(json));
      final withSecret = await ServerBotConfig.load(file);
      expect(await withSecret.secret('apiKey'), 'secret-from-file');
      expect(withSecret.setup.values, isEmpty);
      expect(withSecret.setup.instanceId, config.setup.instanceId);
    },
  );

  test(
    'server runs the example plugin against Telegram and cancels polling on stop',
    () async {
      Hive.init(p.join(directory.path, 'state'));
      final progress = HiveProgressStore();
      await progress.open();
      final config = await ServerBotConfig.load(file);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final reply = Completer<String>();
      final heldPoll = Completer<void>();
      final stop = Completer<void>();
      var polls = 0;
      final updateMessage = {
        'message_id': 1,
        'date': 1700000000,
        'chat': {'id': 42, 'type': 'private', 'first_name': 'Reader'},
        'from': {'id': 42, 'is_bot': false, 'first_name': 'Reader'},
        'text': '/start',
        'entities': [
          {'offset': 0, 'length': 6, 'type': 'bot_command'},
        ],
      };
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final Object result;
        switch (request.uri.pathSegments.last) {
          case 'getMe':
            result = {
              'id': 99,
              'is_bot': true,
              'first_name': 'Test',
              'username': 'fixture_bot',
            };
          case 'getUpdates':
            if (++polls > 1) {
              if (!heldPoll.isCompleted) heldPoll.complete();
              return;
            }
            result = [
              {'update_id': 1, 'message': updateMessage},
            ];
          case 'sendMessage':
            final payload = jsonDecode(body) as Map<String, dynamic>;
            if (!reply.isCompleted) reply.complete(payload['text'] as String);
            result = {...updateMessage, 'text': payload['text']};
          default:
            request.response.statusCode = 400;
            await request.response.close();
            return;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'ok': true, 'result': result}));
        await request.response.close();
      });
      final logs = <String>[];
      final worker = runServerBot(
        config,
        progress: progress,
        stopRequested: stop.future,
        log: logs.add,
        telegramBaseUrl: 'http://127.0.0.1:${server.port}',
      );
      try {
        final completed = expectLater(worker, completes);
        expect(
          await reply.future.timeout(const Duration(seconds: 5)),
          'Hello from Bottogram!',
        );
        await heldPoll.future.timeout(const Duration(seconds: 5));
        stop.complete();
        await completed.timeout(const Duration(seconds: 5));
        expect(logs.last, 'Bot stopped.');
      } finally {
        if (!stop.isCompleted) stop.complete();
        await server.close(force: true);
      }
    },
  );
}
