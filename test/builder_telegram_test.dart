import 'dart:convert';
import 'dart:io';
import 'package:bottogram/builder/database.dart';
import 'package:bottogram/builder/session.dart';
import 'package:bottogram/builder/store.dart';
import 'package:bottogram/builder/telegram.dart';
import 'package:bottogram/builder/values.dart';
import 'package:bottogram/units/virt_act.dart';
import 'package:bottogram/units/virt_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:televerse/televerse.dart';
import 'package:televerse/telegram.dart';
import 'inbox_repository_test.dart' show message, update;
import 'plugins_test.dart' show MemoryVault;

void main() {
  test(
    'media inputs reject filesystem paths before contacting the API',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var calls = 0;
      server.listen((request) async {
        calls++;
        request.response.statusCode = 500;
        await request.response.close();
      });
      final bot = Bot.local(
        '99:fixture',
        baseURL: 'http://127.0.0.1:${server.port}',
      );
      final port = BuilderTelegramPort(bot.api);
      try {
        for (final kind in [
          'photo',
          'video',
          'audio',
          'document',
          'animation',
          'voice',
          'sticker',
        ]) {
          for (final source in [
            '/bot_data/neighbor.sqlite',
            r'C:\app\bot_data\neighbor.sqlite',
            r'\\server\share\state.hive',
            'file:///bot_data/neighbor.sqlite',
            'ftp://example.invalid/media.png',
            'https://',
            'https://[',
            'https://name:password@example.invalid/media.png',
            'https://example.invalid/media.png#fragment',
          ]) {
            await expectLater(
              port.execute(kind, {'chatId': '1', 'media': source}),
              throwsA(isA<BuilderFailure>()),
              reason: '$kind: $source',
            );
          }
        }
        expect(calls, 0);
      } finally {
        bot.api.closeClient();
        await server.close(force: true);
      }
    },
  );

  test(
    'media keeps Telegram file IDs and HTTP(S) URLs as API values',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final calls = <(String, Map)>[];
      server.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        calls.add((request.uri.pathSegments.last, body));
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'ok': true,
            'result': message(1, calls.length, text: 'Sent'),
          }),
        );
        await request.response.close();
      });
      final bot = Bot.local(
        '99:fixture',
        baseURL: 'http://127.0.0.1:${server.port}',
      );
      final port = BuilderTelegramPort(bot.api);
      try {
        final sources = [
          'telegram_file_fixture',
          'http://example.invalid/media.png',
          'https://example.invalid/media.png',
        ];
        for (final source in sources) {
          final result = await port.execute('photo', {
            'chatId': '1',
            'media': source,
          });
          expect(result['ok'], true);
          expect(calls.last.$1, 'sendPhoto');
          expect(calls.last.$2['photo'], source);
        }
        expect(calls.length, sources.length);
      } finally {
        bot.api.closeClient();
        await server.close(force: true);
      }
    },
  );

  test(
    'manual events execute API, variables, text edits, callback answers, inline answers and media through Televerse',
    () async {
      final root = await Directory.systemTemp.createTemp('builder-telegram-');
      Hive.init(root.path);
      final store = BuilderStore(
        vault: MemoryVault(),
        data: BotDatabases(root: '${root.path}/data'),
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final calls = <(String, Map)>[];
      final address = 'http://127.0.0.1:${server.port}';
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        final method = request.uri.pathSegments.last;
        if (method == 'price') {
          request.response.write('{"price":12}');
          await request.response.close();
          return;
        }
        final raw = await utf8.decoder.bind(request).join();
        final body = raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw) as Map;
        calls.add((method, body));
        final dynamic result;
        if (method == 'getMe') {
          result = {
            'id': 99,
            'is_bot': true,
            'first_name': 'Test',
            'username': 'test_bot',
          };
        } else if (method == 'answerCallbackQuery' ||
            method == 'answerInlineQuery') {
          result = true;
        } else {
          result = message(
            1,
            100 + calls.length,
            text: body['text']?.toString() ?? 'Sent',
          );
        }
        request.response.write(jsonEncode({'ok': true, 'result': result}));
        await request.response.close();
      });
      final bot = Bot.local('99:fixture', baseURL: address);
      final session = BuilderSession('99:fixture', bot.api, store: store);
      await store.addDefinition(
        builderBotId('99:fixture'),
        const VariableDefinition('score', 'user', 'number', 0),
      );
      final command = VirtEvent(type: VirtEventType.command, query: 'price')
        ..acts.addAll([
          VirtAct(type: VirtActType.http, text: '')
            ..config = {'url': '$address/price', 'output': 'lookup'},
          VirtAct(
            type: VirtActType.incrementVariable,
            text: '{{steps.lookup.body.price}}',
          )..config = {'variable': 'score', 'output': 'score'},
          VirtAct(type: VirtActType.reply, text: '*Score*: {{user.score}}')
            ..config = {'format': 'MarkdownV2', 'output': 'sent', 'chatId': ''},
          VirtAct(type: VirtActType.editText, text: 'Updated')
            ..config = {
              'messageId': '{{steps.sent.messageId}}',
              'output': 'edited',
            },
          VirtAct(type: VirtActType.photo, text: 'Photo')
            ..config = {'media': 'telegram_file_fixture', 'output': 'photo'},
          VirtAct(
            type: VirtActType.sql,
            text:
                'CREATE TABLE IF NOT EXISTS scores(user_id INTEGER PRIMARY KEY, score INTEGER NOT NULL)',
          )..config = {'output': 'schema'},
          VirtAct(
              type: VirtActType.sql,
              text:
                  'INSERT INTO scores VALUES(?,?) ON CONFLICT(user_id) DO UPDATE SET score=excluded.score',
            )
            ..config = {
              'output': 'saved',
              'parameters': '["{{event.userId}}","{{user.score}}"]',
            },
          VirtAct(
            type: VirtActType.sql,
            text: 'SELECT score FROM scores WHERE user_id=?',
          )..config = {'output': 'db', 'parameters': '["{{event.userId}}"]'},
          VirtAct(
            type: VirtActType.reply,
            text: 'DB score: {{steps.db.rows.0.score}}',
          )..config = {'output': 'databaseReply'},
        ]);
      command.add(bot, execute: (ctx) => session.receive(command, ctx));
      final button = VirtEvent(type: VirtEventType.callbackQuery, query: 'next')
        ..acts.add(
          VirtAct(type: VirtActType.callbackAnswer, text: 'Done')
            ..config = {'showAlert': true, 'output': 'ack'},
        );
      button.add(bot, execute: (ctx) => session.receive(button, ctx));
      final inline = VirtEvent(type: VirtEventType.inlineQuery, query: 'hello')
        ..acts.add(
          VirtAct(
            type: VirtActType.inlineAnswer,
            text: 'Hello {{event.firstName}}',
          )..config = {'title': 'Greeting', 'output': 'result'},
        );
      inline.add(bot, execute: (ctx) => session.receive(inline, ctx));
      try {
        await bot.init();
        await bot.handleUpdate(Update.fromJson(update(1, 1, text: '/price')));
        expect(
          calls.where((c) => c.$1 == 'sendMessage').first.$2['text'],
          '*Score*: 12',
        );
        expect(
          calls.where((c) => c.$1 == 'sendMessage').first.$2['parse_mode'],
          'MarkdownV2',
        );
        expect(
          calls.where((c) => c.$1 == 'sendMessage').last.$2['text'],
          'DB score: 12',
        );
        expect(
          calls.where((c) => c.$1 == 'editMessageText').single.$2['message_id'],
          102,
        );
        expect(
          calls.where((c) => c.$1 == 'sendPhoto').single.$2['photo'],
          'telegram_file_fixture',
        );
        await bot.handleUpdate(
          Update.fromJson({
            'update_id': 2,
            'callback_query': {
              'id': 'click',
              'from': {'id': 1, 'is_bot': false, 'first_name': 'Alex'},
              'message': message(1, 1),
              'chat_instance': 'chat',
              'data': 'next',
            },
          }),
        );
        expect(calls.where((c) => c.$1 == 'answerCallbackQuery').length, 1);
        expect(
          calls
              .where((c) => c.$1 == 'answerCallbackQuery')
              .single
              .$2['show_alert'],
          true,
        );
        await bot.handleUpdate(
          Update.fromJson({
            'update_id': 3,
            'inline_query': {
              'id': 'inline',
              'from': {'id': 1, 'is_bot': false, 'first_name': 'Alex'},
              'query': 'hello',
              'offset': '',
            },
          }),
        );
        final response = calls
            .where((c) => c.$1 == 'answerInlineQuery')
            .single
            .$2;
        expect(response['is_personal'], true);
        expect(
          (response['results'] as List)
              .single['input_message_content']['message_text'],
          'Hello Alex',
        );
      } finally {
        await session.close();
        bot.api.closeClient();
        await server.close(force: true);
        await store.close();
        await Hive.close();
        await root.delete(recursive: true);
      }
    },
  );
}
