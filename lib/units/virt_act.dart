import 'package:televerse/televerse.dart';

enum VirtActTypes { reply }

class VirtAct {
  VirtActTypes type;
  String text;

  VirtAct({this.type = VirtActTypes.reply, required this.text});

  Future<void> run(Context ctx) async {
    switch (type) {
      case VirtActTypes.reply:
        await ctx.reply(text);
        break;
    }
  }

  Map<String, dynamic> toJSON() {
    return {"type": type, "text": text};
  }

  factory VirtAct.fromJSON(json) {
    return VirtAct(text: json["text"], type: json["type"]);
  }
}
