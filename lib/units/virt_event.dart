import 'package:bottogram/units/virt_act.dart';
import 'package:televerse/televerse.dart';

enum VirtEventType { command }

class VirtEvent {
  static get commonCommands => ['start', 'help'];

  VirtEventType type;
  String query;
  List<VirtAct> acts = [];

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
}
