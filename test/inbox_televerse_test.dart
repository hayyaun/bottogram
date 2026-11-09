import 'dart:convert';
import 'dart:io';

import 'package:bottogram/inbox/repository.dart';
import 'package:bottogram/inbox/transformer.dart';
import 'package:bottogram/units/virt_act.dart';
import 'package:bottogram/units/virt_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:televerse/televerse.dart';

import 'inbox_repository_test.dart' show message, update;

void main() {
  test(
    'Televerse captures unmatched updates and preserves configured automatic actions',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bottogram-televerse-test-',
      );
      final repository = await InboxRepository.open(
        root.path,
        'integrationbot',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final replies = <String>[];
      final updates = [
        update(1, 1, text: 'Unconfigured message'),
        update(1, 2, text: 'hi'),
      ];
      server.listen((request) async {
        final method = request.uri.pathSegments.last;
        dynamic result;
        if (method == 'getMe') {
          result = {
            'id': 99,
            'is_bot': true,
            'first_name': 'Test bot',
            'username': 'test_bot',
          };
        } else if (method == 'getUpdates') {
          result = updates;
        } else if (method == 'sendMessage') {
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          replies.add(body['text'] as String);
          result = message(1, 3, text: body['text'] as String);
        } else {
          request.response.statusCode = 404;
          await request.response.close();
          return;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'ok': true, 'result': result}));
        await request.response.close();
      });
      final bot = Bot.local(
        '99:test-token',
        baseURL: 'http://127.0.0.1:${server.port}',
      );
      bot.api.use(InboxTransformer(() async => repository));
      final event = VirtEvent(type: VirtEventType.text, query: 'hi')
        ..acts.add(VirtAct(type: VirtActType.reply, text: 'Configured reply'));
      event.add(bot);
      try {
        await bot.init();
        final received = await bot.api.getUpdates();
        for (final update in received) {
          await bot.handleUpdate(update);
        }
        expect(replies, ['Configured reply']);
        final cached = await repository.messages(1);
        expect(cached.map((m) => m.text), [
          'Unconfigured message',
          'hi',
          'Configured reply',
        ]);
        expect(cached.last.outgoing, true);
      } finally {
        bot.api.closeClient();
        await server.close(force: true);
        await repository.close();
        await root.delete(recursive: true);
      }
    },
  );
}
