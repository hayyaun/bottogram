import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/runtime/automation_runner.dart';
import 'package:bottogram/runtime/http_transport.dart';
import 'package:bottogram/runtime/ports.dart';
import 'package:bottogram/runtime/registry.dart';

/// Read-only live check. Pass a private connection-file path, never a raw key.
/// Uses isolated in-memory progress and captures replies without contacting
/// Telegram. It neither opens the user's Hive boxes nor creates shop orders.
class _Connection {
  _Connection(this.key, this.origin, this.storefront, this.shopId);
  final String key;
  final Uri origin;
  final String storefront;
  final String shopId;

  static Future<_Connection> read(String path) async {
    try {
      final data = jsonDecode(await File(path).readAsString()) as Json;
      final key = data['api_key'] as String;
      final origin = Uri.parse(data['api_origin'] as String);
      final storefront = data['storefront_url'] as String;
      final shopId = data['shop_id'] as String;
      final scopes = Set<String>.from(data['scopes'] as List);
      if (origin.origin != 'http://127.0.0.1:8080' ||
          key.isEmpty ||
          shopId.isEmpty ||
          Uri.parse(storefront).host != data['storefront_host'] ||
          !scopes.containsAll({'storefront:read', 'shop:orders:read'})) {
        throw const FormatException();
      }
      return _Connection(key, origin, storefront, shopId);
    } catch (_) {
      // JSON/IO exceptions can include private input excerpts. Suppress them.
      throw const RuntimeFailure(
        'The private local connection file is invalid.',
        permanent: true,
      );
    }
  }
}

class _ReadTransport implements JsonTransport {
  _ReadTransport(this.connection);
  final _Connection connection;
  final inner = BoundedJsonTransport();
  int catalogRequests = 0;
  int lookupRequests = 0;
  int orderRequests = 0;
  int products = 0;
  int orders = 0;
  int paid = 0;

  @override
  Future<Json> get(Uri url, Map<String, String> headers) async {
    final expectedOrders = '/v1/shops/${connection.shopId}/orders';
    if (url.origin != connection.origin.origin ||
        !{
          '/v1/storefront',
          '/v1/storefront/products',
          expectedOrders,
        }.contains(url.path)) {
      throw const RuntimeFailure(
        'The probe refused an unexpected API destination.',
        permanent: true,
      );
    }
    final body = await inner.get(url, headers);
    if (url.path == '/v1/storefront') {
      lookupRequests++;
      if (body['id'] != connection.shopId) {
        throw const RuntimeFailure(
          'Shop lookup did not match the registered key.',
          permanent: true,
        );
      }
    } else if (url.path == '/v1/storefront/products') {
      catalogRequests++;
      final list = body['products'];
      if (list is! List) {
        throw const RuntimeFailure(
          'Invalid catalog response.',
          permanent: true,
        );
      }
      products += list.length;
    } else {
      orderRequests++;
      final list = body['orders'];
      if (list is! List ||
          list.any(
            (item) => item is! Json || item['shop_id'] != connection.shopId,
          )) {
        throw const RuntimeFailure(
          'An order summary did not match the registered shop.',
          permanent: true,
        );
      }
      orders += list.length;
      paid += list.where((item) => item['status'] == 'paid').length;
    }
    return body;
  }

  @override
  void close() => inner.close();
}

class _Progress implements ProgressStore {
  final values = <String, Json>{};
  @override
  Future<Json> read(String key) async =>
      jsonDecode(jsonEncode(values[key] ?? {})) as Json;
  @override
  Future<void> write(String key, Json value) async {
    values[key] = jsonDecode(jsonEncode(value)) as Json;
  }

  @override
  Future<void> removeInstance(String instanceId) async =>
      values.removeWhere((k, _) => k.startsWith('$instanceId:'));
}

class _CaptureTelegram implements TelegramPort {
  int messages = 0;
  @override
  void command(String command, void Function(Json) receive) {}
  @override
  Future<void> send(String chatId, String text, {Json? replyMarkup}) async {
    // Deliberately count only; no text, recipients or credentials in logs.
    if (text.isEmpty) {
      throw const RuntimeFailure(
        'The rendered reply was empty.',
        permanent: true,
      );
    }
    messages++;
  }
}

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/inshopa_local_smoke.dart <private-connection.json>',
    );
    exitCode = 64;
    return;
  }
  _ReadTransport? transport;
  AutomationRunner? runner;
  try {
    final connection = await _Connection.read(arguments.single);
    final package = PluginManifest.parse(
      Uint8List.fromList(
        await File(
          'examples/plugins/inshopa.sales.local.bottogram-plugin.json',
        ).readAsBytes(),
      ),
    );
    for (final automation in package.automations) {
      for (final component in [automation.trigger, ...automation.actions]) {
        if (AutomationRegistry.standard
            .requestsFor(component)
            .any(
              (request) =>
                  Uri.parse(request['url'] as String).origin !=
                  connection.origin.origin,
            )) {
          throw const RuntimeFailure(
            'Use the local development plugin for this probe.',
            permanent: true,
          );
        }
      }
    }
    final client = transport = _ReadTransport(connection);
    final telegram = _CaptureTelegram();
    final context = RuntimeContext(
      http: client,
      telegram: telegram,
      secret: (field) async => field == 'apiKey' ? connection.key : null,
      fields: {'storefrontUrl': connection.storefront},
      adminIds: const ['1'],
    );
    final products = package.automations.firstWhere((a) => a.id == 'products');
    var event = <String, dynamic>{'id': 'read-probe', 'chatId': '1', 'page': 1};
    for (final action in products.actions) {
      event = await AutomationRegistry.standard.actions[action.type]!
          .create(action.config, context)
          .execute(event);
    }
    final renderedCatalog = telegram.messages;
    final progress = _Progress();
    const progressKey = 'local-read-probe:paid-orders';
    final done = Completer<void>();
    runner = AutomationRunner(
      definition: package.automations.firstWhere((a) => a.id == 'paid-orders'),
      context: context,
      store: progress,
      key: progressKey,
      onStatus: (error) {
        if (done.isCompleted) return;
        if (error != null) {
          done.completeError(
            const RuntimeFailure('The live order scan failed.'),
          );
        } else if (progress.values[progressKey]?['initialized'] == true) {
          done.complete();
        }
      },
    );
    unawaited(runner.start());
    await done.future.timeout(const Duration(minutes: 2));
    client.close();
    await runner.stop();
    if (telegram.messages != renderedCatalog) {
      throw const RuntimeFailure(
        'The baseline unexpectedly produced an alert.',
        permanent: true,
      );
    }
    final report = <String, Object>{
      'api_origin': connection.origin.origin,
      'shop_lookup_matched': true,
      'products_returned': client.products,
      'catalog_requests': client.catalogRequests,
      'shop_lookup_requests': client.lookupRequests,
      'order_summary_requests': client.orderRequests,
      'order_summaries_returned': client.orders,
      'paid_summaries_returned': client.paid,
      'initial_baseline_complete': true,
      'baseline_alerts': 0,
      'catalog_reply_rendered': renderedCatalog == 1,
      'telegram_network_tested': false,
      'shop_mutations': 0,
    };
    await File(
      'build/verification/inshopa-local-live-read.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
    stdout.writeln(jsonEncode(report));
  } catch (error) {
    stderr.writeln(
      error is RuntimeFailure
          ? error.message
          : 'Local Inshopa smoke test failed. Private details were suppressed.',
    );
    exitCode = 1;
  } finally {
    transport?.close();
    await runner?.stop();
  }
}
