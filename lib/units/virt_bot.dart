import 'package:bottogram/units/virt_event.dart';
import 'package:televerse/televerse.dart';

class VirtBot {
  bool _active = false;
  Bot bot;
  String token;
  String name;
  List<VirtEvent> events = [
    VirtEvent(query: "start", type: VirtEventType.command),
  ];

  VirtBot(this.name, this.token) : bot = Bot(token);

  bool get active => _active;

  void start() async {
    if (_active) stop(); // stop before restart
    for (var ev in events) {
      ev.add(bot);
    }
    await bot.start();
    _active = true;
  }

  Future<void> stop() async {
    await bot.stop();
  }

  Map<String, dynamic> toJSON() {
    return {
      "name": name,
      "token": token,
      "events": events.map((ev) => ev.toJSON()),
    };
  }

  factory VirtBot.fromJSON(Map<String, dynamic> json) {
    var vbot = VirtBot(json["name"], json["token"]);
    vbot.events = json["events"].map((evJSON) => VirtEvent.fromJSON(evJSON));
    return vbot;
  }
}
