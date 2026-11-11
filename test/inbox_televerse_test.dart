import 'dart:convert';
import 'dart:io';

import 'package:bottogram/builder/telegram.dart';
import 'package:bottogram/inbox/repository.dart';
import 'package:bottogram/inbox/transformer.dart';
import 'package:bottogram/units/virt_act.dart';
import 'package:bottogram/units/virt_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:televerse/televerse.dart';
import 'support/telegram_updates.dart';

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
      final richCalls = <(String, Map)>[];
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
        } else if ({
          'sendRichMessageDraft',
          'sendRichMessage',
          'editMessageText',
        }.contains(method)) {
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          richCalls.add((method, body));
          result = method == 'sendRichMessageDraft'
              ? true
              : (message(1, 4)
                  ..remove('text')
                  ..['rich_message'] = {
                    'blocks': [
                      {'type': 'heading', 'size': 2, 'text': 'Market snapshot'},
                      {'type': 'paragraph', 'text': 'Current prices'},
                    ],
                  });
        } else {
          request.response.statusCode = 404;
          await request.response.close();
          return;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'ok': true, 'result': result}));
        await request.response.close();
      });
      final bot = Bot.local('99:test-token', 'http://127.0.0.1:${server.port}');
      bot.api.use(InboxTransformer(() async => repository));
      final event = VirtEvent(type: VirtEventType.text, query: 'hi')
        ..acts.add(VirtAct(type: VirtActType.reply, text: 'Configured reply'));
      event.add(bot);
      try {
        await bot.initialize();
        final received = await bot.api.getUpdates();
        for (final update in received) {
          await bot.dispatch(update);
        }
        expect(replies, ['Configured reply']);
        final cached = await repository.messages(1);
        expect(cached.map((m) => m.text), [
          'Unconfigured message',
          'hi',
          'Configured reply',
        ]);
        expect(cached.last.outgoing, true);

        final telegram = BuilderTelegramPort(bot.api);
        final target = {'chatId': '1', 'userId': 1};
        for (final status in ['Looking up prices…', 'Preparing the table…']) {
          await telegram.execute('reply', {
            ...target,
            'draftId': '12',
            'richBlocks': [
              {'type': 'thinking', 'text': status},
            ],
          });
        }
        expect((await repository.messages(1)).length, 3);
        final blocks = [
          {'type': 'heading', 'text': 'Market snapshot'},
          {
            'type': 'list',
            'items': ['Literal <b>tag</b> & *asterisks*'],
          },
          {
            'type': 'table',
            'rows': [
              ['Asset', 'USD'],
              ['Bitcoin', 100],
            ],
          },
          {
            'type': 'details',
            'summary': 'Source',
            'blocks': [
              {'type': 'paragraph', 'text': 'CoinGecko'},
            ],
          },
          {
            'type': 'collage',
            'urls': [
              'https://example.com/one.png',
              'https://example.com/two.png',
            ],
          },
          {
            'type': 'buttons',
            'buttons': [
              {'text': 'Refresh', 'callback_data': 'prices:refresh'},
            ],
          },
        ];
        final sent = await telegram.execute('reply', {
          ...target,
          'richBlocks': blocks,
        });
        expect(sent['messageId'], 4);
        await telegram.execute('editText', {
          ...target,
          'messageId': sent['messageId'],
          'richBlocks': blocks,
        });
        expect(richCalls.map((c) => c.$1), [
          'sendRichMessageDraft',
          'sendRichMessageDraft',
          'sendRichMessage',
          'editMessageText',
        ]);
        expect(richCalls.take(2).map((c) => c.$2['draft_id']), [12, 12]);
        final wire = richCalls[2].$2['rich_message']['blocks'] as List;
        expect(wire.map((b) => b['type']), [
          'heading',
          'list',
          'table',
          'details',
          'collage',
          'buttons',
        ]);
        expect(
          wire[1]['items'][0]['blocks'][0]['text'],
          'Literal <b>tag</b> & *asterisks*',
        );
        expect(wire[2]['cells'][0][0]['is_header'], true);
        expect(
          wire[4]['blocks'][0]['photo']['media'],
          'https://example.com/one.png',
        );
        expect(wire[5]['buttons'][0]['callback_data'], 'prices:refresh');
        expect(richCalls.last.$2['text'], isNull);
        expect(
          (await repository.messages(1)).last.text,
          'Market snapshot\nCurrent prices',
        );
      } finally {
        bot.api.closeClient();
        await server.close(force: true);
        await repository.close();
        await root.delete(recursive: true);
      }
    },
  );
}
