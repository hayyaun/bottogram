import 'dart:async';

import 'package:televerse/televerse.dart';

import '../runtime/http_transport.dart';
import '../runtime/plugin_execution.dart';
import '../runtime/ports.dart';
import '../runtime/telegram_port.dart';
import 'config.dart';

class ServerWorkerException implements Exception {
  const ServerWorkerException(this.message);
  final String message;
}

Future<void> runServerBot(
  ServerBotConfig config, {
  required ProgressStore progress,
  required Future<void> stopRequested,
  required void Function(String message) log,
  String? telegramBaseUrl,
}) async {
  final client = DioHttpClient(
    timeout: const Duration(seconds: 22),
    receiveTimeout: const Duration(seconds: 45),
  );
  final bot = Bot(config.token, httpClient: client, baseUrl: telegramBaseUrl);
  final reportedFailures = <String, String>{};
  final execution = PluginExecution(
    manifest: config.manifest,
    setup: config.setup,
    telegram: BotTelegramPort(bot),
    http: BoundedJsonTransport(),
    progress: progress,
    secret: config.secret,
    onStatus: (key, message) {
      if (message != null && key.startsWith('@telegram.')) log(message);
    },
    onFailure: (key, failure) {
      if (failure == null) {
        reportedFailures.remove(key);
      } else if (reportedFailures[key] != failure.code) {
        reportedFailures[key] = failure.code;
        log('Automation $key reported ${failure.code}.');
      }
    },
  );

  var stopping = false;
  final shutdown = stopRequested.then((_) => stopping = true);
  try {
    try {
      await Future.any<Object?>([
        bot.initialize().timeout(const Duration(seconds: 22)),
        shutdown,
      ]);
    } catch (_) {
      throw const ServerWorkerException(
        'Telegram initialization failed. Check the bot token and network connection.',
      );
    }
    if (stopping) return;

    final widgets = execution.start();
    final fetcher = LongPollingFetcher(
      bot.api,
      config: widgets
          ? const LongPollingConfig(allowedUpdates: [])
          : const LongPollingConfig(),
    );
    final exhausted = Completer<void>();
    bot.onError((error) {
      if (error.isOfType<FetcherException>()) {
        // Televerse retries transient failures. When retries run out, the
        // fetcher can stop while the bot's start future is still pending.
        if (!fetcher.isRunning && !exhausted.isCompleted) exhausted.complete();
      } else {
        log('A Telegram update handler failed.');
      }
    });
    final polling = bot.start(fetcher);
    execution.synchronizeTelegram();
    log('Running plugin ${config.manifest.storageKey}.');
    try {
      await Future.any<void>([
        polling,
        exhausted.future,
        shutdown.then((_) {}),
      ]);
    } catch (_) {
      throw const ServerWorkerException('Telegram polling failed.');
    }
    if (!stopping) {
      throw const ServerWorkerException(
        'Telegram polling stopped unexpectedly.',
      );
    }
  } finally {
    final drained = execution.stop();
    final stopped = bot.stop();
    client.dio.close(force: true);
    await Future.wait<void>([stopped, drained]);
  }
  log('Bot stopped.');
}
