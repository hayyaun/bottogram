import 'package:hive/hive.dart';
import 'package:televerse/televerse.dart';

part 'virt_act.g.dart';

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
}

enum VirtActTypes { reply }

class VirtActTypeAdapter extends TypeAdapter<VirtActTypes> {
  @override
  final typeId = 21;

  @override
  VirtActTypes read(BinaryReader reader) {
    int index = reader.readByte();
    return VirtActTypes.values[index];
  }

  @override
  void write(BinaryWriter writer, VirtActTypes obj) {
    writer.writeByte(obj.index);
  }
}
