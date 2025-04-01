import 'package:hive/hive.dart';
import 'package:televerse/televerse.dart';

part 'user.freezed.dart';
part 'user.g.dart';

enum VirtActTypes { reply }

@HiveType(typeId: 2)
class VirtAct {
  @HiveField(0)
  VirtActTypes type;
  @HiveField(1)
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
    return {"type": type.index, "text": text};
  }

  factory VirtAct.fromJSON(json) {
    return VirtAct(text: json["text"], type: VirtActTypes.values[json["type"]]);
  }
}
