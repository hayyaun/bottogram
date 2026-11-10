import 'dart:convert';
import 'dart:io';

import 'package:bottogram/runtime/http_headers.dart';
import 'package:bottogram/runtime/http_request.dart';
import 'package:bottogram/runtime/http_transport.dart';
import 'package:bottogram/runtime/ports.dart';
import 'package:flutter_test/flutter_test.dart';

import 'automation_runtime_test.dart' show FakeHttp, FakeTelegram;

RuntimeContext context({
  JsonTransport? http,
  Map<String, String> fields = const {},
  Future<String?> Function(String)? secret,
}) => RuntimeContext(
  http: http ?? FakeHttp(),
  telegram: FakeTelegram(),
  fields: fields,
  secret: secret ?? (_) async => 'test-credential',
  adminId: '1',
);

Matcher failure(String code, {bool? permanent}) => isA<RuntimeFailure>()
    .having((e) => e.code, 'code', code)
    .having(
      (e) => permanent == null || e.permanent == permanent,
      'permanence',
      true,
    );

void main() {
  test(
    'arbitrary headers, field bindings and custom-header authentication reach a real server',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final transport = BoundedJsonTransport();
      var requests = 0;
      server.listen((request) async {
        requests++;
        expect(request.uri.path, '/resources/resource-7');
        expect(request.uri.queryParameters, {'page': '2'});
        expect(request.headers.value('x-client'), 'Ticket kiosk');
        expect(request.headers.value('x-tenant'), 'tenant-42');
        expect(
          request.headers.value('x-portal-origin'),
          'https://events.example.test:8443',
        );
        expect(
          request.headers.value('x-portal-authority'),
          'events.example.test:8443',
        );
        expect(request.headers.value('x-api-key'), 'test-credential');
        expect(request.headers.value('authorization'), isNull);
        expect(request.headers.value('accept'), 'application/vnd.example+json');
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'ok': true}));
        await request.response.close();
      });
      final request = {
        'method': 'GET',
        'url': 'http://127.0.0.1:${server.port}/resources/{resourceId}',
        'headers': {
          'X-Client': 'Ticket kiosk',
          'X-Tenant': {'field': 'tenant', 'transform': 'value'},
          'X-Portal-Origin': {'field': 'portal', 'transform': 'url.origin'},
          'X-Portal-Authority': {
            'field': 'portal',
            'transform': 'url.authority',
          },
          'Accept': 'application/vnd.example+json',
        },
        'authentication': {
          'type': 'header',
          'header': 'X-Api-Key',
          'secretField': 'apiKey',
        },
      };
      try {
        expect(
          headerFieldBindings(request).map((binding) => binding.field).toSet(),
          {'tenant', 'portal'},
        );
        final result =
            await HttpRequest(
              request,
              context(
                http: transport,
                fields: {
                  'tenant': 'tenant-42',
                  'portal': 'https://events.example.test:8443/',
                },
              ),
            ).fetch(
              query: {'page': '2'},
              pathParameters: {'resourceId': 'resource-7'},
            );
        expect(result, {'ok': true});
        expect(requests, 1);
      } finally {
        transport.close();
        await server.close(force: true);
      }
    },
  );

  test(
    'bearer credentials remain separate and URL transforms accept ordinary origins',
    () async {
      final resolved = await resolveHttpHeaders({
        'headers': {'X-Locale': 'en'},
        'authentication': {'type': 'bearer', 'secretField': 'apiKey'},
      }, context());
      expect(resolved, {
        'X-Locale': 'en',
        'Authorization': 'Bearer test-credential',
      });
      for (final address in [
        'http://localhost:8080/',
        'https://[::1]:8443',
        'https://مثال.test',
      ]) {
        final origin = Uri.parse(address);
        expect(
          await resolveHttpHeaders({
            'headers': {
              'X-Origin': {'field': 'portal', 'transform': 'url.origin'},
              'X-Authority': {'field': 'portal', 'transform': 'url.authority'},
            },
          }, context(fields: {'portal': address})),
          {'X-Origin': origin.origin, 'X-Authority': origin.authority},
        );
      }
    },
  );

  test(
    'header contract rejects injection, duplicate casing, session headers and credential collisions',
    () {
      final invalid = <Json>[
        {
          'headers': {'X-Test': 'line\r\ninjected'},
        },
        {
          'headers': {'X-Test': 'null\u0000byte'},
        },
        {
          'headers': {'X-Test': '\u0100'},
        },
        {
          'headers': {'Bad Header': 'value'},
        },
        {
          'headers': {'X-Test': 'a', 'x-test': 'b'},
        },
        {
          'headers': {'X-Test': 123},
        },
        {
          'headers': {
            'X-Test': {'field': 'tenant', 'transform': 'eval'},
          },
        },
        {
          'headers': {
            'X-Test': {'field': 'tenant', 'transform': 'value', 'extra': true},
          },
        },
        {
          'headers': {
            'X-Test': {'field': 'secret.path', 'transform': 'value'},
          },
        },
        {
          'headers': {'X-Key': 'public'},
          'authentication': {
            'type': 'header',
            'header': 'x-key',
            'secretField': 'key',
          },
        },
        {
          'authentication': {
            'type': 'bearer',
            'header': 'X-Key',
            'secretField': 'key',
          },
        },
        {
          'authentication': {
            'type': 'header',
            'header': 'Cookie',
            'secretField': 'key',
          },
        },
        {
          'authentication': {
            'type': 'header',
            'header': 'Content-Length',
            'secretField': 'key',
          },
        },
        {
          'authentication': {'type': 'unknown', 'secretField': 'key'},
        },
        {
          'headers': {for (var i = 0; i < 33; i++) 'X-$i': 'v'},
        },
        {
          'headers': {for (var i = 0; i < 32; i++) 'X-$i': 'v'},
          'authentication': {'type': 'bearer', 'secretField': 'key'},
        },
      ];
      for (final name in [
        'Host',
        'Content-Length',
        'Transfer-Encoding',
        'Connection',
        'Proxy-Connection',
        'Keep-Alive',
        'TE',
        'Trailer',
        'Upgrade',
        'Expect',
        'Authorization',
        'Cookie',
        'Set-Cookie',
        'Proxy-Authorization',
      ]) {
        invalid.add({
          'headers': {name: 'blocked'},
        });
      }
      for (final config in invalid) {
        expect(() => validateHttpHeaders(config), throwsFormatException);
      }
    },
  );

  test(
    'runtime binding and credential failures never echo configured values or vault exceptions',
    () async {
      const marker = 'private-marker';
      for (final address in [
        'https://user:$marker@portal.example.test',
        'https://@portal.example.test',
        'https://portal.example.test/path',
        'https://portal.example.test?key=$marker',
        'https://portal.example.test#$marker',
        ' https://portal.example.test',
        'https://portal.example.test\\@other.test',
        'https://portal%2eexample.test',
        'file:///private-marker',
        'https://portal.example.test:70000',
      ]) {
        try {
          await resolveHttpHeaders({
            'headers': {
              'X-Portal': {'field': 'portal', 'transform': 'url.origin'},
            },
          }, context(fields: {'portal': address}));
          fail('Invalid origin was accepted.');
        } on RuntimeFailure catch (error) {
          expect(error.code, 'http.invalid_origin');
          expect(error.permanent, isTrue);
          expect(error.toString(), isNot(contains(marker)));
          expect(error.toString(), isNot(contains(address)));
        }
      }
      for (final secret in <Future<String?> Function(String)>[
        (_) async => null,
        (_) async => '',
        (_) async => '$marker\r\nInjected: value',
        (_) async => '\u0100',
        (_) async => throw StateError('https://user:$marker@host.test'),
      ]) {
        try {
          await resolveHttpHeaders({
            'authentication': {
              'type': 'header',
              'header': 'X-Key',
              'secretField': 'apiKey',
            },
          }, context(secret: secret));
          fail('Invalid credential was accepted.');
        } on RuntimeFailure catch (error) {
          expect(error.code, 'http.credentials_unavailable');
          expect(error.toString(), isNot(contains(marker)));
        }
      }
      await expectLater(
        resolveHttpHeaders({
          'headers': {
            'X-Tenant': {'field': 'tenant', 'transform': 'value'},
          },
        }, context(fields: {'tenant': '$marker\nInjected: value'})),
        throwsA(failure('http.invalid_headers', permanent: true)),
      );
      await expectLater(
        resolveHttpHeaders({
          'headers': {
            'X-Tenant': {'field': 'missing', 'transform': 'value'},
          },
        }, context()),
        throwsA(failure('http.invalid_headers', permanent: true)),
      );
    },
  );

  test(
    'HTTP statuses carry stable codes and host-owned retry classification without response bodies',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final transport = BoundedJsonTransport();
      var status = 401;
      server.listen((request) async {
        request.response.statusCode = status;
        request.response.headers.set('Retry-After', '99999');
        request.response.write('private-response-body');
        await request.response.close();
      });
      const cases = <int, (String, bool)>{
        401: ('http.unauthorized', true),
        403: ('http.forbidden', true),
        408: ('http.timeout', false),
        429: ('http.rate_limited', false),
        503: ('http.request_failed', false),
        302: ('http.request_failed', true),
      };
      final url = Uri.parse('http://127.0.0.1:${server.port}/resource');
      try {
        for (final entry in cases.entries) {
          status = entry.key;
          for (final get in [true, false]) {
            try {
              if (get) {
                await transport.get(url, {});
              } else {
                await transport.request('GET', url, {});
              }
              fail('Non-success status accepted.');
            } on RuntimeFailure catch (error) {
              expect(error.code, entry.value.$1);
              expect(error.permanent, entry.value.$2);
              expect(error.retryAfter, const Duration(hours: 1));
              expect(error.message, isNot(contains('private-response-body')));
            }
          }
        }
      } finally {
        transport.close();
        await server.close(force: true);
      }
    },
  );

  test(
    'malformed and oversized JSON failures are classified and transport rejects unsafe headers',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final transport = BoundedJsonTransport();
      var body = 'not-json';
      server.listen((request) async {
        request.response.write(body);
        await request.response.close();
      });
      final url = Uri.parse('http://127.0.0.1:${server.port}/resource');
      try {
        for (final invalid in ['not-json', '[]', 'x' * (1024 * 1024 + 1)]) {
          body = invalid;
          await expectLater(
            transport.get(url, {}),
            throwsA(failure('http.invalid_response', permanent: true)),
          );
        }
        for (final headers in [
          {'X-Case': 'a', 'x-case': 'b'},
          {'Host': 'other.test'},
          {'X-Value': 'a\nb'},
          {'X-Value': '\u0100'},
        ]) {
          await expectLater(
            transport.get(url, headers),
            throwsA(failure('http.invalid_headers', permanent: true)),
          );
          await expectLater(
            transport.request('GET', url, headers),
            throwsA(failure('http.invalid_headers', permanent: true)),
          );
        }
      } finally {
        transport.close();
        await server.close(force: true);
      }
    },
  );
}
