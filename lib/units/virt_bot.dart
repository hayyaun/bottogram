import 'package:bottogram/units/virt_event.dart';
import 'package:televerse/televerse.dart';

class VirtBot {
  List<VirtEvent> events = [];

  Bot bot;

  VirtBot(String token) : bot = Bot(token);

  void start() async {
    for (var ev in events) {
      ev.add(bot);
    }
  }
}
