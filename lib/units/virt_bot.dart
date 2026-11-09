import 'dart:async';

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

part 'virt_bot.g.dart';

@HiveType(typeId: 10)
class VirtBot extends HiveObject {
  bool _active = false; // TODO change it to (Date? activeSince)
  Bot bot;
  // Stored separately; existing Hive field IDs and legacy bot records stay intact.
  BotSetup? setup;
  String? setupError;
  String? runtimeError;
  VoidCallback? onRunningChanged;
  int _runGeneration = 0;
  Future<InboxRepository> get inbox => InboxRepository.forToken(token);

  void _attachInbox() {
    bot.api.use(InboxTransformer(() => inbox));
  }

  @HiveField(0)
  String name;
  @HiveField(1)
  String token;
  @HiveField(2)
  List<VirtEvent> events = [];

  VirtBot(this.name, this.token, {bool addSamples = true}) : bot = Bot(token) {
    _attachInbox();
    if (!addSamples) return;
    // Sample Events/Actions
    final btn = KeyValue('Dice 🎲', 'dice');
    final keyboard =
        VirtRMUInlineKeyboard()
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
    final generation = ++_runGeneration;
    if (!pluginRuntime) {
      for (var ev in events) {
        ev.add(bot);
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
      bot.start().catchError((Object error) {
        if (generation != _runGeneration) return;
        _active = false;
        onRunningChanged?.call();
        debugPrint('Bot could not start. Check its token and connection.');
      }),
    );
    _active = true;
    onRunningChanged?.call();
  }

  Future<void> stop() async {
    _runGeneration++;
    await bot.stop();
    bot = Bot(token);
    _attachInbox();
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
