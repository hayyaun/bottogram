import 'package:bottogram/units/virt_act.dart';
import 'package:televerse/televerse.dart';

enum VirtEventType { command }

class VirtEvent {
  static get commonCommands => ['start', 'help'];

  VirtEventType type;
  String query;
  List<VirtAct> acts;

  VirtEvent({
    this.type = VirtEventType.command,
    required this.query,
    this.acts = const [],
  }) {
    if (acts.isEmpty) {
      acts.add(VirtAct(text: "Hello!", type: VirtActTypes.reply));
    }
  }

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
    return VirtEvent(
      query: json["query"],
      type: json["type"],
      acts: json["acts"].map((actJSON) => VirtAct.fromJSON(actJSON)),
    );
  }
}
