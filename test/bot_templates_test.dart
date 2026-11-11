import 'dart:io';
import 'package:bottogram/builder/console.dart';
import 'package:bottogram/builder/database.dart';
import 'package:bottogram/builder/engine.dart';
import 'package:bottogram/builder/event_match.dart';
import 'package:bottogram/builder/rich_message.dart';
import 'package:bottogram/builder/session.dart';
import 'package:bottogram/builder/store.dart';
import 'package:bottogram/runtime/http_transport.dart';
import 'package:bottogram/runtime/ports.dart';
import 'package:bottogram/templates/catalog.dart';
import 'package:bottogram/templates/model.dart';
import 'package:bottogram/units/virt_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:televerse/telegram.dart';
import 'plugins_test.dart' show MemoryVault;

class TemplateTelegram implements BuilderTelegram {
  final calls = <BuilderJson>[];
  @override
  Future<BuilderJson> execute(String kind, BuilderJson args) async {
    expect((args['text'] as String).length, lessThanOrEqualTo(4096));
    if (args['keyboard'] != null) {
      InlineKeyboardMarkup.fromJson(
        Map<String, dynamic>.from(args['keyboard'] as Map),
      );
    }
    if (args['richBlocks'] != null) {
      BuilderRichMessage.build(
        args['richBlocks'],
        draft: args['draftId'] != null,
      );
    }
    calls.add({'kind': kind, ...args});
    return {'ok': true, 'messageId': calls.length, 'chatId': args['chatId']};
  }
}

class PriceTransport extends BoundedJsonTransport {
  int calls = 0;
  dynamic response = [
    {
      'market_cap_rank': 1,
      'name': 'Bitcoin',
      'symbol': 'btc',
      'current_price': 100,
      'image': 'https://coin-images.coingecko.com/bitcoin.png',
    },
    {
      'market_cap_rank': 2,
      'name': 'Ethereum',
      'symbol': 'eth',
      'current_price': 50,
      'image': 'https://coin-images.coingecko.com/ethereum.png',
    },
  ];
  bool fail = false;
  @override
  Future<Json> request(
    String method,
    Uri uri,
    Map<String, String> headers, {
    dynamic body,
  }) async {
    calls++;
    expect(method, 'GET');
    expect(uri.host, 'api.coingecko.com');
    expect(uri.queryParameters['order'], 'market_cap_desc');
    if (fail) throw const RuntimeFailure('API request failed (HTTP 429).');
    return {'status': 200, 'body': response};
  }
}

class TemplateHarness {
  TemplateHarness(this.id, this.draft, this.store, this.transport) {
    engine = BuilderEngine(
      botId: id,
      telegram: telegram,
      variables: store.variables(id),
      secret: (_) async => null,
      console: console,
      http: transport,
    );
  }
  final String id;
  final BotTemplateDraft draft;
  final BuilderStore store;
  final PriceTransport transport;
  final telegram = TemplateTelegram();
  final console = BuilderConsole();
  late final BuilderEngine engine;
  int tick = 0;
  Future<void> command(String command, {int user = 1}) =>
      send(VirtEventType.command, command, user: user);
  Future<void> click(String data, {int user = 1}) =>
      send(VirtEventType.callbackQuery, data, user: user);
  Future<void> text(String text, {int user = 1}) =>
      send(VirtEventType.text, text, user: user);
  Future<void> send(
    VirtEventType type,
    String input, {
    int user = 1,
    int? chat,
    bool allowErrors = false,
  }) async {
    final event = draft.events.firstWhere(
      (e) =>
          e.type == type &&
          (type == VirtEventType.command
              ? e.query == input
              : BuilderEventMatch.remainder(
                      input,
                      e.query,
                      e.config['match']?.toString() ?? 'exact',
                    ) !=
                    null),
    );
    final remainder = type == VirtEventType.command
        ? ''
        : BuilderEventMatch.remainder(
            input,
            event.query,
            event.config['match']?.toString() ?? 'exact',
          );
    await engine.run('$type:$input', {
      'updateId': tick + 1,
      'userId': user,
      'chatId': chat ?? user,
      'text': input,
      'input': remainder ?? '',
      'callbackData': input,
      'firstName': 'Person $user',
      'timestamp': DateTime.utc(
        2026,
        11,
        10,
      ).add(Duration(seconds: 20 * tick++)).toIso8601String(),
    }, BuilderSession.steps(event));
    if (!allowErrors) {
      expect(
        console.entries(id).where((e) => e.status == 'error'),
        isEmpty,
        reason: console
            .entries(id)
            .map((e) => '${e.step}: ${e.message}')
            .join('\n'),
      );
    }
  }

  Future<List<dynamic>> query(
    String sql, [
    List<dynamic> args = const [],
  ]) async => (await store.data.query(id, sql, args))['rows'] as List;
  List<String> get messages =>
      telegram.calls.map((c) => c['text'].toString()).toList();
}

void nativeFlowTest(
  String name,
  Future<void> Function() body, {
  Timeout timeout = const Timeout(Duration(minutes: 3)),
}) => test(name, body, timeout: timeout);

void main() {
  group('built-in templates', () {
    late Directory root;
    late BuilderStore store;
    final harnesses = <TemplateHarness>[];
    setUp(() async {
      root = await Directory.systemTemp.createTemp('bottogram-templates-');
      Hive.init(root.path);
      store = BuilderStore(
        vault: MemoryVault(),
        data: BotDatabases(root: '${root.path}/data'),
      );
      await store.ready;
    });
    tearDown(() async {
      for (final h in harnesses) {
        await h.engine.close();
        h.console.dispose();
      }
      harnesses.clear();
      await store.close();
      await Hive.close();
      await root.delete(recursive: true);
    });
    Future<TemplateHarness> create(
      String name, {
      List<Map<String, dynamic>>? rows,
    }) async {
      final template = BotTemplates.all.firstWhere((t) => t.id == name);
      final draft = BotTemplates.create(
        template,
        template.defaults(),
        rows ?? template.sampleRows(),
        '99',
      );
      final id = builderBotId(name + harnesses.length.toString());
      for (final d in draft.variables) {
        await store.addDefinition(id, d);
      }
      final h = TemplateHarness(id, draft, store, PriceTransport());
      harnesses.add(h);
      return h;
    }

    nativeFlowTest(
      'all seven templates start, stay editable and initialize idempotently',
      () async {
        expect(BotTemplates.all.map((t) => t.id), [
          'quiz',
          'crypto',
          'tasks',
          'library',
          'feedback',
          'requests',
          'registration',
        ]);
        for (final template in BotTemplates.all) {
          final h = await create(template.id);
          expect(h.draft.events.every((e) => e.acts.length <= 64), isTrue);
          await h.command('start');
          await h.command('start');
          expect(h.messages, isNotEmpty);
          expect(h.transport.calls, 0);
          expect(
            h.draft.events.where((e) => e.type == VirtEventType.polling),
            isEmpty,
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
    nativeFlowTest(
      'quiz scores are per user, repeated answers do not score and bests persist',
      () async {
        final h = await create('quiz');
        await h.command('start');
        await h.click('quiz:topic:Everyday knowledge');
        await h.click('quiz:A:1');
        await h.click('quiz:A:1');
        expect(
          (await h.query(
            'SELECT score,position FROM quiz_runs WHERE user_id=?',
            ['1'],
          )).single,
          {'score': 1, 'position': 1},
        );
        await h.click('quiz:B:2');
        await h.click('quiz:C:3');
        expect(h.messages.last, contains('Personal best: 3'));
        await h.click('quiz:topic:Everyday knowledge');
        await h.click('quiz:B:1');
        await h.click('quiz:A:2');
        await h.click('quiz:A:3');
        expect(h.messages.last, contains('Score: 0 / 3'));
        expect(h.messages.last, contains('Personal best: 3'));
        await h.command('score', user: 2);
        expect(h.messages.last, contains('first score'));
        expect(
          await h.query('SELECT best FROM quiz_scores WHERE user_id=?', ['1']),
          [
            {'best': 3},
          ],
        );
      },
    );
    nativeFlowTest(
      'task creation, paging, toggle and deletion never affect another user',
      () async {
        final h = await create('tasks');
        await h.command('start');
        for (var i = 0; i < 7; i++) {
          await h.click('task:add');
          await h.text('Task $i');
        }
        expect(h.telegram.calls.last['keyboard']['inline_keyboard'].length, 7);
        await h.click('task:next');
        expect(h.messages.last, contains('Task 0'));
        expect(h.messages.last, isNot(contains('Task 6')));
        await h.click('task:toggle:1', user: 2);
        await h.click('task:delete:1', user: 2);
        expect(
          (await h.query('SELECT done FROM tasks WHERE id=1')).single['done'],
          0,
        );
        await h.click('task:toggle:1');
        expect(
          (await h.query('SELECT done FROM tasks WHERE id=1')).single['done'],
          1,
        );
        await h.click('task:toggle:1');
        expect(
          (await h.query('SELECT done FROM tasks WHERE id=1')).single['done'],
          0,
        );
        await h.click('task:delete:1');
        expect(await h.query('SELECT id FROM tasks WHERE id=1'), isEmpty);
        await h.click('task:add');
        await h.text('x' * 201);
        expect(h.messages.last, contains('1–200'));
        await h.command('cancel');
        await h.text('Do not save');
        expect(
          (await h.query('SELECT count(*) AS n FROM tasks')).single['n'],
          6,
        );
      },
    );
    nativeFlowTest(
      'library supports literal search, details and private favorites',
      () async {
        final h = await create('library');
        await h.command('start');
        await h.click('lib:category:Getting started');
        expect(h.messages.last, contains('Welcome guide'));
        await h.click('lib:open:1');
        expect(
          h.telegram.calls.last['keyboard']['inline_keyboard'][0][0]['url'],
          'https://example.org/welcome',
        );
        await h.click('lib:favorite:1');
        await h.click('lib:favorites');
        expect(h.messages.last, contains('Welcome guide'));
        await h.click('lib:favorites', user: 2);
        expect(h.messages.last, contains('No matching'));
        await h.command('search');
        await h.text('WELCOME');
        expect(h.messages.last, contains('Welcome guide'));
        await h.command('search');
        await h.text("%' OR 1=1 --");
        expect(h.messages.last, contains('No matching'));
        await h.click('lib:favorite:1');
        expect(await h.query('SELECT * FROM library_favorites'), isEmpty);
      },
    );
    nativeFlowTest(
      'survey supports back, review paging, one atomic submission and admin summary',
      () async {
        final h = await create('feedback');
        await h.command('start');
        await h.click('survey:begin');
        await h.click('survey:5:1');
        await h.text('x' * 1001);
        expect(h.messages.last, contains('1–1000'));
        await h.text('First feedback');
        await h.click('survey:back');
        await h.text('Updated feedback');
        await h.click('survey:4:3');
        expect(h.messages.last, contains('Review your answers'));
        expect(h.messages.last, contains('Updated feedback'));
        await h.click('survey:next');
        expect(h.messages.last, contains('recommend'));
        await h.click('survey:submit');
        await h.click('survey:submit');
        final result = (await h.query(
          'SELECT summary,rating_sum,rating_count FROM survey_submissions',
        )).single;
        expect(result['summary'], contains('Updated feedback'));
        expect(result['rating_sum'], 9);
        expect(result['rating_count'], 2);
        final before = h.messages.length;
        await h.command('report', user: 2);
        expect(h.messages.length, before);
        await h.command('report', user: 99);
        expect(h.messages.last, contains('Submissions: 1'));
        expect(h.messages.last, contains('4.5'));
      },
    );
    nativeFlowTest(
      'request subjects do not submit prematurely and replies are admin-only',
      () async {
        final h = await create('requests');
        await h.command('start');
        await h.click('request:new');
        await h.text('Community question');
        expect(await h.query('SELECT * FROM requests'), isEmpty);
        await h.text('Here are the details.');
        expect(
          (await h.query('SELECT count(*) AS n FROM requests')).single['n'],
          1,
        );
        await h.click('request:open:1', user: 2);
        expect(h.messages.last, contains('not available to you'));
        await h.click('request:close:1', user: 2);
        expect(
          (await h.query('SELECT status FROM requests')).single['status'],
          'Open',
        );
        await h.command('inbox', user: 99);
        expect(h.messages.last, contains('Community question'));
        await h.click('request:reply:1', user: 99);
        await h.text('Here is an answer.', user: 99);
        expect((await h.query('SELECT reply,status FROM requests')).single, {
          'reply': 'Here is an answer.',
          'status': 'Replied',
        });
        expect(
          h.telegram.calls.any(
            (c) =>
                c['chatId'] == '1' &&
                c['text'].toString().contains('Here is an answer.'),
          ),
          isTrue,
        );
        await h.click('request:close:1', user: 99);
        expect(
          (await h.query('SELECT status FROM requests')).single['status'],
          'Closed',
        );
        await h.click('request:reopen:1', user: 99);
        expect(
          (await h.query('SELECT status FROM requests')).single['status'],
          'Open',
        );
      },
    );
    nativeFlowTest(
      'registration cannot overbook, duplicate or cancel another person’s seat',
      () async {
        final template = BotTemplates.all.last;
        final rows = template.sampleRows()..first['capacity'] = 1;
        final h = await create('registration', rows: rows);
        await h.command('start');
        await Future.wait([
          for (var user = 1; user <= 8; user++)
            h.click('reg:join:1', user: user),
        ]);
        expect(
          (await h.query(
            'SELECT count(*) AS n FROM registrations WHERE event_id=1',
          )).single['n'],
          1,
        );
        await h.click('reg:join:1');
        expect(
          (await h.query(
            'SELECT count(*) AS n FROM registrations',
          )).single['n'],
          1,
        );
        await h.click('reg:cancel:1', user: 2);
        expect(
          (await h.query(
            'SELECT user_id FROM registrations',
          )).single['user_id'],
          '1',
        );
        await h.click('reg:cancel:1');
        await h.click('reg:join:1', user: 2);
        expect(
          (await h.query(
            'SELECT user_id FROM registrations',
          )).single['user_id'],
          '2',
        );
        final other = await create('registration');
        await other.command('start');
        expect(await other.query('SELECT * FROM registrations'), isEmpty);
      },
    );
    nativeFlowTest(
      'prices are demand-only, cooled down and handle rate limits or missing fields gracefully',
      () async {
        final h = await create('crypto');
        await h.command('start');
        expect(h.transport.calls, 0);
        await h.command('prices');
        expect(h.messages.last, contains('Bitcoin'));
        expect(h.messages.last, contains('CoinGecko'));
        final output = h.telegram.calls;
        expect(output[output.length - 2]['draftId'], isNotEmpty);
        expect(output.last['draftId'], isNull);
        expect(
          (output.last['richBlocks'] as List).map((block) => block['type']),
          containsAllInOrder(['heading', 'table', 'collage', 'buttons']),
        );
        h.tick--;
        await h.click('prices:refresh');
        expect(h.transport.calls, 1);
        expect(h.messages.last, contains('Please wait'));
        h.transport.fail = true;
        await h.send(VirtEventType.command, 'prices', allowErrors: true);
        expect(h.messages.last, contains('Prices are unavailable'));
        expect(h.messages.last, isNot(contains('HTTP')));
        h.console.clear(h.id);
        h.transport.fail = false;
        h.transport.response = [
          {'name': 'Missing price'},
        ];
        await h.send(VirtEventType.command, 'prices', allowErrors: true);
        expect(h.messages.last, contains('Prices are unavailable'));
        expect(
          h
              .telegram
              .calls
              .last['keyboard']['inline_keyboard'][0][0]['callback_data'],
          'prices:refresh',
        );
      },
    );
    nativeFlowTest(
      'group use cannot expose private template content',
      () async {
        final h = await create('tasks');
        await h.send(VirtEventType.command, 'start', chat: -123);
        expect(h.messages.single, contains('private chat'));
        expect(
          await store.read(h.id, '1'),
          containsPair('bot', containsPair('initialized', false)),
        );
      },
    );
  });
}
