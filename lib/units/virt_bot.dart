import 'package:bottogram/units/virt_event.dart';
import 'package:televerse/televerse.dart';

class VirtBot {
  Bot bot;
  String token;
  String name;
  List<VirtEvent> events;

  VirtBot(this.name, this.token, {this.events = const []}) : bot = Bot(token) {
    if (events.isEmpty) {
      events.add(VirtEvent(query: "start", type: VirtEventType.command));
    }
  }

  void start() async {
    for (var ev in events) {
      ev.add(bot);
    }
    await bot.start();
  }

  Map<String, dynamic> toJSON() {
    return {
      "name": name,
      "token": token,
      "events": events.map((ev) => ev.toJSON()),
    };
  }

  factory VirtBot.fromJSON(Map<String, dynamic> json) {
    return VirtBot(
      json["name"],
      json["token"],
      events: json["events"].map((evJSON) => VirtEvent.fromJSON(evJSON)),
    );
  }
}
