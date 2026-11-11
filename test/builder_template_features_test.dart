import 'dart:convert';
import 'dart:io';
import 'package:bottogram/builder/engine.dart';
import 'package:bottogram/builder/event_match.dart';
import 'package:bottogram/builder/list_renderer.dart';
import 'package:bottogram/builder/telegram.dart';
import 'package:bottogram/builder/values.dart';
import 'package:bottogram/units/virt_act.dart';
import 'package:bottogram/units/virt_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:televerse/televerse.dart';
import 'support/telegram_updates.dart';
import 'package:televerse/telegram.dart';
import 'inbox_repository_test.dart' show message, update;

void main() {
  test('matching is literal and broad text never consumes commands', () {
    expect(BuilderEventMatch.remainder('x.[42', 'x.[', 'prefix'), '42');
    expect(BuilderEventMatch.remainder('other', 'x.[', 'prefix'), isNull);
    expect(BuilderEventMatch.remainder('Hello', 'Hello', 'exact'), '');
    expect(BuilderEventMatch.remainder('Hello!', 'Hello', 'exact'), isNull);
    expect(BuilderEventMatch.remainder('/start', '', 'any'), isNull);
    expect(
      BuilderEventMatch.remainder('A normal answer', '', 'any'),
      'A normal answer',
    );
    expect(BuilderEventMatch.remainder('anything', '', 'prefix'), isNull);
  });
  test(
    'rendered lists retain typed button maps and escape no data into configuration',
    () {
      final result = BuilderListRenderer.render(
        const BuilderStep('renderList', '{{index}}. {{item.title}}', {
          'items': '{{steps.query.rows}}',
          'buttons': '[{"text":"Open","callback_data":"item:{{item.id}}"}]',
          'footerButtons': '[[{"text":"Back","callback_data":"home"}]]',
        }),
        {
          'steps': {
            'query': {
              'rows': [
                {'id': 7, 'title': '{{user.secret}}'},
              ],
            },
          },
        },
      );
      expect(result['text'], '1. {{user.secret}}');
      expect(
        result['keyboard']['inline_keyboard'][0][0]['callback_data'],
        'item:7',
      );
      expect(result['count'], 1);
      expect(
        BuilderListRenderer.render(
          const BuilderStep('renderList', '{{item.title}}', {
            'items': '{{items}}',
            'emptyText': 'Nothing here.',
          }),
          {'items': []},
        )['text'],
        'Nothing here.',
      );
    },
  );
  test('grouped controls omit hidden buttons before resolving their bindings', () {
    final result = BuilderListRenderer.render(
      const BuilderStep('renderList', '{{item.title}}', {
        'items': '{{items}}',
        'richLayout': {'groupItemButtons': true},
        'buttons':
            '[{"text":"Open","callback_data":"open:{{item.id}}","style":"primary"}]',
        'footerButtons':
            '[[{"text":"Next","callback_data":"next:{{next}}","when":{"left":"{{hasNext}}","right":true}}],[{"text":"Home","callback_data":"home"}]]',
      }),
      {
        'items': [
          {'id': 7, 'title': 'Literal {{item.title}}'},
        ],
        'hasNext': false,
      },
    );
    final blocks = result['rich'] as List;
    expect(blocks[0]['text'], 'Literal {{item.title}}');
    expect(blocks[1]['buttons'], [
      {'text': 'Open', 'callback_data': 'open:7', 'style': 'primary'},
    ]);
    expect(result['keyboard']['inline_keyboard'], [
      [
        {'text': 'Home', 'callback_data': 'home'},
      ],
    ]);
  });
  test(
    'list budgets reject excessive results, missing fields and oversized UTF-8 callbacks',
    () {
      BuilderStep step(String buttons) => BuilderStep(
        'renderList',
        '{{item.title}}',
        {'items': '{{items}}', 'buttons': buttons},
      );
      expect(
        () => BuilderListRenderer.render(step('[]'), {
          'items': List.filled(51, {'title': 'x'}),
        }),
        throwsA(isA<BuilderFailure>()),
      );
      expect(
        () => BuilderListRenderer.render(step('[]'), {
          'items': [{}],
        }),
        throwsA(isA<BuilderFailure>()),
      );
      expect(
        () => BuilderListRenderer.render(
          step(
            jsonEncode([
              {'text': 'Open', 'callback_data': 'آ' * 33},
            ]),
          ),
          {
            'items': [
              {'title': 'x'},
            ],
          },
        ),
        throwsA(isA<BuilderFailure>()),
      );
      expect(
        () => BuilderListRenderer.render(
          step('[{"text":"Open","url":"file:///local.sqlite"}]'),
          {
            'items': [
              {'title': 'x'},
            ],
          },
        ),
        throwsA(isA<BuilderFailure>()),
      );
      expect(
        () => BuilderListRenderer.render(step('[]'), {
          'items': [
            {'title': 'x' * 4097},
          ],
        }),
        throwsA(isA<BuilderFailure>()),
      );
    },
  );
  test(
    'literal event modes dispatch through public Televerse APIs and generated keyboards send',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <Map<String, dynamic>>[];
      server.listen((request) async {
        final name = request.uri.pathSegments.last;
        final raw = await utf8.decoder.bind(request).join();
        if (name == 'sendMessage') {
          requests.add(jsonDecode(raw) as Map<String, dynamic>);
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'ok': true,
            'result': name == 'getMe'
                ? {
                    'id': 99,
                    'is_bot': true,
                    'first_name': 'Fixture',
                    'username': 'fixture_bot',
                  }
                : name == 'sendMessage'
                ? message(1, 9)
                : true,
          }),
        );
        await request.response.close();
      });
      final bot = Bot.local('99:fixture', 'http://127.0.0.1:${server.port}');
      final received = <String>[];
      final errors = <Object>[];
      bot.onError((error) => errors.add(error));
      final exact = VirtEvent(type: VirtEventType.text, query: 'Hello')
        ..config = {'match': 'exact'};
      final broad = VirtEvent(type: VirtEventType.text, query: 'Input')
        ..config = {'match': 'any'};
      final prefix = VirtEvent(
        type: VirtEventType.callbackQuery,
        query: 'item.[.',
      );
      prefix.config = {'match': 'prefix'};
      prefix.acts = [VirtAct(type: VirtActType.callbackAnswer, text: '')];
      exact.add(bot, execute: (ctx) async => received.add('exact'));
      broad.add(
        bot,
        execute: (ctx) async => received.add('text:${ctx.message!.text!}'),
      );
      prefix.add(
        bot,
        execute: (ctx) async => received.add(
          'item:${BuilderEventMatch.remainder(ctx.callbackQuery!.data!, 'item.[.', 'prefix')!}',
        ),
      );
      try {
        await bot.initialize();
        await bot.dispatch(Update.fromJson(update(1, 1, text: 'Hello')));
        await bot.dispatch(Update.fromJson(update(1, 2, text: '/start')));
        await bot.dispatch(Update.fromJson(update(1, 3, text: 'An answer')));
        await bot.dispatch(
          Update.fromJson({
            'update_id': 4,
            'callback_query': {
              'id': 'click',
              'from': {'id': 1, 'is_bot': false, 'first_name': 'User'},
              'chat_instance': 'fixture',
              'data': 'item.[.42',
              'message': message(1, 3),
            },
          }),
        );
        expect(received, ['exact', 'text:An answer', 'item:42']);
        expect(errors, isEmpty);
        await BuilderTelegramPort(bot.api).execute('reply', {
          'chatId': '1',
          'text': 'A generated list',
          'keyboard': {
            'inline_keyboard': [
              [
                {'text': 'Open', 'callback_data': 'item:42'},
              ],
            ],
          },
        });
        expect(
          requests
              .single['reply_markup']['inline_keyboard'][0][0]['callback_data'],
          'item:42',
        );
      } finally {
        bot.api.closeClient();
        await server.close(force: true);
      }
    },
  );
}
