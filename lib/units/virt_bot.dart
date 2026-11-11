import 'dart:async';
import 'package:bottogram/builder/session.dart';

import 'package:bottogram/inbox/repository.dart';
import 'package:bottogram/inbox/transformer.dart';
import 'package:bottogram/plugins/bot_setup.dart';
import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/units/virt_act.dart';
import 'package:bottogram/units/virt_event.dart';
import 'package:bottogram/units/virt_rmu.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:televerse/televerse.dart';

part 'virt_bot.adapter.dart';

class VirtBot extends HiveObject {
  bool _active = false; // TODO change it to (Date? activeSince)
  late Bot bot;
  late DioHttpClient _telegramClient;
  final String? _telegramBaseUrl;
  // Stored separately; existing Hive field IDs and legacy bot records stay intact.
  BotSetup? setup;
  String? setupError;
  String? runtimeError;
  VoidCallback? onRunningChanged;
  int _runGeneration = 0;
  BuilderSession? _builder;
  Future<InboxRepository> get inbox => InboxRepository.forToken(token);

  void _createTelegramSession() {
    _telegramClient = DioHttpClient(
      timeout: const Duration(seconds: 22),
      receiveTimeout: const Duration(seconds: 45),
    );
    bot = Bot(token, httpClient: _telegramClient, baseUrl: _telegramBaseUrl);
    bot.api.use(InboxTransformer(() => inbox));
  }

  String name;
  String token;
  List<VirtEvent> events = [];

  VirtBot(
    this.name,
    this.token, {
    bool addSamples = true,
    String? telegramBaseUrl,
  }) : _telegramBaseUrl = telegramBaseUrl {
    _createTelegramSession();
    if (!addSamples) return;
    // Sample Events/Actions
    final btn = KeyValue('Dice 🎲', 'dice');
    final keyboard = VirtRMUInlineKeyboard()
      ..items = [btn, btn, btn, null, btn, btn, null, btn];
    events
      ..add(
        VirtEvent(query: 'start', type: VirtEventType.command)
          ..acts.add(
            VirtAct(text: 'Roll a Dice! 🎲', type: VirtActType.reply)
              ..rmu = keyboard,
          ),
      )
      ..add(
        VirtEvent(query: 'dice', type: VirtEventType.callbackQuery)
          ..acts.add(VirtAct(text: '1', type: VirtActType.dice)),
      )
      ..add(
        VirtEvent(query: 'hi', type: VirtEventType.text)
          ..acts.add(VirtAct(text: 'Hello!', type: VirtActType.reply)),
      );
  }

  bool get active => _active;

  Future<void> start({bool pluginRuntime = false}) async {
    if (setupError != null) throw PluginException(setupError!);
    if ((setup?.usesPlugin ?? false) && !pluginRuntime) {
      throw const PluginException(
        'Plugin settings are saved. Live plugin execution is not available yet.',
      );
    }
    if (_active) await stop(); // stop before restart
    await bot.initialize().timeout(const Duration(seconds: 22));
    final generation = ++_runGeneration;
    var acceptsWidgets = false;
    if (!pluginRuntime) {
      final session = _builder = BuilderSession(token, bot.api);
      acceptsWidgets = session.registerWidgetQueries(bot, events);
      for (var ev in events) {
        ev.add(bot, execute: (context) => session.receive(ev, context));
      }
    }
    bot.onError((err) {
      if (generation != _runGeneration) return;
      runtimeError =
          'Telegram polling stopped. Check the bot token and connection, then restart.';
      _active = false;
      onRunningChanged?.call();
    });
    // start() runs for the lifetime of polling; don't await that loop here.
    unawaited(
      bot
          .start(
            acceptsWidgets
                ? LongPollingFetcher(
                    bot.api,
                    config: const LongPollingConfig(allowedUpdates: []),
                  )
                : null,
          )
          .then<void>(
            (_) => _pollingEnded(generation),
            onError: (Object error, StackTrace _) {
              _pollingEnded(generation);
              debugPrint(
                'Bot could not start. Check its token and connection.',
              );
            },
          ),
    );
    _active = true;
    if (!pluginRuntime) _builder!.startPolling(events);
    onRunningChanged?.call();
  }

  void _pollingEnded(int generation) {
    if (generation != _runGeneration || !_active) return;
    _active = false;
    onRunningChanged?.call();
  }

  Future<void> stop() async {
    _runGeneration++;
    final builder = _builder;
    _builder = null;
    final drained = builder?.close();
    final stopping = bot.stop();
    // Closing the owned client cancels any in-flight poll or send, including
    // when initialization failed before polling started.
    _telegramClient.dio.close(force: true);
    try {
      await stopping;
    } finally {
      await drained;
    }
    _createTelegramSession();
    _active = false;
    onRunningChanged?.call();
  }

  Future<void> toggle() async {
    if (_active) {
      await stop();
    } else {
      await start();
    }
  }

  void addEvent(VirtEvent ev) {
    events.add(ev); // push
    ev.add(bot); // listen event
  }
}
