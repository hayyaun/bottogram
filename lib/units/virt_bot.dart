import 'package:bottogram/units/virt_event.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:televerse/televerse.dart';

part 'virt_bot.g.dart';

@HiveType(typeId: 10)
class VirtBot extends HiveObject {
  bool _active = false;
  Bot bot;
  @HiveField(0)
  String name;
  @HiveField(1)
  String token;
  @HiveField(2)
  List<VirtEvent> events =
      VirtEvent.commonCommands
          .map((c) => VirtEvent(query: c, type: VirtEventType.command))
          .toList();

  VirtBot(this.name, this.token) : bot = Bot(token);

  bool get active => _active;

  Future<void> start() async {
    if (_active) await stop(); // stop before restart
    for (var ev in events) {
      ev.add(bot);
    }
    bot.onError((err) {
      if (kDebugMode) print('--> bot error: $err');
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
}
