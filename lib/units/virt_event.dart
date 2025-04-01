import 'package:bottogram/units/virt_act.dart';
import 'package:televerse/televerse.dart';

enum VirtEventType { command }

class VirtEvent {
  static get commonCommands => ['start', 'help'];

  VirtEventType type;
  String query;
  List<VirtAct> acts = [VirtAct(text: "Hello!", type: VirtActTypes.reply)];

  VirtEvent({this.type = VirtEventType.command, required this.query});

  Future<void> callback(Context ctx) async {
    for (var act in acts) {
      await act.run(ctx);
    }
  }

  void add(Bot bot) async {
    switch (type) {
      case VirtEventType.command:
        return bot.command(query, callback);
    }
  }

  Map<String, dynamic> toJSON() {
    return {
      "type": VirtEventType.command,
      "query": query,
      "acts": acts.map((act) => act.toJSON()),
    };
  }

  factory VirtEvent.fromJSON(json) {
    var vev = VirtEvent(query: json["query"], type: json["type"]);
    vev.acts = json["acts"].map((actJSON) => VirtAct.fromJSON(actJSON));
    return vev;
  }
}
