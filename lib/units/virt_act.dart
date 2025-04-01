import 'package:televerse/televerse.dart';

enum VirtActTypes { reply }

class VirtAct {
  VirtActTypes type;
  String text;
  List<VirtAct> acts = [];

  VirtAct({this.type = VirtActTypes.reply, required this.text});

  Future<void> run(Context ctx) async {
    switch (type) {
      case VirtActTypes.reply:
        await ctx.reply(text);
        break;
    }
  }
}
