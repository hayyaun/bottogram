import 'dart:convert';
import 'dart:io';

import 'package:bottogram/plugins/bot_setup.dart';
import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/runtime/coordinator.dart';
import 'package:bottogram/runtime/telegram_port.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:televerse/telegram.dart' show Update;
import 'package:televerse/televerse.dart';
import 'support/telegram_updates.dart';

import 'automation_runtime_test.dart' show FakeHttp, MemoryProgress, until;
import 'plugins_test.dart' show MemoryCatalog;
import 'runtime_lifecycle_test.dart' show TestLease;

Map<String, dynamic> commandDefinition() => {
  'manifestVersion': 2,
  'hostApiMajor': 2,
  'id': 'example.commands',
  'name': 'Example commands',
  'version': '1.0.0',
  'executionStatus': 'live',
  'requiresBotFields': <String>[],
  'setupFields': [
    {
      'key': 'publicOrigin',
      'label': 'Public origin',
      'type': 'text',
      'required': true,
    },
  ],
  'telegram': <String, dynamic>{
    'commands': [
      {'command': 'start', 'description': 'Start'},
      {'command': 'help', 'description': 'Help'},
    ],
  },
  'automations': [
    commandAutomation('navigation', ['start', 'help', 'alias']),
  ],
};

Map<String, dynamic> commandAutomation(String id, List<String> commands) => {
  'id': id,
  'trigger': {
    'type': 'telegram.command.v2',
    'config': {
      'commands': commands,
      'chatTypes': ['private'],
      'arguments': 'ignore',
    },
  },
  'actions': [
    {
      'id': 'reply',
      'type': 'telegram.reply.v1',
      'config': {'text': 'Welcome'},
    },
  ],
};

Map<String, dynamic> menuDeclaration() => {
  'text': 'Open',
  'webApp': {'originField': 'publicOrigin', 'path': '/'},
};

PluginManifest commandManifest(Map<String, dynamic> definition) =>
    PluginManifest.parse(utf8.encode(jsonEncode(definition)));

/// The SDK's public local-server constructor exercises actual wire payloads.
class CommandApi {
  CommandApi(this.server);
  final HttpServer server;
  final calls = <(String, Map<String, dynamic>)>[];
  final denied = <String>{};
  final errors = <Object>[];
  late final bot = Bot.local(
    '199:fake-token',
    'http://127.0.0.1:${server.port}',
  )..onError((error) => errors.add(error));

  static Future<CommandApi> open() async {
    final api = CommandApi(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    api.server.listen((request) async {
      final method = request.uri.pathSegments.last;
      final text = await utf8.decoder.bind(request).join();
      final body = text.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(text) as Map<String, dynamic>;
      api.calls.add((method, body));
      final rejected = api.denied.contains(method);
      dynamic result = true;
      if (method == 'getMe') {
        result = {
          'id': 199,
          'is_bot': true,
          'first_name': 'Example',
          'username': 'example_bot',
        };
      } else if (method == 'sendMessage') {
        result = {
          'message_id': api.calls.length,
          'date': 1700000000,
          'chat': {'id': 42, 'type': 'private'},
          'text': body['text'],
        };
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(
          rejected
              ? {
                  'ok': false,
                  'error_code': 403,
                  'description':
                      'raw-private-detail /bot199:fake-token/$method',
                }
              : {'ok': true, 'result': result},
        ),
      );
      await request.response.close();
    });
    return api;
  }

  Future<void> command(String command) => bot.dispatch(
    Update.fromJson({
      'update_id': calls.length + 1,
      'message': {
        'message_id': calls.length + 1,
        'date': 1700000000,
        'chat': {'id': 42, 'type': 'private'},
        'from': {'id': 42, 'is_bot': false, 'first_name': 'User'},
        'text': '/$command',
        'entities': [
          {'offset': 0, 'length': command.length + 1, 'type': 'bot_command'},
        ],
      },
    }),
  );

  Future<void> close() async {
    bot.api.closeClient();
    await server.close(force: true);
  }
}

class CommandBot extends VirtBot {
  CommandBot(Bot session)
    : super('Command test', '199:fake-token', addSamples: false) {
    bot = session;
  }
  bool running = false;
  @override
  bool get active => running;
  @override
  Future<void> start({bool pluginRuntime = false}) async {
    running = true;
    onRunningChanged?.call();
  }

  @override
  Future<void> stop() async {
    running = false;
    onRunningChanged?.call();
  }
}

class CommandHarness {
  CommandHarness(this.api, this.catalog, this.runtime, this.bot);
  final CommandApi api;
  final MemoryCatalog catalog;
  final BotRuntime runtime;
  final CommandBot bot;

  static Future<CommandHarness> create(
    Map<String, dynamic> definition, {
    Set<String> denied = const {},
  }) async {
    final manifest = commandManifest(definition);
    final api = await CommandApi.open()
      ..denied.addAll(denied);
    final catalog = MemoryCatalog()..entries.add(manifest);
    final bot = CommandBot(api.bot)
      ..setup = BotSetup(
        instanceId: 'command-instance',
        tokenFingerprint: BotSetup.fingerprint('199:fake-token'),
        adminTelegramUserId: '123',
        pluginKey: manifest.storageKey,
        pluginDigest: manifest.digest,
        pluginName: manifest.name,
        values: const {'publicOrigin': 'https://public.example.test'},
        secretFields: const [],
      );
    final runtime = BotRuntime(
      TestLease(),
      catalog,
      progress: MemoryProgress(),
      httpClientFactory: FakeHttp.new,
    );
    return CommandHarness(api, catalog, runtime, bot);
  }

  Future<void> close() async {
    await runtime.close();
    catalog.dispose();
    await api.close();
  }
}

void main() {
  test(
    'commands-only metadata publishes the declared private default-language list through the SDK',
    () async {
      final h = await CommandHarness.create(commandDefinition());
      try {
        await h.runtime.start(h.bot);
        await until(
          () => h.api.calls.any((call) => call.$1 == 'setMyCommands'),
        );
        final body = h.api.calls
            .firstWhere((call) => call.$1 == 'setMyCommands')
            .$2;
        expect(body['commands'], [
          {'command': 'start', 'description': 'Start'},
          {'command': 'help', 'description': 'Help'},
        ]);
        expect(body['scope'], {'type': 'all_private_chats'});
        expect(body['language_code'], '');
        expect(
          h.api.calls.any((call) => call.$1 == 'setChatMenuButton'),
          isFalse,
        );
        await h.api.command('alias');
        await until(() => h.api.calls.any((call) => call.$1 == 'sendMessage'));
        expect(h.bot.runtimeError, isNull);
        expect(h.bot.active, isTrue);
        expect(h.api.errors, isEmpty);
      } finally {
        await h.close();
      }
    },
  );

  test(
    'an absent command declaration leaves existing Telegram commands alone',
    () async {
      final definition = commandDefinition();
      definition['telegram'] = {'menuButton': menuDeclaration()};
      final h = await CommandHarness.create(definition);
      try {
        await h.runtime.start(h.bot);
        await until(
          () => h.api.calls.any((call) => call.$1 == 'setChatMenuButton'),
        );
        expect(
          await BotTelegramPort(
            h.api.bot,
          ).synchronizeCommands(definition['telegram']),
          isTrue,
        );
        expect(h.api.calls.any((call) => call.$1 == 'setMyCommands'), isFalse);
        expect(h.bot.active, isTrue);
      } finally {
        await h.close();
      }
    },
  );

  for (final failedMethod in ['setChatMenuButton', 'setMyCommands']) {
    test(
      'a failed $failedMethod does not skip the other control or expose SDK details',
      () async {
        final definition = commandDefinition();
        definition['telegram']['menuButton'] = menuDeclaration();
        final h = await CommandHarness.create(
          definition,
          denied: {failedMethod},
        );
        try {
          await h.runtime.start(h.bot);
          await until(() => h.runtime.errorFor(h.bot) != null);
          await until(
            () =>
                h.api.calls.any((call) => call.$1 == 'setChatMenuButton') &&
                h.api.calls.any((call) => call.$1 == 'setMyCommands'),
          );
          expect(
            h.api.calls.where((call) => call.$1 == 'setChatMenuButton').length,
            1,
          );
          expect(
            h.api.calls.where((call) => call.$1 == 'setMyCommands').length,
            1,
          );
          expect(
            h.runtime.errorFor(h.bot),
            contains(failedMethod == 'setMyCommands' ? 'command list' : 'menu'),
          );
          expect(h.bot.runtimeError, isNot(contains('raw-private-detail')));
          expect(h.bot.runtimeError, isNot(contains('fake-token')));
          await h.api.command('start');
          await until(
            () => h.api.calls.any((call) => call.$1 == 'sendMessage'),
          );
          expect(h.bot.active, isTrue);
          expect(h.api.errors, isEmpty);
        } finally {
          await h.close();
        }
      },
    );
  }

  test(
    'an actual automation failure takes priority over command synchronization failure',
    () async {
      final h = await CommandHarness.create(
        commandDefinition(),
        denied: {'setMyCommands', 'sendMessage'},
      );
      try {
        await h.runtime.start(h.bot);
        await until(
          () => h.runtime.errorFor(h.bot)?.contains('command list') == true,
        );
        await h.api.command('start');
        await until(() => h.runtime.failureFor(h.bot) != null);
        expect(
          h.runtime.failureFor(h.bot)!.code,
          'telegram.delivery_unconfirmed',
        );
        expect(h.runtime.errorFor(h.bot), isNot(contains('command list')));
        expect(h.bot.runtimeError, isNot(contains('raw-private-detail')));
        expect(h.bot.runtimeError, isNot(contains('fake-token')));
        expect(h.api.errors, isEmpty);
      } finally {
        await h.close();
      }
    },
  );

  test('manifest accepts a handler that includes private and group chats', () {
    final definition = commandDefinition();
    definition['automations'][0]['trigger']['config']['chatTypes'] = [
      'private',
      'group',
    ];
    expect(commandManifest(definition).telegram!['commands'], hasLength(2));
  });

  test(
    'manifest accepts 100 handled commands and one-character descriptions',
    () {
      final definition = commandDefinition();
      final commands = List.generate(100, (index) => 'command$index');
      definition['telegram'] = {
        'commands': [
          for (final command in commands)
            {'command': command, 'description': 'X'},
        ],
      };
      definition['automations'] = [
        for (var offset = 0; offset < commands.length; offset += 16)
          commandAutomation(
            'navigation$offset',
            commands.skip(offset).take(16).toList(),
          ),
      ];
      expect(commandManifest(definition).telegram!['commands'], hasLength(100));
    },
  );

  test(
    'manifest rejects invalid command metadata and commands without private v2 handlers',
    () {
      final invalid = <dynamic>[
        {},
        {'commands': null},
        {'commands': 'start'},
        {'commands': []},
        {
          'commands': List.generate(
            101,
            (index) => {'command': 'command$index', 'description': 'Command'},
          ),
        },
        {
          'commands': [null],
        },
        {
          'commands': [
            {'command': 'start', 'description': 'Start', 'unknown': true},
          ],
        },
        {
          'commands': [
            {'command': 'start'},
          ],
        },
        {
          'commands': [
            {'command': 'start', 'description': 'Start'},
            {'command': 'start', 'description': 'Duplicate'},
          ],
        },
        for (final name in [
          '',
          'START',
          '/start',
          'two words',
          'start-here',
          'x' * 33,
        ])
          {
            'commands': [
              {'command': name, 'description': 'Start'},
            ],
          },
        for (final description in [
          '',
          '   ',
          'x' * 257,
          'Line\nBreak',
          'Tab\t',
          'Null\u0000',
          'Control\u0085',
        ])
          {
            'commands': [
              {'command': 'start', 'description': description},
            ],
          },
        {
          'commands': [
            {'command': 'unhandled', 'description': 'Unknown'},
          ],
        },
        {
          'commands': [
            {'command': 'start', 'description': 'Start'},
          ],
          'unknown': true,
        },
      ];
      for (final telegram in invalid) {
        final definition = commandDefinition()..['telegram'] = telegram;
        expect(
          () => commandManifest(definition),
          throwsA(isA<PluginException>()),
          reason: jsonEncode(telegram),
        );
      }
      for (final chatTypes in [
        ['group'],
        ['group', 'supergroup'],
      ]) {
        final definition = commandDefinition();
        definition['automations'][0]['trigger']['config']['chatTypes'] =
            chatTypes;
        expect(
          () => commandManifest(definition),
          throwsA(isA<PluginException>()),
        );
      }
      final legacy = commandDefinition();
      legacy['telegram']['commands'] = [
        {'command': 'start', 'description': 'Start'},
      ];
      legacy['automations'][0]['trigger'] = {
        'type': 'telegram.command.v1',
        'config': {'command': 'start'},
      };
      expect(() => commandManifest(legacy), throwsA(isA<PluginException>()));
    },
  );
}
