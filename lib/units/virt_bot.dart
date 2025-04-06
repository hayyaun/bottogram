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

  @HiveField(0)
  String name;
  @HiveField(1)
  String token;
  @HiveField(2)
  List<VirtEvent> events = [];

  VirtBot(this.name, this.token) : bot = Bot(token) {
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

  Future<void> start() async {
    if (_active) await stop(); // stop before restart
    for (var ev in events) {
      ev.add(bot);
    }
    bot.onError((err) {
      debugPrint('❌ bot error: $err');
    });
    bot.start();
    _active = true;
  }

  Future<void> stop() async {
    await bot.stop();
    bot = Bot(token);
    _active = false;
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
