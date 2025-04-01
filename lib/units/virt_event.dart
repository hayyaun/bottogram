import 'package:bottogram/units/virt_act.dart';
import 'package:hive/hive.dart';
import 'package:televerse/televerse.dart';

part 'user.freezed.dart';
part 'user.g.dart';

enum VirtEventType { command }

@HiveType(typeId: 1)
class VirtEvent extends HiveObject {
  static get commonCommands => ['start', 'help'];

  @HiveField(0)
  VirtEventType type;
  @HiveField(1)
  String query;
  @HiveField(2)
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
      "type": VirtEventType.command.index,
      "query": query,
      "acts": acts.map((act) => act.toJSON()),
    };
  }

  factory VirtEvent.fromJSON(json) {
    var vev = VirtEvent(
      query: json["query"],
      type: VirtEventType.values[json["type"]],
    );
    vev.acts = json["acts"].map((actJSON) => VirtAct.fromJSON(actJSON));
    return vev;
  }
}
