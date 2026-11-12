import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../plugins/repository.dart';
import '../plugins/manifest.dart';
import '../units/virt_bot.dart';
import 'plugin_execution.dart';
import 'http_transport.dart';
import 'ports.dart';
import 'progress_store.dart';
import 'telegram_port.dart';
import 'failure_presentation.dart';

/// Lifecycle operations serialize; long-running automations never occupy this
/// queue. Android and desktop supply the same narrow execution lease.
class BotRuntime extends ChangeNotifier {
  BotRuntime(
    this.lease,
    this.plugins, {
    ProgressStore? progress,
    this.httpClientFactory,
  }) : progress = progress ?? HiveProgressStore();
  final ExecutionLease lease;
  final PluginRepository plugins;
  final ProgressStore progress;
  final JsonTransport Function()? httpClientFactory;
  final Set<VirtBot> _bots = {};
  final Set<VirtBot> _connectionWarnings = {};
  int? _publishedWarningCount;
  final _pluginExecutions = <VirtBot, PluginExecution>{};
  final Map<VirtBot, Map<String, String>> _errors = {};
  final Map<VirtBot, Map<String, FailurePresentation>> _failureDetails = {};
  Future<void> _tail = Future.value();
  Future<void> _warningTail = Future.value();
  bool _closed = false;
  int _totalBots = 0;
  int get activeCount => _bots.where((bot) => bot.active).length;
  String? _firstErrorKey(VirtBot bot) {
    final keys = _errors[bot]?.keys;
    return keys?.where((key) => !key.startsWith('@telegram.')).firstOrNull ??
        keys?.firstOrNull;
  }

  String? errorFor(VirtBot bot) => _errors[bot]?[_firstErrorKey(bot)];
  FailurePresentation? failureFor(VirtBot bot) {
    final key = _firstErrorKey(bot);
    return key == null ? null : _failureDetails[bot]?[key];
  }

  List<FailurePresentation> failuresFor(VirtBot bot) {
    final key = _firstErrorKey(bot);
    return [
      if (failureFor(bot) case final FailurePresentation failure) failure,
      for (final entry
          in (_failureDetails[bot] ?? const <String, FailurePresentation>{})
              .entries)
        if (entry.key != key) entry.value,
    ];
  }

  Future<void> _queue(Future<void> Function() work) {
    final result = _tail.then((_) async {
      if (!_closed) await work();
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> setTotalBots(int count) => _queue(() async {
    _totalBots = count;
    if (activeCount > 0) {
      await _sync();
    } else {
      await _syncConnectionWarning();
    }
  });

  Future<void> start(VirtBot bot) => _queue(() async {
    if (bot.active) return;
    if (bot.setupError != null) throw PluginException(bot.setupError!);
    await plugins.ready;
    final setup = bot.setup;
    final manifest = plugins.manifestFor(setup);
    if (setup?.usesPlugin == true && manifest?.executable != true) {
      throw const PluginException(
        'This plugin version is setup-only. Install a live version and create a new bot with it.',
      );
    }
    // Keep a connection warning visible until the new session reaches Telegram.
    await _stop(bot, preserveConnectionIssue: true);
    try {
      final active = activeCount;
      await lease.startService(_connectedCount, max(_totalBots, active + 1));
    } catch (_) {
      await _sync();
      rethrow;
    }
    _bots.add(bot);
    _errors[bot] = {};
    _failureDetails[bot] = {};
    bot.onTelegramConnectionChanged = () {
      if (_closed || !_bots.contains(bot)) return;
      if (bot.telegramConnectionIssue == null) {
        _connectionWarnings.remove(bot);
      } else {
        _connectionWarnings.add(bot);
      }
      notifyListeners();
      unawaited(_syncConnectionWarning());
      unawaited(
        _queue(() => _sync(stopIfIdle: false)).catchError((Object _) {}),
      );
    };
    bot.onRunningChanged = () {
      if (_closed) return;
      notifyListeners();
      if (!bot.active) {
        unawaited(
          _queue(() async {
            if (!_bots.contains(bot) || bot.active) return;
            final failure =
                bot.runtimeError ??
                (bot.telegramConnectionIssue == null
                    ? 'Telegram polling stopped. Restart this bot.'
                    : null);
            await _stop(bot, preserveConnectionIssue: true);
            bot.runtimeError = failure;
            await _sync();
            notifyListeners();
          }).catchError((Object _) {}),
        );
      }
    };
    PluginExecution? execution;
    try {
      await bot.initializeTelegram();
      if (manifest != null && setup != null) {
        execution = _pluginExecutions[bot] = PluginExecution(
          manifest: manifest,
          setup: setup,
          telegram: BotTelegramPort(bot.bot),
          http: httpClientFactory?.call() ?? BoundedJsonTransport(),
          progress: progress,
          secret: (field) => plugins.vault.read(setup.secretKey(field)),
          onFailure: (key, failure) {
            if (_closed || !_bots.contains(bot)) return;
            if (failure == null) {
              _failureDetails[bot]?.remove(key);
            } else {
              _failureDetails.putIfAbsent(bot, () => {})[key] = failure;
            }
            notifyListeners();
          },
          onStatus: (key, error) {
            if (_closed || !_bots.contains(bot)) return;
            if (error == null) {
              _errors[bot]?.remove(key);
            } else {
              _errors[bot]?[key] = error;
            }
            bot.runtimeError = errorFor(bot);
            notifyListeners();
          },
        );
      }
      bot.pluginWidgetQueries = execution?.start() ?? false;
      await bot.start(pluginRuntime: manifest?.executable == true);
      execution?.synchronizeTelegram();
    } catch (_) {
      await _stop(bot, preserveConnectionIssue: true);
      rethrow;
    } finally {
      await _sync();
      notifyListeners();
    }
  });

  Future<void> _stop(
    VirtBot bot, {
    bool preserveConnectionIssue = false,
  }) async {
    final issue = preserveConnectionIssue ? bot.telegramConnectionIssue : null;
    bot.onRunningChanged = null;
    bot.onTelegramConnectionChanged = null;
    final drained = _pluginExecutions.remove(bot)?.stop();
    // Close Telegram before waiting for actions so a stalled send cannot hold Stop.
    await Future.wait<void>([bot.stop(), if (drained != null) drained]);
    _bots.remove(bot);
    _errors.remove(bot);
    _failureDetails.remove(bot);
    bot.runtimeError = null;
    bot.telegramConnectionIssue = issue;
    if (issue == null) _connectionWarnings.remove(bot);
  }

  Future<void> stop(VirtBot bot) => _queue(() async {
    await _stop(bot);
    await _sync();
    notifyListeners();
  });
  Future<void> stopAll() => _queue(() async {
    var failed = false;
    for (final bot in {..._bots, ..._connectionWarnings}) {
      try {
        await _stop(bot);
      } catch (_) {
        failed = true;
      }
    }
    await _sync();
    notifyListeners();
    if (failed) {
      throw const RuntimeFailure(
        'Some bots could not be stopped. Open Bottogram and try again.',
      );
    }
  });
  Future<void> forget(VirtBot bot) async {
    await stop(bot);
    final id = bot.setup?.instanceId;
    if (id != null) await progress.removeInstance(id);
  }

  int get _connectedCount => _bots
      .where((bot) => bot.active && bot.telegramConnectionIssue == null)
      .length;

  Future<void> _syncConnectionWarning() =>
      _warningTail = _warningTail.then((_) async {
        final count = _connectionWarnings.length;
        if (_publishedWarningCount == count) return;
        try {
          await lease.updateConnectionWarning(count);
          _publishedWarningCount = count;
        } catch (_) {
          // Retry on the next sync without interrupting the bot or its service.
        }
      });

  Future<void> _sync({bool stopIfIdle = true}) async {
    final active = activeCount;
    try {
      if (active > 0) {
        await lease.updateService(_connectedCount, max(_totalBots, active));
      } else if (stopIfIdle) {
        await lease.stopService();
      }
    } finally {
      await _syncConnectionWarning();
    }
  }

  Future<void> close() async {
    await stopAll();
    await _tail;
    _closed = true;
    super.dispose();
  }
}
