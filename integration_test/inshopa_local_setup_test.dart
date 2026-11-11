import 'dart:convert';
import 'dart:io';
import 'package:bottogram/main.dart' as app;
import 'package:bottogram/pages/home.dart';
import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/runtime/ports.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:televerse/televerse.dart' show ID, TelegramException;

Future<Json> _privateJson(String path) async {
  try {
    return jsonDecode(await File(path).readAsString()) as Json;
  } catch (_) {
    throw StateError('Private test connection file could not be read.');
  }
}

/// Explicit opt-in live setup through the app's public domain services. Stores
/// credentials only in the normal app Hive/secure-storage paths. Never prints
/// raw credentials, API payloads, SDK exception URLs, or private-file contents.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'configure and verify the owner-authorized local Inshopa test bot',
    (tester) async {
      BotsCubit? store;
      VirtBot? bot;
      final report = <String, dynamic>{};
      var stage = 'private inputs';
      try {
        const credentialsPath = String.fromEnvironment(
          'BOTTOGRAM_LOCAL_TEST_CREDENTIALS',
        );
        const reportPath = String.fromEnvironment(
          'BOTTOGRAM_LOCAL_TEST_REPORT',
        );
        if (!Platform.isLinux ||
            credentialsPath.isEmpty ||
            reportPath.isEmpty) {
          throw StateError(
            'Supply the explicit private Linux live-test configuration.',
          );
        }
        final credentials = await _privateJson(credentialsPath);
        final connection = await _privateJson(
          credentials['inshopa_connection_file'] as String,
        );
        if (connection['api_origin'] != 'http://127.0.0.1:8080') {
          throw StateError('This setup is local only.');
        }
        final token = credentials['telegram_token'] as String;
        final admin = credentials['admin_telegram_user_id'] as String;
        stage = 'app initialization';
        app.main();
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (find.byType(HomePage).evaluate().isEmpty &&
            DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        if (find.byType(HomePage).evaluate().isEmpty) {
          throw StateError('The normal app did not initialize.');
        }
        final context = tester.element(find.byType(HomePage));
        store = context.read<BotsCubit>();
        await store.ready;
        final plugins = context.read<PluginRepository>();
        await plugins.ready;
        final bytes = await rootBundle.load(
          'examples/plugins/inshopa.sales.local.bottogram-plugin.json',
        );
        final local = PluginManifest.parse(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
        stage = 'plugin installation';
        if (!plugins.installed.any((p) => p.storageKey == local.storageKey)) {
          await plugins.install(local);
        }
        bot = store.state.where((b) => b.token == token).firstOrNull;
        report['created_new_bot'] = bot == null;
        if (bot == null) {
          stage = 'secure bot creation';
          await store.create(
            name: 'Inshopa local test',
            token: token,
            adminIds: admin,
            plugin: local,
            parameters: {
              'apiKey': connection['api_key'] as String,
              'storefrontUrl': connection['storefront_url'] as String,
            },
          );
          bot = store.state.where((b) => b.token == token).single;
        }
        stage = 'saved configuration verification';
        final setup = bot.setup;
        if (setup == null ||
            setup.pluginDigest != local.digest ||
            !setup.adminIds.contains(admin)) {
          throw StateError(
            'An existing bot uses different settings; no replacement was performed.',
          );
        }
        final saved = await plugins.vault.read(setup.secretKey('apiKey'));
        if (saved != connection['api_key']) {
          throw StateError('Secure storage verification failed.');
        }
        report['secure_api_key_verified'] = true;
        stage = 'Telegram startup';
        await store.runtime.start(bot);
        if (!bot.active) {
          throw StateError('The Telegram test session did not start.');
        }
        final identity = bot.bot.me;
        report['bot_username'] = identity.username;
        report['bot_id'] = identity.id;
        final progressKey = '${setup.instanceId}:${local.digest}:paid-orders';
        stage = 'order baseline';
        final scanDeadline = DateTime.now().add(const Duration(seconds: 40));
        var baseline = false;
        while (DateTime.now().isBefore(scanDeadline)) {
          final state = await store.runtime.progress.read(progressKey);
          if (state['initialized'] == true) {
            baseline = true;
            break;
          }
          if (bot.runtimeError != null) {
            throw StateError('The local polling automation reported an error.');
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        if (!baseline) {
          throw StateError('The initial order baseline did not complete.');
        }
        report['order_baseline_complete'] = true;
        report['admin_connection_test_sent'] = false;
        try {
          await bot.bot.api
              .getChat(ID.create(int.parse(admin)))
              .timeout(const Duration(seconds: 15));
          await bot.bot.api
              .sendMessage(
                ID.create(int.parse(admin)),
                'Bottogram local test connected. Send /products to see your shop’s catalog.',
              )
              .timeout(const Duration(seconds: 15));
          report['admin_connection_test_sent'] = true;
        } catch (error) {
          report['admin_check_error_type'] = error.runtimeType.toString();
          if (error is TelegramException) {
            report['admin_check_error_code'] = error.code;
          }
        }
        await store.runtime.stop(bot);
        report['stored_bot_name'] = bot.name;
        report['plugin_version'] = local.version;
        report['setup_complete'] = true;
        await File(reportPath).writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(report)}\n',
        );
        debugPrint(
          'Local Inshopa test bot configured; private credentials were not logged.',
        );
        expect(report['setup_complete'], isTrue);
      } catch (error) {
        fail(
          'Local test-bot setup failed at $stage (${error.runtimeType}). Private details were suppressed.',
        );
      } finally {
        await store?.runtime.stopAll();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await Hive.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
