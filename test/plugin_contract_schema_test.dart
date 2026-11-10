import 'dart:convert';

import 'package:bottogram/plugins/capability_review.dart';
import 'package:bottogram/plugins/manifest.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

typedef Json = Map<String, dynamic>;

Json eventServicePackage() => {
  'manifestVersion': 2,
  'hostApiMajor': 2,
  'id': 'example.event-portal',
  'name': 'Event portal',
  'version': '1.0.0',
  'executionStatus': 'live',
  'setupFields': [
    {
      'key': 'accountId',
      'label': 'Account identifier',
      'type': 'text',
      'required': true,
    },
    {
      'key': 'portalOrigin',
      'label': 'Event portal URL',
      'type': 'text',
      'required': true,
    },
    {
      'key': 'eventKey',
      'label': 'Event API key',
      'type': 'secret',
      'required': true,
    },
  ],
  'errorMessages': {
    'eventAccessDenied': <String, dynamic>{
      'title': 'Event access denied',
      'message': 'The event service rejected the connection.',
      'help': 'Check the event API key and account identifier.',
      'action': 'editPluginParameters',
    },
  },
  'automations': [
    {
      'id': 'event-tickets',
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
          'id': 'fetch-tickets',
          'type': 'http.get-json.v1',
          'errorMap': {'http.forbidden': 'eventAccessDenied'},
          'config': {
            'request': {
              'method': 'GET',
              'url': 'https://api.events.example.test/v1/tickets',
              'headers': {
                'X-Account': {'field': 'accountId', 'transform': 'value'},
                'X-Portal-Origin': {
                  'field': 'portalOrigin',
                  'transform': 'url.origin',
                },
                'X-Portal-Host': {
                  'field': 'portalOrigin',
                  'transform': 'url.authority',
                },
                'X-Client': 'literal-value-must-not-be-displayed',
              },
              'authentication': {
                'type': 'header',
                'header': 'X-Event-Key',
                'secretField': 'eventKey',
              },
            },
            'resultKey': 'tickets',
          },
        },
        {
          'id': 'reply',
          'type': 'telegram.reply.v1',
          'config': {'text': 'Event tickets loaded.'},
        },
      ],
    },
  ],
};

PluginManifest parse(Json package) =>
    PluginManifest.parse(utf8.encode(jsonEncode(package)));
Json request(Json package) =>
    package['automations'][0]['actions'][0]['config']['request'] as Json;

void main() {
  test(
    'generic field headers and custom credential authentication resolve declared field contracts',
    () {
      final parsed = parse(eventServicePackage());
      expect(parsed.id, 'example.event-portal');
      final fetch = parsed.automations.single.actions.first;
      expect(fetch.errorMap, {'http.forbidden': 'eventAccessDenied'});
      expect(
        parsed.errorMessages?['eventAccessDenied']['title'],
        'Event access denied',
      );
      expect(
        fetch.config['request']['headers']['X-Account']['field'],
        'accountId',
      );
      expect(
        fetch.config['request']['authentication']['header'],
        'X-Event-Key',
      );
      final integerValue = eventServicePackage();
      integerValue['setupFields'][0]['type'] = 'integer';
      expect(parse(integerValue).fields.first.type, PluginFieldType.integer);
    },
  );

  test(
    'public header bindings require declared required non-secret sources',
    () {
      for (final mutate in <void Function(Json)>[
        (package) =>
            request(package)['headers']['X-Account']['field'] = 'notDeclared',
        (package) =>
            request(package)['headers']['X-Account']['field'] = 'eventKey',
        (package) => package['setupFields'][0]['required'] = false,
        (package) => package['setupFields'][1]['type'] = 'integer',
      ]) {
        final package = eventServicePackage();
        mutate(package);
        expect(() => parse(package), throwsA(isA<PluginException>()));
      }
    },
  );

  test(
    'credential authentication requires a declared required secret source',
    () {
      for (final mutate in <void Function(Json)>[
        (package) =>
            request(package)['authentication']['secretField'] = 'notDeclared',
        (package) =>
            request(package)['authentication']['secretField'] = 'accountId',
        (package) => package['setupFields'][2]['required'] = false,
      ]) {
        final package = eventServicePackage();
        mutate(package);
        expect(() => parse(package), throwsA(isA<PluginException>()));
      }
    },
  );

  test(
    'component error maps reference declared plugin resources without policy overrides',
    () {
      final missing = eventServicePackage();
      missing['automations'][0]['actions'][0]['errorMap']['http.forbidden'] =
          'notDeclared';
      expect(() => parse(missing), throwsA(isA<PluginException>()));

      final rawMap = eventServicePackage();
      rawMap['automations'][0]['actions'][0]['errorMap'] = {
        'not-a-host-code': 'eventAccessDenied',
      };
      expect(() => parse(rawMap), throwsA(isA<PluginException>()));

      final policyOverride = eventServicePackage();
      policyOverride['errorMessages']['eventAccessDenied']['permanent'] = false;
      expect(() => parse(policyOverride), throwsA(isA<PluginException>()));
    },
  );

  test(
    'removed implicit storefront header syntax is rejected rather than decoded',
    () {
      final package = eventServicePackage();
      request(package)['storefrontUrlField'] = 'portalOrigin';
      expect(() => parse(package), throwsA(isA<PluginException>()));
    },
  );

  testWidgets(
    'review describes arbitrary event headers and credential methods without showing values',
    (tester) async {
      final custom = eventServicePackage();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PluginCapabilityReview(
                plugin: parse(custom),
                fields: const {
                  'accountId': 'actual-account-value-must-not-be-displayed',
                  'portalOrigin':
                      'https://actual-origin-must-not-be-displayed.example.test',
                  'eventKey': 'secret-value-must-not-be-displayed',
                },
              ),
            ),
          ),
        ),
      );
      expect(find.text('/tickets · /passes · private chats'), findsOneWidget);
      expect(
        find.text('Header: X-Account ← Account identifier (field value)'),
        findsOneWidget,
      );
      expect(
        find.text('Header: X-Portal-Origin ← Event portal URL (URL origin)'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Header: X-Portal-Host ← Event portal URL (URL host and port)',
        ),
        findsOneWidget,
      );
      expect(find.text('Header: X-Client (literal value)'), findsOneWidget);
      expect(
        find.text(
          'Authentication: Custom header X-Event-Key ← Event API key (secure storage)',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('must-not-be-displayed'), findsNothing);
      expect(find.textContaining('Inshopa'), findsNothing);
      expect(find.textContaining('Storefront'), findsNothing);
      expect(tester.takeException(), isNull);

      request(custom)['authentication'] = {
        'type': 'bearer',
        'secretField': 'eventKey',
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PluginCapabilityReview(plugin: parse(custom)),
            ),
          ),
        ),
      );
      expect(
        find.text(
          'Authentication: Bearer token ← Event API key (secure storage)',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('literal-value-must-not-be-displayed'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
