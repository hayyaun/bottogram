import 'dart:async';
import 'package:flutter/foundation.dart';
import '../plugins/repository.dart';
import '../plugins/manifest.dart';
import '../units/virt_bot.dart';
import 'automation_runner.dart';
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
  final Map<VirtBot, List<AutomationRunner>> _runners = {};
  final Map<VirtBot, JsonTransport> _clients = {};
  final Map<VirtBot, Map<String, String>> _errors = {};
  final Map<VirtBot, Map<String, FailurePresentation>> _failureDetails = {};
  Future<void> _tail = Future.value();
  bool _closed = false;
  int get activeCount => _bots.where((bot) => bot.active).length;
  String? _firstErrorKey(VirtBot bot) {
    final keys = _errors[bot]?.keys;
    return keys?.where((key) => key != '@telegram.menu').firstOrNull ??
        keys?.firstOrNull;
  }

  String? errorFor(VirtBot bot) => _errors[bot]?[_firstErrorKey(bot)];
  FailurePresentation? failureFor(VirtBot bot) {
    final key = _firstErrorKey(bot);
    return key == null ? null : _failureDetails[bot]?[key];
  }

  Future<void> _queue(Future<void> Function() work) {
    final result = _tail.then((_) async {
      if (!_closed) await work();
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

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
    // Clean up a previous session that ended unexpectedly before replacing it.
    await _stop(bot);
    try {
      await lease.startService(activeCount + 1);
    } catch (_) {
      await _sync();
      rethrow;
    }
    _bots.add(bot);
    _errors[bot] = {};
    _failureDetails[bot] = {};
    bot.onRunningChanged = () {
      if (_closed) return;
      notifyListeners();
      if (!bot.active) {
        unawaited(
          _queue(() async {
            final failure =
                bot.runtimeError ??
                'Telegram polling stopped. Restart this bot.';
            await _stop(bot);
            bot.runtimeError = failure;
            await _sync();
            notifyListeners();
          }).catchError((Object _) {}),
        );
      }
    };
    BotTelegramPort? telegram;
    try {
      await bot.bot.init().timeout(const Duration(seconds: 22));
      if (manifest != null && setup != null) {
        final http = _clients[bot] =
            httpClientFactory?.call() ?? BoundedJsonTransport();
        telegram = BotTelegramPort(bot.bot);
        final context = RuntimeContext(
          http: http,
          telegram: telegram,
          secret: (field) => plugins.vault.read(setup.secretKey(field)),
          fields: setup.values,
          adminId: setup.adminTelegramUserId,
        );
        final settings = manifest.settingValues(setup.settings);
        final runners = _runners[bot] = [];
        for (final definition in manifest.automations) {
          if (definition.enabledBySetting != null &&
              settings[definition.enabledBySetting] != true) {
            continue;
          }
          final runner = AutomationRunner(
            definition: definition,
            context: context,
            store: progress,
            key: '${setup.instanceId}:${manifest.digest}:${definition.id}',
            errorMessages: manifest.errorMessages,
            onFailure: (failure) {
              if (_closed || !_bots.contains(bot)) return;
              if (failure == null) {
                _failureDetails[bot]?.remove(definition.id);
              } else {
                _failureDetails.putIfAbsent(bot, () => {})[definition.id] =
                    failure;
              }
              notifyListeners();
            },
            onStatus: (error) {
              if (_closed || !_bots.contains(bot)) return;
              if (error == null) {
                _errors[bot]?.remove(definition.id);
              } else {
                _errors[bot]?[definition.id] = error;
              }
              bot.runtimeError = errorFor(bot);
              notifyListeners();
            },
          );
          runners.add(runner);
          // Registers command handlers synchronously before Telegram polling.
          unawaited(runner.start());
        }
      }
      await bot.start(pluginRuntime: manifest?.executable == true);
      if (manifest?.telegram != null && setup != null && telegram != null) {
        unawaited(
          _synchronizeMenu(bot, telegram, manifest!.telegram!, setup.values),
        );
      }
    } catch (_) {
      await _stop(bot);
      rethrow;
    } finally {
      await _sync();
      notifyListeners();
    }
  });

  Future<void> _synchronizeMenu(
    VirtBot bot,
    BotTelegramPort telegram,
    Json declaration,
    Map<String, String> fields,
  ) async {
    final success = await telegram.synchronizeMenu(declaration, fields);
    if (_closed || !_bots.contains(bot) || bot.bot != telegram.bot) return;
    const key = '@telegram.menu';
    if (success) {
      _errors[bot]?.remove(key);
    } else {
      _errors[bot]?[key] =
          'The Telegram menu could not be updated. Command replies and other automations remain available.';
    }
    bot.runtimeError = errorFor(bot);
    notifyListeners();
  }

  Future<void> _stop(VirtBot bot) async {
    bot.onRunningChanged = null;
    _clients.remove(bot)?.close();
    // Stop cancels requests; pending action acknowledgements are drained before
    // a bot can be restarted or deleted.
    final runners = _runners.remove(bot) ?? [];
    final drained = Future.wait(runners.map((runner) => runner.stop()));
    try {
      // Televerse's supported stop closes its API client. Do this before waiting
      // for actions so a stalled Telegram send cannot hold the Stop operation.
      await bot.stop();
    } finally {
      await drained;
    }
    _bots.remove(bot);
    _errors.remove(bot);
    _failureDetails.remove(bot);
    bot.runtimeError = null;
  }

  Future<void> stop(VirtBot bot) => _queue(() async {
    await _stop(bot);
    await _sync();
    notifyListeners();
  });
  Future<void> stopAll() => _queue(() async {
    var failed = false;
    for (final bot in List<VirtBot>.of(_bots)) {
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

  Future<void> _sync() =>
      activeCount == 0 ? lease.stopService() : lease.updateService(activeCount);
  Future<void> close() async {
    await stopAll();
    await _tail;
    _closed = true;
    super.dispose();
  }
}
