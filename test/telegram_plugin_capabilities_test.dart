import 'dart:convert';

import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/runtime/components.dart';
import 'package:bottogram/runtime/ports.dart';
import 'package:bottogram/runtime/telegram_config.dart';
import 'package:flutter_test/flutter_test.dart';

import 'automation_runtime_test.dart' show FakeHttp, FakeTelegram;

Json arbitraryPackage() => {
  'manifestVersion': 2,
  'hostApiMajor': 2,
  'id': 'example.event-tickets',
  'name': 'Event tickets',
  'version': '1.0.0',
  'executionStatus': 'live',
  'setupFields': [
    {
      'key': 'portalOrigin',
      'type': 'text',
      'required': true,
      'label': 'Portal',
    },
  ],
  'telegram': {
    'menuButton': {
      'text': 'Open event',
      'webApp': {'originField': 'portalOrigin', 'path': '/event'},
    },
  },
  'automations': [
    {
      'id': 'tickets',
      'trigger': {
        'type': 'telegram.command.v2',
        'config': {
          'commands': ['tickets', 'passes'],
          'chatTypes': ['private'],
          'arguments': 'ignore',
        },
      },
      'actions': [
        {
          'id': 'show-tickets',
          'type': 'telegram.reply.v2',
          'config': {
            'text': 'Your event passes',
            'inlineKeyboard': [
              [
                {
                  'text': 'View passes',
                  'webApp': {'originField': 'portalOrigin', 'path': '/tickets'},
                },
              ],
            ],
          },
        },
      ],
    },
  ],
};

PluginManifest parse(Json package) =>
    PluginManifest.parse(utf8.encode(jsonEncode(package)));
Json triggerConfig(Json package) =>
    package['automations'][0]['trigger']['config'] as Json;
Json actionConfig(Json package) =>
    package['automations'][0]['actions'][0]['config'] as Json;
Json buttonTarget(Json package) =>
    actionConfig(package)['inlineKeyboard'][0][0]['webApp'] as Json;

class MarkupTelegram extends FakeTelegram {
  Json? markup;
  @override
  Future<void> send(String chat, String text, {Json? replyMarkup}) async {
    markup = replyMarkup;
    await super.send(chat, text, replyMarkup: replyMarkup);
  }
}

void main() {
  test(
    'an unrelated plugin owns aliases, copy, field names, routes and menu',
    () async {
      final manifest = parse(arbitraryPackage());
      expect(manifest.telegram?['menuButton']['text'], 'Open event');
      final definition = manifest.automations.single;
      final telegram = MarkupTelegram();
      final http = FakeHttp();
      var secretReads = 0;
      final context = RuntimeContext(
        http: http,
        telegram: telegram,
        secret: (_) async {
          secretReads++;
          return 'must-not-be-used';
        },
        fields: {'portalOrigin': 'https://events.example.test:8443/'},
        adminId: '123',
      );
      final trigger = TelegramCommandTrigger(
        definition.trigger.config,
        context,
      );
      try {
        expect(telegram.commands.keys, ['tickets', 'passes']);
        telegram.commands['tickets']!({
          'id': '1',
          'chatId': '-10',
          'chatType': 'group',
        });
        telegram.commands['passes']!({
          'id': '2',
          'chatId': '42',
          'chatType': 'private',
          'arguments': ['anything'],
        });
        final batch = await trigger.next(null);
        expect(batch.events.single['id'], '2');
        expect(batch.events.single.containsKey('arguments'), isFalse);
        await TelegramMessageAction(
          definition.actions.single.config,
          context,
          adminOnly: false,
        ).execute(batch.events.single);
        expect(telegram.messages, [('42', 'Your event passes')]);
        expect(telegram.markup, {
          'inline_keyboard': [
            [
              {
                'text': 'View passes',
                'web_app': {'url': 'https://events.example.test:8443/tickets'},
              },
            ],
          ],
        });
        expect(
          webAppTargets(
            telegram: manifest.telegram,
            actionConfigs: definition.actions.map((a) => a.config),
          ).map((t) => t['path']),
          ['/event', '/tickets'],
        );
        expect(secretReads, 0);
        expect(http.requests, isEmpty);
      } finally {
        trigger.close();
      }
    },
  );

  test(
    'invalid URL references, undeclared keys and non-private Mini Apps fail at import',
    () {
      final mutations = <void Function(Json)>[
        (p) => buttonTarget(p)['originField'] = 'missing',
        (p) => p['setupFields'][0]['type'] = 'secret',
        (p) => p['setupFields'][0]['required'] = false,
        (p) => buttonTarget(p)['path'] = '//other.example.test',
        (p) => buttonTarget(p)['path'] = '/tickets?session=secret',
        (p) => buttonTarget(p)['path'] = '/tickets#session',
        (p) => buttonTarget(p)['path'] = '/{{event.secret}}',
        (p) => buttonTarget(p)['path'] = '/\\other.example.test',
        (p) => buttonTarget(p)['url'] = 'https://other.example.test',
        (p) =>
            actionConfig(p)['inlineKeyboard'][0][0]['callbackData'] = 'login',
        (p) => actionConfig(p)['inlineKeyboard'] = [],
        (p) => triggerConfig(p)['chatTypes'] = ['private', 'group'],
        (p) => triggerConfig(p)['commands'] = ['tickets', 'tickets'],
        (p) => triggerConfig(p)['arguments'] = 'javascript',
        (p) => p['telegram']['menuButton']['webApp']['originField'] = 'missing',
        (p) => p['telegram']['menuButton']['webApp']['path'] =
            'https://other.example.test',
      ];
      for (var index = 0; index < mutations.length; index++) {
        final package = arbitraryPackage();
        mutations[index](package);
        expect(
          () => parse(package),
          throwsA(isA<PluginException>()),
          reason: 'mutation $index',
        );
      }
      final duplicate = arbitraryPackage();
      duplicate['automations'].add({
        'id': 'duplicate',
        'trigger': {
          'type': 'telegram.command.v1',
          'config': {'command': 'passes'},
        },
        'actions': [
          {
            'id': 'reply',
            'type': 'telegram.reply.v1',
            'config': {'text': 'Duplicate'},
          },
        ],
      });
      expect(() => parse(duplicate), throwsA(isA<PluginException>()));
    },
  );

  test(
    'invalid configured origins never leak their value or become usable links',
    () {
      for (final value in [
        '',
        'http://localhost:3000',
        '//events.example.test',
        'https://user:private-secret@events.example.test',
        'https://@events.example.test',
        'https://events.example.test?key=private-secret',
        'https://events.example.test#private-secret',
        'https://events.example.test/auth',
        ' https://events.example.test',
        'https://events.example.test\\@other.test',
        'https://events.example.test:65536',
        'https://%40events.example.test',
        'https://events.example.test%2f.other.test',
        'https://events.example.test%3a443',
        'https://events.example.test%5c.other.test',
        'events.example.test/auth',
        'events.example.test?key=private-secret',
        'events.example.test#private-secret',
        'events.example.test:65536',
        '[::1]:65536',
        'events.example.test:',
        'events.example.test:invalid',
        'user:private-secret@events.example.test',
        'events.example.test\r\nX-Injected: value',
        'ftp://events.example.test',
        'custom:443',
        'javascript:443',
        'https:events.example.test',
      ]) {
        expect(
          () => resolveWebAppTarget(
            {'originField': 'portalOrigin', 'path': '/tickets'},
            {'portalOrigin': value},
          ),
          throwsA(
            isA<RuntimeFailure>().having(
              (e) => e.message,
              'sanitized message',
              isNot(contains('private-secret')),
            ),
          ),
        );
      }
    },
  );

  test('bare authorities open Mini App paths on their HTTPS origin', () {
    for (final address in [
      'events.example.test',
      'EVENTS.example.test:8443',
      'events.example.test/',
      'events.example.test:443/',
      '127.0.0.1:8443',
      'localhost:8443',
      '[::1]',
      '[::1]:8443/',
      'bücher.example',
      'مثال.test',
      'xn--bcher-kva.example:8443',
    ]) {
      final expected = Uri.parse('https://$address');
      final fields = {'portalOrigin': address};
      final result = Uri.parse(
        resolveWebAppTarget({
          'originField': 'portalOrigin',
          'path': '/tickets',
        }, fields),
      );
      expect(result.origin, expected.origin);
      expect(result.path, '/tickets');
      expect(fields['portalOrigin'], address);
    }
  });

  test('Unicode and punycode custom domains retain their parsed origin', () {
    for (final address in [
      'https://bücher.example',
      'https://xn--bcher-kva.example',
    ]) {
      final result = Uri.parse(
        resolveWebAppTarget(
          {'originField': 'portalOrigin', 'path': '/tickets'},
          {'portalOrigin': address},
        ),
      );
      expect(result.origin, Uri.parse(address).origin);
      expect(result.path, '/tickets');
      expect(result.hasQuery, isFalse);
      expect(result.hasFragment, isFalse);
    }
  });
}
