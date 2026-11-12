import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:televerse/televerse.dart';
import 'package:bottogram/plugins/bot_setup.dart';
import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/runtime/coordinator.dart';
import 'package:bottogram/runtime/ports.dart';
import 'package:bottogram/runtime/telegram_connection.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'automation_runtime_test.dart' show MemoryProgress;
import 'plugins_test.dart' show MemoryCatalog;

class TestLease implements ExecutionLease {
  final counts = <int>[];
  final totals = <int>[];
  final warnings = <int>[];
  bool fail = false;
  @override
  Future<void> startService(int active, int total) async {
    if (fail) throw StateError('Service unavailable');
    counts.add(active);
    totals.add(total);
  }

  @override
  Future<void> updateService(int active, int total) async {
    counts.add(active);
    totals.add(total);
  }

  @override
  Future<void> updateConnectionWarning(int affected) async {
    warnings.add(affected);
  }

  @override
  Future<void> stopService() async {
    counts.add(0);
  }
}

class InitializedBot extends Fake implements Bot<Context> {
  int initializations = 0;
  @override
  Future<BotInfo> initialize() async {
    initializations++;
    return const BotInfo();
  }
}

class RuntimeBot extends VirtBot {
  RuntimeBot([super.name = 'Test', super.token = '1:testing'])
    : super(addSamples: false) {
    bot = InitializedBot();
  }
  bool running = false;
  int starts = 0;
  @override
  bool get active => running;
  @override
  Future<void> start({bool pluginRuntime = false}) async {
    starts++;
    running = true;
    onRunningChanged?.call();
  }

  @override
  Future<void> stop() async {
    running = false;
    onRunningChanged?.call();
  }
}

void main() {
  test(
    'stopping a real SDK session cancels an outstanding long poll',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final poll = Completer<void>();
      var initializations = 0;
      server.listen((request) async {
        if (request.uri.pathSegments.last == 'getUpdates') {
          if (!poll.isCompleted) poll.complete();
          // Hold the request open until the client cancels the long poll.
          return;
        }
        initializations++;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'ok': true,
            'result': {
              'id': 99,
              'is_bot': true,
              'first_name': 'Test',
              'username': 'fixture_bot',
            },
          }),
        );
        await request.response.close();
      });
      final bot = VirtBot(
        'Test',
        '99:fixture',
        addSamples: false,
        telegramBaseUrl: 'http://127.0.0.1:${server.port}',
      );
      try {
        await bot.start(pluginRuntime: true);
        await poll.future.timeout(const Duration(seconds: 5));
        expect(bot.active, true);
        await bot.stop().timeout(const Duration(seconds: 5));
        expect(bot.active, false);
        expect(initializations, 1);
      } finally {
        await server.close(force: true);
        if (bot.active) await bot.stop();
      }
    },
  );
  test(
    'Telegram failures raise and clear the Android warning as the bot recovers',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var identityStatus = HttpStatus.unauthorized;
      var pollRequests = 0;
      final allowPolling = Completer<void>();
      final finishFirstPoll = Completer<void>();
      server.listen((request) async {
        final method = request.uri.pathSegments.last;
        request.response.headers.contentType = ContentType.json;
        if (method == 'getMe') {
          if (identityStatus != HttpStatus.ok) {
            request.response.statusCode = identityStatus;
            if (identityStatus == HttpStatus.unauthorized) {
              request.response.write(
                '{"ok":false,"error_code":401,"description":"Unauthorized"}',
              );
            }
          } else {
            request.response.write(
              jsonEncode({
                'ok': true,
                'result': {
                  'id': 99,
                  'is_bot': true,
                  'first_name': 'Test',
                  'username': 'fixture_bot',
                },
              }),
            );
          }
        } else if (method == 'getUpdates') {
          pollRequests++;
          if (pollRequests == 1) {
            await allowPolling.future;
            request.response.statusCode = HttpStatus.badGateway;
          } else if (pollRequests == 2) {
            await finishFirstPoll.future;
            request.response.write('{"ok":true,"result":[]}');
          } else {
            // Hold a successful replacement poll until stop cancels it.
            return;
          }
        } else {
          request.response.write('{"ok":true,"result":true}');
        }
        await request.response.close();
      });

      final manifest = PluginManifest.parse(
        await File(
          'examples/headless/config/hello.bottogram-plugin.json',
        ).readAsBytes(),
      );
      final catalog = MemoryCatalog()..entries.add(manifest);
      final lease = TestLease();
      final runtime = BotRuntime(lease, catalog, progress: MemoryProgress());
      final bot =
          VirtBot(
              'Test',
              '99:fixture',
              addSamples: false,
              telegramBaseUrl: 'http://127.0.0.1:${server.port}',
            )
            ..setup = BotSetup(
              instanceId: 'fixture',
              tokenFingerprint: 'fixture',
              adminIds: const [],
              pluginKey: manifest.storageKey,
              pluginDigest: manifest.digest,
            );

      Future<void> until(bool Function() condition) async {
        final watch = Stopwatch()..start();
        while (!condition()) {
          if (watch.elapsed > const Duration(seconds: 8)) {
            fail('Timed out waiting for the Telegram state and warning.');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      try {
        await runtime.setTotalBots(1);
        await expectLater(runtime.start(bot), throwsA(isA<BotError>()));
        expect(bot.telegramConnectionIssue, isNull);
        expect(lease.warnings, [0]);

        identityStatus = HttpStatus.badGateway;
        await expectLater(runtime.start(bot), throwsA(isA<BotError>()));
        expect(bot.active, isFalse);
        expect(
          bot.telegramConnectionIssue,
          TelegramConnectionIssue.unavailable,
        );
        expect(lease.warnings, [0, 1]);

        identityStatus = HttpStatus.ok;
        await runtime.start(bot);
        expect(lease.warnings, [0, 1, 0]);
        allowPolling.complete();
        await until(() => lease.warnings.length == 4 && lease.counts.last == 0);
        expect(bot.active, isTrue);
        expect(
          bot.telegramConnectionIssue,
          TelegramConnectionIssue.reconnecting,
        );
        expect(lease.counts.last, 0);
        expect(lease.warnings.last, 1);

        await until(() => pollRequests >= 2);
        finishFirstPoll.complete();
        await until(() => lease.warnings.length == 5 && lease.counts.last == 1);
        expect(bot.active, isTrue);
        expect(bot.telegramConnectionIssue, isNull);
        expect(lease.counts.last, 1);
        expect(lease.warnings, [0, 1, 0, 1, 0]);
      } finally {
        if (!allowPolling.isCompleted) allowPolling.complete();
        if (!finishFirstPoll.isCompleted) finishFirstPoll.complete();
        await runtime.close();
        await server.close(force: true);
        catalog.dispose();
      }
    },
  );

  test(
    'one lifecycle owner serializes duplicate Starts and aggregates two bot leases',
    () async {
      final lease = TestLease();
      final catalog = MemoryCatalog();
      final runtime = BotRuntime(lease, catalog, progress: MemoryProgress());
      final first = RuntimeBot(), second = RuntimeBot();
      await runtime.setTotalBots(3);
      await Future.wait([
        runtime.start(first),
        runtime.start(first),
        runtime.start(second),
      ]);
      expect(first.starts, 1);
      expect(second.starts, 1);
      expect((first.bot as InitializedBot).initializations, 1);
      expect(runtime.activeCount, 2);
      expect(lease.counts, [0, 1, 1, 2]);
      expect(lease.totals, [3, 3, 3, 3]);
      await runtime.setTotalBots(4);
      expect(lease.counts.last, 2);
      expect(lease.totals.last, 4);
      await runtime.stop(first);
      expect(runtime.activeCount, 1);
      expect(lease.counts.last, 1);
      await runtime.stopAll();
      expect(runtime.activeCount, 0);
      expect(lease.counts.last, 0);
      await runtime.close();
      catalog.dispose();
    },
  );
  test(
    'foreground service failure prevents Telegram startup and releases the lease',
    () async {
      final lease = TestLease()..fail = true;
      final catalog = MemoryCatalog();
      final runtime = BotRuntime(lease, catalog, progress: MemoryProgress());
      final bot = RuntimeBot();
      await expectLater(runtime.start(bot), throwsStateError);
      expect(bot.starts, 0);
      expect((bot.bot as InitializedBot).initializations, 0);
      expect(runtime.activeCount, 0);
      expect(lease.counts.last, 0);
      await runtime.close();
      catalog.dispose();
    },
  );
}
